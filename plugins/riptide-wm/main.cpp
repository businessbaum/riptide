// riptide-wm – our one Hyprland plugin (plugin.hpp). Loaded at login by
// hypr/modules/autostart.lua; built by plugins/build.sh for the installed Hyprland.

#include "plugin.hpp"

#include <stdexcept>
#include <string>

APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    PHANDLE = handle;

    if (std::string(__hyprland_api_get_hash()) != std::string(__hyprland_api_get_client_hash()))
        throw std::runtime_error("[riptide-wm] built for another Hyprland version");

    windowButtonsInit();
    titlebarsInit(); // last: it reloads the config once its options exist

    return {"riptide-wm", "Title bars with traffic lights and macOS-style window behaviour", "riptide (title bars: hyprbars by Vaxry)", "1.0"};
}

// Unloading: every part removes what it hooked while its code is still loaded
APICALL EXPORT void PLUGIN_EXIT() {
    windowButtonsExit();
    titlebarsExit();
}
