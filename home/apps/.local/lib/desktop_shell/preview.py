"""Vorschau – like Preview and QuickTime on a Mac: one app to look at files.

    pictures   PNG, JPEG, WebP, HEIC, SVG, TIFF, BMP …  zoom, rotate, ←/→ through the folder
    audio      MP3, FLAC, OGG, WAV, M4A …                play with controls
    video      MP4, MKV, WebM, MOV, AVI, GIF …           play with controls
    PDF        read, search, mark up, fill forms, sign, rearrange pages (pdf_document.py)

Every file opens in its own window. Without a file an "Open" dialog appears.
Shortcuts (⌘ is translated to ⌃ by Hyprland): ⌘O open, ⌘S save, ⌘⇧S save as,
⌘Z undo, ⌘C copy marked text, ⌘F find, ⌘+ / ⌘- / ⌘0 zoom, ⌘W close, space play/pause.
"""

import os
import sys

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Gdk", "4.0")
gi.require_version("Adw", "1")
gi.require_version("GdkPixbuf", "2.0")
gi.require_version("Gst", "1.0")
# drawing on pages (selection, markup, search hits) needs pycairo (package python-cairo);
# without it GTK silently draws nothing
gi.require_foreign("cairo")
from gi.repository import Adw, Gdk, GdkPixbuf, Gio, GLib, GObject, Gst, Gtk  # noqa: E402

from .pdf_document import PdfDocument  # noqa: E402

CSS = """
.page {
    background: white;
    box-shadow: 0 1px 4px rgba(0, 0, 0, 0.35);
}
.thumbnail { box-shadow: 0 1px 3px rgba(0, 0, 0, 0.35); }
.pages-sidebar row { padding: 8px 6px; border-radius: 8px; }
.pages-sidebar row:selected { background: alpha(@accent_bg_color, 0.35); }
.viewer-background { background: alpha(black, 0.15); }
.audio-title { font-size: 20px; font-weight: 600; }
"""

PICTURE_SAVE_TYPES = {"png": "png", "jpg": "jpeg", "jpeg": "jpeg", "bmp": "bmp", "tif": "tiff",
                      "tiff": "tiff", "ico": "ico"}


def content_type(gfile):
    try:
        info = gfile.query_info("standard::content-type", Gio.FileQueryInfoFlags.NONE, None)
        return info.get_content_type() or ""
    except GLib.Error:
        return Gio.content_type_guess(gfile.get_basename(), None)[0] or ""


def kind_of(gfile):
    ctype = content_type(gfile)
    if ctype == "application/pdf":
        return "pdf"
    if ctype == "image/gif":
        return "video"  # animated – played like a short video, in a loop
    if ctype.startswith("image/"):
        return "image"
    if ctype.startswith("audio/"):
        return "audio"
    if ctype.startswith("video/"):
        return "video"
    return None


def message_page(icon, title, text=""):
    return Adw.StatusPage(icon_name=icon, title=title, description=text)


# ======================================================================
# Pictures
# ======================================================================

