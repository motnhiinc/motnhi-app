import uuid
from datetime import datetime, timezone

from sqlalchemy import event, func, select

from app.models import (
    ArScene,
    ChildProfile,
    ConsentEvent,
    Device,
    InteractionEvent,
    NarrationSegment,
    PrivacySettings,
    Question,
    QuestionChoice,
    Story,
    StoryPage,
    StorySession,
    User,
)
from app.services import child_data_deletion

EXPECTED_DELETE_ORDER = [
    "interaction_events",
    "story_sessions",
    "question_choices",
    "questions",
    "ar_scenes",
    "narration_segments",
    "story_pages",
    "stories",
    "child_profiles",
    "consent_events",
    "privacy_settings",
]


def _populate(db, user_id, with_user=True):
    now = datetime.now(timezone.utc)
    if with_user:
        db.add(User(
            id=user_id,
            email=None,
            auth_provider="device",
            created_at=now,
            updated_at=now,
        ))
    ids = {
        "user_id": user_id,
        "device_id": str(uuid.uuid4()),
        "profile_id": str(uuid.uuid4()),
        "story_id": str(uuid.uuid4()),
        "page_id": str(uuid.uuid4()),
        "segment_id": str(uuid.uuid4()),
        "scene_id": str(uuid.uuid4()),
        "question_id": str(uuid.uuid4()),
        "choice_id": str(uuid.uuid4()),
        "choice2_id": str(uuid.uuid4()),
        "curated_story_id": str(uuid.uuid4()),
        "curated_page_id": str(uuid.uuid4()),
        "curated_segment_id": str(uuid.uuid4()),
        "curated_question_id": str(uuid.uuid4()),
        "curated_choice_id": str(uuid.uuid4()),
        "session_id": str(uuid.uuid4()),
        "curated_session_id": str(uuid.uuid4()),
        "event_id": str(uuid.uuid4()),
        "curated_event_id": str(uuid.uuid4()),
        "consent_id": str(uuid.uuid4()),
        "consent2_id": str(uuid.uuid4()),
    }

    # No ORM relationships link these tables, so the unit of work will not
    # order INSERTs across them: flush after each FK dependency level.
    db.flush()

    db.add(Device(
        id=ids["device_id"],
        device_id=f"dev-{ids['device_id'][:8]}",
        user_id=user_id,
        secret_hash="hash",
        created_at=now,
    ))
    db.add(ChildProfile(
        id=ids["profile_id"],
        user_id=user_id,
        nickname=None,
        age_band="3-4",
        language_code="en",
        bedtime_mode_default=False,
        microphone_enabled=False,
        ar_enabled=True,
        created_at=now,
        updated_at=now,
    ))
    db.add(Story(
        id=ids["story_id"],
        title="authored",
        slug=ids["story_id"],
        description=None,
        age_min=3,
        age_max=8,
        language_code="en",
        duration_seconds=60,
        cover_asset_id=None,
        content_status="published",
        rights_owner_id=None,
        themes=[],
        owner_user_id=user_id,
    ))
    db.add(Story(
        id=ids["curated_story_id"],
        title="curated",
        slug=ids["curated_story_id"],
        description=None,
        age_min=3,
        age_max=8,
        language_code="en",
        duration_seconds=60,
        cover_asset_id=None,
        content_status="published",
        rights_owner_id=None,
        themes=[],
        owner_user_id=None,
    ))
    db.add(ConsentEvent(
        id=ids["consent_id"], user_id=user_id, scope="core_storage",
        granted=True, policy_version="2026-08-28", created_at=now,
    ))
    db.add(ConsentEvent(
        id=ids["consent2_id"], user_id=user_id, scope="cloud_tts",
        granted=False, policy_version="2026-08-28", created_at=now,
    ))
    # Device registration (API tests) may have already created the default
    # settings row: update it in place instead of inserting a duplicate.
    settings = db.get(PrivacySettings, user_id)
    if settings is None:
        settings = PrivacySettings(user_id=user_id)
        db.add(settings)
    settings.accepted_policy_version = "2026-08-28"
    settings.core_storage_accepted_at = now
    settings.progress_tracking_enabled = True
    settings.cloud_tts_enabled = False
    settings.last_active_at = now
    settings.updated_at = now
    db.flush()

    db.add(StoryPage(
        id=ids["page_id"], story_id=ids["story_id"], page_number=1,
        page_text="hello", page_image_asset_id=None, image_target_id=None,
    ))
    db.add(StoryPage(
        id=ids["curated_page_id"], story_id=ids["curated_story_id"], page_number=1,
        page_text="curated", page_image_asset_id=None, image_target_id=None,
    ))
    db.flush()

    db.add(NarrationSegment(
        id=ids["segment_id"], story_id=ids["story_id"], page_id=ids["page_id"],
        speaker_key="narrator", text="hello", voice_id="alloy",
        emotion=None, speed=1.0, audio_asset_id=None, start_ms=0, end_ms=0,
        sort_order=0,
    ))
    db.add(ArScene(
        id=ids["scene_id"], story_id=ids["story_id"], page_id=ids["page_id"],
        scene_json={}, status="published",
    ))
    db.add(Question(
        id=ids["question_id"], story_id=ids["story_id"], page_id=ids["page_id"],
        type="choice", prompt="pick one", sort_order=0,
    ))
    db.add(NarrationSegment(
        id=ids["curated_segment_id"], story_id=ids["curated_story_id"],
        page_id=ids["curated_page_id"], speaker_key="narrator", text="curated",
        voice_id="alloy", emotion=None, speed=1.0, audio_asset_id=None,
        start_ms=0, end_ms=0, sort_order=0,
    ))
    db.add(Question(
        id=ids["curated_question_id"], story_id=ids["curated_story_id"],
        page_id=ids["curated_page_id"], type="choice", prompt="curated pick",
        sort_order=0,
    ))
    db.flush()

    db.add(QuestionChoice(
        id=ids["choice_id"], question_id=ids["question_id"],
        label="a", emoji=None, is_correct=True, sort_order=0,
    ))
    db.add(QuestionChoice(
        id=ids["choice2_id"], question_id=ids["question_id"],
        label="b", emoji=None, is_correct=False, sort_order=1,
    ))
    db.add(QuestionChoice(
        id=ids["curated_choice_id"], question_id=ids["curated_question_id"],
        label="a", emoji=None, is_correct=True, sort_order=0,
    ))
    db.add(StorySession(
        id=ids["session_id"], child_profile_id=ids["profile_id"],
        story_id=ids["story_id"], started_at=now, completed_at=None,
        last_page_number=1, mode="library",
    ))
    db.add(StorySession(
        id=ids["curated_session_id"], child_profile_id=ids["profile_id"],
        story_id=ids["curated_story_id"], started_at=now, completed_at=None,
        last_page_number=0, mode="library",
    ))
    db.flush()

    db.add(InteractionEvent(
        id=ids["event_id"], story_session_id=ids["session_id"],
        event_type="story_started", page_id=None, payload={}, created_at=now,
    ))
    db.add(InteractionEvent(
        id=ids["curated_event_id"], story_session_id=ids["curated_session_id"],
        event_type="story_started", page_id=None, payload={}, created_at=now,
    ))
    db.flush()
    return ids


