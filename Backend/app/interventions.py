"""Intervention log + aggregate insight computation.

An "intervention" is any structured action the patient takes (or is prompted
to take) that we can attribute an outcome to: breathing exercise, walk,
sleep-hygiene checklist, journaling, medication adherence, etc.

Two responsibilities live here:

1. ``log_intervention`` — persists the record, snapshotting the current
   personal baseline so the outcome delta is stable even as the rolling
   60-day window shifts underneath.

2. ``compute_pending_outcomes`` — hunts for logs whose 72h evaluation window
   has closed and now has enough post-trigger check-ins to score. Runs
   opportunistically from the check-in write path (see routers/checkins.py)
   so we don't need a separate cron worker for MVP.

Aggregate insights (``insights_for_patient``) group scored outcomes by
intervention type and emit average deltas. We deliberately hide anything
with fewer than ``MIN_SAMPLES_FOR_INSIGHT`` observations — small samples
would produce claims like "walking reduces your anxiety" from a single
lucky day, which is the exact opposite of a trustworthy personalization
loop.
"""
from __future__ import annotations

import json
import logging
from datetime import datetime, timedelta, timezone
from statistics import mean

from sqlalchemy.orm import Session

from . import models, schemas
from .baselines import BASELINE_METRICS, snapshot_for_intervention
from .security import decrypt_field, encrypt_field


logger = logging.getLogger("neuremia.interventions")


# 72h post-trigger before we score an intervention. Shorter windows conflate
# noise; longer ones make the personalization feedback feel disconnected
# from the action.
OUTCOME_WINDOW_HOURS = 72
# Below this many scored outcomes we withhold the insight entirely.
MIN_SAMPLES_FOR_INSIGHT = 3
# Threshold for calling a delta "significant" in the UI. Not a p-value —
# just a magnitude cutoff (~0.3 on our 0–5 diary scale ≈ half a category).
SIGNIFICANCE_THRESHOLD = 0.3


def _utcnow_naive() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


# ------------------------------------------------------------ write path


def log_intervention(
    db: Session,
    patient_id: int,
    *,
    intervention_type: str,
    trigger_source: str,
    notes: str,
) -> models.InterventionLog:
    """Record a new intervention log. Caller commits."""
    baseline_snapshot = snapshot_for_intervention(db, patient_id)
    record = models.InterventionLog(
        patient_id=patient_id,
        intervention_type=intervention_type,
        trigger_source=trigger_source,
        triggered_at=_utcnow_naive(),
        baseline_snapshot_json=json.dumps(baseline_snapshot),
        # Notes are treated as PHI (may include mood context, medication
        # rationale, therapist prompts) — encrypted at rest.
        notes_encrypted=encrypt_field(notes) if notes else "",
    )
    db.add(record)
    return record


# ----------------------------------------------------------- outcome scoring


def _post_trigger_checkins(
    db: Session, patient_id: int, triggered_at: datetime
) -> list[models.DailyCheckIn]:
    window_end = triggered_at + timedelta(hours=OUTCOME_WINDOW_HOURS)
    return (
        db.query(models.DailyCheckIn)
        .filter(
            models.DailyCheckIn.patient_id == patient_id,
            models.DailyCheckIn.deleted_at.is_(None),
            models.DailyCheckIn.created_at > triggered_at,
            models.DailyCheckIn.created_at <= window_end,
        )
        .order_by(models.DailyCheckIn.created_at.asc())
        .all()
    )


def _score_outcome(
    baseline_snapshot: dict[str, float],
    post_checkins: list[models.DailyCheckIn],
) -> dict[str, float]:
    """Compute per-metric delta between post-trigger average and the baseline
    mean captured when the intervention was logged. Positive = above the
    patient's personal normal for that metric.

    Anxiety and irritability are inverted at the aggregate layer (a *drop*
    from baseline is a *positive* outcome), so the raw sign here is preserved
    and interpretation is left to the insights layer.
    """
    result: dict[str, float] = {}
    for metric in BASELINE_METRICS:
        values = [float(getattr(c, metric)) for c in post_checkins]
        if not values:
            continue
        baseline_mean = baseline_snapshot.get(metric)
        if baseline_mean is None:
            continue
        post_mean = mean(values)
        result[f"{metric}_delta"] = round(post_mean - baseline_mean, 4)
    result["days_measured"] = len({c.created_at.date() for c in post_checkins})
    return result


