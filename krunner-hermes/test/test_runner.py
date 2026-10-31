#!/usr/bin/env python3
"""Unit tests for krunner-hermes pure logic (no session bus needed).

Run:  python3 test/test_runner.py
Covers UX-SPEC B-2 state matrix rows, error humanizer, log tail cleaner,
typed cache, CategoryRelevance enum bounds, and prefix edge cases.
"""

import json
import os
import sys
import time
import unittest
import urllib.error
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import hermes_runner as hr  # noqa: E402

CONF = json.loads(json.dumps(hr.DEFAULT_CONF))
VALID_REL = {0, 30, 50, 70, 100}  # querymatch.h CategoryRelevance


class FakeCache:
    def __init__(self):
        self.m = {}

    def get(self, q):
        return self.m.get(q)

    def drop(self, q):
        self.m.pop(q, None)

    def recent_answers(self, n=5):
        items = [(q, v[2]) for q, v in self.m.items() if v[0] == "answer"]
        items.sort(key=lambda t: t[1], reverse=True)
        return items[:n]


def one(rows):
    assert len(rows) == 1, f"expected 1 row, got {len(rows)}: {rows}"
    return rows[0]


class Routing(unittest.TestCase):
    def test_bare_ai_shows_lane_help(self):
        r = one(hr.route("ai ", FakeCache(), set(), {}, CONF))
        self.assertEqual(r[0], "ai-help")
        self.assertIn("after 'ai'", r[1])

    def test_bare_hr_shows_lane_help(self):
        r = one(hr.route("hr", FakeCache(), set(), {}, CONF))
        self.assertEqual(r[0], "hr-help")

    def test_cold_ask_row(self):
        r = one(hr.route("ai What port is SearXNG?", FakeCache(), set(),
                         {}, CONF))
        self.assertTrue(r[0].startswith("ask:"))
        self.assertEqual(r[0], "ask:what port is searxng?")
        self.assertIn("Ask Hermes:", r[1])
        self.assertEqual(r[4], 100)          # catrel Highest
        self.assertEqual(r[5], 1.0)          # relevance
        self.assertEqual(r[6].get("actions"), [])  # no actions while cold

    def test_in_flight_row(self):
        r = one(hr.route("ai ping", FakeCache(), {"ping"}, {}, CONF))
        self.assertEqual(r[0], "asking:ping")
        self.assertEqual(r[3], "clock")

    def test_cached_answer_row_plus_web_sibling(self):
        c = FakeCache()
        c.m["ping"] = ("answer", "pong", time.time())
        rows = hr.route("ai ping", c, set(), {}, CONF)
        self.assertEqual(len(rows), 2)
        r = rows[0]
        self.assertEqual(r[0], "answer:ping")
        self.assertIn("CACHED", r[2])
        self.assertIn("ENTER COPIES", r[2])
        self.assertTrue(r[6]["multiline"])
        self.assertEqual(r[6]["actions"], ["copy", "askagain", "reshow"])
        w = rows[1]
        self.assertEqual(w[0], "web:ping")
        self.assertEqual(w[1], "Web search: ping")
        self.assertIn("SEARCH DUCKDUCKGO", w[2])
        self.assertEqual(w[3], "internet-web-browser")
        self.assertEqual(w[4], 70)               # High tier — same as parent
        self.assertEqual(w[5], 0.6)              # below the answer's 0.95
        self.assertEqual(w[6].get("actions"), [])

    def test_error_row(self):
        c = FakeCache()
        c.m["ping"] = ("error", "LiteLLM unreachable at x", time.time())
        r = one(hr.route("ai ping", c, set(), {}, CONF))
        self.assertEqual(r[0], "error:ping")
        self.assertEqual(r[3], "dialog-error")
        self.assertIn("ENTER RETRIES", r[2])
        self.assertEqual(r[6]["actions"], ["askagain"])

    def test_task_cold_row(self):
        r = one(hr.route("hr rebuild the NAS index", FakeCache(), set(),
                         {}, CONF))
        self.assertEqual(r[0], "task:rebuild the nas index")
        self.assertEqual(r[3], "system-run")

    def test_task_running_row(self):
        running = {"rebuild the nas index":
                   {"pid": 1, "start": time.time() - 45, "logf": "/dev/null"}}
        r = one(hr.route("hr rebuild the NAS index", FakeCache(), set(),
                         running, CONF))
        self.assertEqual(r[0], "taskrun:rebuild the nas index")
        self.assertIn("45s", r[2])
        self.assertIn("ENTER SHOWS TAIL", r[2])

    def test_hermes_keyword_help(self):
        rows = hr.route("hermes", FakeCache(), set(), {}, CONF)
        self.assertEqual([x[0] for x in rows],
                         ["help-ai", "help-hr", "help-dictation"])

    def test_no_match_outside_prefixes(self):
        self.assertEqual(hr.route("searxng port", FakeCache(), set(),
                                  {}, CONF), [])

    def test_prefix_word_not_substring(self):
        # "aifoo" must NOT route to the ai lane
        self.assertEqual(hr.route("aifoo bar", FakeCache(), set(), {}, CONF),
                         [])
        self.assertEqual(hr.route("hrtask", FakeCache(), set(), {}, CONF), [])

    def test_case_insensitive_prefix(self):
        r = one(hr.route("AI ping", FakeCache(), set(), {}, CONF))
        self.assertEqual(r[0], "ask:ping")

    def test_all_rows_valid_catrel(self):
        cache = FakeCache()
        cache.m["q"] = ("answer", "a" * 500, time.time())
        running = {"t": {"pid": 1, "start": time.time(), "logf": "/dev/null"}}
        queries = ["ai", "hr", "ai q", "hr t", "hermes", "hr running",
                   "ai x y z"]
        for q in queries:
            for r in hr.route(q, cache, {"x y z"}, running, CONF):
                self.assertIn(r[4], VALID_REL, f"{q}: {r[4]}")
                self.assertTrue(0.0 <= r[5] <= 1.0)

    def test_answer_title_clipped(self):
        cache = FakeCache()
        cache.m["q"] = ("answer", "z" * 500, time.time())
        rows = hr.route("ai q", cache, set(), {}, CONF)
        r = rows[0]
        self.assertLessEqual(len(r[1]), 240)
        self.assertTrue(r[1].endswith("…"))