def _counts(db, ids):
    return {
        "events": db.scalar(select(func.count(InteractionEvent.id)).where(
            InteractionEvent.id.in_([ids["event_id"], ids["curated_event_id"]])
        )),
        "sessions": db.scalar(select(func.count(StorySession.id)).where(
            StorySession.id.in_([ids["session_id"], ids["curated_session_id"]])
        )),
        "choices": db.scalar(select(func.count(QuestionChoice.id)).where(
            QuestionChoice.id.in_([ids["choice_id"], ids["choice2_id"]])
        )),
        "questions": db.scalar(
            select(func.count(Question.id)).where(Question.id == ids["question_id"])
        ),
        "scenes": db.scalar(
            select(func.count(ArScene.id)).where(ArScene.id == ids["scene_id"])
        ),
        "segments": db.scalar(
            select(func.count(NarrationSegment.id)).where(
                NarrationSegment.id == ids["segment_id"]
            )
        ),
        "pages": db.scalar(
            select(func.count(StoryPage.id)).where(StoryPage.id == ids["page_id"])
        ),
        "stories": db.scalar(
            select(func.count(Story.id)).where(Story.id == ids["story_id"])
        ),
        "profiles": db.scalar(
            select(func.count(ChildProfile.id)).where(
                ChildProfile.id == ids["profile_id"]
            )
        ),
        "consents": db.scalar(select(func.count(ConsentEvent.id)).where(
            ConsentEvent.id.in_([ids["consent_id"], ids["consent2_id"]])
        )),
        "settings": db.scalar(
            select(func.count(PrivacySettings.user_id)).where(
                PrivacySettings.user_id == ids["user_id"]
            )
        ),
    }


