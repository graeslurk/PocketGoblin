#!/usr/bin/env python3
"""Generates Pocket Goblin's UI textures (white shapes, tinted in-game).

Shapes are drawn as signed distance fields with 1px anti-aliasing and saved
as 32-bit TGA, which WoW loads directly. The emblem textures, the AddOns
list icon and the project logo come from tools/make_emblem.js instead.
Run from anywhere:

    python3 tools/make_media.py
"""

import math
import os
import struct

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Media")


# --- SDF primitives (negative inside) -----------------------------------

def circle(px, py, cx, cy, r):
    return math.hypot(px - cx, py - cy) - r


def ring(px, py, cx, cy, r, width):
    return abs(circle(px, py, cx, cy, r)) - width / 2


def round_rect(px, py, cx, cy, hw, hh, r):
    qx = abs(px - cx) - hw + r
    qy = abs(py - cy) - hh + r
    outside = math.hypot(max(qx, 0), max(qy, 0))
    return outside + min(max(qx, qy), 0) - r


def capsule(px, py, ax, ay, bx, by, r):
    pax, pay = px - ax, py - ay
    bax, bay = bx - ax, by - ay
    h = max(0, min(1, (pax * bax + pay * bay) / (bax * bax + bay * bay)))
    return math.hypot(pax - bax * h, pay - bay * h) - r


def tapered_box(px, py, cx, top, bottom, hw_top, hw_bottom, r):
    """Rounded box whose half-width shrinks from top to bottom (approximate SDF)."""
    t = max(0.0, min(1.0, (py - top) / (bottom - top)))
    hw = hw_top + (hw_bottom - hw_top) * t
    qx = abs(px - cx) - hw + r
    qy = max(top - py, py - bottom) + r
    return math.hypot(max(qx, 0), max(qy, 0)) + min(max(qx, qy), 0) - r


def ellipse(px, py, cx, cy, rx, ry):
    """Approximate distance to an ellipse (good enough for 1px edges)."""
    k = math.hypot((px - cx) / rx, (py - cy) / ry)
    return (k - 1) * min(rx, ry)


def polygon(px, py, points):
    """Exact distance to a closed polygon (negative inside)."""
    d = (px - points[0][0]) ** 2 + (py - points[0][1]) ** 2
    sign = 1
    j = len(points) - 1
    for i in range(len(points)):
        (ax, ay), (bx, by) = points[i], points[j]
        ex, ey = bx - ax, by - ay
        wx, wy = px - ax, py - ay
        t = max(0.0, min(1.0, (wx * ex + wy * ey) / (ex * ex + ey * ey)))
        d = min(d, (wx - ex * t) ** 2 + (wy - ey * t) ** 2)
        inside = (py >= ay, py < by, ex * wy > ey * wx)
        if all(inside) or not any(inside):
            sign = -sign
        j = i
    return sign * math.sqrt(d)


def rotated_box(px, py, cx, cy, hw, hh, angle, r=0.5):
    c, s = math.cos(angle), math.sin(angle)
    dx, dy = px - cx, py - cy
    return round_rect(c * dx + s * dy, -s * dx + c * dy, 0, 0, hw, hh, r)


# --- Output --------------------------------------------------------------

def render(name, width, height, sdf, color=(255, 255, 255)):
    r, g, b = color
    pixels = bytearray()
    for y in range(height):
        for x in range(width):
            d = sdf(x + 0.5, y + 0.5)
            alpha = max(0.0, min(1.0, 0.5 - d))
            pixels += bytes((b, g, r, round(alpha * 255)))  # BGRA
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, width, height, 32, 0x28)
    with open(os.path.join(OUT, name + ".tga"), "wb") as f:
        f.write(header + pixels)


