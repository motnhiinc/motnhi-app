from app.models import Asset


def test_asset_roundtrip(db):
    db.add(Asset(
        asset_id="aud_demo",
        kind="audio",
        storage_key="audio/aud_demo.m4a",
        content_type="audio/mp4",
        byte_size=8,
    ))
    db.flush()
    got = db.get(Asset, "aud_demo")
    assert got is not None
    assert got.kind == "audio"
    assert got.storage_key == "audio/aud_demo.m4a"
    assert got.content_type == "audio/mp4"
    assert got.byte_size == 8
    assert got.duration_ms is None
    assert got.created_at is not None
