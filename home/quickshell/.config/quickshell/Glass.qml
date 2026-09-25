import QtQuick

// The frosted surface every popup of the shell is made of: menus, panels, dialogs,
// banners, tooltips. Change the look here and all of them follow.
Rectangle {
    radius: Config.radiusPanel
    color: Config.glassMenu
    border.color: Config.border
}
