import unicodedata

import unittest

from app.services.page_narration import normalize_page_narration


class PageNarrationTests(unittest.TestCase):
    def test_vietnamese_numbers_inherit_full_page_context(self):
        cases = [
            ("0", "không"), ("13", "mười ba"), ("15", "mười lăm"),
            ("21", "hai mươi mốt"), ("25", "hai mươi lăm"),
            ("105", "một trăm lẻ năm"), ("1001", "một nghìn không trăm lẻ một"),
            ("1000000", "một triệu"), ("1000000005", "một tỷ không trăm lẻ năm"),
        ]
        for number, spoken in cases:
            with self.subTest(number=number):
                self.assertEqual(normalize_page_narration(["Những chú thỏ", number]), ["Những chú thỏ", spoken])


    def test_sentence_punctuation_and_unicode_decomposition(self):
        text = unicodedata.normalize("NFD", "Có 13 chú thỏ.")
        self.assertEqual(normalize_page_narration([text])[0], text.replace("13", "mười ba"))
        self.assertEqual(normalize_page_narration(["Có tất cả 13."]), ["Có tất cả mười ba."])
        self.assertEqual(normalize_page_narration(["Có 13 con cá."]), ["Có mười ba con cá."])


    def test_english_and_ambiguous_numeric_notation_are_preserved(self):
        self.assertEqual(normalize_page_narration(["There are 13 rabbits.", "15"]), ["There are 13 rabbits.", "15"])
        self.assertEqual(normalize_page_narration(["There are 13 tables in the café."]), ["There are 13 tables in the café."])
        text = "Ngày 13/10/2026, mã A13, A13.5, 007, -13, 1.5 và 1,000."
        self.assertEqual(normalize_page_narration([text]), [text])
