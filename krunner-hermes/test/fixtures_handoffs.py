# Fixture table for the handoffs lane (Phase 2 / UX-SPEC F-5) — foyer
# sanitize semantics + claim exactness. Consumed by test/test_runner.py.

SANITIZE_FIXTURES = [
    # (entry, expected_ok) — foyer-identical rules
    ({"prefix": "gh", "label": "GitHub", "url": "https://github.com/search?q=%s"}, True),
    ({"prefix": "sea", "label": "SearXNG fleet", "url": "http://192.168.1.249:8787/search?q=%s"}, True),
    ({"prefix": "maps", "label": "Maps", "url": "https://example.com/%s"}, True),  # 4 lowercase letters: valid (product cut of the `map` DEFAULT was UX scope, not sanitize)
    ({"prefix": "toolongprefix", "label": "X", "url": "https://a.co/?q=%s"}, False),  # >6 chars
    ({"prefix": "Gh", "label": "GitHub", "url": "https://github.com/search?q=%s"}, False),  # uppercase
    ({"prefix": "a", "label": "A", "url": "https://a.co/?q=%s"}, False),             # 1 char
    ({"prefix": "gh", "label": "", "url": "https://a.co/?q=%s"}, False),             # empty label
    ({"prefix": "gh", "label": "x" * 25, "url": "https://a.co/?q=%s"}, False),       # label >24
    ({"prefix": "gh", "label": "Ok", "url": "ftp://a.co/?q=%s"}, False),             # not http(s)
    ({"prefix": "gh", "label": "Ok", "url": "https://a.co/search"}, False),          # missing %s
    ({"prefix": "gh", "label": "Ok", "url": "https://a.co/%s/%s"}, False),           # two %s
    ({"prefix": "gh", "label": "Ok"}, False),                                        # missing url key
    ("not-a-dict", False),                                                            # wrong type
]

# Reserved-from-config: a handoff may never shadow the lane prefixes.
# (run with answer_prefix/task_prefix customized: "gh" must be rejected)
CLAIM_FIXTURES = [
    # (query, should_claim) — exact first word only
    ("gh krunner hermes", True),
    ("gh", True),              # bare prefix -> help row
    ("GH krunner", True),      # route lowercases first (normalize) before match
    ("ghost story", False),    # never eat 'ghost'
    ("sea krunner plugins", True),
    ("seagate ironwolf", False),
    ("el icinga logs", True),
    ("elbow", False),
    ("firefox", False),
    ("2+2", False),
]
