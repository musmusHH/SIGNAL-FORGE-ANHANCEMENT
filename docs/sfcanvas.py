"""Faithful Python emulation of the MQL4 CCanvas primitives used by the EA.

The previous renderers drew panels with PIL's rounded_rectangle, which produces
CORRECT rounded corners. The EA's RoundRect() built its corners from
CCanvas::Circle(), which draws a FULL RING - leaving an 'O' bubble at every
corner. Because the renderer never executed the EA's own corner algorithm, it
could not reproduce that defect, and the bug shipped.

These primitives mirror the .mq4 implementations line for line, so a defect in
the EA's drawing logic shows up in the preview.
"""
from PIL import Image

class Canvas:
    def __init__(self, w, h, bg=(8, 11, 20)):
        self.w, self.h = w, h
        self.img = Image.new("RGB", (w, h), bg)
        self.px = self.img.load()

    def _blend(self, x, y, c):
        if not (0 <= x < self.w and 0 <= y < self.h):
            return
        if len(c) == 4:
            a = c[3] / 255.0
            if a <= 0:
                return
            o = self.px[x, y]
            self.px[x, y] = (int(c[0]*a + o[0]*(1-a)),
                             int(c[1]*a + o[1]*(1-a)),
                             int(c[2]*a + o[2]*(1-a)))
        else:
            self.px[x, y] = c

    def PixelSet(self, x, y, c):
        self._blend(int(x), int(y), c)

    def FillRectangle(self, x1, y1, x2, y2, c):
        x1, y1, x2, y2 = int(x1), int(y1), int(x2), int(y2)
        if x2 < x1: x1, x2 = x2, x1
        if y2 < y1: y1, y2 = y2, y1
        for yy in range(y1, y2 + 1):
            for xx in range(x1, x2 + 1):
                self._blend(xx, yy, c)

    def FillCircle(self, cx, cy, r, c):
        cx, cy, r = int(cx), int(cy), int(r)
        for yy in range(cy - r, cy + r + 1):
            for xx in range(cx - r, cx + r + 1):
                if (xx - cx) ** 2 + (yy - cy) ** 2 <= r * r:
                    self._blend(xx, yy, c)

    def Circle(self, cx, cy, r, c):
        """CCanvas::Circle - a FULL ring. This is the call that caused the bug."""
        cx, cy, r = int(cx), int(cy), int(r)
        x, y, err = r, 0, 1 - r
        while x >= y:
            for sx, sy in ((x, y), (y, x), (-x, y), (-y, x),
                           (x, -y), (y, -x), (-x, -y), (-y, -x)):
                self._blend(cx + sx, cy + sy, c)
            y += 1
            if err < 0: err += 2 * y + 1
            else:
                x -= 1; err += 2 * (y - x) + 1

    def ArcQuarter(self, cx, cy, r, quad, c):
        """Mirrors the EA's ArcQuarter(): one quadrant only. 0=TL 1=TR 2=BL 3=BR"""
        if r <= 0: return
        cx, cy, r = int(cx), int(cy), int(r)
        x, y, err = r, 0, 1 - r
        while x >= y:
            if quad == 0:   pts = ((-x, -y), (-y, -x))
            elif quad == 1: pts = ((x, -y), (y, -x))
            elif quad == 2: pts = ((-x, y), (-y, x))
            else:           pts = ((x, y), (y, x))
            for sx, sy in pts:
                self._blend(cx + sx, cy + sy, c)
            y += 1
            if err < 0: err += 2 * y + 1
            else:
                x -= 1; err += 2 * (y - x) + 1

    def Line(self, x1, y1, x2, y2, c):
        x1, y1, x2, y2 = int(x1), int(y1), int(x2), int(y2)
        dx, dy = abs(x2 - x1), -abs(y2 - y1)
        sx = 1 if x1 < x2 else -1
        sy = 1 if y1 < y2 else -1
        err = dx + dy
        while True:
            self._blend(x1, y1, c)
            if x1 == x2 and y1 == y2: break
            e2 = 2 * err
            if e2 >= dy: err += dy; x1 += sx
            if e2 <= dx: err += dx; y1 += sy

    def save(self, path):
        self.img.save(path)


def RoundRect(cv, x, y, w, h, r, fill, border, drawBorder=True, use_arc=True):
    """Mirrors the EA's RoundRect(). use_arc=False reproduces the OLD buggy
    full-ring corners, so the regression test can prove the bug is gone."""
    if w <= 0 or h <= 0: return
    r = max(0, min(r, min(w, h) // 2))
    cv.FillRectangle(x + r, y, x + w - r, y + h, fill)
    cv.FillRectangle(x, y + r, x + r, y + h - r, fill)
    cv.FillRectangle(x + w - r, y + r, x + w, y + h - r, fill)
    if r > 0:
        cv.FillCircle(x + r, y + r, r, fill)
        cv.FillCircle(x + w - r - 1, y + r, r, fill)
        cv.FillCircle(x + r, y + h - r - 1, r, fill)
        cv.FillCircle(x + w - r - 1, y + h - r - 1, r, fill)
    if drawBorder:
        cv.Line(x + r, y, x + w - r, y, border)
        cv.Line(x + r, y + h - 1, x + w - r, y + h - 1, border)
        cv.Line(x, y + r, x, y + h - r, border)
        cv.Line(x + w - 1, y + r, x + w - 1, y + h - r, border)
        if r > 0:
            if use_arc:
                cv.ArcQuarter(x + r, y + r, r, 0, border)
                cv.ArcQuarter(x + w - r - 1, y + r, r, 1, border)
                cv.ArcQuarter(x + r, y + h - r - 1, r, 2, border)
                cv.ArcQuarter(x + w - r - 1, y + h - r - 1, r, 3, border)
            else:
                cv.Circle(x + r, y + r, r, border)
                cv.Circle(x + w - r - 1, y + r, r, border)
                cv.Circle(x + r, y + h - r - 1, r, border)
                cv.Circle(x + w - r - 1, y + h - r - 1, r, border)
