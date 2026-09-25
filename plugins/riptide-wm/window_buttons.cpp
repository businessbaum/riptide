// window buttons – part of riptide-wm (plugin.hpp)
//
// Apps with their own title bar (GNOME apps like Finder/Nautilus, GTK apps) send the
// Wayland request "xdg_toplevel.move" when dragged by their bar. Hyprland (0.55, 0.56) ignores
// it – that is why Finder could not be moved. This plugin answers those requests the
// way our macOS-style desktop expects:
//
//   drag at the title bar   → Hyprland moves the window,
//                             on release macos.drag_ended() runs (snapping)
//   minimize button (yellow) → hidden desktop "minimized" (like ⌘M)
//   maximize button (green)  → macos.zoom() (like our own title bars)
//   top edge of any window   → moves the window instead of resizing it (Hyprland's grab
//                              zone there kept catching drags meant for the title bar)
//   menu bar                 → a border: a dragged window never goes above it
//
// It also tells the window switcher (⌥Tab / ⌘Tab) when ⌥ or ⌘ is released.

#include <wayland-server.h>
#include <cstring>
#include <format>
#include <linux/input-event-codes.h>

#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/Compositor.hpp>
#include <hyprland/src/desktop/view/Window.hpp>
#include <hyprland/src/desktop/state/FocusState.hpp>
#include <hyprland/src/desktop/state/WindowState.hpp>
#include <hyprland/src/desktop/state/ViewState.hpp>
#include <hyprland/src/desktop/state/ViewHitTester.hpp>
#include <hyprland/src/managers/fullscreen/FullscreenController.hpp>
#include <hyprland/src/config/ConfigValue.hpp>
#include <hyprland/src/layout/LayoutManager.hpp>
#include <hyprland/src/layout/target/Target.hpp>
#include <hyprland/src/output/Monitor.hpp>
#include <hyprland/src/render/decorations/DecorationPositioner.hpp>
#include <hyprland/src/state/MonitorState.hpp>
#include <hyprland/src/protocols/XDGShell.hpp>
#include <hyprland/src/protocols/core/Compositor.hpp>
#include <hyprland/src/managers/KeybindManager.hpp>
#include <hyprland/src/managers/input/InputManager.hpp>
#include <hyprland/src/layout/LayoutManager.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/config/supplementary/executor/Executor.hpp>
#include <hyprland/protocols/xdg-shell.hpp>

#include "plugin.hpp"

static bool g_dragging   = false;
static bool g_buttonDown = false; // is the left mouse button pressed right now?

// ⌥Tab / ⌘Tab: which modifier keys are held, and did Tab come while one of them was
static bool g_altHeld = false, g_superHeld = false, g_switching = false;

static void runCommand(const std::string& cmd) {
    Config::Supplementary::executor()->spawn(cmd);
}

static PHLWINDOW windowOf(CXdgToplevel* r) {
    const auto TL = CXDGToplevelResource::fromResource(r->resource());
    return TL ? TL->m_window.lock() : nullptr;
}

// The requests arrive at the Wayland object "xdg_toplevel". Hyprland keeps it private,
// so we look it up among all objects of the app.
struct SLookup {
    SP<CXDGToplevelResource> wanted;
    CXdgToplevel*            found = nullptr;
};

static wl_iterator_result checkResource(wl_resource* res, void* data) {
    auto* s = sc<SLookup*>(data);
    if (std::strcmp(wl_resource_get_class(res), "xdg_toplevel") != 0)
        return WL_ITERATOR_CONTINUE;
    if (CXDGToplevelResource::fromResource(res) != s->wanted)
        return WL_ITERATOR_CONTINUE;
    s->found = sc<CXdgToplevel*>(wl_resource_get_user_data(res));
    return WL_ITERATOR_STOP;
}

// The xdg_toplevel object of a window, or nullptr (X11 apps, windows without a surface)
static SLookup findToplevel(PHLWINDOW w) {
    if (!w || w->m_isX11 || !w->m_xdgSurface || !w->m_xdgSurface->m_toplevel || !w->wlSurface() || !w->wlSurface()->resource())
        return {};

    SLookup s{.wanted = w->m_xdgSurface->m_toplevel.lock()};
    wl_client_for_each_resource(w->wlSurface()->resource()->client(), checkResource, &s);
    return s;
}

