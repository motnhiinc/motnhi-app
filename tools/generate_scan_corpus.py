"""Create 50 ORIGINAL synthetic Vietnamese fixtures; not physical-device evidence.

Run with the backend's Pillow environment:
  cd backend && uv run python ../tools/generate_scan_corpus.py --output /approved/local/path
"""
import argparse
import json
from pathlib import Path
import unicodedata

from PIL import Image, ImageDraw, ImageFont

PASSAGES = [
    ["Buổi sáng, chú thỏ mở cửa sổ.", "Những chiếc lá xanh rung rinh trong gió.", "Mẹ gọi: Hãy cùng nhau đọc sách nhé!", "Chú thỏ mỉm cười rồi ngồi xuống."],
    ["Ở bờ hồ có một cây liễu nhỏ.", "Đàn cá bơi dưới làn nước trong veo.", "Bé đếm những đám mây trắng trên trời.", "Một chú chim sẻ hót líu lo."],
    ["Quả khế vàng nằm trong chiếc giỏ.", "Bố nhẹ nhàng rửa từng quả một.", "Bé hỏi vì sao khế có hình ngôi sao.", "Cả nhà cùng ngắm khu vườn yên tĩnh."],
    ["Đêm xuống, ánh trăng soi mái nhà.", "Bà kể chuyện về một chuyến đi xa.", "Bé kéo chăn, lắng nghe từng lời kể.", "Ngày mai sẽ có nhiều điều mới mẻ."],
    ["Tiếng Việt có những dấu rất đẹp.", "Ă, Â, Ê, Ô, Ơ, Ư và Đ đều có mặt.", "Bé viết: ấ, ề, ễ, ộ, ớ, ự, ỷ.", "Mỗi chữ được đọc rõ ràng, chậm rãi."],
]


def generate(output: Path) -> None:
    output.mkdir(parents=True, exist_ok=True)
    font_path = Path(__file__).resolve().parents[1] / "assets/fonts/NunitoSans-Regular.ttf"
    records = []
    for index in range(50):
        condition = ["plain", "small_type", "illustrated", "glare_proxy", "two_columns"][index % 5]
        font = ImageFont.truetype(str(font_path), 24 if condition == "small_type" else 44)
        lines = list(PASSAGES[(index // 5) % len(PASSAGES)])
        # Longer-page and reading-order regression fixtures, still under limits.
        if index >= 25: lines = lines * 4
        image = Image.new("RGB", (2400, 3200), "#fff9ed")
        draw = ImageDraw.Draw(image)
        if condition == "illustrated":
            draw.ellipse((1400, 1900, 2300, 2800), fill="#9fc89e")
            draw.rectangle((0, 2700, 2400, 3200), fill="#8db4d0")
        for line_index, text in enumerate(lines):
            column = line_index // ((len(lines) + 1) // 2) if condition == "two_columns" else 0
            row = line_index % ((len(lines) + 1) // 2) if condition == "two_columns" else line_index
            draw.text((100 + column * 1200, 160 + row * 90), unicodedata.normalize("NFC", text), font=font, fill="#222222")
        if condition == "glare_proxy":
            draw.rectangle((800, 120, 850, 1700), fill="white")
        image_path = f"vi-{index + 1:02d}.jpg"
        image.save(output / image_path, quality=92)
        records.append({"page_id": f"vi-{index + 1:02d}", "image": image_path,
                        "content_language": "vi", "lines": lines, "condition": condition,
                        "split": "held_out" if index % 5 == index // 10 else "calibration",
                        "source": "original_synthetic", "readability_label": None})
    for language, lines in [("en", ["The rabbit opens a window.", "Green leaves move in the wind."]),
                            ("mixed", ["Chú thỏ nói: Hello, my friend!", "Bạn nhỏ đáp: Chào buổi sáng!"])]:
        image = Image.new("RGB", (2400, 3200), "white")
        draw = ImageDraw.Draw(image)
        font = ImageFont.truetype(str(font_path), 44)
        for index, line in enumerate(lines): draw.text((100, 160 + index * 90), line, font=font, fill="black")
        image.save(output / f"{language}.jpg", quality=92)
        records.append({"page_id": language, "image": f"{language}.jpg", "content_language": "en" if language == "en" else "vi",
                        "lines": lines, "condition": language, "split": "regression", "source": "original_synthetic", "readability_label": None})
    (output / "manifest.json").write_text(json.dumps(records, ensure_ascii=False, indent=2), encoding="utf-8")
    print("Generated 50 Vietnamese + 2 regression fixtures. Human readability labels and physical book captures are still required.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    generate(parser.parse_args().output)