class Humanize(unittest.TestCase):
    def test_urlerror_refused(self):
        e = urllib.error.URLError(ConnectionRefusedError(111))
        self.assertEqual(hr.humanize(e, CONF),
                         f"LiteLLM unreachable at "
                         f"{CONF['litellm']['base_url']}")

    def test_urlerror_timeout(self):
        e = urllib.error.URLError(TimeoutError("timed out"))
        self.assertIn("timeout after 45s", hr.humanize(e, CONF))

    def test_json_error(self):
        self.assertEqual(
            hr.humanize(json.JSONDecodeError("x", "doc", 1), CONF),
            "LiteLLM returned malformed JSON")

    def test_generic_error_single_line(self):
        self.assertEqual(hr.humanize(Exception("boom\nline2"), CONF), "boom")


def io_stub():
    import io
    return io.BytesIO(b"{'error': 'bad key'}")


class CleanTail(unittest.TestCase):
    def test_ansi_and_cr_stripped(self):
        p = Path("/tmp/hr-test-tail.log")
        p.write_text("step1\x1b[32m OK\x1b[0m\r\nstep2\n\n\n\nstep3")
        out = hr.clean_tail(p)
        self.assertNotIn("\x1b", out)
        self.assertNotIn("\r", out)
        self.assertNotIn("\n\n\n", out)

    def test_tail_keeps_last_400(self):
        p = Path("/tmp/hr-test-tail2.log")
        p.write_text("A" * 1000)
        self.assertEqual(len(hr.clean_tail(p)), 400)

    def test_missing_file(self):
        self.assertEqual(hr.clean_tail("/nonexistent/x.log"),
                         "(log unreadable)")


class CacheAndHelpers(unittest.TestCase):
    def test_typed_cache_roundtrip(self):
        c = hr.AnswerCache(size=2)
        c.put("q", "answer", "text")
        kind, text, _ = c.get("q")
        self.assertEqual((kind, text), ("answer", "text"))
        c.drop("q")
        self.assertIsNone(c.get("q"))

    def test_cache_bounded(self):
        c = hr.AnswerCache(size=2)
        for i in range(5):
            c.put(f"q{i}", "answer", str(i))
        self.assertEqual(len(c.map), 2)

    def test_clip(self):
        self.assertEqual(hr.clip("abcdef", 4), "abc…")
        self.assertEqual(hr.clip("ab", 4), "ab")
        self.assertEqual(hr.clip(None, 4), "")

    def test_age(self):
        now = time.time()
        self.assertEqual(hr.age_str(now - 30, now), "30s")
        self.assertEqual(hr.age_str(now - 120, now), "2m")
        self.assertEqual(hr.age_str(now - 7200, now), "2h")

    def test_key_from_env_file(self):
        p = Path("/tmp/hr-test-key.env")
        p.write_text('OTHER=1\nZHW_PROXY_API_KEY="sk-test-123"\n')
        conf = json.loads(json.dumps(CONF))
        conf["litellm"]["api_key_file"] = str(p)
        old = os.environ.pop("ZHW_PROXY_API_KEY", None)
        try:
            self.assertEqual(hr.litellm_key(conf), "sk-test-123")
        finally:
            if old:
                os.environ["ZHW_PROXY_API_KEY"] = old
        p.unlink()


