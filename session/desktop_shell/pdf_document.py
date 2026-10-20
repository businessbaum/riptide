"""The PDF part of Vorschau (preview.py), without any user interface – so it can be tested.

Built on PyMuPDF (nixpkgs: python3Packages.pymupdf). Two coordinate systems matter:
  - "display" points: the page as it is shown, i.e. already rotated (what the user clicks on)
  - PDF points: the unrotated page; text, search results and annotations live here
Every public method takes and returns display points and converts internally.

Every change is undoable: before a change the whole document is kept in memory
(at most UNDO_STEPS times), undo() goes back to it.
"""

import os
import tempfile

import cairo
import pymupdf as fitz

UNDO_STEPS = 30

HIGHLIGHT = (1.0, 0.85, 0.2)     # like the yellow marker in Preview
INK = (0.1, 0.2, 0.55)           # dark blue, for drawing and signatures
SHAPE = (0.9, 0.2, 0.2)          # red rectangles
TEXT = (0.0, 0.0, 0.0)
TEXT_SIZE = 12


class PdfDocument:
    def __init__(self, path, password=None):
        self.path = path
        self.doc = fitz.open(path)
        if self.doc.needs_pass and not self.doc.authenticate(password or ""):
            raise PermissionError("password required")
        self.undo_stack = []
        self.dirty = False
        self._chars = {}  # page → its characters (text selection), until the next change

    # ---------- basics ----------

    def __len__(self):
        return len(self.doc)

    def page_size(self, n):
        """Size of page n as shown (rotation applied), in points."""
        r = self.doc[n].rect
        return r.width, r.height

    def render(self, n, zoom):
        """Page n as RGB pixels: (width, height, stride, bytes)."""
        pix = self.doc[n].get_pixmap(matrix=fitz.Matrix(zoom, zoom), alpha=False)
        return pix.width, pix.height, pix.stride, pix.samples

    def _to_pdf(self, page, x, y):
        return fitz.Point(x, y) * page.derotation_matrix

    def _rect_to_pdf(self, page, x0, y0, x1, y1):
        return fitz.Rect(self._to_pdf(page, x0, y0), self._to_pdf(page, x1, y1)).normalize()

    def _rect_to_display(self, page, rect):
        return (fitz.Rect(rect) * page.rotation_matrix).normalize()

    # ---------- undo ----------

    def _remember(self):
        self._chars = {}
        self.undo_stack.append(self.doc.tobytes())
        del self.undo_stack[:-UNDO_STEPS]
        self.dirty = True

    def can_undo(self):
        return bool(self.undo_stack)

    def undo(self):
        self._chars = {}
        if self.undo_stack:
            self.doc = fitz.open("pdf", self.undo_stack.pop())
            self.dirty = True

    # ---------- markup (display points in, one page each) ----------

    def highlight(self, n, x0, y0, x1, y1):
        """Highlight the words inside the dragged rectangle. False if there is no text."""
        page = self.doc[n]
        area = self._rect_to_pdf(page, x0, y0, x1, y1)
        words = [fitz.Rect(w[:4]) for w in page.get_text("words") if fitz.Rect(w[:4]).intersects(area)]
        if not words:
            return False
        self._remember()
        annot = page.add_highlight_annot([w.quad for w in words])
        annot.set_colors(stroke=HIGHLIGHT)
        annot.update()
        return True

    def add_text(self, n, x, y, text):
        """A line of text whose top left corner is at (x, y)."""
        if not text.strip():
            return False
        page = self.doc[n]
        width = fitz.get_text_length(text, fontname="helv", fontsize=TEXT_SIZE) + 8
        height = TEXT_SIZE * 1.6
        self._remember()
        rect = self._rect_to_pdf(page, x, y, x + width, y + height)
        annot = page.add_freetext_annot(rect, text, fontsize=TEXT_SIZE, fontname="helv",
                                        text_color=TEXT, rotate=page.rotation)
        annot.update()
        return True

    def draw(self, n, points):
        """A freehand line (also for signatures). points: [(x, y), …]."""
        if len(points) < 2:
            return False
        page = self.doc[n]
        self._remember()
        annot = page.add_ink_annot([[tuple(self._to_pdf(page, x, y)) for x, y in points]])
        annot.set_colors(stroke=INK)
        annot.set_border(width=2)
        annot.update()
        return True

    def rectangle(self, n, x0, y0, x1, y1):
        page = self.doc[n]
        area = self._rect_to_pdf(page, x0, y0, x1, y1)
        if area.width < 3 or area.height < 3:
            return False
        self._remember()
        annot = page.add_rect_annot(area)
        annot.set_colors(stroke=SHAPE)
        annot.set_border(width=2)
        annot.update()
        return True

    def erase(self, n, x, y):
        """Remove the annotation under the point. False if there is none."""
        page = self.doc[n]
        p = self._to_pdf(page, x, y)
        # find it first – deleting while PyMuPDF iterates over the annotations crashes
        hit = next((a.xref for a in page.annots() if a.rect.contains(p)), None)
        if hit is None:
            return False
        self._remember()
        page.delete_annot(page.load_annot(hit))
        return True

    # ---------- text selection, like in a text editor ----------
    # A selection runs from one character to another in reading order – across lines –
    # not over a rectangle. Characters are indexes into chars(n).

    @staticmethod
    def _beside(top0, bottom0, top1, bottom1):
        """Two lines side by side – the cells of a table row: their heights overlap by more
        than half (the lines of a paragraph overlap a little at most)."""
        overlap = min(bottom0, bottom1) - max(top0, top1)
        return overlap > 0.5 * min(bottom0 - top0, bottom1 - top1)

    def chars(self, n):
        """The characters of page n in reading order: [(char, display rect, line)], where
        line is (number, display rect of the whole line)."""
        if n not in self._chars:
            page, found, number = self.doc[n], [], 0
            for block in page.get_text("rawdict").get("blocks", []):
                for line in block.get("lines", []):
                    line_rect = tuple(self._rect_to_display(page, line["bbox"]))
                    for span in line.get("spans", []):
                        for ch in span.get("chars", []):
                            found.append((ch["c"], tuple(self._rect_to_display(page, ch["bbox"])), (number, line_rect)))
                    number += 1
            self._chars[n] = found
        return self._chars[n]

    def char_at(self, n, x, y):
        """The character nearest to (x, y): on the line at that height (else the nearest
        line) – of several at that height (the cells of a table row are lines of their own)
        the one under x, else the nearest –, the character under x (else the nearest).
        None if the page has no text."""
        chars = self.chars(n)
        if not chars:
            return None
        def line_distance(item):
            lx0, ly0, lx1, ly1 = item[1][2][1]
            dy = 0 if ly0 <= y <= ly1 else min(abs(y - ly0), abs(y - ly1))
            dx = 0 if lx0 <= x <= lx1 else min(abs(x - lx0), abs(x - lx1))
            return dy, dx
        best_line = min(enumerate(chars), key=line_distance)[1][2][0]
        on_line = [(i, c) for i, c in enumerate(chars) if c[2][0] == best_line]
        for i, (_, (cx0, _, cx1, _), _) in on_line:
            if cx0 <= x <= cx1:
                return i
        return min(on_line, key=lambda ic: min(abs(x - ic[1][1][0]), abs(x - ic[1][1][2])))[0]

    def selection_rects(self, n, a, b):
        """The marked area of the characters a…b: one rectangle per line."""
        lines = {}
        for ch, (x0, y0, x1, y1), (number, (_, ly0, _, ly1)) in self.chars(n)[min(a, b):max(a, b) + 1]:
            r = lines.get(number)
            lines[number] = (min(r[0], x0), ly0, max(r[2], x1), ly1) if r else (x0, ly0, x1, ly1)
        # the cells of a table row: one band over the row, as in a text editor
        rows = []
        for r in sorted(lines.values(), key=lambda r: (r[1], r[0])):
            row = next((i for i, o in enumerate(rows) if self._beside(o[1], o[3], r[1], r[3])), None)
            if row is None:
                rows.append(r)
            else:
                o = rows[row]
                rows[row] = (min(o[0], r[0]), min(o[1], r[1]), max(o[2], r[2]), max(o[3], r[3]))
        # lines of a paragraph overlap a little: cut each at the one above, so no strip
        # is marked twice (it would look darker)
        rects = sorted(rows, key=lambda r: r[1])
        for i in range(1, len(rects)):
            x0, y0, x1, y1 = rects[i]
            above = rects[i - 1]
            if y0 < above[3] < y1 and min(x1, above[2]) > max(x0, above[0]):
                rects[i] = (x0, above[3], x1, y1)
        return rects

    def selection_text(self, n, a, b):
        """The text of the characters a…b, a line break between lines – a space between
        lines side by side (the cells of a table row)."""
        out, last = [], None
        for ch, _, (number, (_, ly0, _, ly1)) in self.chars(n)[min(a, b):max(a, b) + 1]:
            if last is not None and number != last[0]:
                if not self._beside(last[1], last[2], ly0, ly1):
                    out.append("\n")
                elif not (out and out[-1].isspace()) and not ch.isspace():
                    out.append(" ")
            out.append(ch)
            last = (number, ly0, ly1)
        return "".join(out).strip()

    def word_range(self, n, i):
        """The word around character i: (first, last)."""
        chars = self.chars(n)
        line = chars[i][2][0]
        a = b = i
        while a > 0 and chars[a - 1][2][0] == line and not chars[a - 1][0].isspace():
            a -= 1
        while b < len(chars) - 1 and chars[b + 1][2][0] == line and not chars[b + 1][0].isspace():
            b += 1
        return a, b

    def line_range(self, n, i):
        """The line around character i: (first, last) – with the lines beside it (a table
        row's cells) that come next to it in reading order."""
        chars = self.chars(n)
        _, (_, top, _, bottom) = chars[i][2]
        def same_row(j):
            _, (_, t, _, b) = chars[j][2]
            return chars[j][2][0] == chars[i][2][0] or self._beside(top, bottom, t, b)
        a = b = i
        while a > 0 and same_row(a - 1):
            a -= 1
        while b < len(chars) - 1 and same_row(b + 1):
            b += 1
        return a, b

    def highlight_range(self, n, a, b):
        """Mark the characters a…b yellow (one highlight over the lines)."""
        rects = self.selection_rects(n, a, b)
        if not rects:
            return False
        page = self.doc[n]
        quads = [self._rect_to_pdf(page, *r).quad for r in rects]
        self._remember()
        annot = page.add_highlight_annot(quads)
        annot.set_colors(stroke=HIGHLIGHT)
        annot.update()
        return True

    def words_in(self, n, x0, y0, x1, y1):
        """Where the words inside a rectangle are, as display rectangles (to show a selection)."""
        page = self.doc[n]
        area = self._rect_to_pdf(page, x0, y0, x1, y1)
        return [tuple(self._rect_to_display(page, w[:4])) for w in page.get_text("words")
                if fitz.Rect(w[:4]).intersects(area)]

    def text_in(self, n, x0, y0, x1, y1):
        """The text inside a rectangle (for copying)."""
        page = self.doc[n]
        return page.get_textbox(self._rect_to_pdf(page, x0, y0, x1, y1)).strip()

    # ---------- forms ----------

    def field_at(self, n, x, y):
        """The form field under the point: (index, kind, value) or None.
        kind is "text", "checkbox" or "other"."""
        page = self.doc[n]
        p = self._to_pdf(page, x, y)
        for i, w in enumerate(page.widgets()):
            if w.rect.contains(p):
                kind = {fitz.PDF_WIDGET_TYPE_TEXT: "text",
                        fitz.PDF_WIDGET_TYPE_CHECKBOX: "checkbox"}.get(w.field_type, "other")
                return i, kind, w.field_value
        return None

    def set_field(self, n, index, value=None):
        """Text fields: set the text. Checkboxes: toggle (value is ignored)."""
        page = self.doc[n]
        widget = list(page.widgets())[index]
        self._remember()
        if widget.field_type == fitz.PDF_WIDGET_TYPE_CHECKBOX:
            on = widget.on_state()
            widget.field_value = "Off" if widget.field_value == on else on
        else:
            widget.field_value = value
        widget.update()

    # ---------- pages ----------

    def rotate_page(self, n, degrees):
        self._remember()
        page = self.doc[n]
        page.set_rotation((page.rotation + degrees) % 360)

    def delete_page(self, n):
        if len(self.doc) <= 1:
            return False  # a PDF needs at least one page
        self._remember()
        self.doc.delete_page(n)
        return True

    def move_page(self, n, to):
        """Move page n so that it ends up at position `to`."""
        if n == to or not (0 <= to < len(self.doc)):
            return False
        self._remember()
        # PyMuPDF inserts before the given page (-1 = at the end); moving down needs one more
        before = to + 1 if to > n else to
        self.doc.move_page(n, -1 if before >= len(self.doc) else before)
        return True

    def insert_pdf(self, path, after):
        """Insert all pages of another PDF after page `after`. Returns the number of pages."""
        other = fitz.open(path)
        self._remember()
        self.doc.insert_pdf(other, start_at=after + 1)
        return len(other)

    # ---------- search ----------

    def search(self, text):
        """All places of `text`: [(page, (x0, y0, x1, y1)), …] in display points."""
        hits = []
        if not text:
            return hits
        for n, page in enumerate(self.doc):
            for rect in page.search_for(text):
                r = self._rect_to_display(page, rect)
                hits.append((n, (r.x0, r.y0, r.x1, r.y1)))
        return hits

    # ---------- printing ----------

    def draw_for_print(self, cr, n, width, height, dpi):
        """Draw page n as shown (markup and filled forms included) onto a cairo context in
        points: shrunk to fit width × height when larger, centred, as pixels at the
        printer's resolution `dpi` (PyMuPDF cannot draw onto cairo itself)."""
        page = self.doc[n]
        pw, ph = page.rect.width, page.rect.height
        scale = min(width / pw, height / ph, 1.0)
        pix = page.get_pixmap(matrix=fitz.Matrix(scale * dpi / 72, scale * dpi / 72), alpha=False)
        w, h = pix.width, pix.height
        # cairo wants 32-bit pixels, in memory blue, green, red, unused (little endian)
        data = bytearray(w * h * 4)
        rgb = pix.samples
        data[0::4], data[1::4], data[2::4] = rgb[2::3], rgb[1::3], rgb[0::3]
        del pix, rgb
        image = cairo.ImageSurface.create_for_data(data, cairo.FORMAT_RGB24, w, h, w * 4)
        cr.save()
        cr.translate((width - pw * scale) / 2, (height - ph * scale) / 2)
        cr.scale(72 / dpi, 72 / dpi)
        cr.set_source_surface(image, 0, 0)
        cr.paint()
        cr.restore()

    # ---------- saving ----------

    def save(self, path=None):
        """Write the PDF (to `path`, or over the original). Via a temporary file in the same
        folder, so the original is never half written."""
        target = path or self.path
        folder = os.path.dirname(os.path.abspath(target))
        fd, tmp = tempfile.mkstemp(suffix=".pdf", dir=folder)
        os.close(fd)
        try:
            self.doc.save(tmp, garbage=3, deflate=True)
            os.replace(tmp, target)
        except Exception:
            if os.path.exists(tmp):
                os.unlink(tmp)
            raise
        self.path = target
        self.dirty = False