static void hookWindow(PHLWINDOW w) {
    auto s = findToplevel(w);
    if (!s.found)
        return;

    s.found->setMove([](CXdgToplevel* r, wl_resource*, uint32_t) {
        const auto W = windowOf(r);
        // only while the mouse button is held, otherwise the drag would get stuck
        // (a fullscreen window is not floating in Hyprland's sense, so it is left alone)
        if (!W || !W->m_isFloating || !g_buttonDown)
            return;
        Desktop::focusState()->fullWindowFocus(W, Desktop::FOCUS_REASON_CLICK);
        g_pKeybindManager->changeMouseBindMode(MBIND_MOVE);
        g_dragging = true;
    });

    s.found->setSetMinimized([](CXdgToplevel* r) {
        const auto W = windowOf(r);
        if (!W)
            return;
        runCommand(std::format("hyprctl dispatch 'hl.dsp.window.move({{ window = \"address:0x{:x}\", workspace = \"special:minimized\", follow = false }})'",
                               rc<uintptr_t>(W.get())));
    });

    s.found->setSetMaximized([](CXdgToplevel*) { runCommand("hyprctl dispatch 'macos.zoom()'"); });
    s.found->setUnsetMaximized([](CXdgToplevel*) { runCommand("hyprctl dispatch 'macos.zoom()'"); });

    // Hyprland only tells apps "fullscreen and maximize are possible". GTK then greys out
    // the minimize button and never sends the request above. Announce minimize as well;
    // the app picks it up with the next configure event, which setSize() schedules.
    if (s.found->version() >= 5) {
        wl_array arr;
        wl_array_init(&arr);
        for (uint32_t cap : {XDG_TOPLEVEL_WM_CAPABILITIES_FULLSCREEN, XDG_TOPLEVEL_WM_CAPABILITIES_MAXIMIZE, XDG_TOPLEVEL_WM_CAPABILITIES_MINIMIZE})
            *sc<uint32_t*>(wl_array_add(&arr, sizeof(uint32_t))) = cap;
        s.found->sendWmCapabilities(&arr);
        wl_array_release(&arr);
        s.wanted->setSize(s.wanted->m_pendingApply.size);
    }
}

// A left-button press in the resize zone along the top edge (above the window, or in its
// rounded top corners) starts a move instead: the top edge never resizes.
static bool moveInsteadOfTopResize(Event::SCallbackInfo& info) {
    static auto PRESIZE = CConfigValue<Config::INTEGER>("general:resize_on_border");
    static auto PBORDER = CConfigValue<Config::INTEGER>("general:border_size");
    static auto PEXTEND = CConfigValue<Config::INTEGER>("general:extend_border_grab_area");
    if (!*PRESIZE)
        return false;

    const auto GRAB = *PBORDER + *PEXTEND;
    const auto POS  = g_pInputManager->getMouseCoordsInternal();
    const auto W    = Desktop::viewState()->hitTest().windowAt(POS, Desktop::View::ALLOW_FLOATING | Desktop::View::RESERVED_EXTENTS | Desktop::View::INPUT_EXTENTS);
    if (!W || !W->m_isFloating || W->m_isX11 || Fullscreen::controller()->isFullscreen(W))
        return false;

    const CBox REAL      = W->geometricBox(Desktop::View::IGeometric::GEOMETRIC_CURRENT);
    const bool ABOVE     = POS.y < REAL.y && POS.y >= REAL.y - GRAB && POS.x >= REAL.x - GRAB && POS.x <= REAL.x + REAL.w + GRAB;
    const bool TOPCORNER = POS.y >= REAL.y && POS.y < REAL.y + W->rounding() && W->isInCurvedCorner(POS.x, POS.y);
    if (!ABOVE && !TOPCORNER)
        return false;

    Desktop::focusState()->fullWindowFocus(W, Desktop::FOCUS_REASON_CLICK);
    g_pKeybindManager->changeMouseBindMode(MBIND_MOVE);
    g_dragging     = true;
    info.cancelled = true;
    return true;
}

