"""Regression suite for the personal-baseline + intervention-log loop.

Covers:
- Baseline rows are created/updated after each check-in.
- Mean and stdev reflect only the rolling 60-day window.
- Interventions with a scored 72h window produce an insight; unscored logs
  count as pending; small samples are withheld until >= MIN_SAMPLES_FOR_INSIGHT.
- Notes persist as PHI (round-trip through encryption).
"""
import json
from datetime import datetime, timedelta, timezone

from .conftest import grant_consent, login, register


PATIENT_PAYLOAD = {
    "mood": 3.0,
    "anxiety": 2.0,
    "energy": 3.0,
    "irritability": 2.0,
    "sleep_hours": 7.0,
    "appetite": 3.0,
    "libido": 3.0,
    "medication_taken": True,
    "side_effects": "",
    "automatic_thoughts": "",
    "suicidal_ideation": False,
    "journal_entry": "",
}


def _bearer(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _post_checkin(client, token: str, **overrides) -> None:
    payload = dict(PATIENT_PAYLOAD)
    payload.update(overrides)
    response = client.post("/v1/checkins", json=payload, headers=_bearer(token))
    assert response.status_code == 200, response.text


# ------------------------------------------------------------ baselines


def test_baselines_created_after_first_checkin(client):
    register(client, email="base1@example.com")
    token = login(client, email="base1@example.com")
    grant_consent(client, token=token)

    _post_checkin(client, token, mood=4.0, anxiety=1.5, sleep_hours=8.0)

    response = client.get("/v1/me/baselines", headers=_bearer(token))
    assert response.status_code == 200
    rows = response.json()
    metrics = {row["metric"]: row for row in rows}
    # All five diary metrics should be present after a single check-in.
    assert set(metrics) == {"mood", "anxiety", "energy", "irritability", "sleep_hours"}
    # Single-sample baselines have stdev 0 and z_score 0 (division-by-zero guarded).
    assert metrics["mood"]["sample_count"] == 1
    assert metrics["mood"]["mean_value"] == 4.0
    assert metrics["mood"]["stdev_value"] == 0.0
    assert metrics["mood"]["z_score"] == 0.0


def test_baseline_mean_reflects_rolling_window(client):
    register(client, email="base2@example.com")
    token = login(client, email="base2@example.com")
    grant_consent(client, token=token)

    _post_checkin(client, token, mood=2.0)
    _post_checkin(client, token, mood=4.0)
    _post_checkin(client, token, mood=3.0)

    baselines = {r["metric"]: r for r in client.get("/v1/me/baselines", headers=_bearer(token)).json()}
    assert baselines["mood"]["sample_count"] == 3
    assert baselines["mood"]["mean_value"] == 3.0
    # Population stdev of {2,4,3} ≈ 0.8165.
    assert 0.8 <= baselines["mood"]["stdev_value"] <= 0.9
    # current_value is the most recent submission (3.0), so z ≈ 0.
    assert abs(baselines["mood"]["z_score"]) < 0.1


def test_baseline_excludes_old_checkins(client):
    """Anything older than the 60d window must not affect the mean. We
    backdate one row directly in the DB then submit a fresh check-in to
    force a recompute."""
    from app import database, models

    register(client, email="base3@example.com")
    token = login(client, email="base3@example.com")
    grant_consent(client, token=token)

    # Old outlier that must be excluded from the rolling window.
    _post_checkin(client, token, mood=0.5)
    with database.SessionLocal() as session:
        row = session.query(models.DailyCheckIn).order_by(
            models.DailyCheckIn.created_at.asc()
        ).first()
        row.created_at = datetime.now(timezone.utc).replace(tzinfo=None) - timedelta(days=90)
        session.commit()

    # Two recent rows that should define the current baseline.
    _post_checkin(client, token, mood=4.0)
    _post_checkin(client, token, mood=4.0)

    baselines = {r["metric"]: r for r in client.get("/v1/me/baselines", headers=_bearer(token)).json()}
    # Only the two recent (mood=4.0) samples inform the mean — outlier dropped.
    assert baselines["mood"]["sample_count"] == 2
    assert baselines["mood"]["mean_value"] == 4.0


def test_baselines_require_patient_role(client, admin_api_key):
    """Clinicians shouldn't be able to hit /me/baselines — the endpoint is
    scoped to the patient viewing their own personalization state."""
    from .conftest import promote_to_clinician

    user = register(client, email="doc@example.com")
    promote_to_clinician(client, user_id=user["user"]["id"], admin_key=admin_api_key)
    token = login(client, email="doc@example.com")

    response = client.get("/v1/me/baselines", headers=_bearer(token))
    assert response.status_code == 403


# ------------------------------------------------------------ interventions


def test_intervention_log_persists_notes_encrypted(client):
    register(client, email="int1@example.com")
    token = login(client, email="int1@example.com")
    grant_consent(client, token=token)

    response = client.post(
        "/v1/me/interventions",
        json={
            "intervention_type": "breathing",
            "trigger_source": "app_suggestion",
            "notes": "5 min diaphragmatic breathing after mood dip",
        },
        headers=_bearer(token),
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["intervention_type"] == "breathing"
    assert body["trigger_source"] == "app_suggestion"
    assert body["notes"] == "5 min diaphragmatic breathing after mood dip"
    assert body["outcome_computed_at"] is None
    assert body["outcome_delta"] is None

    # Confirm PHI is not stored in plaintext on the DB column.
    from app import database, models
    with database.SessionLocal() as session:
        record = session.query(models.InterventionLog).first()
        assert record.notes_encrypted != "5 min diaphragmatic breathing after mood dip"
        assert record.notes_encrypted != ""


def _place_log_and_post_checkin_in_window(
    session,
    models_module,
    log,
    *,
    window_hours_ago: float,
    post_hours_ago: float,
) -> None:
    """Position an intervention log and one existing check-in inside the same
    72h evaluation window.

    Real-world flow: intervention fires → patient checks in 1–3 days later.
    Because the write path stamps ``created_at``/``triggered_at`` with
    ``now``, we can't reproduce that window without touching the DB. This
    helper centralizes the backdating so the intent stays legible in the
    test bodies.
    """
    now_naive = datetime.now(timezone.utc).replace(tzinfo=None)
    log.triggered_at = now_naive - timedelta(hours=window_hours_ago)
    # Find the most recent check-in and drop it inside the window.
    checkin = (
        session.query(models_module.DailyCheckIn)
        .order_by(models_module.DailyCheckIn.created_at.desc())
        .first()
    )
    if checkin is not None:
        checkin.created_at = now_naive - timedelta(hours=post_hours_ago)


def test_intervention_insights_hidden_below_min_samples(client):
    """A single scored outcome is not enough — insights layer withholds until
    at least MIN_SAMPLES_FOR_INSIGHT observations exist per family."""
    from app import database, models
    from app.interventions import compute_pending_outcomes

    register(client, email="int2@example.com")
    token = login(client, email="int2@example.com")
    grant_consent(client, token=token)

    _post_checkin(client, token, mood=2.5)

    client.post(
        "/v1/me/interventions",
        json={"intervention_type": "walk", "trigger_source": "user_manual", "notes": ""},
        headers=_bearer(token),
    )

    _post_checkin(client, token, mood=4.0)

    with database.SessionLocal() as session:
        log = session.query(models.InterventionLog).first()
        patient_id = log.patient_id
        _place_log_and_post_checkin_in_window(
            session, models,
            log,
            window_hours_ago=75,   # triggered 75h ago → window closed
            post_hours_ago=10,     # follow-up check-in sits inside [-75h, -3h]
        )
        session.commit()

        # Score the eligible log directly — mirrors what the check-in write
        # path would do on the next legitimate submission.
        compute_pending_outcomes(session, patient_id)
        session.commit()

    insights = client.get(
        "/v1/me/interventions/insights", headers=_bearer(token)
    ).json()
    assert insights["insights"] == []
    assert insights["pending_outcomes"] == 0


def test_intervention_insight_surfaces_after_min_samples(client):
    """Three scored outcomes with consistent post-trigger mood lift produce
    a surfaced insight flagged is_significant."""
    from app import database, models
    from app.interventions import compute_pending_outcomes

    register(client, email="int3@example.com")
    token = login(client, email="int3@example.com")
    grant_consent(client, token=token)

    # Three baseline-triggering / post-window check-ins, three interventions.
    # We stage them one at a time so each log gets its own follow-up check-in.
    patient_id_holder = {}
    now_naive = datetime.now(timezone.utc).replace(tzinfo=None)

    for i in range(3):
        _post_checkin(client, token, mood=2.0)  # baseline pass
        client.post(
            "/v1/me/interventions",
            json={"intervention_type": "walk", "trigger_source": "user_manual", "notes": ""},
            headers=_bearer(token),
        )
        _post_checkin(client, token, mood=4.5)  # post-trigger

        with database.SessionLocal() as session:
            log = (
                session.query(models.InterventionLog)
                .order_by(models.InterventionLog.id.desc())
                .first()
            )
            patient_id_holder["id"] = log.patient_id
            # Space the three logs out in the past so they don't fight for
            # the same follow-up check-in. Each window is 15h wide well
            # inside the 72h eligibility bound.
            offset_hours = 75 + i * 200
            log.triggered_at = now_naive - timedelta(hours=offset_hours)
            baseline_snapshot = json.loads(log.baseline_snapshot_json)
            baseline_snapshot["mood"] = 2.0
            log.baseline_snapshot_json = json.dumps(baseline_snapshot)
            latest_checkin = (
                session.query(models.DailyCheckIn)
                .order_by(models.DailyCheckIn.created_at.desc())
                .first()
            )
            latest_checkin.created_at = now_naive - timedelta(hours=offset_hours - 10)
            session.commit()

    with database.SessionLocal() as session:
        compute_pending_outcomes(session, patient_id_holder["id"])
        session.commit()

    insights = client.get(
        "/v1/me/interventions/insights", headers=_bearer(token)
    ).json()

    assert insights["pending_outcomes"] == 0
    assert len(insights["insights"]) == 1
    walk = insights["insights"][0]
    assert walk["intervention_type"] == "walk"
    assert walk["sample_size"] == 3
    # Post mood (4.5) − baseline mean at trigger time (2.0) ≈ +2.5 lift.
    assert walk["avg_mood_delta"] >= 2.0
    assert walk["is_significant"] is True


def test_intervention_pending_counts_unscored_logs(client):
    """Logs whose 72h window has not yet closed count as pending, not scored."""
    register(client, email="int4@example.com")
    token = login(client, email="int4@example.com")
    grant_consent(client, token=token)

    _post_checkin(client, token)
    client.post(
        "/v1/me/interventions",
        json={"intervention_type": "journaling", "trigger_source": "user_manual", "notes": ""},
        headers=_bearer(token),
    )

    insights = client.get(
        "/v1/me/interventions/insights", headers=_bearer(token)
    ).json()
    assert insights["pending_outcomes"] == 1
    assert insights["insights"] == []


def test_intervention_list_endpoint_returns_recent(client):
    register(client, email="int5@example.com")
    token = login(client, email="int5@example.com")
    grant_consent(client, token=token)

    for intervention_type in ("breathing", "walk", "journaling"):
        client.post(
            "/v1/me/interventions",
            json={
                "intervention_type": intervention_type,
                "trigger_source": "user_manual",
                "notes": "",
            },
            headers=_bearer(token),
        )

    response = client.get("/v1/me/interventions", headers=_bearer(token))
    assert response.status_code == 200
    body = response.json()
    assert len(body) == 3
    # Newest first ordering — journaling was posted last.
    assert body[0]["intervention_type"] == "journaling"
