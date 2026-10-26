from datetime import datetime, timedelta, timezone

from app import models, schemas
from app.episode_pipeline import detect_episode_events


def _payload(
    *,
    mood=3.5,
    anxiety=2.0,
    energy=3.0,
    irritability=2.0,
    sleep_hours=7.0,
    medication_taken=True,
    suicidal_ideation=False,
):
    return schemas.DailyCheckInCreate(
        mood=mood,
        anxiety=anxiety,
        energy=energy,
        irritability=irritability,
        sleep_hours=sleep_hours,
        appetite=3.0,
        libido=3.0,
        medication_taken=medication_taken,
        side_effects="",
        automatic_thoughts="",
        suicidal_ideation=suicidal_ideation,
        journal_entry="",
    )


def _checkin(day_offset: int, **kwargs):
    payload = _payload(**kwargs)
    return models.DailyCheckIn(
        patient_id=1,
        created_at=datetime.now(timezone.utc) - timedelta(days=day_offset),
        mood=payload.mood,
        anxiety=payload.anxiety,
        energy=payload.energy,
        irritability=payload.irritability,
        sleep_hours=payload.sleep_hours,
        appetite=payload.appetite,
        libido=payload.libido,
        medication_taken=payload.medication_taken,
        side_effects="",
        automatic_thoughts="",
        suicidal_ideation=payload.suicidal_ideation,
        journal_entry="",
    )


def _baseline_history(days: int = 30):
    return [
        _checkin(
            day,
            mood=3.8,
            anxiety=1.8,
            energy=3.4,
            irritability=1.7,
            sleep_hours=7.4,
            medication_taken=True,
        )
        for day in range(8, 8 + days)
    ]


def test_pipeline_detects_mania_prodrome():
    current = _payload(mood=4.2, anxiety=2.0, energy=4.5, irritability=4.2, sleep_hours=4.8)
    previous = [
        _checkin(day, mood=4.0, energy=4.4, irritability=4.1, sleep_hours=5.0)
        for day in range(1, 6)
    ] + _baseline_history()

    events = detect_episode_events(current=current, previous=previous, assessments=[])

    assert any(event.detector_key == "mania_prodrome" for event in events)
    assert all(event.alert_type == models.AlertType.clinical_watch for event in events if event.detector_key == "mania_prodrome")


def test_pipeline_detects_sustained_mood_emergency():
    current = _payload(mood=1.0)
    previous = [_checkin(1, mood=1.0), *_baseline_history()]

    events = detect_episode_events(current=current, previous=previous, assessments=[])

    emergency = next(event for event in events if event.detector_key == "suicide_or_sustained_mood_crash")
    assert emergency.alert_type == models.AlertType.psychiatric_emergency
    assert emergency.escalation_target == models.EscalationTarget.clinician_caregiver_now


def test_pipeline_detects_low_adherence_and_circadian_shift():
    current = _payload(sleep_hours=4.7, medication_taken=False)
    previous = [
        _checkin(day, sleep_hours=4.5 if day % 2 else 8.8, medication_taken=(day % 3 == 0))
        for day in range(1, 14)
    ] + _baseline_history()

    events = detect_episode_events(current=current, previous=previous, assessments=[])
    keys = {event.detector_key for event in events}

    assert "low_adherence_14d" in keys
    assert "circadian_shift" in keys


def test_pipeline_compares_with_previous_real_episode():
    current = _payload(mood=3.0, anxiety=4.1, energy=2.6, irritability=3.4, sleep_hours=6.0)
    current_window = [
        _checkin(day, mood=3.0, anxiety=4.0, energy=2.6, irritability=3.4, sleep_hours=6.0)
        for day in range(1, 14)
    ]
    older_baseline = _baseline_history(20)
    antecedent = [
        _checkin(day, mood=3.0, anxiety=4.0, energy=2.6, irritability=3.4, sleep_hours=6.0)
        for day in range(40, 54)
    ]
    episode = [
        _checkin(day, mood=2.8, anxiety=4.5, energy=2.4, irritability=3.8, sleep_hours=5.8)
        for day in range(33, 40)
    ]
    previous = current_window + older_baseline + episode + antecedent

    events = detect_episode_events(current=current, previous=previous, assessments=[])

    assert any(event.detector_key.startswith("historical_match_") for event in events)
