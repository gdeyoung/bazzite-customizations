# Fixture table for query normalization (Phase 1a) — ported from
# omarchy-foyer tests/voice-model.test.mjs and adapted to krunner-hermes
# lanes ('ai' answers, 'hr' tasks). Consumed by test/test_runner.py.
#
# Format: (input, expected_output). Group names mirror the foyer tests so
# semantics stay traceable to the proven original.

NORMALIZE_FIXTURES = [
    # --- dictated phrases become lane prefixes -----------------------------
    ("ask ai why is dns slow",              "ai why is dns slow"),
    ("ask the assistant about tailscale",   "ai tailscale"),
    ("ask hermes about liteermm timeouts",  "ai liteermm timeouts"),
    ("question the computer about zram",    "ai zram"),
    ("tell hermes to check the backups",    "hr check the backups"),
    ("tell the assistant to restart samba", "hr restart samba"),
    ("have hermes look at the jellyfin log", "hr look at the jellyfin log"),

    # --- dictated colons collapse to the typed prefix form -----------------
    ("ai : why is dns slow",   "ai why is dns slow"),
    ("AI:  why is dns slow",   "ai why is dns slow"),
    ("hr :  clean the outbox", "hr clean the outbox"),
    ("HR: clean the outbox",   "hr clean the outbox"),

    # --- filler after an early rewrite drops out (idempotence while typing)
    ("ai about dns",  "ai dns"),
    ("hr to  check the backups", "hr check the backups"),

    # --- ordinary queries pass through UNTOUCHED (no false claims) ---------
    ("firefox",                 "firefox"),
    ("google chrome",           "google chrome"),
    ("ask a friend",            "ask a friend"),          # not 'ask ai/hermes'
    ("searching for cats",      "searching for cats"),
    ("asking hermesy things",   "asking hermesy things"), # not lane word
    ("2048 game",               "2048 game"),
    ("2+2",                     "2+2"),
    ("why is dns slow",         "why is dns slow"),       # no prefix added
    ("ai why is dns slow",      "ai why is dns slow"),    # already prefixed
    ("hr check the backups",    "hr check the backups"),
    ("hermes",                  "hermes"),
]

# Every fixture must ALSO be idempotent: normalize(x) == normalize(normalize(x))
# (the runner sees the text again on every keystroke).

# tell->hr intended defaults (UX review RC-7: document the design choice)
NORMALIZE_FIXTURES += [
    ("tell ai a joke",                "hr a joke"),
    ("tell hermes about the incident", "hr the incident"),
]