def main():
    os.makedirs(OUT, exist_ok=True)

    # Panels and controls (sliced in-game, so corners keep their shape).
    render("rounded", 32, 32, lambda x, y: round_rect(x, y, 16, 16, 16, 16, 6))
    render("rounded-border", 32, 32,
           lambda x, y: abs(round_rect(x, y, 16, 16, 15.5, 15.5, 6)) - 0.5)
    render("pill", 64, 32, lambda x, y: round_rect(x, y, 32, 16, 32, 16, 16))
    render("circle", 32, 32, lambda x, y: circle(x, y, 16, 16, 15))
    render("ring", 64, 64, lambda x, y: ring(x, y, 32, 32, 29, 3))

    # Icons, drawn on a 32px grid.
    def list_icon(x, y):
        d = 1e9
        for row in (9, 16, 23):
            d = min(d, circle(x, y, 7, row, 2), capsule(x, y, 13, row, 26, row, 1.4))
        return d
    render("icon-list", 32, 32, list_icon)

    def gear(x, y):
        d = circle(x, y, 16, 16, 9)
        for i in range(8):
            a = i * math.pi / 4
            d = min(d, rotated_box(x, y, 16 + math.cos(a) * 11, 16 + math.sin(a) * 11, 2.6, 2.2, a))
        return max(d, -circle(x, y, 16, 16, 4))
    render("icon-gear", 32, 32, gear)

    def coins(x, y):
        d = ring(x, y, 16, 16, 11, 2.6)
        return min(d, ring(x, y, 16, 16, 5.5, 2.6))
    render("icon-coin", 32, 32, coins)

    def bag(x, y):
        body = abs(round_rect(x, y, 16, 19, 10, 9, 3)) - 1.3
        handle = max(ring(x, y, 16, 10, 5, 2.6), y - 10)
        return min(body, handle)
    render("icon-bag", 32, 32, bag)

    def info(x, y):
        d = ring(x, y, 16, 16, 12, 2.6)
        d = min(d, circle(x, y, 16, 10, 1.9))
        return min(d, capsule(x, y, 16, 15, 16, 22, 1.4))
    render("icon-info", 32, 32, info)

    def close(x, y):
        return min(capsule(x, y, 9, 9, 23, 23, 1.6), capsule(x, y, 23, 9, 9, 23, 1.6))
    render("icon-close", 32, 32, close)

    def search(x, y):
        return min(ring(x, y, 14, 14, 7, 2.6), capsule(x, y, 19.5, 19.5, 25, 25, 1.5))
    render("icon-search", 32, 32, search)

    def chevron(x, y):  # downward arrow for dropdowns
        return min(capsule(x, y, 9, 12.5, 16, 19.5, 1.7), capsule(x, y, 16, 19.5, 23, 12.5, 1.7))
    render("icon-chevron", 32, 32, chevron)

    def hammer(x, y):  # repairs
        handle = capsule(x, y, 8, 25, 19.5, 13.5, 1.8)
        head = rotated_box(x, y, 21, 11, 8, 3.6, math.pi / 4, 1.2)  # across the handle
        return min(handle, head)
    render("icon-repair", 32, 32, hammer)

    def lock(x, y):  # padlock, for kept items
        shackle = max(ring(x, y, 16, 13, 6, 2.6), y - 15)
        shackle = min(shackle, capsule(x, y, 10, 13, 10, 16, 1.3), capsule(x, y, 22, 13, 22, 16, 1.3))
        body = round_rect(x, y, 16, 21.5, 9, 7, 2)
        keyhole = min(circle(x, y, 16, 20, 1.8), capsule(x, y, 16, 20, 16, 24, 0.9))
        return min(shackle, max(body, -keyhole))
    render("icon-lock", 32, 32, lock)

    def funnel(x, y):  # filter funnel, for the junk rules page
        top = tapered_box(x, y, 16, 7, 17, 11.5, 3, 1.2)
        stem = round_rect(x, y, 16, 21.5, 2.2, 5.5, 1)
        return min(top, stem)
    render("icon-filter", 32, 32, funnel)

    def history(x, y):  # clock
        hands = min(capsule(x, y, 16, 16, 16, 9.5, 1.4), capsule(x, y, 16, 16, 20.5, 19, 1.4))
        return min(ring(x, y, 16, 16, 11.5, 2.6), hands)
    render("icon-history", 32, 32, history)

    def profile(x, y):  # person: head and shoulders
        head = circle(x, y, 16, 10.5, 5.2)
        shoulders = max(round_rect(x, y, 16, 26, 10.5, 7.5, 7), y - 27)
        return min(head, max(shoulders, -circle(x, y, 16, 10.5, 7.2)))
    render("icon-profile", 32, 32, profile)

    def quest(x, y):  # quest-giver style "!"
        return min(capsule(x, y, 16, 6, 16, 19, 2.8), circle(x, y, 16, 25.5, 2.9))
    render("icon-quest", 32, 32, quest)

    def trash(x, y):
        lid = capsule(x, y, 8, 9, 24, 9, 1.4)
        handle = abs(round_rect(x, y, 16, 6.5, 3.5, 2.5, 1)) - 1.1
        handle = max(handle, y - 8)
        body = abs(round_rect(x, y, 16, 19, 7, 8.5, 2)) - 1.3
        body = max(body, -(y - 11))  # open top, the lid closes it
        lines = min(capsule(x, y, 13, 15, 13, 23, 1.1), capsule(x, y, 19, 15, 19, 23, 1.1))
        return min(lid, handle, body, lines)
    render("icon-trash", 32, 32, trash)

    def sort(x, y):  # bars getting shorter, and an arrow down: sort bags
        bars = min(capsule(x, y, 5, 9, 18, 9, 1.4), capsule(x, y, 5, 16, 15, 16, 1.4),
                   capsule(x, y, 5, 23, 12, 23, 1.4))
        arrow = min(capsule(x, y, 24, 7, 24, 24, 1.4), capsule(x, y, 19.5, 19.5, 24, 24, 1.4),
                    capsule(x, y, 28.5, 19.5, 24, 24, 1.4))
        return min(bars, arrow)
    render("icon-sort", 32, 32, sort)

    # Mood faces: a goblin head with long pointed ears, slanted eyes and a
    # grin. One flat shape with cut-outs for the details.
    # Goblin face cut-outs for each mood, drawn around (26, 31).
    def happy_face(x, y):  # mischievous eyes, grin
        eyes = min(capsule(x, y, 19.5, 28.5, 23.5, 31, 2.1), capsule(x, y, 28.5, 31, 32.5, 28.5, 2.1))
        grin = max(ring(x, y, 26, 32, 7.5, 2.2), 36.5 - y, abs(x - 26) - 6.5)
        return min(eyes, grin)

    def eager_face(x, y):  # wide eyes with pupils, big grin
        eyes = min(ring(x, y, 21, 29.5, 2.6, 1.6), ring(x, y, 31, 29.5, 2.6, 1.6))
        grin = max(ring(x, y, 26, 31, 8.5, 2.4), 35.5 - y, abs(x - 26) - 7.5)
        return min(eyes, grin)

    def worried_face(x, y):  # eyes higher at the inner corners, frown
        eyes = min(capsule(x, y, 19.5, 31, 23.5, 28.5, 2.0), capsule(x, y, 28.5, 28.5, 32.5, 31, 2.0))
        frown = max(ring(x, y, 26, 42, 5.5, 2.2), y - 38.5, abs(x - 26) - 5)
        return min(eyes, frown)

    def sleepy_face(x, y):  # closed eyes, small open mouth
        eyes = min(capsule(x, y, 19.5, 30, 23.5, 30.5, 1.2), capsule(x, y, 28.5, 30.5, 32.5, 30, 1.2))
        return min(eyes, circle(x, y, 26, 37, 1.9))

    def goblin(x, y, face):
        head = ellipse(x, y, 26, 31, 12.5, 13.5)
        left_ear = polygon(x, y, [(17, 25), (16, 35), (5, 15)])
        right_ear = polygon(x, y, [(35, 25), (36, 35), (47, 15)])
        shape = min(head, left_ear, right_ear)
        return max(shape, -face(x, y))

    def snore(x, y):  # a small "z" above the head
        return min(capsule(x, y, 34, 2.5, 41, 2.5, 1.3), capsule(x, y, 41, 2.5, 34, 9.5, 1.3),
                   capsule(x, y, 34, 9.5, 41, 9.5, 1.3))

    def logo_with(face, extra=None):
        def logo(x, y):
            # The goblin spans x 5-47 and y 15-44.5: scaled to the icon's
            # width and centred on it.
            scale = 1.42
            shape = goblin(26 + (x - 32) / scale, 29.75 + (y - 32) / scale, face) * scale
            return min(shape, extra(x, y)) if extra else shape
        return logo

    logo = logo_with(happy_face)
    render("logo", 64, 64, logo)
    render("logo-eager", 64, 64, logo_with(eager_face))
    render("logo-worried", 64, 64, logo_with(worried_face))
    render("logo-sleepy", 64, 64, logo_with(sleepy_face, snore))


if __name__ == "__main__":
    main()