// The menu bar is a border: while a window is dragged, it never goes above the free area
// of the screen (below the menu bar), title bar included. Runs every frame, right after
// Hyprland has moved the window with the mouse, so it never shows up above the line.
static void keepDraggedWindowBelowMenuBar() {
    const auto& DRAG = g_layoutManager->dragController();
    if (DRAG->mode() != MBIND_MOVE)
        return;
    const auto TARGET = DRAG->target();
    if (!TARGET || !TARGET->floating())
        return;
    const auto W = TARGET->window();
    if (!W)
        return;
    const auto MON = State::monitorState()->query().vec(g_pInputManager->getMouseCoordsInternal()).run();
    if (!MON)
        return;

    const CBox   WORK = MON->logicalBoxMinusReserved();                                   // below menu bar, above dock
    const double TOP  = WORK.y + g_pDecorationPositioner->getWindowDecorationReserved(W).topLeft.y; // + title bar
    CBox         box  = TARGET->position();
    if (box.y >= TOP)
        return;
    box.y = TOP;
    TARGET->setPositionGlobal(box);
    TARGET->warpPositionSize();
}

void windowButtonsInit() {
    static auto NEW_WINDOW = Event::bus()->m_events.window.open.listen([](PHLWINDOW w) { hookWindow(w); });
    static auto TICK       = Event::bus()->m_events.tick.listen([] { keepDraggedWindowBelowMenuBar(); });

    // Mouse button released → end the drag and check snapping
    static auto MOUSE = Event::bus()->m_events.input.mouse.button.listen([](IPointer::SButtonEvent e, Event::SCallbackInfo& info) {
        if (e.button == BTN_LEFT)
            g_buttonDown = e.state == WL_POINTER_BUTTON_STATE_PRESSED;
        if (e.button == BTN_LEFT && e.state == WL_POINTER_BUTTON_STATE_PRESSED && !g_dragging && moveInsteadOfTopResize(info))
            return;
        if (!g_dragging || e.state == WL_POINTER_BUTTON_STATE_PRESSED)
            return;
        g_dragging = false;
        g_pKeybindManager->changeMouseBindMode(MBIND_INVALID);
        runCommand("hyprctl dispatch 'macos.drag_ended()'");
    });

    // ⌥Tab / ⌘Tab (dotfiles/hypr/modules/switcher.lua): Hyprland's Lua cannot see ⌥ or ⌘
    // being released after Tab. So: Tab pressed while ⌥/⌘ is held starts a switch, and when
    // that key is let go we call macos.switcher_release(). (Right Alt is AltGr for typing.)
    static auto KEY = Event::bus()->m_events.input.keyboard.key.listen([](IKeyboard::SKeyEvent e, Event::SCallbackInfo&) {
        const bool down = e.state == WL_KEYBOARD_KEY_STATE_PRESSED;
        switch (e.keycode) {
            case KEY_LEFTALT: g_altHeld = down; break;
            case KEY_LEFTMETA:
            case KEY_RIGHTMETA: g_superHeld = down; break;
            case KEY_TAB:
                if (down && (g_altHeld || g_superHeld))
                    g_switching = true;
                return;
            default: return;
        }
        if (!down && g_switching && !g_altHeld && !g_superHeld) {
            g_switching = false;
            runCommand("hyprctl dispatch 'macos.switcher_release()'");
        }
    });

    // Windows that are already open
    for (auto& w : Desktop::windowState()->windows())
        if (w->m_isMapped)
            hookWindow(w);
}

// Unloading (e.g. to load a newer build): remove our handlers from every window while
// their code is still loaded – otherwise the next plugin would replace them after this
// library is gone, and Hyprland would crash.
void windowButtonsExit() {
    for (auto& w : Desktop::windowState()->windows()) {
        auto s = findToplevel(w);
        if (!s.found)
            continue;
        s.found->setMove(nullptr);
        s.found->setSetMinimized(nullptr);
        s.found->setSetMaximized(nullptr);
        s.found->setUnsetMaximized(nullptr);
    }
}