def _survivor_counts(db, ids):
    return {
        "users": db.scalar(
            select(func.count(User.id)).where(User.id == ids["user_id"])
        ),
        "devices": db.scalar(
            select(func.count(Device.id)).where(Device.id == ids["device_id"])
        ),
        "curated_stories": db.scalar(
            select(func.count(Story.id)).where(Story.id == ids["curated_story_id"])
        ),
        "curated_pages": db.scalar(
            select(func.count(StoryPage.id)).where(StoryPage.id == ids["curated_page_id"])
        ),
        "curated_segments": db.scalar(
            select(func.count(NarrationSegment.id)).where(
                NarrationSegment.id == ids["curated_segment_id"]
            )
        ),
        "curated_questions": db.scalar(
            select(func.count(Question.id)).where(
                Question.id == ids["curated_question_id"]
            )
        ),
        "curated_choices": db.scalar(
            select(func.count(QuestionChoice.id)).where(
                QuestionChoice.id == ids["curated_choice_id"]
            )
        ),
    }


def test_delete_child_data_deletes_in_order_without_commit(db):
    ids = _populate(db, "child-data-order-user")
    delete_statements = []
    commits = []

    def on_commit(session):
        commits.append(session)

    def before_cursor_execute(conn, cursor, statement, parameters, context, executemany):
        if statement.startswith("DELETE FROM"):
            delete_statements.append(statement.split()[2])

    event.listen(db, "after_commit", on_commit)
    event.listen(db.get_bind(), "before_cursor_execute", before_cursor_execute)
    try:
        child_data_deletion.delete_child_data(db, ids["user_id"])
    finally:
        event.remove(db, "after_commit", on_commit)
        event.remove(db.get_bind(), "before_cursor_execute", before_cursor_execute)

    assert commits == []
    assert delete_statements == EXPECTED_DELETE_ORDER

    assert set(_counts(db, ids).values()) == {0}
    assert _survivor_counts(db, ids) == {
        "users": 1,
        "devices": 1,
        "curated_stories": 1,
        "curated_pages": 1,
        "curated_segments": 1,
        "curated_questions": 1,
        "curated_choices": 1,
    }


def test_delete_child_data_rollback_restores_everything(db):
    ids = _populate(db, "child-data-rollback-user")
    # Commit the baseline into the outer transaction so the rollback below
    # only undoes the deletion, not the populated fixtures.
    db.commit()
    before = _counts(db, ids)

    child_data_deletion.delete_child_data(db, ids["user_id"])
    assert set(_counts(db, ids).values()) == {0}

    db.rollback()
    assert _counts(db, ids) == before
    assert set(_survivor_counts(db, ids).values()) == {1}


def test_delete_child_data_is_idempotent(db):
    ids = _populate(db, "child-data-idempotent-user")

    child_data_deletion.delete_child_data(db, ids["user_id"])
    child_data_deletion.delete_child_data(db, ids["user_id"])

    assert set(_counts(db, ids).values()) == {0}


def test_delete_child_data_on_empty_db_succeeds(db):
    now = datetime.now(timezone.utc)
    db.add(User(
        id="child-data-empty-user",
        email=None,
        auth_provider="device",
        created_at=now,
        updated_at=now,
    ))
    db.flush()

    child_data_deletion.delete_child_data(db, "child-data-empty-user")

    assert db.scalar(select(func.count(User.id)).where(
        User.id == "child-data-empty-user"
    )) == 1


def test_delete_endpoint_reauth_and_privacy_get_recreates_defaults(client, db):
    registered = client.post(
        "/v1/auth/device", json={"device_id": "p-child-data-device"}
    ).json()
    token = registered["token"]
    user_id = registered["user_id"]
    device_secret = registered["device_secret"]
    headers = {"Authorization": f"Bearer {token}"}

    ids = _populate(db, user_id, with_user=False)

    resp = client.delete("/v1/privacy/child-data", headers=headers)

    assert resp.status_code == 204
    assert resp.content == b""
    db.expire_all()
    assert set(_counts(db, ids).values()) == {0}
    assert _survivor_counts(db, ids) == {
        "users": 1,
        "devices": 1,
        "curated_stories": 1,
        "curated_pages": 1,
        "curated_segments": 1,
        "curated_questions": 1,
        "curated_choices": 1,
    }

    reauth = client.post("/v1/auth/device", json={
        "device_id": "p-child-data-device",
        "device_secret": device_secret,
    })
    assert reauth.status_code == 200
    assert reauth.json()["user_id"] == user_id

    state = client.get("/v1/privacy", headers={
        "Authorization": f"Bearer {reauth.json()['token']}"
    })
    assert state.status_code == 200
    body = state.json()
    assert body["accepted_policy_version"] is None
    assert body["core_storage_accepted_at"] is None
    assert body["review_required"] is True
    assert body["progress_tracking_enabled"] is False
    assert body["cloud_tts_enabled"] is False
    assert body["counts"] == {
        "child_profiles": 0,
        "authored_stories": 0,
        "story_sessions": 0,
        "interaction_events": 0,
    }
