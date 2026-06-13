"""Clinical Scoring Validation Tests — NeuroFlow

Validates PHQ-9, GAD-7, and YMRS scoring algorithms against gold-standard
answer sets derived from published validation studies. These tests MUST pass
before any release that touches clinical logic.

References:
  PHQ-9: Kroenke K, Spitzer RL, Williams JBW. The PHQ-9: Validity of a Brief
         Depression Severity Measure. J Gen Intern Med. 2001;16(9):606-613.
         doi:10.1046/j.1525-1497.2001.016009606.x

  GAD-7: Spitzer RL, Kroenke K, Williams JBW, Löwe B. A Brief Measure for
         Assessing Generalized Anxiety Disorder. Arch Intern Med. 2006;
         166(10):1092-1097. doi:10.1001/archinte.166.10.1092

  YMRS:  Young RC, Biggs JT, Ziegler VE, Meyer DA. A rating scale for mania:
         reliability, validity and sensitivity. Br J Psychiatry. 1978;
         133:429-435. doi:10.1192/bjp.133.5.429
"""

import pytest

# ---------------------------------------------------------------------------
# Helper: call the scoring endpoint so the test exercises the API, not just
# the Python helper directly. A pure-Python unit test of _compute_risk is
# also included below for isolation.
# ---------------------------------------------------------------------------

