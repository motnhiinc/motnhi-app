import json
from pathlib import Path

import pytest

DATA_DIR = Path(__file__).resolve().parent.parent.parent / "assets" / "data"
SLUGS = json.loads((DATA_DIR / "manifest.json").read_text())["stories"]


def _auth(client):
    token = client.post("/v1/auth/device", json={"device_id": "dc"}).json()["token"]
    return {"Authorization": f"Bearer {token}"}


def _strip_runtime(story: dict) -> dict:
    # Server-derived flags the bundled file may set differently.
    return {k: v for k, v in story.items() if k not in ("is_downloaded", "is_unlocked")}


@pytest.mark.parametrize("slug", SLUGS)
def test_detail_reproduces_bundled_json(client, seeded, slug):
    bundled = json.loads((DATA_DIR / f"{slug}.json").read_text())
    story_id = bundled["story"]["id"]
    got = client.get(f"/v1/stories/{story_id}", headers=_auth(client)).json()

    assert _strip_runtime(got["story"]) == _strip_runtime(bundled["story"])
    assert {p["id"] for p in got["pages"]} == {p["id"] for p in bundled["pages"]}
    assert {s["id"] for s in got["segments"]} == {s["id"] for s in bundled["segments"]}
    by_id = {s["id"]: s for s in got["segments"]}
    for s in bundled["segments"]:
        assert by_id[s["id"]]["audio_asset_id"] == f"aud_{s['id']}"
    assert len(got["questions"]) == len(bundled["questions"])
    for q_got, q_exp in zip(got["questions"], bundled["questions"]):
        assert q_got["prompt"] == q_exp["prompt"]
        assert [c["id"] for c in q_got["choices"]] == [c["id"] for c in q_exp["choices"]]
    # AR scene_json preserved verbatim where present
    assert {a["id"] for a in got["ar_scenes"]} == {a["id"] for a in bundled.get("ar_scenes", [])}