class ImageView:
    """A picture: fits the window, ⌘+ / ⌘- zoom, rotate, ←/→ to the next picture in the folder."""

    def __init__(self, window, gfile):
        self.window = window
        self.dirty = False
        self.zoom = None  # None = fit into the window
        self.picture = Gtk.Picture(can_shrink=True, content_fit=Gtk.ContentFit.CONTAIN,
                                   hexpand=True, vexpand=True)
        self.scroller = Gtk.ScrolledWindow(child=self.picture)
        self.scroller.add_css_class("viewer-background")
        self.widget = self.scroller

        scroll = Gtk.EventControllerScroll(flags=Gtk.EventControllerScrollFlags.VERTICAL)
        scroll.connect("scroll", self.on_scroll)
        self.scroller.add_controller(scroll)
        keys = Gtk.EventControllerKey()
        keys.connect("key-pressed", self.on_key)
        window.add_controller(keys)

        for icon, tip, action in (("object-rotate-left-symbolic", "Nach links drehen", lambda: self.rotate(90)),
                                  ("object-rotate-right-symbolic", "Nach rechts drehen", lambda: self.rotate(-90))):
            b = Gtk.Button(icon_name=icon, tooltip_text=tip)
            b.connect("clicked", lambda *_, a=action: a())
            window.header.pack_end(b)
        self.load(gfile)

    def load(self, gfile):
        self.gfile = gfile
        try:
            self.pixbuf = GdkPixbuf.Pixbuf.new_from_file(gfile.get_path())
        except GLib.Error as e:
            self.scroller.set_child(message_page("image-missing-symbolic", "Bild kann nicht geöffnet werden", e.message))
            return
        self.scroller.set_child(self.picture)
        self.dirty = False
        self.zoom = None
        self.show()
        self.window.set_file(gfile, f"{self.pixbuf.get_width()} × {self.pixbuf.get_height()}")

    def show(self):
        self.picture.set_paintable(Gdk.Texture.new_for_pixbuf(self.pixbuf))
        if self.zoom is None:
            self.picture.set_size_request(-1, -1)
            self.picture.set_can_shrink(True)
            self.picture.set_content_fit(Gtk.ContentFit.CONTAIN)
        else:
            self.picture.set_can_shrink(False)
            self.picture.set_content_fit(Gtk.ContentFit.FILL)
            self.picture.set_size_request(int(self.pixbuf.get_width() * self.zoom),
                                          int(self.pixbuf.get_height() * self.zoom))

    # ---------- zoom ----------

    def fitted_zoom(self):
        w, h = self.scroller.get_width() or 800, self.scroller.get_height() or 600
        return min(w / self.pixbuf.get_width(), h / self.pixbuf.get_height(), 1.0)

    def zoom_by(self, factor):
        self.zoom = max(0.05, min(20.0, (self.zoom or self.fitted_zoom()) * factor))
        self.show()

    def zoom_in(self):
        self.zoom_by(1.25)

    def zoom_out(self):
        self.zoom_by(0.8)

    def zoom_reset(self):
        self.zoom = None
        self.show()

    def on_scroll(self, controller, _dx, dy):
        if controller.get_current_event_state() & Gdk.ModifierType.CONTROL_MASK:
            self.zoom_by(0.9 if dy > 0 else 1.1)
            return True
        return False

    # ---------- rotate, next picture ----------

    def rotate(self, degrees):
        self.pixbuf = self.pixbuf.rotate_simple(degrees % 360)
        self.dirty = True
        self.window.update_title()
        self.show()

    def neighbours(self):
        folder = self.gfile.get_parent()
        names = []
        for info in folder.enumerate_children("standard::name,standard::content-type",
                                              Gio.FileQueryInfoFlags.NONE, None):
            ctype = info.get_content_type() or ""
            if ctype.startswith("image/") and ctype != "image/gif":
                names.append(info.get_name())
        return folder, sorted(names, key=str.lower)

    def step(self, direction):
        if self.dirty:
            self.window.toast("Erst sichern (⌘S) – das Bild wurde gedreht.")
            return
        folder, names = self.neighbours()
        name = self.gfile.get_basename()
        if name not in names or len(names) < 2:
            return
        self.load(folder.get_child(names[(names.index(name) + direction) % len(names)]))

    def on_key(self, _controller, keyval, _code, state):
        if state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.ALT_MASK):
            return False
        if keyval in (Gdk.KEY_Right, Gdk.KEY_Down, Gdk.KEY_space):
            self.step(1)
            return True
        if keyval in (Gdk.KEY_Left, Gdk.KEY_Up, Gdk.KEY_BackSpace):
            self.step(-1)
            return True
        return False

    # ---------- saving ----------

    def save(self, path=None):
        path = path or self.gfile.get_path()
        kind = PICTURE_SAVE_TYPES.get(os.path.splitext(path)[1].lower().lstrip("."))
        if not kind:
            self.window.save_as()  # e.g. WebP/HEIC cannot be written – choose PNG or JPEG
            return False
        options = (["quality"], ["95"]) if kind == "jpeg" else ([], [])
        self.pixbuf.savev(path, kind, *options)
        self.dirty = False
        self.gfile = Gio.File.new_for_path(path)
        self.window.set_file(self.gfile)
        return True


# ======================================================================
# Audio and video
# ======================================================================

class VideoView:
    """Video (and animated GIF) with GTK's own player and controls."""

    def __init__(self, window, gfile):
        self.dirty = False
        self.window = window
        self.media = Gtk.MediaFile.new_for_file(gfile)
        self.media.set_loop(content_type(gfile) == "image/gif")
        self.media.connect("notify::error", self.on_error)
        self.widget = Gtk.Video(media_stream=self.media, autoplay=True, hexpand=True, vexpand=True)
        self.widget.add_css_class("viewer-background")
        keys = Gtk.EventControllerKey()
        keys.connect("key-pressed", self.on_key)
        window.add_controller(keys)
        window.connect("close-request", lambda *_: (self.media.pause(), False)[1])
        window.set_file(gfile)

    def on_error(self, *_):
        err = self.media.get_error()
        if err:
            self.window.content.set_content(message_page("dialog-error-symbolic", "Kann nicht abgespielt werden", err.message))

    def on_key(self, _controller, keyval, _code, state):
        if keyval == Gdk.KEY_space and not state & Gdk.ModifierType.CONTROL_MASK:
            self.media.set_playing(not self.media.get_playing())
            return True
        return False


