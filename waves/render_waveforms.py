#!/usr/bin/env python3
"""Render PNG waveform screenshots from the NTT VCD using headless Chrome.

Parse recorded signal transitions, generate SVG waveform views, and
rasterize them as PNG images.
"""

import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
VCD_PATH = os.path.join(HERE, "ntt_top.vcd")
OUT_DIR = os.path.join(os.path.dirname(HERE), "docs", "images")
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

STATE_NAMES = {0: "IDLE", 1: "LOAD", 2: "READ", 3: "COMPUTE", 4: "WRITE"}


def parse_vcd(path):
    """Return (name_to_id, id_to_width, id_to_timeline) from a VCD file."""
    name_to_id = {}
    id_to_width = {}
    id_to_timeline = {}
    scope_stack = []
    time = 0
    in_defs = True

    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            if in_defs:
                if line.startswith("$scope"):
                    scope_stack.append(line.split()[2])
                    continue
                if line.startswith("$upscope"):
                    scope_stack.pop()
                    continue
                if line.startswith("$enddefinitions"):
                    in_defs = False
                    continue
                if line.startswith("$var"):
                    parts = line.split()
                    width = int(parts[2])
                    sig_id = parts[3]
                    base = parts[4]
                    full = ".".join(scope_stack + [base])
                    name_to_id[full] = sig_id
                    id_to_width.setdefault(sig_id, width)
                    id_to_timeline.setdefault(sig_id, [])
                continue

            if line.startswith("#"):
                time = int(line[1:])
                continue
            if line.startswith("$"):
                continue
            if line[0] == "b":
                val, sig_id = line[1:].split()
                id_to_timeline.setdefault(sig_id, []).append((time, val))
            else:
                val = line[0]
                sig_id = line[1:]
                id_to_timeline.setdefault(sig_id, []).append((time, val))

    return name_to_id, id_to_width, id_to_timeline


def value_at(timeline, width, t):
    """Value active at time t (last change at or before t)."""
    v = "x" * width
    for ts, val in timeline:
        if ts <= t:
            v = val
        else:
            break
    return v


def segments(timeline, width, t_start, t_end):
    """[(seg_start, seg_end, value), ...] clipped to [t_start, t_end]."""
    cur_val = value_at(timeline, width, t_start)
    cur_start = t_start
    out = []
    for ts, val in timeline:
        if ts <= t_start:
            continue
        if ts >= t_end:
            break
        out.append((cur_start, ts, cur_val))
        cur_start = ts
        cur_val = val
    out.append((cur_start, t_end, cur_val))
    return out


def to_int(val):
    if "x" in val or "z" in val:
        return None
    return int(val, 2)


def label_for(sig_key, val):
    n = to_int(val)
    if n is None:
        return "x"
    if sig_key == "state":
        return STATE_NAMES.get(n, str(n))
    return str(n)


LANE_H = 34
LABEL_W = 190
LEFT_PAD = 20
RIGHT_PAD = 20
TOP_PAD = 54
BOT_PAD = 16


