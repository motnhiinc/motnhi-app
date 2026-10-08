"""Speech-only normalization; OCR text and approval input are never rewritten."""

import re
import unicodedata

_DIGITS = ("không", "một", "hai", "ba", "bốn", "năm", "sáu", "bảy", "tám", "chín")
_SCALES = ("", "nghìn", "triệu", "tỷ")
_VI_MARKS = re.compile(r"[ăâđêôơưáàạảãấầẩẫậắằẳẵặéèẹẻẽếềểễệíìỉĩịóòọỏõốồổỗộớờởỡợúùụủũứừửữựýỳỷỹỵ]", re.I)
_VI_WORDS = {"một", "của", "và", "có", "được", "những", "người", "trong", "này", "không", "đến", "rồi", "bạn", "cũng"}
_EN_WORDS = {"the", "a", "an", "is", "are", "was", "were", "has", "have", "this", "that", "there", "with", "in", "of", "and", "to"}
_NUMBER = re.compile(r"(?<![\w.,/:+\-])[+-]?[0-9]+(?:[.,/:\-][0-9]+)*(?!\w)")


def _vietnamese_page(lines: list[str]) -> bool:
    text = unicodedata.normalize("NFC", " ".join(lines)).lower()
    words = re.findall(r"\w+", text)
    english = sum(word in _EN_WORDS for word in words)
    vietnamese = sum(word in _VI_WORDS for word in words)
    # A loanword or accented name in an English story does not change its language.
    if english >= 2 and english > vietnamese:
        return False
    return bool(_VI_MARKS.search(text)) or vietnamese >= 2


def _triplet(value: int, full: bool) -> str:
    hundreds, remainder = divmod(value, 100)
    tens, units = divmod(remainder, 10)
    words = []
    if hundreds or full:
        words.extend((_DIGITS[hundreds], "trăm"))
    if tens >= 2:
        words.extend((_DIGITS[tens], "mươi"))
    elif tens == 1:
        words.append("mười")
    elif units and (hundreds or full):
        words.append("lẻ")
    if units:
        words.append("mốt" if units == 1 and tens >= 2 else "lăm" if units == 5 and tens else _DIGITS[units])
    return " ".join(words)


def _integer(token: str) -> str:
    # Compound notation, signed values, and identifiers remain untouched.
    if not token.isascii() or not token.isdigit() or len(token) > 12:
        return token
    if len(token) > 1 and token.startswith("0"):
        return token
    value = int(token)
    if value == 0:
        return _DIGITS[0]
    groups = []
    while value:
        value, group = divmod(value, 1000)
        groups.append(group)
    words = []
    for index in range(len(groups) - 1, -1, -1):
        if groups[index]:
            words.append(_triplet(groups[index], full=bool(words) and groups[index] < 100))
            if _SCALES[index]:
                words.append(_SCALES[index])
    return " ".join(words)


def normalize_page_narration(lines: list[str]) -> list[str]:
    if not _vietnamese_page(lines):
        return list(lines)
    return [_NUMBER.sub(lambda match: _integer(match.group()), line) for line in lines]
