def _auth(client):
    token = client.post("/v1/auth/device", json={"device_id": "d1"}).json()["token"]
    return {"Authorization": f"Bearer {token}"}


def test_library_lists_published_stories(client, seeded):
    resp = client.get("/v1/stories", headers=_auth(client))
    assert resp.status_code == 200
    stories = resp.json()["stories"]
    assert len(stories) == 5
    assert all(s["is_unlocked"] for s in stories)


def test_library_filters_by_age_band(client, seeded):
    resp = client.get("/v1/stories?age_band=3-4", headers=_auth(client))
    titles = [s["title"] for s in resp.json()["stories"]]
    assert "Bunny and the Moon" in titles  # age_min 3, age_max 5


def test_story_detail_404_for_unknown(client, seeded):
    resp = client.get("/v1/stories/nope", headers=_auth(client))
    assert resp.status_code == 404


def test_requires_auth(client, seeded):
    assert client.get("/v1/stories").status_code == 401
