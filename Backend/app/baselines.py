"""Personal-baseline compute layer.

Owns rolling 60-day baselines for the diary metrics we care about (mood,
anxiety, energy, irritability, sleep_hours). Called synchronously from the
check-in write path so downstream consumers (episode pipeline, insights,
UI) always read a fresh row.

Design notes
------------
* Fixed 60-day window is a reasonable compromise between responsiveness and
  stability. Shorter windows over-react to a bad week; longer ones dilute
  a genuine downward drift.
* Baselines are ``upsert`` per (patient, metric). We do NOT retain history —
  the ``computed_at`` timestamp is the only temporal signal exposed. If we
  need trend-of-baseline later, that will be a separate table so this one
  stays cheap to read from every dashboard render.
* The current z-score is included as a derived field on read (not persisted)
  because callers want it in the same shape as the mean/stdev anyway and it
  avoids a second denormalized column that could drift out of sync.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from statistics import mean, pstdev

from sqlalchemy.orm import Session

from . import models, schemas


BASELINE_WINDOW_DAYS = 60

# All metrics kept in one place so the compute loop and the /me/baselines
# endpoint agree on the set without stringly-typed drift.
BASELINE_METRICS: tuple[str, ...] = (
    models.BaselineMetric.mood.value,
    models.BaselineMetric.anxiety.value,
    models.BaselineMetric.energy.value,
    models.BaselineMetric.irritability.value,
    models.BaselineMetric.sleep_hours.value,
)


def _metric_value(checkin: models.DailyCheckIn, metric: str) -> float:
    return float(getattr(checkin, metric))


def _load_recent_checkins(
    db: Session, patient_id: int, window_days: int
) -> list[models.DailyCheckIn]:
    cutoff = datetime.now(timezone.utc).replace(tzinfo=None) - timedelta(days=window_days)
    return (
        db.query(models.DailyCheckIn)
        .filter(
            models.DailyCheckIn.patient_id == patient_id,
            models.DailyCheckIn.deleted_at.is_(None),
            models.DailyCheckIn.created_at >= cutoff,
        )
        .order_by(models.DailyCheckIn.created_at.desc())
        .all()
    )


def recompute_for_patient(
    db: Session,
    patient_id: int,
    *,
    window_days: int = BASELINE_WINDOW_DAYS,
) -> int:
    """Recompute every metric baseline for one patient.

    Returns the number of rows written or updated. Caller commits — this is
    designed to run inside the same transaction as the check-in insert so a
    rollback wipes both cleanly.
    """
    checkins = _load_recent_checkins(db, patient_id, window_days)
    if not checkins:
        # No data yet — clear any stale rows (e.g. after retention purge) so
        # the client doesn't render a pre-purge mean that no longer reflects
        # the user's actual state.
        deleted = (
            db.query(models.UserBaseline)
            .filter(models.UserBaseline.patient_id == patient_id)
            .delete()
        )
        return deleted

    now = datetime.now(timezone.utc).replace(tzinfo=None)
    latest = checkins[0]

    written = 0
    for metric in BASELINE_METRICS:
        values = [_metric_value(c, metric) for c in checkins]
        sample_count = len(values)
        mean_value = mean(values) if sample_count else 0.0
        # Population stdev: matches the "your normal" framing. sample stdev
        # would over-inflate when we only have ~10 datapoints.
        stdev_value = pstdev(values) if sample_count >= 2 else 0.0
        current_value = _metric_value(latest, metric)

        existing = (
            db.query(models.UserBaseline)
            .filter(
                models.UserBaseline.patient_id == patient_id,
                models.UserBaseline.metric == metric,
            )
            .first()
        )
        if existing is None:
            db.add(
                models.UserBaseline(
                    patient_id=patient_id,
                    metric=metric,
                    window_days=window_days,
                    sample_count=sample_count,
                    mean_value=mean_value,
                    stdev_value=stdev_value,
                    current_value=current_value,
                    computed_at=now,
                )
            )
        else:
            existing.window_days = window_days
            existing.sample_count = sample_count
            existing.mean_value = mean_value
            existing.stdev_value = stdev_value
            existing.current_value = current_value
            existing.computed_at = now
        written += 1
    return written


def _z_score(current: float, mean_value: float, stdev_value: float) -> float:
    if stdev_value <= 0:
        return 0.0
    return (current - mean_value) / stdev_value


def baseline_read(baseline: models.UserBaseline) -> schemas.UserBaselineRead:
    return schemas.UserBaselineRead(
        metric=baseline.metric,  # validated against Literal on serialization
        window_days=baseline.window_days,
        sample_count=baseline.sample_count,
        mean_value=baseline.mean_value,
        stdev_value=baseline.stdev_value,
        current_value=baseline.current_value,
        z_score=_z_score(
            baseline.current_value, baseline.mean_value, baseline.stdev_value
        ),
        computed_at=baseline.computed_at,
    )


def list_for_patient(
    db: Session, patient_id: int
) -> list[schemas.UserBaselineRead]:
    rows = (
        db.query(models.UserBaseline)
        .filter(models.UserBaseline.patient_id == patient_id)
        .order_by(models.UserBaseline.metric.asc())
        .all()
    )
    return [baseline_read(row) for row in rows]


def snapshot_for_intervention(db: Session, patient_id: int) -> dict[str, float]:
    """Compact snapshot of the current baseline row per metric — persisted on
    an intervention log so the delta computation later doesn't depend on the
    ever-shifting rolling window. Only mean is stored (the outcome delta is
    "current − mean at trigger time")."""
    rows = (
        db.query(models.UserBaseline)
        .filter(models.UserBaseline.patient_id == patient_id)
        .all()
    )
    return {row.metric: float(row.mean_value) for row in rows}