class Normalize(unittest.TestCase):
    """UX-SPEC F-1 — foyer voice-model fixture table + idempotence."""

    def test_fixtures(self):
        sys.path.insert(0, str(Path(__file__).resolve().parent))
        import fixtures_normalize as fx
        self.assertGreater(len(fx.NORMALIZE_FIXTURES), 20)
        for src, want in fx.NORMALIZE_FIXTURES:
            self.assertEqual(hr.normalize(src, CONF), want, src)

    def test_idempotent(self):
        sys.path.insert(0, str(Path(__file__).resolve().parent))
        import fixtures_normalize as fx
        for src, _ in fx.NORMALIZE_FIXTURES:
            once = hr.normalize(src, CONF)
            self.assertEqual(hr.normalize(once, CONF), once, src)

    def test_custom_prefix_targets(self):
        conf = json.loads(json.dumps(CONF))
        conf["answer_prefix"], conf["task_prefix"] = "qq", "tt"
        self.assertEqual(hr.normalize("ask hermes about dns", conf), "qq dns")
        self.assertEqual(hr.normalize("tell hermes to check backups", conf),
                         "tt check backups")
        self.assertEqual(hr.normalize("QQ: dns slow", conf), "qq dns slow")


class WebSibling(unittest.TestCase):
    def test_sibling_only_on_cached_answers(self):
        c = FakeCache()
        c.m["ping"] = ("error", "x", time.time())
        self.assertEqual(len(hr.route("ai ping", c, set(), {}, CONF)), 1)
        self.assertEqual(len(hr.route("ai ping", FakeCache(), {"ping"}, {},
                                      CONF)), 1)
        self.assertEqual(hr.route("ai", FakeCache(), set(), {}, CONF)[0][0],
                         "ai-help")

    def test_target_original_case_and_quote(self):
        self.assertEqual(hr.web_target(CONF, "Why is DNS Slow?"),
                         "https://duckduckgo.com/?q=Why+is+DNS+Slow%3F")

    def test_custom_fleet_url(self):
        conf = json.loads(json.dumps(CONF))
        conf["web_search_url"] = "http://192.168.1.249:8787/search?q=%s"
        self.assertEqual(hr.web_target(conf, "x y"),
                         "http://192.168.1.249:8787/search?q=x+y")


class Recents(unittest.TestCase):
    def test_order_privacy_and_relevance(self):
        c = FakeCache()
        t = time.time()
        for i, q in enumerate(["q1", "q2", "q3", "q4", "q5", "q6", "q7"]):
            c.m[q] = ("answer", f"a{i}", t + i)      # q7 newest
        c.m["err"] = ("error", "boom", t + 99)        # newest, but excluded
        rows = hr.route("ai", c, set(), {}, CONF)
        self.assertEqual(rows[0][0], "ai-help")       # help stays on top
        self.assertEqual(len(rows), 6)                # help + cap 5
        self.assertEqual([r[0] for r in rows[1:]],
                         ["recent:q7", "recent:q6", "recent:q5",
                          "recent:q4", "recent:q3"])
        # titles are the QUESTIONS, not the answers
        self.assertEqual([r[1] for r in rows[1:]],
                         ["q7", "q6", "q5", "q4", "q3"])
        self.assertEqual([r[5] for r in rows[1:]],
                         [0.5, 0.47, 0.44, 0.41, 0.38])
        self.assertTrue(all(r[5] < rows[0][5] for r in rows[1:]))
        for r in rows[1:]:
            self.assertIn("ANSWER CACHED", r[2])
            self.assertIn("ENTER COPIES", r[2])
            self.assertEqual(r[6]["actions"], ["copy", "askagain", "reshow"])

    def test_empty_cache_help_only(self):
        self.assertEqual(len(hr.route("ai", FakeCache(), set(), {}, CONF)), 1)


