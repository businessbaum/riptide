#pragma once
// riptide-wm: our one Hyprland plugin (docs/os-plan.md, "Architecture"). Two parts:
//   titlebars/       title bars with traffic lights (based on hyprbars, see titlebars/LICENSE)
//   window_buttons   drag/minimize/zoom for apps with their own title bar, no resizing at
//                    the top edge, the menu bar as a border, ⌥/⌘ release for the switcher

#include <hyprland/src/plugins/PluginAPI.hpp>

inline HANDLE PHANDLE = nullptr;

void titlebarsInit();
void titlebarsExit();
void windowButtonsInit();
void windowButtonsExit();