class AudioView:
    """Music: GStreamer's "playbin" directly, with our own controls.
    (GTK's player uses playbin3, which crashes on MP3 files in GStreamer 1.26.)"""

    def __init__(self, window, gfile):
        Gst.init(None)
        self.dirty = False
        self.window = window
        self.closed = False
        self.seeking = False
        self.player = Gst.ElementFactory.make("playbin", None)
        self.player.set_property("uri", gfile.get_uri())
        self.player.set_property("video-sink", Gst.ElementFactory.make("fakesink", None))
        bus = self.player.get_bus()
        bus.add_signal_watch()
        bus.connect("message::eos", lambda *_: self.stopped())
        bus.connect("message::error", self.on_error)
        bus.connect("message::tag", self.on_tags)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16,
                      valign=Gtk.Align.CENTER, margin_start=40, margin_end=40)
        box.append(Gtk.Image(icon_name="audio-x-generic", pixel_size=128))
        self.title = Gtk.Label(label=os.path.splitext(gfile.get_basename())[0], wrap=True,
                               justify=Gtk.Justification.CENTER)
        self.title.add_css_class("audio-title")
        self.artist = Gtk.Label(visible=False)
        self.artist.add_css_class("dim-label")
        box.append(self.title)
        box.append(self.artist)

        self.position = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 0, 1, 1)
        self.position.set_draw_value(False)
        self.position.set_hexpand(True)
        self.position.connect("change-value", self.on_seek)
        self.elapsed = Gtk.Label(label="0:00", width_chars=5)
        self.remaining = Gtk.Label(label="0:00", width_chars=6)
        line = Gtk.Box(spacing=8)
        line.append(self.elapsed)
        line.append(self.position)
        line.append(self.remaining)
        box.append(line)

        self.button = Gtk.Button(icon_name="media-playback-pause-symbolic", halign=Gtk.Align.CENTER)
        self.button.add_css_class("circular")
        self.button.add_css_class("suggested-action")
        self.button.set_size_request(48, 48)
        self.button.connect("clicked", lambda *_: self.toggle())
        box.append(self.button)
        self.widget = box

        keys = Gtk.EventControllerKey()
        keys.connect("key-pressed", self.on_key)
        window.add_controller(keys)
        window.connect("close-request", lambda *_: (self.close(), False)[1])
        window.set_file(gfile)
        self.player.set_state(Gst.State.PLAYING)
        GLib.timeout_add(250, self.tick)

    @staticmethod
    def clock(ns):
        s = max(0, int(ns / Gst.SECOND))
        return f"{s // 3600}:{s // 60 % 60:02d}:{s % 60:02d}" if s >= 3600 else f"{s // 60}:{s % 60:02d}"

    def playing(self):
        return self.player.get_state(0)[1] == Gst.State.PLAYING

    def toggle(self):
        if self.playing():
            self.player.set_state(Gst.State.PAUSED)
            self.button.set_icon_name("media-playback-start-symbolic")
        else:
            self.player.set_state(Gst.State.PLAYING)
            self.button.set_icon_name("media-playback-pause-symbolic")

    def stopped(self):
        self.player.set_state(Gst.State.PAUSED)
        self.player.seek_simple(Gst.Format.TIME, Gst.SeekFlags.FLUSH, 0)
        self.button.set_icon_name("media-playback-start-symbolic")

    def tick(self):
        if self.closed:
            return False
        ok_d, duration = self.player.query_duration(Gst.Format.TIME)
        ok_p, position = self.player.query_position(Gst.Format.TIME)
        if ok_d and ok_p and duration > 0 and not self.seeking:
            self.position.set_range(0, duration)
            self.position.set_value(position)
            self.elapsed.set_label(self.clock(position))
            self.remaining.set_label("-" + self.clock(duration - position))
        return True

    def on_seek(self, _scale, _scroll, value):
        self.player.seek_simple(Gst.Format.TIME, Gst.SeekFlags.FLUSH | Gst.SeekFlags.KEY_UNIT, int(value))
        return False

    def on_tags(self, _bus, message):
        tags = message.parse_tag()
        ok, title = tags.get_string(Gst.TAG_TITLE)
        if ok and title:
            self.title.set_label(title)
        ok, artist = tags.get_string(Gst.TAG_ARTIST)
        if ok and artist:
            self.artist.set_label(artist)
            self.artist.set_visible(True)

    def on_error(self, _bus, message):
        err, _debug = message.parse_error()
        self.close()
        self.window.content.set_content(message_page("dialog-error-symbolic", "Kann nicht abgespielt werden", err.message))

    def on_key(self, _controller, keyval, _code, state):
        if keyval == Gdk.KEY_space and not state & Gdk.ModifierType.CONTROL_MASK:
            self.toggle()
            return True
        return False

    def close(self):
        if not self.closed:
            self.closed = True
            self.player.set_state(Gst.State.NULL)



# ======================================================================
# PDF
# ======================================================================

TOOLS = (("select", "Auswahl", "Über Text ziehen: markieren, ⌘C kopiert · Klick in ein Formularfeld: ausfüllen"),
         ("highlight", "Markieren", "Über Text ziehen, um ihn gelb zu markieren"),
         ("text", "Text", "Klicken, um Text einzufügen"),
         ("draw", "Zeichnen", "Mit der Maus zeichnen oder unterschreiben"),
         ("rect", "Rechteck", "Rechteck ziehen"),
         ("erase", "Entfernen", "Auf eine Markierung klicken, um sie zu entfernen"))