def render_view(name_to_id, id_to_width, id_to_timeline,
                 title, t_start, t_end, px_per_unit, rows, out_svg):
    """rows: list of (label, fullpath, kind) where kind in {'bit','bus'}."""
    content_width = LABEL_W + LEFT_PAD + int((t_end - t_start) * px_per_unit) + RIGHT_PAD
    title_width = LEFT_PAD + int(len(title) * 9) + RIGHT_PAD
    width_px = max(content_width, title_width)
    height_px = TOP_PAD + len(rows) * LANE_H + BOT_PAD

    svg = []
    svg.append(f'<svg xmlns="http://www.w3.org/2000/svg" width="{width_px}" '
                f'height="{height_px}" font-family="Menlo, Consolas, monospace">')
    svg.append(f'<rect width="{width_px}" height="{height_px}" fill="#1e1e1e"/>')
    svg.append(f'<text x="{LEFT_PAD}" y="22" fill="#e0e0e0" font-size="15" '
                f'font-weight="bold">{title}</text>')

    def x_of(t):
        return LABEL_W + LEFT_PAD + (t - t_start) * px_per_unit

    # Label every Nth clock tick to avoid overlapping timestamps.
    tick = 10
    min_label_gap_px = 34
    ticks_per_label = max(1, -(-min_label_gap_px // max(1, int(tick * px_per_unit))))
    t0 = (t_start // tick) * tick
    grid_top = TOP_PAD - 8
    label_y = TOP_PAD - 16
    t = t0
    i = 0
    while t <= t_end:
        if t >= t_start:
            x = x_of(t)
            svg.append(f'<line x1="{x:.1f}" y1="{grid_top}" x2="{x:.1f}" '
                        f'y2="{height_px - BOT_PAD}" stroke="#333" stroke-width="1"/>')
            if i % ticks_per_label == 0:
                svg.append(f'<text x="{x:.1f}" y="{label_y}" fill="#888" '
                            f'font-size="10" text-anchor="middle">{t}</text>')
        t += tick
        i += 1

    for row_idx, (label, fullpath, kind) in enumerate(rows):
        y_top = TOP_PAD + row_idx * LANE_H
        y_mid = y_top + LANE_H / 2
        y_lo = y_top + LANE_H - 8
        y_hi = y_top + 8

        svg.append(f'<text x="{LEFT_PAD}" y="{y_mid + 4:.1f}" fill="#d4d4d4" '
                    f'font-size="12">{label}</text>')
        svg.append(f'<line x1="{LABEL_W + LEFT_PAD}" y1="{y_top}" '
                    f'x2="{width_px - RIGHT_PAD}" y2="{y_top}" stroke="#2a2a2a"/>')

        sig_id = name_to_id[fullpath]
        width = id_to_width[sig_id]
        timeline = id_to_timeline[sig_id]
        segs = segments(timeline, width, t_start, t_end)

        if kind == "bit":
            path = []
            prev_y = None
            for seg_start, seg_end, val in segs:
                y = y_hi if to_int(val) == 1 else y_lo
                x1, x2 = x_of(seg_start), x_of(seg_end)
                if prev_y is None:
                    path.append(f"M{x1:.1f},{y:.1f}")
                elif prev_y != y:
                    path.append(f"L{x1:.1f},{prev_y:.1f} L{x1:.1f},{y:.1f}")
                path.append(f"L{x2:.1f},{y:.1f}")
                prev_y = y
            svg.append(f'<path d="{" ".join(path)}" fill="none" '
                        f'stroke="#4fc3f7" stroke-width="2"/>')
        else:
            for seg_start, seg_end, val in segs:
                x1, x2 = x_of(seg_start), x_of(seg_end)
                w = x2 - x1
                undefined = to_int(val) is None
                fill = "#3a2a2a" if undefined else "#2d4a3a"
                stroke = "#774444" if undefined else "#4caf80"
                svg.append(f'<rect x="{x1:.1f}" y="{y_hi:.1f}" width="{max(w,0):.1f}" '
                            f'height="{y_lo - y_hi:.1f}" fill="{fill}" '
                            f'stroke="{stroke}" stroke-width="1"/>')
                if w > 18:
                    txt = label_for(label, val)
                    svg.append(f'<text x="{(x1+x2)/2:.1f}" y="{y_mid + 4:.1f}" '
                                f'fill="#e8e8e8" font-size="11" '
                                f'text-anchor="middle">{txt}</text>')

    svg.append("</svg>")

    html = (f'<!doctype html><html><head><meta charset="utf-8"></head>'
            f'<body style="margin:0;background:#1e1e1e;">{"".join(svg)}</body></html>')
    html_path = out_svg.replace(".svg", ".html")
    with open(html_path, "w") as f:
        f.write(html)
    return html_path, width_px, height_px


def shoot(html_path, png_path, width_px, height_px):
    subprocess.run([
        CHROME, "--headless=new", "--disable-gpu",
        f"--screenshot={png_path}",
        f"--window-size={width_px},{height_px}",
        f"file://{html_path}",
    ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    name_to_id, id_to_width, id_to_timeline = parse_vcd(VCD_PATH)

    views = []

    # Complete transform, including control signals and stage progression.
    views.append((
        "ntt_top: complete transform (x = [1,2,3,4,5,6,7,8])",
        0, 440, 1.6,
        [
            ("clk", "dump_waveforms.clk", "bit"),
            ("rst", "dump_waveforms.rst", "bit"),
            ("start", "dump_waveforms.start", "bit"),
            ("busy", "dump_waveforms.busy", "bit"),
            ("done", "dump_waveforms.done", "bit"),
            ("state", "dump_waveforms.dut.u_ctrl.state", "bus"),
            ("stage", "dump_waveforms.dut.u_ctrl.stage", "bus"),
            ("bidx", "dump_waveforms.dut.u_ctrl.bidx", "bus"),
        ],
        "ntt-complete-execution",
    ))

    # One butterfly operation, showing its READ, COMPUTE, and WRITE phases.
    views.append((
        "ntt_controller: one butterfly, READ / COMPUTE / WRITE (stage 0, bidx 1)",
        86, 116, 9.0,
        [
            ("state", "dump_waveforms.dut.u_ctrl.state", "bus"),
            ("stage", "dump_waveforms.dut.u_ctrl.stage", "bus"),
            ("bidx", "dump_waveforms.dut.u_ctrl.bidx", "bus"),
            ("lo", "dump_waveforms.dut.u_ctrl.lo", "bus"),
            ("hi", "dump_waveforms.dut.u_ctrl.hi", "bus"),
            ("twiddle_exp", "dump_waveforms.dut.u_ctrl.twiddle_exp", "bus"),
            ("a_reg", "dump_waveforms.dut.u_ctrl.a_reg", "bus"),
            ("b_reg", "dump_waveforms.dut.u_ctrl.b_reg", "bus"),
            ("tw_reg", "dump_waveforms.dut.u_ctrl.tw_reg", "bus"),
            ("u_reg", "dump_waveforms.dut.u_ctrl.u_reg", "bus"),
            ("v_reg", "dump_waveforms.dut.u_ctrl.v_reg", "bus"),
            ("write_enable", "dump_waveforms.dut.write_enable", "bit"),
        ],
        "butterfly-operation",
    ))

    # Modular arithmetic signals for the butterfly shown above.
    views.append((
        "butterfly_datapath: modular arithmetic (mod_add, mod_sub, mod_mul)",
        86, 116, 9.0,
        [
            ("a", "dump_waveforms.dut.u_ctrl.u_bfly.u_mod_add.a", "bus"),
            ("b", "dump_waveforms.dut.u_ctrl.u_bfly.u_mod_add.b", "bus"),
            ("sum (mod_add)", "dump_waveforms.dut.u_ctrl.u_bfly.u_mod_add.sum", "bus"),
            ("diff (mod_sub)", "dump_waveforms.dut.u_ctrl.u_bfly.u_mod_sub.diff", "bus"),
            ("tw", "dump_waveforms.dut.u_ctrl.u_bfly.u_mod_mul.tw", "bus"),
            ("p (diff*tw)", "dump_waveforms.dut.u_ctrl.u_bfly.u_mod_mul.p", "bus"),
            ("l (p[3:0])", "dump_waveforms.dut.u_ctrl.u_bfly.u_mod_mul.l", "bus"),
            ("h (p[8:4])", "dump_waveforms.dut.u_ctrl.u_bfly.u_mod_mul.h", "bus"),
            ("v (mod_mul)", "dump_waveforms.dut.u_ctrl.u_bfly.u_mod_mul.v", "bus"),
        ],
        "modular-arithmetic",
    ))

    for title, t_start, t_end, px_per_unit, rows, basename in views:
        for _, fullpath, _ in rows:
            if fullpath not in name_to_id:
                print(f"ERROR: signal not found in VCD: {fullpath}", file=sys.stderr)
                sys.exit(1)
        svg_path = os.path.join(OUT_DIR, basename + ".svg")
        html_path, w, h = render_view(name_to_id, id_to_width, id_to_timeline,
                                       title, t_start, t_end, px_per_unit, rows, svg_path)
        png_path = os.path.join(OUT_DIR, basename + ".png")
        shoot(html_path, png_path, w, h)
        os.remove(html_path)
        print(f"wrote {png_path} ({w}x{h})")


if __name__ == "__main__":
    main()
