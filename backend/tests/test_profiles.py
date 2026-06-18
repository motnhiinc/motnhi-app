import uuid


def _auth(client, device="p-dev"):
    token = client.post("/v1/auth/device", json={"device_id": device}).json()["token"]
    return {"Authorization": f"Bearer {token}"}


def _profile_body():
    return {"id": str(uuid.uuid4()), "nickname": "Bun", "age_band": "3-4",
            "language_code": "en", "bedtime_mode_default": False,
            "microphone_enabled": False, "ar_enabled": True}


def test_create_and_list_profile(client):
    h = _auth(client)
    body = _profile_body()
    created = client.post("/v1/child-profiles", json=body, headers=h)
    assert created.status_code == 200
    assert created.json()["user_id"]  # set from JWT, not body

    listed = client.get("/v1/child-profiles", headers=h).json()
    assert [p["id"] for p in listed] == [body["id"]]


def test_patch_updates_permissions(client):
    h = _auth(client)
    body = _profile_body()
    client.post("/v1/child-profiles", json=body, headers=h)
    patched = client.patch(f"/v1/child-profiles/{body['id']}",
                           json={"microphone_enabled": True}, headers=h)
    assert patched.json()["microphone_enabled"] is True


def test_profiles_isolated_per_device(client):
    body = _profile_body()
    client.post("/v1/child-profiles", json=body, headers=_auth(client, "dev-A"))
    other = client.get("/v1/child-profiles", headers=_auth(client, "dev-B")).json()
    assert other == []
