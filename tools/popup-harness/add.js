var panels = panels();
for (var i = 0; i < panels.length; i++) {
    print("HARNESS-ADD panel " + panels[i].id);
    panels[i].addWidget("com.gdeyoung.plasma.stocktick");
}
