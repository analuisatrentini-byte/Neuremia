"""Temporal episode detection for typed clinical alerts.

This is intentionally deterministic and auditable. It is not a diagnosis and
does not replace a trained model; it turns longitudinal windows into typed
events so notification routing is driven by event semantics, not risk_score.
"""
from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from math import sqrt
from statistics import mean, pstdev

from . import models, schemas


@dataclass(frozen=True)
class EpisodeAlertEvent:
    level: str
    alert_type: models.AlertType
    escalation_target: models.EscalationTarget
    title: str
    message: str
    detector_key: str


CheckInLike = schemas.DailyCheckInCreate | models.DailyCheckIn


def detect_episode_events(
    *,
    current: schemas.DailyCheckInCreate,
    previous: list[models.DailyCheckIn],
    assessments: list[models.ScaleAssessment],
    now: datetime | None = None,
) -> list[EpisodeAlertEvent]:
    reference_now = now or datetime.now(timezone.utc)
    records = [current, *previous]
    events: list[EpisodeAlertEvent] = []

    sustained_mood_crash = _count(records[:3], lambda item: _value(item, "mood") <= 1.0) >= 2
    if current.suicidal_ideation or sustained_mood_crash:
        events.append(EpisodeAlertEvent(
            level="high",
            alert_type=models.AlertType.psychiatric_emergency,
            escalation_target=models.EscalationTarget.clinician_caregiver_now,
            title="Emergência psiquiátrica",
            message=(
                "Ideação suicida ou humor ≤1 sustentado nos últimos registros "
                "exige revisão imediata e plano de segurança."
            ),
            detector_key="suicide_or_sustained_mood_crash",
        ))

    ymrs_acute = next(
        (
            assessment for assessment in assessments
            if assessment.scale_name == "YMRS"
            and assessment.score >= 22
            and _days_between(assessment.created_at, reference_now) <= 14
        ),
        None,
    )
    if ymrs_acute is not None:
        events.append(EpisodeAlertEvent(
            level="high",
            alert_type=models.AlertType.psychiatric_emergency,
            escalation_target=models.EscalationTarget.clinician_caregiver_now,
            title="YMRS em faixa de mania aguda",
            message="YMRS ≥22 em avaliação recente requer avaliação clínica imediata.",
            detector_key="ymrs_acute_mania",
        ))

    baseline = _baseline(records)
    recent7 = records[:7]
    recent14 = records[:14]

    if len(recent7) >= 4:
        mania_evidence = _mania_prodrome(recent7, baseline)
        if mania_evidence:
            events.append(_watch_event(
                "Pródromo de mania",
                f"Janela recente sugere ativação com risco de mania: {mania_evidence}.",
                "mania_prodrome",
            ))

        depression_evidence = _depressive_relapse(recent7, baseline)
        if depression_evidence:
            events.append(_watch_event(
                "Possível recaída depressiva",
                f"Janela recente sugere recaída depressiva: {depression_evidence}.",
                "depressive_relapse",
            ))

        anxiety_evidence = _anxiety_crisis(recent7, baseline)
        if anxiety_evidence:
            events.append(_watch_event(
                "Crise de ansiedade em evolução",
                f"Janela recente sugere ansiedade em escalada: {anxiety_evidence}.",
                "anxiety_crisis",
            ))

        circadian_evidence = _circadian_shift(recent7, baseline)
        if circadian_evidence:
            events.append(_watch_event(
                "Alteração circadiana",
                f"Sono recente saiu do padrão pessoal: {circadian_evidence}.",
                "circadian_shift",
            ))

    if len(recent14) >= 7:
        adherence = _mean([1.0 if _value(item, "medication_taken") else 0.0 for item in recent14])
        if adherence < 0.60:
            events.append(_watch_event(
                "Adesão abaixo de 60%",
                f"Adesão medicamentosa em 14 dias: {round(adherence * 100)}%.",
                "low_adherence_14d",
            ))

        past_match = _match_previous_episode(records)
        if past_match is not None:
            kind, probability = past_match
            events.append(_watch_event(
                "Padrão semelhante a episódio anterior",
                (
                    f"Os últimos 14 dias se parecem com a janela que precedeu "
                    f"um episódio prévio de {kind}. Probabilidade heurística "
                    f"de piora em 7 dias: {probability}%."
                ),
                f"historical_match_{kind}",
            ))

    return _dedupe_by_key(events)