class PdfPage:
    """One page on screen: the rendered picture with a drawing layer on top."""

    def __init__(self, view, n):
        self.view, self.n = view, n
        self.picture = Gtk.Picture(can_shrink=False, content_fit=Gtk.ContentFit.FILL)
        self.layer = Gtk.DrawingArea()
        self.layer.set_draw_func(self.draw_layer)
        self.widget = Gtk.Overlay(child=self.picture, halign=Gtk.Align.CENTER)
        self.widget.add_overlay(self.layer)
        self.widget.add_css_class("page")
        self.rendered_zoom = None
        self.drag = None  # current drag: list of display points
        self.selection = []  # selected words: display rectangles, blue until the next click
        self.resize()

        drag = Gtk.GestureDrag()
        drag.connect("drag-begin", self.on_drag_begin)
        drag.connect("drag-update", self.on_drag_update)
        drag.connect("drag-end", self.on_drag_end)
        self.layer.add_controller(drag)

    def resize(self):
        w, h = self.view.doc.page_size(self.n)
        z = self.view.zoom
        self.width, self.height = int(w * z), int(h * z)
        self.picture.set_size_request(self.width, self.height)
        self.layer.set_size_request(self.width, self.height)

    def render(self):
        if self.rendered_zoom == self.view.zoom:
            return
        w, h, stride, data = self.view.doc.render(self.n, self.view.zoom)
        texture = Gdk.MemoryTexture.new(w, h, Gdk.MemoryFormat.R8G8B8, GLib.Bytes.new(data), stride)
        self.picture.set_paintable(texture)
        self.rendered_zoom = self.view.zoom

    def forget(self):
        """Free the pixels of a page far away from the visible area."""
        self.picture.set_paintable(None)
        self.rendered_zoom = None

    # ---------- mouse ----------

    def to_points(self, x, y):
        return x / self.view.zoom, y / self.view.zoom

    def on_drag_begin(self, _gesture, x, y):
        self.drag = [self.to_points(x, y)]
        self.view.clear_selection()
        self.layer.queue_draw()

    def on_drag_update(self, gesture, dx, dy):
        ok, x, y = gesture.get_start_point()
        self.drag.append(self.to_points(x + dx, y + dy))
        self.layer.queue_draw()

    def on_drag_end(self, gesture, dx, dy):
        points, self.drag = self.drag, None
        self.layer.queue_draw()
        ok, x, y = gesture.get_start_point()
        if not points:
            return
        start, end = points[0], points[-1]
        click = abs(dx) < 3 and abs(dy) < 3
        self.view.on_page_action(self, start, end, points, click, (x, y))

    def draw_layer(self, _area, cr, _w, _h):
        z = self.view.zoom
        # search results of this page
        cr.set_source_rgba(1.0, 0.8, 0.0, 0.35)
        for n, (x0, y0, x1, y1) in self.view.search_hits:
            if n == self.n:
                cr.rectangle(x0 * z, y0 * z, (x1 - x0) * z, (y1 - y0) * z)
                cr.fill()
        # selected text, like in a text editor
        if self.selection:
            cr.set_source_rgba(0.04, 0.52, 1.0, 0.35)
            for x0, y0, x1, y1 in self.selection:
                cr.rectangle(x0 * z, y0 * z, (x1 - x0) * z, (y1 - y0) * z)
                cr.fill()
        if not self.drag:
            return
        tool = self.view.tool
        if tool == "draw":
            cr.set_source_rgb(0.1, 0.2, 0.55)
            cr.set_line_width(2 * z)
            cr.move_to(self.drag[0][0] * z, self.drag[0][1] * z)
            for x, y in self.drag[1:]:
                cr.line_to(x * z, y * z)
            cr.stroke()
        elif tool in ("select", "highlight", "rect") and len(self.drag) > 1:
            (x0, y0), (x1, y1) = self.drag[0], self.drag[-1]
            colour = {"highlight": (1.0, 0.85, 0.2), "rect": (0.9, 0.2, 0.2)}.get(tool, (0.04, 0.52, 1.0))
            cr.set_source_rgba(*colour, 0.25)
            cr.rectangle(min(x0, x1) * z, min(y0, y1) * z, abs(x1 - x0) * z, abs(y1 - y0) * z)
            cr.fill_preserve()
            cr.set_source_rgba(*colour, 0.9)
            cr.set_line_width(1.5)
            cr.stroke()


