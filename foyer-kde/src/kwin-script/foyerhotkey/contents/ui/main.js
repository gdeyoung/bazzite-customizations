// foyerhotkey — registers Meta+Space as a real KWin shortcut that toggles
// the Foyer overlay via its session-bus method. Runs inside kwin, so the
// shortcut is active and grabbed the moment the script starts; kwin re-runs
// enabled scripts at every login.
registerShortcut(
    "FoyerSummon",
    "Summon Foyer",
    "Meta+Space",
    function () {
        callDBus(
            "gdeyoung.foyer",
            "/gdeyoung/foyer",
            "gdeyoung.foyer",
            "toggle",
            function () {}
        );
    }
);