def _watch_event(title: str, message: str, key: str) -> EpisodeAlertEvent:
    return EpisodeAlertEvent(
        level="moderate",
        alert_type=models.AlertType.clinical_watch,
        escalation_target=models.EscalationTarget.clinician_digest,
        title=title,
        message=message,
        detector_key=key,
    )


def _mania_prodrome(recent: list[CheckInLike], baseline: dict[str, tuple[float, float]]) -> str | None:
    sleep_avg = _metric_mean(recent, "sleep_hours")
    energy_avg = _metric_mean(recent, "energy")
    irritability_avg = _metric_mean(recent, "irritability")
    mood_avg = _metric_mean(recent, "mood")
    sleep_drop = _z("sleep_hours", sleep_avg, baseline) <= -1.3 or sleep_avg < 5.5
    activation = (
        _z("energy", energy_avg, baseline) >= 1.0
        or _z("irritability", irritability_avg, baseline) >= 1.0
        or (energy_avg >= 4.0 and mood_avg >= 3.8)
    )
    if sleep_drop and activation:
        return (
            f"sono médio {sleep_avg:.1f}h, energia {energy_avg:.1f}, "
            f"irritabilidade {irritability_avg:.1f}"
        )
    return None


def _depressive_relapse(recent: list[CheckInLike], baseline: dict[str, tuple[float, float]]) -> str | None:
    mood_avg = _metric_mean(recent, "mood")
    energy_avg = _metric_mean(recent, "energy")
    sleep_avg = _metric_mean(recent, "sleep_hours")
    mood_drop = _z("mood", mood_avg, baseline) <= -1.3 or mood_avg <= 2.2
    low_energy = _z("energy", energy_avg, baseline) <= -1.0 or energy_avg <= 2.2
    sleep_disrupted = sleep_avg < 6.0 or sleep_avg > 9.0
    if mood_drop and (low_energy or sleep_disrupted):
        return f"humor médio {mood_avg:.1f}, energia {energy_avg:.1f}, sono {sleep_avg:.1f}h"
    return None


def _anxiety_crisis(recent: list[CheckInLike], baseline: dict[str, tuple[float, float]]) -> str | None:
    anxiety3 = recent[:3]
    anxiety_avg3 = _metric_mean(anxiety3, "anxiety")
    anxiety_avg7 = _metric_mean(recent, "anxiety")
    irritability_avg = _metric_mean(recent, "irritability")
    if anxiety_avg3 >= 4.3 or (_z("anxiety", anxiety_avg7, baseline) >= 1.4 and anxiety_avg7 >= 3.5):
        return f"ansiedade 3d {anxiety_avg3:.1f}, ansiedade 7d {anxiety_avg7:.1f}, irritabilidade {irritability_avg:.1f}"
    return None


def _circadian_shift(recent: list[CheckInLike], baseline: dict[str, tuple[float, float]]) -> str | None:
    sleeps = [_value(item, "sleep_hours") for item in recent]
    sleep_avg = _mean(sleeps)
    sleep_sd = pstdev(sleeps) if len(sleeps) >= 2 else 0.0
    short_sleep_days = sum(1 for value in sleeps if value < 5.5)
    baseline_sleep = baseline.get("sleep_hours", (7.0, 1.0))[0]
    if short_sleep_days >= 3 or sleep_sd >= 1.75 or abs(sleep_avg - baseline_sleep) >= 1.5:
        return f"sono médio {sleep_avg:.1f}h, variação {sleep_sd:.1f}h, {short_sleep_days} dias <5,5h"
    return None