class PdfView:
    def __init__(self, window, gfile, password=None):
        self.window = window
        self.doc = PdfDocument(gfile.get_path(), password)
        self.zoom = 1.0
        self.tool = "select"
        self.selected = None  # marked text: (page, x0, y0, x1, y1) in display points
        self.search_hits, self.search_index = [], -1
        self.pages = []

        # sidebar with page thumbnails (like Preview)
        self.thumbs = Gtk.ListBox(selection_mode=Gtk.SelectionMode.SINGLE)
        self.thumbs.add_css_class("navigation-sidebar")
        self.thumbs.add_css_class("pages-sidebar")
        self.thumbs.connect("row-activated", lambda _l, row: self.scroll_to(row.get_index()))
        sidebar = Gtk.ScrolledWindow(child=self.thumbs, width_request=150,
                                     hscrollbar_policy=Gtk.PolicyType.NEVER)

        self.column = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=18,
                              margin_top=18, margin_bottom=18, margin_start=18, margin_end=18,
                              halign=Gtk.Align.CENTER)
        self.scroller = Gtk.ScrolledWindow(child=self.column, hexpand=True, vexpand=True)
        self.scroller.add_css_class("viewer-background")
        self.scroller.get_vadjustment().connect("value-changed", lambda *_: self.visible_changed())
        scroll = Gtk.EventControllerScroll(flags=Gtk.EventControllerScrollFlags.VERTICAL)
        scroll.connect("scroll", self.on_scroll)
        self.scroller.add_controller(scroll)

        self.split = Adw.OverlaySplitView(sidebar=sidebar, content=self.scroller, show_sidebar=True,
                                          min_sidebar_width=140, max_sidebar_width=180)

        # search bar (⌘F)
        self.search_entry = Gtk.SearchEntry(placeholder_text="In PDF suchen", width_chars=30)
        self.search_entry.connect("activate", lambda *_: self.find_next())
        self.search_entry.connect("search-changed", lambda *_: self.find(self.search_entry.get_text()))
        self.search_bar = Gtk.SearchBar(child=self.search_entry, show_close_button=True)
        self.search_bar.connect_entry(self.search_entry)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        box.append(self.search_bar)
        box.append(self.split)
        self.widget = box
        self.build_header()
        self.rebuild()
        window.set_file(gfile, f"{len(self.doc)} Seiten")
        GLib.idle_add(self.fit_width)

    @property
    def dirty(self):
        return self.doc.dirty

    # ---------- header bar ----------

    def build_header(self):
        header = self.window.header
        toggle = Gtk.ToggleButton(icon_name="sidebar-show-symbolic", active=True, tooltip_text="Seitenleiste")
        toggle.bind_property("active", self.split, "show-sidebar",
                             GObject.BindingFlags.BIDIRECTIONAL | GObject.BindingFlags.SYNC_CREATE)
        header.pack_start(toggle)

        tools = Adw.ToggleGroup()
        for name, label, tip in TOOLS:
            tools.add(Adw.Toggle(name=name, label=label, tooltip=tip))
        tools.set_active_name("select")
        tools.connect("notify::active-name", lambda g, _: self.set_tool(g.get_active_name()))
        # the tools sit in their own bar below the title bar, like Preview's markup toolbar
        bar = Gtk.CenterBox(center_widget=tools, margin_top=4, margin_bottom=6)
        self.window.content.add_top_bar(bar)

        page_menu = Gio.Menu()
        for label, action in (("Nach links drehen", "win.page-rotate-left"),
                              ("Nach rechts drehen", "win.page-rotate-right"),
                              ("Nach oben", "win.page-up"), ("Nach unten", "win.page-down"),
                              ("PDF danach einfügen …", "win.page-insert"),
                              ("Seite löschen", "win.page-delete")):
            page_menu.append(label, action)
        header.pack_end(Gtk.MenuButton(icon_name="view-paged-symbolic", menu_model=page_menu,
                                       tooltip_text="Seite"))
        find = Gtk.Button(icon_name="system-search-symbolic", tooltip_text="Suchen (⌘F)")
        find.connect("clicked", lambda *_: self.find_start())
        header.pack_end(find)
        undo = Gtk.Button(icon_name="edit-undo-symbolic", tooltip_text="Widerrufen (⌘Z)")
        undo.connect("clicked", lambda *_: self.undo())
        header.pack_end(undo)

        actions = {"page-rotate-left": lambda: self.page_op(lambda n: self.doc.rotate_page(n, -90)),
                   "page-rotate-right": lambda: self.page_op(lambda n: self.doc.rotate_page(n, 90)),
                   "page-up": lambda: self.page_op(lambda n: self.doc.move_page(n, n - 1), -1),
                   "page-down": lambda: self.page_op(lambda n: self.doc.move_page(n, n + 1), 1),
                   "page-delete": lambda: self.page_op(self.delete_page),
                   "page-insert": self.insert_pdf}
        for name, callback in actions.items():
            action = Gio.SimpleAction.new(name, None)
            action.connect("activate", lambda *_, c=callback: c())
            self.window.add_action(action)

    def clear_selection(self):
        self.selected = None
        for p in self.pages:
            if p.selection:
                p.selection = []
                p.layer.queue_draw()

    def copy(self):
        """⌘C: the marked text to the clipboard."""
        if not self.selected:
            return
        text = self.doc.text_in(*self.selected)
        if text:
            Gdk.Display.get_default().get_clipboard().set(text)
            self.window.toast("Text kopiert")

    def set_tool(self, name):
        self.clear_selection()
        self.tool = name or "select"
        cursor = {"text": "text", "draw": "crosshair", "rect": "crosshair",
                  "highlight": "text", "erase": "pointer"}.get(self.tool, "default")
        for p in self.pages:
            p.layer.set_cursor_from_name(cursor)

    # ---------- pages on screen ----------

    def rebuild(self, keep_page=None):
        """Build all page widgets and thumbnails again (after page changes or zoom)."""
        current = self.current_page() if keep_page is None else keep_page
        while child := self.column.get_first_child():
            self.column.remove(child)
        self.pages = [PdfPage(self, n) for n in range(len(self.doc))]
        for p in self.pages:
            self.column.append(p.widget)
        self.set_tool(self.tool)
        self.rebuild_thumbnails()
        GLib.idle_add(lambda: (self.scroll_to(min(current, len(self.pages) - 1)), False)[1])

    def rebuild_thumbnails(self):
        while row := self.thumbs.get_row_at_index(0):
            self.thumbs.remove(row)
        for n in range(len(self.doc)):
            w, h = self.doc.page_size(n)
            zoom = 110 / max(w, h)
            tw, th, stride, data = self.doc.render(n, zoom)
            picture = Gtk.Picture(paintable=Gdk.MemoryTexture.new(tw, th, Gdk.MemoryFormat.R8G8B8,
                                                                    GLib.Bytes.new(data), stride),
                                  can_shrink=False, halign=Gtk.Align.CENTER)
            picture.add_css_class("thumbnail")
            box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
            box.append(picture)
            box.append(Gtk.Label(label=str(n + 1)))
            row = Gtk.ListBoxRow(child=box)
            self.add_thumbnail_dnd(row, n)
            self.thumbs.append(row)

    def add_thumbnail_dnd(self, row, n):
        """Drag a thumbnail onto another one to move the page there (like in Preview)."""
        source = Gtk.DragSource(actions=Gdk.DragAction.MOVE)
        source.connect("prepare", lambda *_: Gdk.ContentProvider.new_for_value(str(n)))
        row.add_controller(source)
        target = Gtk.DropTarget.new(str, Gdk.DragAction.MOVE)
        target.connect("drop", lambda _t, value, *_: self.drop_page(int(value), n))
        row.add_controller(target)

    def drop_page(self, n, to):
        if self.doc.move_page(n, to):
            self.changed(rebuild=True, keep_page=to)
        return True

    def refresh_page(self, n):
        """After a change on page n: draw it and its thumbnail again."""
        self.pages[n].rendered_zoom = None
        self.pages[n].render()
        self.rebuild_thumbnails()
        self.select_thumbnail(n)

    def visible_changed(self):
        """Render the pages in view (and one before/after), forget far ones – keeps memory low."""
        adj = self.scroller.get_vadjustment()
        top, bottom = adj.get_value(), adj.get_value() + adj.get_page_size()
        visible = []
        for p in self.pages:
            ok, bounds = p.widget.compute_bounds(self.column)
            if not ok:
                continue
            y0, y1 = bounds.get_y(), bounds.get_y() + bounds.get_height()
            margin = adj.get_page_size()
            if y1 >= top - margin and y0 <= bottom + margin:
                p.render()
                if y1 >= top and y0 <= bottom:
                    visible.append(p.n)
            elif p.rendered_zoom is not None:
                p.forget()
        if visible:
            self.select_thumbnail(visible[0])
        return False

    def select_thumbnail(self, n):
        row = self.thumbs.get_row_at_index(n)
        if row and self.thumbs.get_selected_row() != row:
            self.thumbs.select_row(row)

    def current_page(self):
        row = self.thumbs.get_selected_row()
        return row.get_index() if row else 0

    def scroll_to(self, n, y_points=None):
        if not (0 <= n < len(self.pages)):
            return
        ok, bounds = self.pages[n].widget.compute_bounds(self.column)
        if not ok:
            GLib.timeout_add(50, lambda: (self.scroll_to(n, y_points), False)[1])
            return
        offset = 0 if y_points is None else max(0, y_points * self.zoom - 80)
        self.scroller.get_vadjustment().set_value(bounds.get_y() + offset)
        self.select_thumbnail(n)
        self.visible_changed()

    # ---------- zoom ----------

    def set_zoom(self, zoom):
        page = self.current_page()
        self.zoom = max(0.25, min(5.0, zoom))
        for p in self.pages:
            p.resize()
            p.forget()
        GLib.idle_add(lambda: (self.scroll_to(page), False)[1])

    def fit_width(self):
        width = self.scroller.get_width()
        if width < 100:
            return True  # not laid out yet – try again
        page_w = max(self.doc.page_size(n)[0] for n in range(min(len(self.doc), 20)))
        self.set_zoom(min((width - 60) / page_w, 2.0))
        return False

    def zoom_in(self):
        self.set_zoom(self.zoom * 1.2)

    def zoom_out(self):
        self.set_zoom(self.zoom / 1.2)

    def zoom_reset(self):
        self.fit_width()

    def on_scroll(self, controller, _dx, dy):
        if controller.get_current_event_state() & Gdk.ModifierType.CONTROL_MASK:
            self.set_zoom(self.zoom * (0.9 if dy > 0 else 1.1))
            return True
        return False

    # ---------- editing ----------

    def changed(self, page=None, rebuild=False, keep_page=None):
        if rebuild:
            self.rebuild(keep_page)
        elif page is not None:
            self.refresh_page(page)
        self.window.update_title()

    def on_page_action(self, page, start, end, points, click, widget_pos):
        n, tool = page.n, self.tool
        (x0, y0), (x1, y1) = start, end
        if tool == "select":
            if click:
                self.fill_field(page, x0, y0, widget_pos)
            else:
                # the words stay marked (blue); ⌘C copies them
                page.selection = self.doc.words_in(n, x0, y0, x1, y1)
                self.selected = (n, x0, y0, x1, y1) if page.selection else None
                page.layer.queue_draw()
        elif tool == "highlight" and not click:
            if self.doc.highlight(n, x0, y0, x1, y1):
                self.changed(n)
            else:
                self.window.toast("Hier ist kein Text zum Markieren")
        elif tool == "text" and click:
            self.ask_text(page, x0, y0, widget_pos)
        elif tool == "draw" and not click:
            if self.doc.draw(n, points):
                self.changed(n)
        elif tool == "rect" and not click:
            if self.doc.rectangle(n, x0, y0, x1, y1):
                self.changed(n)
        elif tool == "erase" and click:
            if self.doc.erase(n, x0, y0):
                self.changed(n)

    def popover_entry(self, page, widget_pos, text, done):
        """A small input field right where the user clicked."""
        entry = Gtk.Entry(text=text or "", width_chars=28, activates_default=True)
        pop = Gtk.Popover(child=entry)
        pop.set_parent(page.layer)
        rect = Gdk.Rectangle()
        rect.x, rect.y, rect.width, rect.height = int(widget_pos[0]), int(widget_pos[1]), 1, 1
        pop.set_pointing_to(rect)
        entry.connect("activate", lambda e: (done(e.get_text()), pop.popdown()))
        pop.connect("closed", lambda p: GLib.idle_add(p.unparent))
        pop.popup()
        entry.grab_focus()

    def ask_text(self, page, x, y, widget_pos):
        def done(text):
            if self.doc.add_text(page.n, x, y, text):
                self.changed(page.n)
        self.popover_entry(page, widget_pos, "", done)

    def fill_field(self, page, x, y, widget_pos):
        field = self.doc.field_at(page.n, x, y)
        if not field:
            return
        index, kind, value = field
        if kind == "checkbox":
            self.doc.set_field(page.n, index)
            self.changed(page.n)
        elif kind == "text":
            def done(text):
                self.doc.set_field(page.n, index, text)
                self.changed(page.n)
            self.popover_entry(page, widget_pos, value, done)

    def page_op(self, operation, moved_by=0):
        n = self.current_page()
        result = operation(n)
        if result is False:
            return
        self.changed(rebuild=True, keep_page=max(0, min(n + moved_by, len(self.doc) - 1)))

    def delete_page(self, n):
        if not self.doc.delete_page(n):
            self.window.toast("Die letzte Seite kann nicht gelöscht werden")
            return False
        return True

    def insert_pdf(self):
        dialog = Gtk.FileDialog(title="PDF einfügen", default_filter=pdf_filter())

        def chosen(d, result):
            try:
                gfile = d.open_finish(result)
            except GLib.Error:
                return
            n = self.current_page()
            count = self.doc.insert_pdf(gfile.get_path(), n)
            self.changed(rebuild=True, keep_page=n + 1)
            self.window.toast(f"{count} Seiten eingefügt")
        dialog.open(self.window, None, chosen)

    def undo(self):
        if not self.doc.can_undo():
            return
        self.doc.undo()
        self.changed(rebuild=True)

    # ---------- search ----------

    def find_start(self):
        self.search_bar.set_search_mode(True)
        self.search_entry.grab_focus()

    def find(self, text):
        self.search_hits = self.doc.search(text) if len(text) >= 2 else []
        self.search_index = -1
        for p in self.pages:
            p.layer.queue_draw()
        if self.search_hits:
            self.find_next()

    def find_next(self):
        if not self.search_hits:
            return
        self.search_index = (self.search_index + 1) % len(self.search_hits)
        n, (x0, y0, x1, y1) = self.search_hits[self.search_index]
        self.scroll_to(n, y0)

    # ---------- saving ----------

    def save(self, path=None):
        try:
            self.doc.save(path)
        except Exception as e:  # noqa: BLE001 – show every problem to the user
            self.window.toast(f"Sichern fehlgeschlagen: {e}")
            return False
        self.window.set_file(Gio.File.new_for_path(self.doc.path), f"{len(self.doc)} Seiten")
        return True


