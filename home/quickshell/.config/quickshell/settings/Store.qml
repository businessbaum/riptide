pragma Singleton

import Quickshell
import qs

// Read and write one value in settings.json, e.g. Store.set("dock", "size", 56).
// `hypr`: Hyprland reads this value too → reload it ("monitors" also re-applies screens).
Singleton {
    function get(section, key, fallback) {
        return Config.settings[section]?.[key] ?? fallback;
    }

    function set(section, key, value, hypr) {
        Config.updateSettings(s => {
            s[section] = s[section] ?? {};
            s[section][key] = value;
        });
        if (hypr)
            HyprReload.soon(hypr === "monitors");
    }
}
