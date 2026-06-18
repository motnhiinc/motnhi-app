import uuid


def _auth(client, device="s-dev"):
    return {"Authorization": f"Bearer {client.post('/v1/auth/device', json={'device_id': device}).json()['token']}"}


def _make_profile(client, h):
    pid = str(uuid.uuid4())
    client.post("/v1/child-profiles",
                json={"id": pid, "age_band": "3-4", "language_code": "en"}, headers=h)
    return pid


def test_start_session_emits_story_started(client, seeded):
    h = _auth(client)
    pid = _make_profile(client, h)
    resp = client.post("/v1/story-sessions",
                       json={"child_profile_id": pid, "story_id": "story_bunny_forest", "mode": "bedtime"},
                       headers=h)
    assert resp.status_code == 200
    sid = resp.json()["id"]
    events = client.get(f"/v1/story-sessions/{sid}/events", headers=h).json()
    assert any(e["event_type"] == "story_started" for e in events)


def test_patch_complete_emits_story_completed(client, seeded):
    h = _auth(client)
    pid = _make_profile(client, h)
    sid = client.post("/v1/story-sessions",
                      json={"child_profile_id": pid, "story_id": "story_bunny_forest"},
                      headers=h).json()["id"]
    patched = client.patch(f"/v1/story-sessions/{sid}",
                          json={"last_page_number": 5, "completed": True}, headers=h).json()
    assert patched["last_page_number"] == 5
    assert patched["completed_at"] is not None
    events = client.get(f"/v1/story-sessions/{sid}/events", headers=h).json()
    assert any(e["event_type"] == "story_completed" for e in events)


def test_record_question_answered_event(client, seeded):
    h = _auth(client)
    pid = _make_profile(client, h)
    sid = client.post("/v1/story-sessions",
                      json={"child_profile_id": pid, "story_id": "story_bunny_forest"},
                      headers=h).json()["id"]
    resp = client.post(f"/v1/story-sessions/{sid}/events",
                      json={"event_type": "question_answered", "page_id": "page_bunny_03",
                            "payload": {"question_id": "q_bunny_02", "answer_id": "a_owl", "is_correct": True}},
                      headers=h)
    assert resp.status_code == 200


def test_list_sessions_by_child(client, seeded):
    h = _auth(client)
    pid = _make_profile(client, h)
    client.post("/v1/story-sessions",
                json={"child_profile_id": pid, "story_id": "story_bunny_forest"}, headers=h)
    listed = client.get(f"/v1/story-sessions?child_profile_id={pid}", headers=h).json()
    assert len(listed) == 1