def pdf_filter():
    f = Gtk.FileFilter(name="PDF-Dokumente")
    f.add_mime_type("application/pdf")
    return f


# ======================================================================
# Window and app
# ======================================================================

class Window(Adw.ApplicationWindow):
    def __init__(self, app, gfile):
        super().__init__(application=app, default_width=1000, default_height=720)
        self.gfile = gfile
        self.subtitle = ""
        self.header = Adw.HeaderBar()
        self.title = Adw.WindowTitle()
        self.header.set_title_widget(self.title)
        self.content = Adw.ToolbarView()
        self.content.add_top_bar(self.header)
        self.toasts = Adw.ToastOverlay(child=self.content)
        self.set_content(self.toasts)
        self.view = None

        for name, callback in (("save", self.save), ("save-as", self.save_as), ("undo", self.undo),
                               ("find", self.find), ("zoom-in", lambda: self.call("zoom_in")),
                               ("zoom-out", lambda: self.call("zoom_out")),
                               ("zoom-reset", lambda: self.call("zoom_reset")), ("close", self.close),
                               ("copy", lambda: self.call("copy"))):
            action = Gio.SimpleAction.new(name, None)
            action.connect("activate", lambda *_, c=callback: c())
            self.add_action(action)
        self.connect("close-request", self.on_close_request)
        self.open_file(gfile)

    def open_file(self, gfile, password=None):
        kind = kind_of(gfile)
        try:
            if kind == "pdf":
                self.view = PdfView(self, gfile, password)
            elif kind == "image":
                self.view = ImageView(self, gfile)
            elif kind == "video":
                self.view = VideoView(self, gfile)
            elif kind == "audio":
                self.view = AudioView(self, gfile)
        except PermissionError:
            self.ask_password(gfile)
            return
        except Exception as e:  # noqa: BLE001
            self.set_file(gfile)
            self.content.set_content(message_page("dialog-error-symbolic", "Datei kann nicht geöffnet werden", str(e)))
            return
        if not self.view:
            self.set_file(gfile)
            self.content.set_content(message_page("dialog-question-symbolic", "Dieses Format wird nicht unterstützt",
                                                  content_type(gfile)))
            return
        self.content.set_content(self.view.widget)

    def ask_password(self, gfile):
        self.set_file(gfile)
        entry = Gtk.PasswordEntry(show_peek_icon=True, activates_default=True)
        dialog = Adw.AlertDialog(heading="Passwort erforderlich",
                                 body=f"„{gfile.get_basename()}“ ist geschützt.", extra_child=entry,
                                 default_response="open", close_response="cancel")
        dialog.add_response("cancel", "Abbrechen")
        dialog.add_response("open", "Öffnen")
        dialog.set_response_appearance("open", Adw.ResponseAppearance.SUGGESTED)

        def answered(_d, response):
            if response == "open":
                self.open_file(gfile, entry.get_text())
            else:
                self.close()
        dialog.connect("response", answered)
        dialog.present(self)

    # ---------- title ----------

    def set_file(self, gfile, subtitle=None):
        self.gfile = gfile
        if subtitle is not None:
            self.subtitle = subtitle
        self.update_title()

    def update_title(self):
        name = self.gfile.get_basename()
        edited = self.view is not None and getattr(self.view, "dirty", False)
        self.title.set_title(name + (" – Bearbeitet" if edited else ""))
        self.title.set_subtitle(self.subtitle)
        self.set_title(name)

    def toast(self, text):
        self.toasts.add_toast(Adw.Toast(title=text, timeout=3))

    # ---------- actions ----------

    def call(self, method):
        if self.view and hasattr(self.view, method):
            getattr(self.view, method)()

    def undo(self):
        self.call("undo")

    def find(self):
        self.call("find_start")

    def save(self):
        if self.view and hasattr(self.view, "save") and self.view.dirty:
            if self.view.save():
                self.update_title()
                return True
        return False

    def save_as(self):
        if not self.view or not hasattr(self.view, "save"):
            return
        dialog = Gtk.FileDialog(title="Sichern unter", initial_name=self.gfile.get_basename(),
                                initial_folder=self.gfile.get_parent())

        def chosen(d, result):
            try:
                target = d.save_finish(result)
            except GLib.Error:
                return
            if self.view.save(target.get_path()):
                self.update_title()
        dialog.save(self, None, chosen)

    def on_close_request(self, _window):
        if not (self.view and getattr(self.view, "dirty", False)):
            return False
        dialog = Adw.AlertDialog(heading=f"Änderungen an „{self.gfile.get_basename()}“ sichern?",
                                 body="Ohne Sichern gehen die Änderungen verloren.",
                                 default_response="save", close_response="cancel")
        dialog.add_response("cancel", "Abbrechen")
        dialog.add_response("discard", "Nicht sichern")
        dialog.add_response("save", "Sichern")
        dialog.set_response_appearance("discard", Adw.ResponseAppearance.DESTRUCTIVE)
        dialog.set_response_appearance("save", Adw.ResponseAppearance.SUGGESTED)

        def answered(_d, response):
            if response == "save" and self.view.save():
                self.destroy()
            elif response == "discard":
                self.destroy()
        dialog.connect("response", answered)
        dialog.present(self)
        return True


