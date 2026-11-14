"""Unit tests for the space profile builder (run: python3 -m unittest discover space/tests)."""
import datetime as dt
import sys
import tempfile
import unittest
import xml.dom.minidom
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import build  # noqa: E402

D0 = dt.date(2026, 1, 1)


def cal(counts):
    return [(D0 + dt.timedelta(days=i), n) for i, n in enumerate(counts)]


class Streaks(unittest.TestCase):
    def test_empty(self):
        self.assertEqual(build.streaks([]), (0, 0))

    def test_longest_and_current(self):
        self.assertEqual(build.streaks(cal([1, 1, 1, 0, 2, 2])), (2, 3))

    def test_empty_today_keeps_current_streak(self):
        self.assertEqual(build.streaks(cal([0, 3, 4, 0])), (2, 2))

    def test_gap_yesterday_breaks_streak(self):
        self.assertEqual(build.streaks(cal([5, 0, 0])), (0, 1))


class Panels(unittest.TestCase):
    def setUp(self):
        self.profile = build.load_fixture(Path(build.HERE, "fixture.json"))

    def test_every_panel_is_well_formed_svg(self):
        with tempfile.TemporaryDirectory() as out:
            self.assertEqual(build.main(["--fixture", str(Path(build.HERE, "fixture.json")), "--out", out]), 0)
            files = sorted(Path(out).glob("*.svg"))
            self.assertEqual(len(files), 5)
            for f in files:
                xml.dom.minidom.parseString(f.read_bytes())  # raises on malformed XML
                self.assertNotIn("<script", f.read_text())

    def test_text_is_escaped(self):
        self.profile.repos[0].name = "<evil & co>"
        svg = build.fleet(self.profile, [])
        self.assertIn("&lt;evil &amp; co&gt;", svg)
        self.assertNotIn("<evil", svg)

    def test_numbers_come_from_the_profile(self):
        svg = build.telemetry(self.profile)
        self.assertIn(f"{self.profile.last_year:,}", svg)
        self.assertIn(f"{self.profile.total_all_time:,}", svg)

    def test_missing_token_fails_cleanly(self):
        import os
        old = os.environ.pop("GITHUB_TOKEN", None)
        try:
            self.assertEqual(build.main(["--out", tempfile.mkdtemp()]), 2)
        finally:
            if old is not None:
                os.environ["GITHUB_TOKEN"] = old


if __name__ == "__main__":
    unittest.main()


class Galaxy(unittest.TestCase):
    def test_one_outlier_day_does_not_dim_the_rest(self):
        p = build.load_fixture(Path(build.HERE, "fixture.json"))
        p.days = cal([4] * 300 + [1200])
        svg = build.galaxy(p)
        # ordinary days still render as full-size glowing alien heads, not the smallest ones
        self.assertIn('width="16.4"', svg)
        self.assertIn('fill="#d4ffe3"', svg)

    def test_activity_levels_follow_quartiles(self):
        self.assertEqual([build.activity_level(n, 8) for n in (0, 1, 2, 3, 4, 6, 8, 50)],
                         [0, 1, 1, 2, 2, 3, 4, 4])
