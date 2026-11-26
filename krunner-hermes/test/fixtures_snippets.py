# F-10 fixtures: snippets sanitize table. Foyer-identical rules:
# name ^[a-z0-9][a-z0-9-]{0,15}$ (unique, not reserved), text non-empty,
# single-line, <=2000 chars. Malformed entries are dropped, never fatal.

SNIPPET_SANITIZE_FIXTURES = [
    # (name, entries, expected [(name, text), ...])
    ("valid entries kept",
     [{"name": "sig", "text": "Greg DeYoung"},
      {"name": "ip-external", "text": "203.0.113.7"}],
     [("sig", "Greg DeYoung"), ("ip-external", "203.0.113.7")]),
    ("bad names dropped",
     [{"name": "UPPER", "text": "x"},        # uppercase
      {"name": "-lead", "text": "x"},        # leading dash
      {"name": "a" * 17, "text": "x"},       # 17 chars > 16
      {"name": "sp ace", "text": "x"},       # space
      {"name": "", "text": "x"}],            # empty
     []),
    ("reserved name dropped",
     [{"name": "help", "text": "x"}],
     []),
    ("bad text dropped",
     [{"name": "ok1", "text": ""},           # empty
      {"name": "ok2", "text": "  \t "},      # whitespace only
      {"name": "ok3", "text": "line\nbreak"},  # newline
      {"name": "ok4", "text": "x" * 2001}],  # over 2000
     []),
    ("duplicate name: first wins",
     [{"name": "dup", "text": "first"},
      {"name": "dup", "text": "second"}],
     [("dup", "first")]),
    ("non-string and None entries dropped",
     [{"name": 7, "text": "x"}, None, "junk", {"text": "no-name"}],
     []),
    ("16-char name allowed (boundary)",
     [{"name": "a" * 16, "text": "boundary ok"}],
     [("a" * 16, "boundary ok")]),
    ("2000-char text allowed (boundary)",
     [{"name": "long", "text": "x" * 2000}],
     [("long", "x" * 2000)]),
]