def _match_previous_episode(records: list[CheckInLike]) -> tuple[str, int] | None:
    if len(records) < 45:
        return None

    ascending = list(reversed(records))
    current = _window_vector(list(reversed(records[:14])))
    best_kind = ""
    best_score = 0.0

    for idx in range(14, len(ascending) - 7):
        future = ascending[idx:idx + 7]
        kind = _episode_kind(future)
        if kind is None:
            continue
        antecedent = ascending[max(0, idx - 14):idx]
        if len(antecedent) < 7:
            continue
        similarity = _similarity(current, _window_vector(antecedent))
        if similarity > best_score:
            best_score = similarity
            best_kind = kind

    if best_score >= 0.78:
        probability = int(min(88, max(62, round(35 + best_score * 55))))
        return best_kind, probability
    return None


def _episode_kind(window: list[CheckInLike]) -> str | None:
    if _count(window, lambda item: _value(item, "suicidal_ideation")) > 0:
        return "risco suicida"
    if _metric_mean(window, "mood") <= 2.0 and _metric_mean(window, "energy") <= 2.4:
        return "recaída depressiva"
    if _metric_mean(window, "anxiety") >= 4.0:
        return "ansiedade"
    if _metric_mean(window, "sleep_hours") < 5.7 and (
        _metric_mean(window, "energy") >= 3.8 or _metric_mean(window, "irritability") >= 3.8
    ):
        return "mania"
    return None


def _window_vector(window: list[CheckInLike]) -> list[float]:
    return [
        _metric_mean(window, "mood"),
        _metric_mean(window, "anxiety"),
        _metric_mean(window, "energy"),
        _metric_mean(window, "irritability"),
        _metric_mean(window, "sleep_hours"),
        _mean([1.0 if _value(item, "medication_taken") else 0.0 for item in window]),
    ]


def _similarity(lhs: list[float], rhs: list[float]) -> float:
    weights = [1.0, 1.0, 0.8, 0.8, 0.7, 0.6]
    distance = sqrt(sum(((a - b) * w) ** 2 for a, b, w in zip(lhs, rhs, weights)))
    return max(0.0, 1.0 - distance / 7.0)


def _baseline(records: list[CheckInLike]) -> dict[str, tuple[float, float]]:
    historical = records[7:67]
    if len(historical) < 14:
        historical = records[7:]
    result: dict[str, tuple[float, float]] = {}
    for metric in ["mood", "anxiety", "energy", "irritability", "sleep_hours"]:
        values = [_value(item, metric) for item in historical]
        if values:
            avg = _mean(values)
            sd = max(pstdev(values), 0.5)
            result[metric] = (avg, sd)
    return result


def _z(metric: str, value: float, baseline: dict[str, tuple[float, float]]) -> float:
    center, sd = baseline.get(metric, (value, 1.0))
    return (value - center) / max(sd, 0.5)


def _metric_mean(records: list[CheckInLike], metric: str) -> float:
    return _mean([_value(item, metric) for item in records])


def _mean(values: list[float]) -> float:
    return mean(values) if values else 0.0


def _count(records: list[CheckInLike], predicate) -> int:
    return sum(1 for item in records if predicate(item))


def _value(record: CheckInLike, field: str):
    return getattr(record, field)


def _days_between(start: datetime, end: datetime) -> int:
    if start.tzinfo is None and end.tzinfo is not None:
        end = end.replace(tzinfo=None)
    elif start.tzinfo is not None and end.tzinfo is None:
        start = start.replace(tzinfo=None)
    return abs((end - start).days)


def _dedupe_by_key(events: list[EpisodeAlertEvent]) -> list[EpisodeAlertEvent]:
    seen: set[str] = set()
    result: list[EpisodeAlertEvent] = []
    for event in events:
        if event.detector_key in seen:
            continue
        seen.add(event.detector_key)
        result.append(event)
    return result
