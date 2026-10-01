pragma Singleton

import QtQuick
import Quickshell

// Night Shift like on a Mac: warmer colours in the evening – on a schedule (settings.json
// "nightshift": schedule, from, to in hours) and by hand from the control centre, which
// holds until the schedule's next change (without a schedule: until 7 in the morning).
// The colours are changed by hyprsunset (hyprsunset.service, started neutral) through
// its IPC; temperature: 2700 K (warm) … 5500 K (a little).
Singleton {
    id: root

    readonly property var settings: Config.settings.nightshift ?? ({})
    readonly property bool schedule: settings.schedule === true
    readonly property real from: settings.from ?? 22
    readonly property real to: settings.to ?? 7
    readonly property int temperature: settings.temperature ?? 3800
    // by hand: { on, until } (ms), until the next change of the schedule
    readonly property var override: settings.override ?? null

    property date now: new Date()
    Timer {
        running: true
        repeat: true
        interval: 60 * 1000
        onTriggered: root.now = new Date()
    }

    function inSchedule(d) {
        if (!schedule)
            return false;
        const h = d.getHours() + d.getMinutes() / 60;
        return from <= to ? h >= from && h < to : h >= from || h < to;
    }
    readonly property bool scheduled: inSchedule(now)
    readonly property bool active: override && now.getTime() < override.until ? override.on : scheduled

    // The next time the schedule changes its mind (or 7:00 without a schedule)
    function nextChange() {
        const d = new Date(now.getTime());
        const target = schedule ? (scheduled ? to : from) : 7;
        d.setHours(Math.floor(target), Math.round((target % 1) * 60), 0, 0);
        if (d.getTime() <= now.getTime())
            d.setDate(d.getDate() + 1);
        return d.getTime();
    }

    function toggle() {
        now = new Date();
        const on = !active;
        // back to what the schedule says: no override needed
        const override = on === scheduled ? null : { on: on, until: nextChange() };
        Config.updateSettings(s => {
            s.nightshift = s.nightshift ?? {};
            s.nightshift.override = override;
        });
    }

    // what hyprsunset shows
    readonly property string wanted: active ? "temperature " + temperature : "identity"
    onWantedChanged: apply()
    Component.onCompleted: apply()
    function apply() {
        Quickshell.execDetached(["hyprctl", "hyprsunset"].concat(wanted.split(" ")));
    }
    // hyprsunset restarted (it forgets): say it again now and then
    Timer {
        running: true
        repeat: true
        interval: 10 * 60 * 1000
        onTriggered: root.apply()
    }
}
