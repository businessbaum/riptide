// Every keyboard shortcut of the system, for System Settings → Tastatur → Tastaturkurzbefehle.
// ⌘ = the Windows key (SUPER), ⌥ = Alt, ⌃ = Ctrl, ⇧ = Shift. Keep in step with
// hypr/modules/keys.lua, shell.lua, switcher.lua and snapping.lua.
.pragma library

const GROUPS = [
    { title: "Apps und Fenster", items: [
        ["⌘ Leertaste", "Spotlight: Apps, Dateien, Rechner, Einstellungen"],
        ["⌘⌥ Leertaste", "Finder öffnen"],
        ["⌘ Tab", "Zwischen Apps wechseln (⇧ rückwärts)"],
        ["⌥ Tab", "Zwischen Fenstern wechseln (⇧ rückwärts)"],
        ["⌘Q", "App beenden"],
        ["⌘H", "App ausblenden"],
        ["⌘M", "Fenster minimieren"],
        ["⌘⇧M", "Alle minimierten Fenster zeigen"],
        ["⌃⌘F", "Vollbild"],
        ["⌘⌥F", "Fenster schweben lassen oder kacheln"],
        ["⌃⌥ ← / →", "Fenster an den linken oder rechten Rand"],
        ["⌃⌥ ↑", "Fenster füllt den Bildschirm"],
        ["⌃⌥ ↓", "Frühere Fenstergröße"],
        ["⌘ + Maus ziehen", "Fenster bewegen (rechte Taste: Größe ändern)"],
        ["⌥⌘ Esc", "Sofort beenden …"],
        ["⌃⇧ Esc", "Aufgabenverwaltung (Mission Center)"]
    ] },
    { title: "Schreibtische", items: [
        ["⌃ ↑", "Mission Control: alle Fenster und Schreibtische"],
        ["⌃ ↓", "App-Fenster: alle Fenster der App im Vordergrund"],
        ["⌃ ← / →", "Zum Schreibtisch links oder rechts"],
        ["⌃1 … ⌃9", "Zu Schreibtisch 1 … 9"],
        ["⌃⇧1 … ⌃⇧9", "Fenster auf Schreibtisch 1 … 9 bewegen"],
        ["⌘ + Mausrad", "Durch die Schreibtische blättern"]
    ] },
    { title: "Bildschirmfotos", items: [
        ["⌘⇧3", "Ganzer Bildschirm, als Datei"],
        ["⌘⇧4", "Bereich auswählen, als Datei"],
        ["⌃⌘⇧3", "Ganzer Bildschirm in die Zwischenablage"],
        ["⌃⌘⇧4", "Bereich in die Zwischenablage"],
        ["⌘⇧S", "Bereich als Datei und in die Zwischenablage"]
    ] },
    { title: "Eingabe", items: [
        ["⌘C / ⌘X", "Kopieren, Ausschneiden (in allen Apps)"],
        ["⌘V", "Verlauf der Zwischenablage: auswählen und einsetzen"],
        ["⌃V", "Direkt einsetzen"],
        ["⌘Z / ⌘⇧Z", "Widerrufen, Wiederholen"],
        ["⌘A / ⌘F / ⌘G", "Alles auswählen, Suchen, Weitersuchen"],
        ["⌘S / ⌘O / ⌘P", "Sichern, Öffnen, Drucken"],
        ["⌘T / ⌘N / ⌘W", "Neuer Tab, neues Fenster, Tab oder Fenster schließen"],
        ["⌘+ / ⌘- / ⌘0", "Vergrößern, verkleinern, Originalgröße"],
        ["⌃⌘ Leertaste", "Emoji & Symbole"],
        ["⌥ ← / →", "Wortweise springen (mit ⇧ markieren)"],
        ["⌘ ← / →", "Zum Zeilenanfang oder -ende (mit ⇧ markieren)"],
        ["⌘ ↑ / ↓", "Zum Anfang oder Ende des Textes"],
        ["⌥ ⌫", "Wort löschen"],
        ["⌘ ⌫", "Bis zum Zeilenanfang löschen"]
    ] },
    { title: "System", items: [
        ["⌃⌘Q / ⌘L", "Bildschirm sperren"],
        ["⌘⇧Q", "Abmelden …"],
        ["⌘ Eingabe", "Terminal öffnen"],
        ["Lautstärketasten", "Lautstärke (auch für Bluetooth)"],
        ["Mikrofontaste", "Mikrofon für alle Apps aus- und einschalten"],
        ["Helligkeitstasten", "Helligkeit beider Bildschirme"],
        ["Medientasten", "Wiedergabe, Weiter, Zurück"],
        ["⌥⌘8 / ⌥⌘+ / ⌥⌘-", "Zoom ein/aus, näher, weiter (Bedienungshilfen)"]
    ] }
];

function search(text) {
    const q = text.trim().toLowerCase();
    if (q === "")
        return GROUPS;
    return GROUPS.map(g => ({ title: g.title, items: g.items.filter(i => (i[0] + " " + i[1]).toLowerCase().includes(q)) }))
        .filter(g => g.items.length > 0);
}
