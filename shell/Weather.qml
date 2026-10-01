pragma Singleton

import QtQuick
import Quickshell

// The weather for the lock screen (LockInfo.qml), from Open-Meteo: free, no account, no key.
// Only the chosen place is sent (settings.json lockscreen.place, picked in System Settings →
// Bildschirme with search()). Fetched only while someone shows it (watch), every 30 minutes;
// after a failure (no network yet at boot) again a minute later.
Singleton {
    id: root

    readonly property var place: Config.settings.lockscreen?.place ?? null
    property var current: null // { temperature, feels, code, day }
    property var hours: []     // [{ time: "2026-09-28T19:00", temperature, code, rain (%), day }], from this hour on
    property var days: []      // [{ date, code, max, min, rain (%), sunrise, sunset }], today first, 7 days
    property double fetchedAt: 0

    property int watchers: 0
    function watch(on) {
        watchers = Math.max(0, watchers + (on ? 1 : -1));
    }
    readonly property bool active: watchers > 0 && place !== null
    onActiveChanged: if (active && Date.now() - fetchedAt > 15 * 60 * 1000) fetch()
    readonly property string placeKey: place ? `${place.lat},${place.lon}` : ""
    onPlaceKeyChanged: {
        current = null;
        hours = [];
        days = [];
        fetchedAt = 0;
        if (active)
            fetch();
    }

    Timer {
        running: root.active
        repeat: true
        interval: 30 * 60 * 1000
        onTriggered: root.fetch()
    }
    Timer {
        id: retry
        interval: 60 * 1000
        onTriggered: if (root.active) root.fetch()
    }

    function fetch() {
        const lat = Number(place?.lat), lon = Number(place?.lon);
        if (!isFinite(lat) || !isFinite(lon))
            return;
        get(`https://api.open-meteo.com/v1/forecast?latitude=${lat.toFixed(3)}&longitude=${lon.toFixed(3)}`
            + "&current=temperature_2m,apparent_temperature,weather_code,is_day"
            + "&hourly=temperature_2m,weather_code,precipitation_probability,is_day&forecast_hours=26"
            + "&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset"
            + "&timezone=auto&forecast_days=7", d => {
            current = { temperature: d.current.temperature_2m, feels: d.current.apparent_temperature,
                        code: d.current.weather_code, day: d.current.is_day === 1 };
            const h = d.hourly ?? {}, hourList = [];
            for (let i = 0; i < (h.time?.length ?? 0); i++)
                hourList.push({ time: h.time[i], temperature: h.temperature_2m[i], code: h.weather_code[i],
                                rain: h.precipitation_probability?.[i] ?? 0, day: h.is_day?.[i] === 1 });
            hours = hourList;
            const dl = d.daily ?? {}, dayList = [];
            for (let i = 0; i < (dl.time?.length ?? 0); i++)
                dayList.push({ date: dl.time[i], code: dl.weather_code[i], max: dl.temperature_2m_max[i],
                               min: dl.temperature_2m_min[i], rain: dl.precipitation_probability_max?.[i] ?? 0,
                               sunrise: dl.sunrise?.[i] ?? "", sunset: dl.sunset?.[i] ?? "" });
            days = dayList;
            fetchedAt = Date.now();
        }, () => retry.restart());
    }

    // Places for a name ("Mün" → München, Münster …): done([{ name, region, lat, lon }]) or done(null)
    function search(name, done) {
        get("https://geocoding-api.open-meteo.com/v1/search?count=6&language=de&format=json&name=" + encodeURIComponent(name),
            d => {
                const list = [];
                for (const r of d.results ?? [])
                    list.push({ name: r.name, region: [r.admin1, r.country].filter(s => s).join(", "), lat: r.latitude, lon: r.longitude });
                done(list);
            }, () => done(null));
    }

    function get(url, ok, failed) {
        const request = new XMLHttpRequest();
        request.onreadystatechange = () => {
            if (request.readyState !== XMLHttpRequest.DONE)
                return;
            let data = null;
            try {
                data = request.status === 200 ? JSON.parse(request.responseText) : null;
            } catch (e) {}
            if (data)
                ok(data);
            else
                failed();
        };
        request.open("GET", url);
        request.send();
    }

    // WMO weather code → words and a symbol (Symbols Nerd Font, md-weather_*)
    function describe(code, day) {
        const c = Number(code);
        if (c <= 1)
            return { text: c === 0 ? "Klar" : "Überwiegend klar", glyph: day === false ? "\u{f0594}" : "\u{f0599}" };
        if (c === 2)
            return { text: "Teilweise bewölkt", glyph: day === false ? "\u{f0f31}" : "\u{f0595}" };
        if (c === 3)
            return { text: "Bedeckt", glyph: "\u{f0590}" };
        if (c === 45 || c === 48)
            return { text: "Nebel", glyph: "\u{f0591}" };
        if (c >= 51 && c <= 55)
            return { text: "Nieselregen", glyph: "\u{f0f33}" };
        if (c === 56 || c === 57 || c === 66 || c === 67)
            return { text: "Gefrierender Regen", glyph: "\u{f067f}" };
        if (c === 61 || c === 63)
            return { text: "Regen", glyph: "\u{f0597}" };
        if (c === 65)
            return { text: "Starker Regen", glyph: "\u{f0596}" };
        if (c >= 71 && c <= 77)
            return { text: c === 75 ? "Starker Schneefall" : "Schnee", glyph: c === 75 ? "\u{f0f36}" : "\u{f0598}" };
        if (c >= 80 && c <= 82)
            return { text: c === 82 ? "Heftige Schauer" : "Regenschauer", glyph: c === 82 ? "\u{f0596}" : "\u{f0f33}" };
        if (c === 85 || c === 86)
            return { text: "Schneeschauer", glyph: "\u{f0f34}" };
        if (c === 95)
            return { text: "Gewitter", glyph: "\u{f067e}" };
        if (c === 96 || c === 99)
            return { text: "Gewitter mit Hagel", glyph: "\u{f0592}" };
        return { text: "", glyph: "\u{f0590}" };
    }
}
