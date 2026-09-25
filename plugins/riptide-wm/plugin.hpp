#pragma once
// riptide-wm: our one Hyprland plugin (docs/os-plan.md, "Architecture"). Two parts:
//   titlebars/       title bars with traffic lights (based on hyprbars, see titlebars/LICENSE)
//   window_buttons   drag/minimize/zoom for apps with their own title bar, no resizing at
//                    the top edge, the menu bar as a border, ⌥/⌘ release for the switcher

#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/managers/input/InputManager.hpp>

inline HANDLE PHANDLE = nullptr;

// A dialog takes all input right now (a layer with exclusive keyboard focus: our share
// dialog, the password prompt): Hyprland then ignores clicks on windows, and so must our
// title bars and window edges – the desktop behind a dialog is inert as a whole.
inline bool dialogOpen() {
    return !g_pInputManager->m_exclusiveLSes.empty();
}

void titlebarsInit();
void titlebarsExit();
void windowButtonsInit();
void windowButtonsExit();
