pragma Singleton

import Quickshell

// How many menus and panels are open right now (MenuPopup, MenuBarPopup count themselves):
// the menu bar and the dock over a full-screen app stay while one is (FullscreenReveal.qml)
Singleton {
    property int count: 0
}