def compute_pending_outcomes(db: Session, patient_id: int) -> int:
    """Score any intervention logs whose 72h window has closed and now has at
    least one post-trigger check-in. Idempotent — already-scored rows are
    skipped by the outcome_computed_at guard."""
    now = _utcnow_naive()
    cutoff = now - timedelta(hours=OUTCOME_WINDOW_HOURS)
    pending = (
        db.query(models.InterventionLog)
        .filter(
            models.InterventionLog.patient_id == patient_id,
            models.InterventionLog.outcome_computed_at.is_(None),
            models.InterventionLog.triggered_at <= cutoff,
        )
        .all()
    )
    scored = 0
    for log in pending:
        try:
            baseline_snapshot = json.loads(log.baseline_snapshot_json or "{}")
        except json.JSONDecodeError:
            logger.warning(
                "Skipping intervention_log %s: unparseable baseline snapshot", log.id
            )
            continue
        post_checkins = _post_trigger_checkins(db, patient_id, log.triggered_at)
        if not post_checkins:
            # No follow-up data yet — leave the row pending. Next check-in
            # will retry via the same hook.
            continue
        outcome = _score_outcome(baseline_snapshot, post_checkins)
        log.outcome_delta_json = json.dumps(outcome)
        log.outcome_computed_at = now
        scored += 1
    return scored


# ------------------------------------------------------------- read path


def _decode_outcome(log: models.InterventionLog) -> dict[str, float] | None:
    if not log.outcome_delta_json:
        return None
    try:
        return json.loads(log.outcome_delta_json)
    except json.JSONDecodeError:
        return None


def log_read(log: models.InterventionLog) -> schemas.InterventionLogRead:
    return schemas.InterventionLogRead(
        id=log.id,
        patient_id=log.patient_id,
        intervention_type=log.intervention_type,
        trigger_source=log.trigger_source,
        triggered_at=log.triggered_at,
        notes=decrypt_field(log.notes_encrypted) if log.notes_encrypted else "",
        outcome_computed_at=log.outcome_computed_at,
        outcome_delta=_decode_outcome(log),
    )


def _average(values: list[float]) -> float:
    return round(mean(values), 4) if values else 0.0


def insights_for_patient(
    db: Session, patient_id: int
) -> schemas.InterventionInsightsResponse:
    """Aggregate scored outcomes into per-intervention insights.

    Only groups with ``MIN_SAMPLES_FOR_INSIGHT`` or more scored logs surface.
    ``pending_outcomes`` reports how many logs are still awaiting the 72h
    window — useful for the UI to communicate "still learning" state
    without pretending we have enough data yet.
    """
    logs = (
        db.query(models.InterventionLog)
        .filter(models.InterventionLog.patient_id == patient_id)
        .all()
    )

    grouped: dict[str, list[dict[str, float]]] = {}
    pending = 0
    for log in logs:
        if log.outcome_computed_at is None:
            pending += 1
            continue
        outcome = _decode_outcome(log)
        if outcome is None:
            continue
        grouped.setdefault(log.intervention_type, []).append(outcome)

    insights: list[schemas.InterventionInsight] = []
    for intervention_type, outcomes in grouped.items():
        if len(outcomes) < MIN_SAMPLES_FOR_INSIGHT:
            continue
        mood_deltas = [o.get("mood_delta", 0.0) for o in outcomes]
        anxiety_deltas = [o.get("anxiety_delta", 0.0) for o in outcomes]
        energy_deltas = [o.get("energy_delta", 0.0) for o in outcomes]
        sleep_deltas = [o.get("sleep_hours_delta", 0.0) for o in outcomes]

        avg_mood = _average(mood_deltas)
        avg_anxiety = _average(anxiety_deltas)
        avg_energy = _average(energy_deltas)
        avg_sleep = _average(sleep_deltas)

        # Significance = any dimension moved by more than the threshold in the
        # clinically-helpful direction (mood/energy up, anxiety down).
        is_significant = (
            avg_mood >= SIGNIFICANCE_THRESHOLD
            or avg_energy >= SIGNIFICANCE_THRESHOLD
            or avg_anxiety <= -SIGNIFICANCE_THRESHOLD
        )

        insights.append(
            schemas.InterventionInsight(
                intervention_type=intervention_type,  # validated by Literal
                sample_size=len(outcomes),
                avg_mood_delta=avg_mood,
                avg_anxiety_delta=avg_anxiety,
                avg_energy_delta=avg_energy,
                avg_sleep_delta=avg_sleep,
                is_significant=is_significant,
            )
        )
    # Deterministic order: strongest signals first, then alphabetic tie-break.
    insights.sort(
        key=lambda i: (
            -(
                max(i.avg_mood_delta, i.avg_energy_delta, -i.avg_anxiety_delta)
            ),
            i.intervention_type,
        )
    )
    return schemas.InterventionInsightsResponse(
        insights=insights, pending_outcomes=pending
    )


def list_logs_for_patient(
    db: Session, patient_id: int, *, limit: int = 100
) -> list[schemas.InterventionLogRead]:
    logs = (
        db.query(models.InterventionLog)
        .filter(models.InterventionLog.patient_id == patient_id)
        .order_by(models.InterventionLog.triggered_at.desc())
        .limit(limit)
        .all()
    )
    return [log_read(log) for log in logs]
