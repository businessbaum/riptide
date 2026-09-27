// What System Settings can do, for Spotlight: "WLAN", "dunkel", "Zeitzone", "Drucker" …
// find the page (opened with scripts/system-settings.sh <page>). Keep in step with
// settings.qml (pages) and the pages' parts (general/about, privacy/microphone …).
.pragma library

const ENTRIES = [
    { page: "network", title: "WLAN & Netzwerk", words: "wlan wifi netzwerk internet ethernet kabel ip dns" },
    { page: "bluetooth", title: "Bluetooth", words: "bluetooth kopfhörer airpods maus tastatur koppeln" },
    { page: "sound", title: "Ton", words: "ton lautstärke lautsprecher mikrofon ausgabe eingabe audio" },
    { page: "notifications", title: "Mitteilungen", words: "mitteilungen benachrichtigungen nicht stören fokus ton banner" },
    { page: "privacy", title: "Datenschutz & Sicherheit", words: "datenschutz sicherheit berechtigungen rechte sandbox" },
    { page: "privacy/microphone", title: "Mikrofon – Berechtigungen", words: "mikrofon zugriff apps" },
    { page: "privacy/camera", title: "Kamera – Berechtigungen", words: "kamera webcam zugriff" },
    { page: "privacy/screen", title: "Bildschirmaufnahme – Berechtigungen", words: "bildschirmaufnahme bildschirm teilen screen" },
    { page: "privacy/local-network", title: "Lokales Netzwerk – Berechtigungen", words: "lokales netzwerk heimnetz lan geräte" },
    { page: "privacy/firewall", title: "Firewall", words: "firewall ssh entfernte anmeldung eingehende verbindungen" },
    { page: "general", title: "Allgemein", words: "allgemein" },
    { page: "general/about", title: "Info", words: "info über diesen computer name hostname prozessor grafik arbeitsspeicher systembericht version" },
    { page: "general/datetime", title: "Datum & Uhrzeit", words: "datum uhrzeit zeitzone uhr 24 stunden sekunden zeitserver" },
    { page: "general/language", title: "Sprache & Region", words: "sprache region format währung zahlen englisch deutsch" },
    { page: "login", title: "Anmeldeobjekte", words: "anmeldeobjekte autostart beim anmelden öffnen hintergrund" },
    { page: "apps", title: "Apps", words: "apps programme deinstallieren größe" },
    { page: "storage", title: "Speicher", words: "speicher festplatte platz belegt frei aufräumen" },
    { page: "timemachine", title: "Time Machine", words: "time machine sicherung backup wiederherstellen frühere versionen snapshot" },
    { page: "defaults", title: "Standard-Apps", words: "standard apps browser mail öffnen mit dateitypen" },
    { page: "appearance", title: "Erscheinungsbild", words: "erscheinungsbild dunkel hell dark mode hintergrundbild akzentfarbe" },
    { page: "desktop", title: "Schreibtisch & Dock", words: "schreibtisch dock größe fenster ecken abstand aktive ecken hot corners mission control" },
    { page: "displays", title: "Bildschirme", words: "bildschirme monitor auflösung skalierung hz night shift nachtmodus" },
    { page: "energy", title: "Energie", words: "energie ruhezustand sperren bildschirm aus energiemodus leistung" },
    { page: "mouse", title: "Maus", words: "maus zeiger geschwindigkeit scrollen natürlich cursor" },
    { page: "keyboard", title: "Tastatur", words: "tastatur layout wiederholrate kurzbefehle" },
    { page: "printers", title: "Drucker & Scanner", words: "drucker scanner drucken scannen tinte toner warteliste" }
];

// the best few for what is typed
function search(text) {
    const q = text.trim().toLowerCase();
    if (q.length < 2)
        return [];
    const found = [];
    for (const e of ENTRIES) {
        const title = e.title.toLowerCase();
        const score = title.startsWith(q) ? 100
            : title.split(/[\s&–-]+/).some(w => w.startsWith(q)) ? 80
            : e.words.split(" ").some(w => w.startsWith(q)) ? 60
            : e.words.includes(q) ? 30 : 0;
        if (score > 0)
            found.push({ entry: e, score: score - e.page.length / 100 });
    }
    found.sort((a, b) => b.score - a.score);
    return found.slice(0, 3).map(f => f.entry);
}
