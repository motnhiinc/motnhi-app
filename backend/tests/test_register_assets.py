from app.models import Asset
from register_assets import register


def test_register_creates_row_for_matching_file(seeded, tmp_path):
    audio = tmp_path / "audio"
    audio.mkdir()
    (audio / "aud_seg_bunny_p1_1.m4a").write_bytes(b"xx")
    result = register(seeded, tmp_path)
    assert "aud_seg_bunny_p1_1" in result["registered"]
    assert seeded.get(Asset, "aud_seg_bunny_p1_1") is not None


def test_register_flags_orphan(seeded, tmp_path):
    audio = tmp_path / "audio"
    audio.mkdir()
    (audio / "aud_not_a_segment.m4a").write_bytes(b"xx")
    result = register(seeded, tmp_path)
    assert "aud_not_a_segment.m4a" in result["orphans"]
    assert seeded.get(Asset, "aud_not_a_segment") is None


def test_register_is_idempotent(seeded, tmp_path):
    audio = tmp_path / "audio"
    audio.mkdir()
    (audio / "aud_seg_bunny_p1_1.m4a").write_bytes(b"xx")
    register(seeded, tmp_path)
    register(seeded, tmp_path)
    assert seeded.get(Asset, "aud_seg_bunny_p1_1") is not None


def test_register_reports_missing(seeded, tmp_path):
    (tmp_path / "audio").mkdir()  # no .m4a files
    result = register(seeded, tmp_path)
    assert "aud_seg_bunny_p1_1" in result["missing"]