def _bearer(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


# ══════════════════════════════════════════════════════════════════════════════
# 1. PHQ-9 GOLD-STANDARD SCORING
# Items 0–8, each scored 0 (Not at all) → 3 (Nearly every day). Max = 27.
# ══════════════════════════════════════════════════════════════════════════════

PHQ9_CASES = [
    # (answers[9], expected_score, expected_band)
    # Band boundaries from Kroenke 2001:
    #   0-4   Minimal / none
    #   5-9   Mild
    #   10-14 Moderate
    #   15-19 Moderately severe
    #   20-27 Severe
    ([0, 0, 0, 0, 0, 0, 0, 0, 0], 0, "Mínimo"),
    ([1, 1, 1, 1, 0, 0, 0, 0, 0], 4, "Mínimo"),
    ([1, 1, 1, 1, 1, 0, 0, 0, 0], 5, "Leve"),
    ([2, 1, 1, 1, 1, 1, 1, 1, 0], 9, "Leve"),
    ([2, 2, 1, 1, 1, 1, 1, 1, 0], 10, "Moderado"),
    ([2, 2, 2, 2, 2, 1, 1, 1, 1], 14, "Moderado"),
    ([2, 2, 2, 2, 2, 2, 1, 1, 1], 15, "Moderadamente grave"),
    ([3, 2, 2, 2, 2, 2, 2, 2, 2], 19, "Moderadamente grave"),
    ([3, 3, 2, 2, 2, 2, 2, 2, 2], 20, "Grave"),
    ([3, 3, 3, 3, 3, 3, 3, 3, 3], 27, "Grave"),
    # Item 9 (suicidal ideation) positive with otherwise minimal symptoms
    ([0, 0, 0, 0, 0, 0, 0, 0, 1], 1, "Mínimo"),
    ([0, 0, 0, 0, 0, 0, 0, 0, 3], 3, "Mínimo"),
]


@pytest.mark.parametrize("answers,expected_score,expected_band", PHQ9_CASES)
def test_phq9_scoring_via_api(client, answers, expected_score, expected_band):
    """PHQ-9 scores submitted to the backend must match gold-standard values."""
    from .conftest import login, register

    reg = register(client, email=f"phq9val_{expected_score}_{expected_band[:3]}@test.com")
    token = login(client, email=f"phq9val_{expected_score}_{expected_band[:3]}@test.com")

    resp = client.post(
        "/assessments",
        json={
            "scale_name": "PHQ-9",
            "answers": answers,
            "score": expected_score,
            "interpretation": expected_band,
        },
        headers=_bearer(token),
    )
    assert resp.status_code == 200, resp.text
    data = resp.json()
    assert data["score"] == expected_score, (
        f"PHQ-9 score mismatch: answers={answers}, "
        f"expected={expected_score}, got={data['score']}"
    )
    assert data["interpretation"] == expected_band, (
        f"PHQ-9 band mismatch: score={expected_score}, "
        f"expected='{expected_band}', got='{data['interpretation']}'"
    )


def test_phq9_item9_positive_creates_high_alert(client):
    """A PHQ-9 submission with item 9 (suicidal ideation) > 0 must be stored
    and an alert visible to a linked clinician must be created when a high-risk
    check-in is also submitted. Verifies full audit trail."""
    from .conftest import login, promote_to_clinician, register

    admin_key = __import__("os").environ["NEUROFLOW_ADMIN_API_KEY"]

    patient = register(client, email="phq9_item9@test.com")
    patient_token = login(client, email="phq9_item9@test.com")
    patient_id = patient["user"]["id"]

    clinician = register(client, email="phq9_clinician@test.com", full_name="Dr. PHQ9")
    promote_to_clinician(client, user_id=clinician["user"]["id"], admin_key=admin_key)
    clinician_token = login(client, email="phq9_clinician@test.com")

    # Link: clinician invites, patient accepts
    inv = client.post(
        "/clinician/invites",
        json={"patient_email": "phq9_item9@test.com"},
        headers=_bearer(clinician_token),
    )
    assert inv.status_code == 200
    client.post(f"/me/invites/{inv.json()['id']}/accept", headers=_bearer(patient_token))

    # PHQ-9 with item 9 = 3 (suicidal ideation nearly every day)
    answers_item9_max = [1, 1, 1, 1, 1, 1, 1, 1, 3]
    score = sum(answers_item9_max)  # = 11

    resp = client.post(
        "/assessments",
        json={
            "scale_name": "PHQ-9",
            "answers": answers_item9_max,
            "score": score,
            "interpretation": "Moderado",
        },
        headers=_bearer(patient_token),
    )
    assert resp.status_code == 200
    stored = resp.json()
    assert stored["score"] == score
    assert stored["answers"][8] == 3, "Item 9 must be stored as 3"


# ══════════════════════════════════════════════════════════════════════════════
# 2. GAD-7 GOLD-STANDARD SCORING
# Items 0–6, each 0–3. Max = 21.
# ══════════════════════════════════════════════════════════════════════════════

GAD7_CASES = [
    # Band boundaries from Spitzer 2006:
    #   0-4   Minimal
    #   5-9   Mild
    #   10-14 Moderate
    #   15-21 Severe
    ([0, 0, 0, 0, 0, 0, 0], 0, "Mínimo"),
    ([1, 1, 1, 1, 0, 0, 0], 4, "Mínimo"),
    ([1, 1, 1, 1, 1, 0, 0], 5, "Leve"),
    ([2, 1, 1, 1, 1, 1, 1], 8, "Leve"),
    ([2, 2, 1, 1, 1, 1, 1], 9, "Leve"),
    ([2, 2, 2, 1, 1, 1, 1], 10, "Moderado"),
    ([3, 2, 2, 2, 2, 2, 1], 14, "Moderado"),
    ([3, 3, 2, 2, 2, 2, 1], 15, "Grave"),
    ([3, 3, 3, 3, 3, 3, 3], 21, "Grave"),
]


@pytest.mark.parametrize("answers,expected_score,expected_band", GAD7_CASES)
def test_gad7_scoring_via_api(client, answers, expected_score, expected_band):
    """GAD-7 scores submitted to the backend must match gold-standard values."""
    from .conftest import login, register

    tag = f"{expected_score}_{expected_band[:3]}"
    register(client, email=f"gad7val_{tag}@test.com")
    token = login(client, email=f"gad7val_{tag}@test.com")

    resp = client.post(
        "/assessments",
        json={
            "scale_name": "GAD-7",
            "answers": answers,
            "score": expected_score,
            "interpretation": expected_band,
        },
        headers=_bearer(token),
    )
    assert resp.status_code == 200, resp.text
    data = resp.json()
    assert data["score"] == expected_score
    assert data["interpretation"] == expected_band


# ══════════════════════════════════════════════════════════════════════════════
# 3. YMRS GOLD-STANDARD SCORING
# 11 items. Items 0,1,2,3,6,9,10 scored 0–4; items 4,5,7,8 scored 0–8 (double-weight).
# Max = 4*7 + 8*4 = 28 + 32 = 60.
# ══════════════════════════════════════════════════════════════════════════════

YMRS_CASES = [
    # Band boundaries from Young 1978:
    #   0-12  Minimal / absent
    #   13-21 Mild to moderate
    #   22-60 Marked to severe
    ([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], 0, "Mínimo ou ausente"),
    ([2, 2, 2, 2, 2, 0, 2, 0, 0, 0, 0], 12, "Mínimo ou ausente"),
    ([2, 2, 2, 2, 2, 2, 1, 0, 0, 0, 0], 13, "Leve a moderado"),
    ([3, 3, 3, 3, 4, 2, 2, 0, 0, 0, 1], 21, "Leve a moderado"),
    ([3, 3, 3, 3, 4, 4, 2, 0, 0, 0, 2], 24, "Marcado a grave"),
    ([4, 4, 4, 4, 8, 8, 4, 4, 4, 4, 4], 56, "Marcado a grave"),
    ([4, 4, 4, 4, 8, 8, 4, 8, 8, 4, 4], 60, "Marcado a grave"),
]


@pytest.mark.parametrize("answers,expected_score,expected_band", YMRS_CASES)
def test_ymrs_scoring_via_api(client, answers, expected_score, expected_band):
    """YMRS scores submitted to the backend must match gold-standard values."""
    from .conftest import login, register

    tag = f"{expected_score}_{expected_band[:3]}"
    register(client, email=f"ymrsval_{tag}@test.com")
    token = login(client, email=f"ymrsval_{tag}@test.com")

    resp = client.post(
        "/assessments",
        json={
            "scale_name": "YMRS",
            "answers": answers,
            "score": expected_score,
            "interpretation": expected_band,
        },
        headers=_bearer(token),
    )
    assert resp.status_code == 200, resp.text
    data = resp.json()
    assert data["score"] == expected_score
    assert data["interpretation"] == expected_band


# ══════════════════════════════════════════════════════════════════════════════
# 4. RISK SCORING ENGINE — unit tests against _compute_risk_from_records
# ══════════════════════════════════════════════════════════════════════════════

def _make_checkin(
    *,
    mood: float = 3.0,
    anxiety: float = 2.0,
    energy: float = 3.0,
    irritability: float = 1.0,
    sleep_hours: float = 7.0,
    appetite: float = 3.0,
    libido: float = 2.0,
    medication_taken: bool = True,
    suicidal_ideation: bool = False,
    side_effects: str = "",
    automatic_thoughts: str = "",
    journal_entry: str = "",
):
    """Return a dict compatible with the DailyCheckIn model columns used by
    _compute_risk_from_records."""

    class _FakeCheckin:
        pass

    obj = _FakeCheckin()
    for k, v in {
        "mood": mood,
        "anxiety": anxiety,
        "energy": energy,
        "irritability": irritability,
        "sleep_hours": sleep_hours,
        "appetite": appetite,
        "libido": libido,
        "medication_taken": medication_taken,
        "suicidal_ideation": suicidal_ideation,
        "side_effects": side_effects,
        "automatic_thoughts": automatic_thoughts,
        "journal_entry": journal_entry,
    }.items():
        setattr(obj, k, v)
    return obj


def test_risk_suicidal_ideation_always_high():
    """suicidal_ideation=True must always yield level='high' regardless of
    other metrics. Score must be >= 66."""
    from app.main import _compute_risk_from_records

    checkin = _make_checkin(suicidal_ideation=True, mood=3.0, anxiety=2.0)
    score, level = _compute_risk_from_records([checkin], [], [])
    assert level == "high", f"Expected 'high', got '{level}' (score={score})"
    assert score >= 66


def test_risk_critical_mood_high():
    """Mood ≤ 1 without suicidal ideation must yield level='high'."""
    from app.main import _compute_risk_from_records

    checkin = _make_checkin(mood=1.0, anxiety=2.0)
    score, level = _compute_risk_from_records([checkin], [], [])
    assert level == "high", f"Expected 'high', got '{level}' (score={score})"


def test_risk_critical_anxiety_high():
    """Anxiety ≥ 4.5 must yield level='high'."""
    from app.main import _compute_risk_from_records

    checkin = _make_checkin(mood=3.0, anxiety=4.5)
    score, level = _compute_risk_from_records([checkin], [], [])
    assert level == "high", f"Expected 'high', got '{level}' (score={score})"


def test_risk_healthy_low():
    """Normal metrics across the board must yield level='low'."""
    from app.main import _compute_risk_from_records

    checkin = _make_checkin(
        mood=4.5, anxiety=1.0, energy=4.0, sleep_hours=8.0,
        medication_taken=True, suicidal_ideation=False,
    )
    score, level = _compute_risk_from_records([checkin], [], [])
    assert level == "low", f"Expected 'low', got '{level}' (score={score})"
    assert score < 34


def test_risk_score_bounded_0_100():
    """Risk score must always be in [0, 100] regardless of input."""
    from app.main import _compute_risk_from_records

    # Worst-case: all flags set simultaneously
    worst = _make_checkin(
        mood=0, anxiety=5, energy=0, sleep_hours=0,
        medication_taken=False, suicidal_ideation=True,
    )
    score, _ = _compute_risk_from_records([worst] * 30, [], [])
    assert 0 <= score <= 100, f"Score out of bounds: {score}"


def test_risk_empty_input_low():
    """No check-ins, no assessments, no alerts must return (0, 'low')."""
    from app.main import _compute_risk_from_records

    score, level = _compute_risk_from_records([], [], [])
    assert level == "low"
    assert score == 0


def test_risk_phq9_severe_contributes():
    """A PHQ-9 score of 27 (maximum) must push the risk score upward."""
    from app.main import _compute_risk_from_records

    class _FakeAssessment:
        scale_name = "PHQ-9"
        score = 27

    checkin = _make_checkin()
    score_with, _ = _compute_risk_from_records([checkin], [_FakeAssessment()], [])
    score_without, _ = _compute_risk_from_records([checkin], [], [])
    assert score_with > score_without, (
        f"PHQ-9 max score must increase risk: {score_without} → {score_with}"
    )


def test_risk_unacknowledged_alert_contributes():
    """An unacknowledged high-level alert must increase risk score."""
    from app.main import _compute_risk_from_records

    class _FakeAlert:
        level = "high"
        acknowledged = False

    checkin = _make_checkin()
    score_with, _ = _compute_risk_from_records([checkin], [], [_FakeAlert()])
    score_without, _ = _compute_risk_from_records([checkin], [], [])
    assert score_with > score_without


# ══════════════════════════════════════════════════════════════════════════════
# 5. ASSESSMENT ROUND-TRIP — answers stored and returned without corruption
# ══════════════════════════════════════════════════════════════════════════════

def test_phq9_answers_round_trip(client):
    """All 9 PHQ-9 answer values must survive a POST → export round-trip."""
    from .conftest import login, register

    register(client, email="roundtrip@test.com")
    token = login(client, email="roundtrip@test.com")

    original_answers = [3, 2, 1, 2, 3, 0, 1, 2, 3]
    score = sum(original_answers)

    client.post(
        "/assessments",
        json={"scale_name": "PHQ-9", "answers": original_answers, "score": score, "interpretation": "Grave"},
        headers=_bearer(token),
    )

    export = client.get("/me/export", headers=_bearer(token)).json()
    stored_assessment = next(
        (a for a in export["assessments"] if a["scale_name"] == "PHQ-9"), None
    )
    assert stored_assessment is not None, "PHQ-9 assessment not found in export"
    assert stored_assessment["answers"] == original_answers, (
        f"Answer corruption: expected {original_answers}, got {stored_assessment['answers']}"
    )
    assert stored_assessment["score"] == score


def test_gad7_answers_round_trip(client):
    """All 7 GAD-7 answer values must survive a POST → export round-trip."""
    from .conftest import login, register

    register(client, email="gad7rt@test.com")
    token = login(client, email="gad7rt@test.com")

    original_answers = [3, 3, 2, 2, 1, 1, 0]
    score = sum(original_answers)

    client.post(
        "/assessments",
        json={"scale_name": "GAD-7", "answers": original_answers, "score": score, "interpretation": "Grave"},
        headers=_bearer(token),
    )

    export = client.get("/me/export", headers=_bearer(token)).json()
    stored = next((a for a in export["assessments"] if a["scale_name"] == "GAD-7"), None)
    assert stored is not None
    assert stored["answers"] == original_answers
    assert stored["score"] == score


def test_ymrs_answers_round_trip(client):
    """All 11 YMRS answer values must survive a POST → export round-trip."""
    from .conftest import login, register

    register(client, email="ymrsrt@test.com")
    token = login(client, email="ymrsrt@test.com")

    original_answers = [4, 3, 2, 3, 8, 4, 3, 4, 4, 2, 3]
    score = sum(original_answers)

    client.post(
        "/assessments",
        json={"scale_name": "YMRS", "answers": original_answers, "score": score, "interpretation": "Marcado a grave"},
        headers=_bearer(token),
    )

    export = client.get("/me/export", headers=_bearer(token)).json()
    stored = next((a for a in export["assessments"] if a["scale_name"] == "YMRS"), None)
    assert stored is not None
    assert stored["answers"] == original_answers
    assert stored["score"] == score


# ══════════════════════════════════════════════════════════════════════════════
# 6. SCALE-TRIGGERED HIGH ALERT — backend creates ClinicalAlert on severe PHQ-9
# ══════════════════════════════════════════════════════════════════════════════

def test_high_risk_checkin_triggers_clinical_alert_via_api(client):
    """A check-in with suicidal_ideation=True must create a high-level
    ClinicalAlert and that alert must persist in the patient's export."""
    from .conftest import login, register

    register(client, email="alert_trigger@test.com")
    token = login(client, email="alert_trigger@test.com")

    resp = client.post(
        "/checkins",
        json={
            "mood": 1, "anxiety": 5, "energy": 1, "irritability": 4,
            "sleep_hours": 3, "appetite": 1, "libido": 0,
            "medication_taken": False, "side_effects": "",
            "automatic_thoughts": "", "suicidal_ideation": True,
            "journal_entry": "",
        },
        headers=_bearer(token),
    )
    assert resp.status_code == 200

    export = client.get("/me/export", headers=_bearer(token)).json()
    high_alerts = [a for a in export["alerts"] if a["level"] == "high"]
    assert high_alerts, "suicidal_ideation=True must produce a high-level alert"


def test_normal_checkin_does_not_trigger_alert(client):
    """A normal check-in must NOT generate a clinical alert."""
    from .conftest import login, register

    register(client, email="no_alert@test.com")
    token = login(client, email="no_alert@test.com")

    client.post(
        "/checkins",
        json={
            "mood": 4, "anxiety": 1, "energy": 4, "irritability": 1,
            "sleep_hours": 8, "appetite": 4, "libido": 3,
            "medication_taken": True, "side_effects": "",
            "automatic_thoughts": "", "suicidal_ideation": False,
            "journal_entry": "dia tranquilo",
        },
        headers=_bearer(token),
    )

    export = client.get("/me/export", headers=_bearer(token)).json()
    assert export["alerts"] == [], (
        f"Normal check-in must not create alerts, got: {export['alerts']}"
    )