class Preview(Adw.Application):
    def __init__(self):
        super().__init__(application_id="org.riptide.Preview", flags=Gio.ApplicationFlags.HANDLES_OPEN)

    def do_startup(self):
        Adw.Application.do_startup(self)
        css = Gtk.CssProvider()
        css.load_from_string(CSS)
        Gtk.StyleContext.add_provider_for_display(Gdk.Display.get_default(), css,
                                                  Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        open_action = Gio.SimpleAction.new("open", None)
        open_action.connect("activate", lambda *_: self.choose_file())
        self.add_action(open_action)
        for action, keys in (("app.open", ["<Control>o"]), ("win.save", ["<Control>s"]),
                             ("win.save-as", ["<Control><Shift>s"]), ("win.undo", ["<Control>z"]),
                             ("win.find", ["<Control>f"]), ("win.close", ["<Control>w"]),
                             ("win.zoom-in", ["<Control>plus", "<Control>equal", "<Control>KP_Add"]),
                             ("win.zoom-out", ["<Control>minus", "<Control>KP_Subtract"]),
                             ("win.zoom-reset", ["<Control>0"]), ("win.copy", ["<Control>c"])):
            self.set_accels_for_action(action, keys)

    def do_activate(self):
        if not self.get_windows():
            self.choose_file()

    def do_open(self, files, _n_files, _hint):
        for gfile in files:
            Window(self, gfile).present()

    def choose_file(self):
        dialog = Gtk.FileDialog(title="Öffnen")
        self.hold()  # keep running while the dialog is open without a window

        def chosen(d, result):
            self.release()
            try:
                gfile = d.open_finish(result)
            except GLib.Error:
                return
            Window(self, gfile).present()
        dialog.open(self.get_active_window(), None, chosen)


def main():
    Preview().run(sys.argv)