class Dispatch(unittest.TestCase):
    """UX-SPEC F-6 — kind/action coverage via run_dispatch + fake ctx."""

    class Ctx:
        def __init__(self):
            self.conf = json.loads(json.dumps(CONF))
            self.cache = FakeCache()
            self.running_tasks = {}
            self.fetched = []
            self.fired = []

        def fetch_answer(self, text):
            self.fetched.append(text)

        def fire_task(self, text):
            self.fired.append(text)

    def test_web_enter_opens_browser_original_case(self):
        from unittest import mock
        with mock.patch("hermes_runner.subprocess.Popen") as po:
            hr.run_dispatch("web", "why dns slow", "Why DNS Slow?", "",
                            self.Ctx())
            po.assert_called_once()
            self.assertEqual(
                po.call_args[0][0],
                ["xdg-open", "https://duckduckgo.com/?q=Why+DNS+Slow%3F"])

    def test_web_other_action_is_noop(self):
        from unittest import mock
        with mock.patch("hermes_runner.subprocess.Popen") as po:
            hr.run_dispatch("web", "k", "t", "copy", self.Ctx())
            po.assert_not_called()

    def test_recent_enter_copies_cached_answer(self):
        from unittest import mock
        ctx = self.Ctx()
        ctx.cache.m["k"] = ("answer", "cached answer", time.time())
        with mock.patch("hermes_runner.clipboard", return_value=True) as cb:
            hr.run_dispatch("recent", "k", "K?", "", ctx)
            cb.assert_called_once_with("cached answer")

    def test_recent_askagain_drops_and_refetches(self):
        ctx = self.Ctx()
        ctx.cache.m["k"] = ("answer", "old", time.time())
        hr.run_dispatch("recent", "k", "Rebuild NAS?", "askagain", ctx)
        self.assertEqual(ctx.fetched, ["Rebuild NAS?"])
        self.assertNotIn("k", ctx.cache.m)

    def test_recent_reshow_notifies_answer_not_question(self):
        from unittest import mock
        ctx = self.Ctx()
        ctx.cache.m["k"] = ("answer", "the answer body", time.time())
        with mock.patch("hermes_runner.notify") as n:
            hr.run_dispatch("recent", "k", "Q?", "reshow", ctx)
            n.assert_called_once()
            self.assertIn("the answer body", n.call_args[0][1])

    def test_answer_dispatch_unchanged_by_refactor(self):
        from unittest import mock
        ctx = self.Ctx()
        ctx.cache.m["k"] = ("answer", "a body", time.time())
        with mock.patch("hermes_runner.clipboard", return_value=True) as cb:
            hr.run_dispatch("answer", "k", "K?", "", ctx)
            cb.assert_called_once_with("a body")


class IconLint(unittest.TestCase):
    """F-6 gate: every icon route() can emit must resolve in Breeze on this
    host (rglob includes symlinked icons — the find -type f trap)."""

    def test_all_route_icons_exist_in_breeze(self):
        c = FakeCache()
        c.m["ping"] = ("answer", "pong", time.time())
        c.m["boom"] = ("error", "x", time.time())
        c.m["old q"] = ("answer", "y", time.time() - 60)
        running = {"t": {"pid": 1, "start": time.time(), "logf": "/dev/null"}}
        battery = [
            hr.route("ai", c, set(), {}, CONF),
            hr.route("ai ping", c, set(), {}, CONF),
            hr.route("ai boom", c, set(), {}, CONF),
            hr.route("ai cold question", c, set(), {}, CONF),
            hr.route("ai live one", c, {"live one"}, {}, CONF),
            hr.route("hr", c, set(), {}, CONF),
            hr.route("hr t", c, set(), {}, CONF),
            hr.route("hr t", c, set(), running, CONF),
            hr.route("hermes", c, set(), {}, CONF),
            hr.route("ask hermes about dns", c, set(), {}, CONF),
        ]
        icons = {r[3] for rows in battery for r in rows}
        self.assertGreaterEqual(len(icons), 6, f"battery too thin: {icons}")
        root = Path("/usr/share/icons/breeze")
        have = set()
        for p in root.rglob("*"):
            have.add(p.name.rsplit(".", 1)[0].lower())
        missing = {i for i in icons if i.lower() not in have}
        self.assertEqual(missing, set(),
                         f"icons missing from Breeze on this host: {missing}")


if __name__ == "__main__":
    unittest.main(verbosity=1)
