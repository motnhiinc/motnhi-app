import json
from pathlib import Path

from app.models import Asset, Story, StoryPage
from app.repositories.manifests import build_image_target_manifest

DATA_DIR = Path(__file__).resolve().parent.parent.parent / "assets" / "data"
SLUGS = json.loads((DATA_DIR / "manifest.json").read_text())["stories"]


def _auth(client):
    token = client.post("/v1/auth/device", json={"device_id": "dm"}).json()["token"]
    return {"Authorization": f"Bearer {token}"}


# ---- endpoint ----
def test_manifest_200_shape(client, seeded):
    resp = client.get("/v1/stories/story_bunny_forest/image-target-manifest",
                      headers=_auth(client))
    assert resp.status_code == 200
    body = resp.json()
    assert body["story_id"] == "story_bunny_forest"
    assert body["version"] == 1
    assert len(body["targets"]) == 5
    numbers = [t["page_number"] for t in body["targets"]]
    assert numbers == sorted(numbers)
    first = body["targets"][0]
    assert set(first) == {
        "page_id", "page_number", "image_target_id",
        "reference_image_url", "physical_width_mm",
    }
    assert first["page_id"] == "page_bunny_01"
    assert first["image_target_id"] == "imgt_page_bunny_01"
    assert first["physical_width_mm"] == 210
    # Seeded page_image_asset_id values are path strings, not registered assets.
    assert all(t["reference_image_url"] is None for t in body["targets"])


def test_manifest_requires_auth(client, seeded):
    assert client.get(
        "/v1/stories/story_bunny_forest/image-target-manifest"
    ).status_code == 401


def test_manifest_404_for_unknown_story(client, seeded):
    resp = client.get("/v1/stories/nope/image-target-manifest", headers=_auth(client))
    assert resp.status_code == 404


def test_manifest_empty_targets_for_story_without_targets(client, db):
    db.add(Story(id="story_no_targets", title="No Targets", slug="no-targets"))
    db.add(StoryPage(id="page_nt_01", story_id="story_no_targets", page_number=1,
                     page_image_asset_id="assets/images/pages/nt_01.png",
                     image_target_id=None))
    db.flush()
    resp = client.get("/v1/stories/story_no_targets/image-target-manifest",
                      headers=_auth(client))
    assert resp.status_code == 200
    body = resp.json()
    assert body["story_id"] == "story_no_targets"
    assert body["targets"] == []


# ---- repository ----
def test_repo_only_targeted_pages_ordered_by_page_number(db):
    db.add(Story(id="story_repo", title="Repo", slug="repo"))
    # Insert out of order; only pages with a target are included, ordered by page_number.
    db.add(StoryPage(id="page_r_03", story_id="story_repo", page_number=3,
                     image_target_id=None))
    db.add(StoryPage(id="page_r_01", story_id="story_repo", page_number=1,
                     image_target_id="imgt_page_r_01"))
    db.add(StoryPage(id="page_r_02", story_id="story_repo", page_number=2,
                     image_target_id="imgt_page_r_02"))
    db.flush()

    manifest = build_image_target_manifest(db, "u_test", "story_repo")
    assert manifest is not None
    assert [t.page_id for t in manifest.targets] == ["page_r_01", "page_r_02"]
    assert [t.page_number for t in manifest.targets] == [1, 2]


def test_repo_defaults_width_and_version(db):
    db.add(Story(id="story_def", title="Def", slug="def"))
    db.add(StoryPage(id="page_d_01", story_id="story_def", page_number=1,
                     image_target_id="imgt_page_d_01"))
    db.flush()

    manifest = build_image_target_manifest(db, "u_test", "story_def")
    assert manifest.version == 1
    assert all(t.physical_width_mm == 210 for t in manifest.targets)


def test_repo_unknown_story_returns_none(db):
    assert build_image_target_manifest(db, "u_test", "story_missing") is None


def test_repo_reference_url_none_for_unregistered_asset(db, seeded):
    manifest = build_image_target_manifest(db, "u_test", "story_bunny_forest")
    assert manifest is not None
    assert len(manifest.targets) == 5
    # page_image_asset_id are path strings, not registered in the assets table.
    assert all(t.reference_image_url is None for t in manifest.targets)


def test_repo_reference_url_signed_for_registered_asset(db):
    db.add(Story(id="story_img", title="Img", slug="img"))
    db.add(StoryPage(id="page_i_01", story_id="story_img", page_number=1,
                     page_image_asset_id="img_page_i_01",
                     image_target_id="imgt_page_i_01"))
    db.add(Asset(asset_id="img_page_i_01", kind="image",
                 storage_key="images/img_page_i_01.png",
                 content_type="image/png", byte_size=4))
    db.flush()

    manifest = build_image_target_manifest(db, "u_test", "story_img")
    url = manifest.targets[0].reference_image_url
    assert url is not None
    assert url.startswith("/v1/assets/img_page_i_01?exp=")
    assert "sig=" in url


# ---- seed / contract ----
def test_every_seeded_page_has_imgt_image_target_id():
    for slug in SLUGS:
        detail = json.loads((DATA_DIR / f"{slug}.json").read_text())
        for page in detail["pages"]:
            assert page["image_target_id"] == f"imgt_{page['id']}"
