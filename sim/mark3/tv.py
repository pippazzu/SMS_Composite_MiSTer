"""Replay the real SMS raster (video_pins.txt from tb_video.vhd) through the
bit-exact encoder model, then decode it like an NTSC TV, after the pattern of
Kitrinx's composite_decoder (NES_MiSTer):

  - sync is added the way a MiSTer composite cable does (csync into luma), at
    the BA7230LS typical depth: 0.65 V sync for 1.55 V white;
  - burst gate and black clamp are timed from sync's TRAILING edge;
  - chroma is blanked until the back porch ends;
  - comb delay is the set's own 227.5 carrier cycles (3412.5 samples), not the
    console's 228-cycle line, which would cancel the burst;
  - gain follows sync: 40 IRE = the measured sync depth.

Writes tv_<pattern>.png (decoded, 2 samples per output pixel horizontally)
and prints the numeric checks.
"""
import sys, numpy as np
from PIL import Image
import model

FS = 53.693175e6
SYNC_DEPTH = 0.65 / 1.55 * 127.5      # counts below blank, BA7230LS typ.


def load_pins():
    rows = np.frombuffer(open('video_pins.txt', 'rb').read(), dtype=np.uint8).reshape(-1, 5)[:, :4] == ord('1')
    return rows[:, 0], rows[:, 1], rows[:, 2], rows[:, 3]


def pattern(name):
    lv = [0, 85, 170, 255]
    img = np.zeros((192, 256, 3), np.uint8)
    if name == 'bars':
        bars = [(255,255,255),(255,255,0),(0,255,255),(0,255,0),(255,0,255),(255,0,0),(0,0,255),(0,0,0)]
        for i, c in enumerate(bars): img[:128, i*32:(i+1)*32] = c
        for i in range(64):                                     # the 64-colour SMS palette
            c = (lv[i & 3], lv[(i >> 2) & 3], lv[i >> 4])
            img[128 + (i // 16) * 12:128 + (i // 16 + 1) * 12, (i % 16) * 16:(i % 16 + 1) * 16] = c
        img[176:, :] = 0
        for w in (1, 2, 3, 4):                                   # stripes 2.68 / 1.34 / 0.89 / 0.67 MHz
            x0 = (w - 1) * 64
            for x in range(64): img[176:, x0 + x] = 255 if (x // w) % 2 == 0 else 0
    return img


def stimulus(img, hs, vs, hb, vb):
    vr = np.flatnonzero(vs[1:] & ~vs[:-1]) + 1
    a, b = vr[0], vr[1]
    st = []; line = -1; x0 = None
    for t in range(a - 3420, b):
        de = not (hb[t] or vb[t])
        if de and (t == 0 or hb[t - 1] or vb[t - 1]):
            line += 1; x0 = t
        r = g = bl = 0
        if de and 0 <= line < 192:
            px = (t - x0) // 10
            if px < 256: r, g, bl = img[line, px]
        st.append((1 if t % 15 == 9 else 0, int(hs[t]), int(vs[t]), int(hs[t] or vs[t]), int(de), int(r), int(g), int(bl)))
    return st


def decode(cvbs, cs):
    sig = cvbs.astype(float) - SYNC_DEPTH * cs                  # what the TV sees, in DAC counts
    n = len(sig)
    # sync separator: trailing edges of the horizontal sync
    tr = [i for i in range(1, n) if cs[i - 1] and not cs[i]]
    tr = [t for i, t in enumerate(tr) if i == 0 or t - tr[i - 1] > 3000]
    w = 2 * np.pi / 15
    lines = []; checks = dict(sync=[], blank=[], burst=[])
    prev = None
    k = np.arange(n)
    for t in tr:
        if t + 3420 > n: break
        blank = sig[t + 200:t + 360].mean()                   # black clamp, back porch
        tip = sig[t - 200:t - 40].mean()                      # sync tip
        g = 40 / (blank - tip)                                # IRE per count: gain follows sync
        seg = (sig[t - 240:t - 240 + 3420] - blank) * g        # line in IRE, from sync leading edge
        # burst gate from the trailing edge
        bi = seg[240 + 40:240 + 160]; bk = k[t + 40:t + 160]
        bI = 2 * np.mean(bi * np.sin(w * bk)); bQ = 2 * np.mean(bi * np.cos(w * bk))
        checks['sync'].append(blank - tip); checks['blank'].append(blank); checks['burst'].append(np.hypot(bI, bQ))
        lines.append((t, seg, np.arctan2(bQ, bI), g, blank))
    # comb (227.5 cycles = 3412.5 samples) on the IRE signal stream
    full = np.zeros(n)
    for t, seg, ph, g, blank in lines: full[t - 240:t - 240 + 3420] = seg
    d = np.zeros(n); d[3413:] = 0.5 * (full[:-3413] + full[1:-3412])
    Y = 0.5 * (full + d); C = 0.5 * (full - d)
    out = []
    lp = np.ones(40) / 40                                      # ~1.3 MHz chroma lowpass (comb TV)
    for t, seg, ph, g, blank in lines:
        s0 = t - 240
        y = Y[s0:s0 + 3420]; c = C[s0:s0 + 3420]; kk = k[s0:s0 + 3420]
        # TV oscillator locked to this line's burst: burst is at 180 deg (-U)
        ref = w * kk + ph
        u = np.convolve(-2 * c * np.sin(ref), lp, 'same'); v = np.convolve(-2 * c * np.cos(ref), lp, 'same')
        u[:620] = v[:620] = 0                                  # chroma blanked until the back porch ends
        Yv = y / 100; U = u / 100; V = v / 100
        R = Yv + V / 0.877; B = Yv + U / 0.492; G = (Yv - 0.299 * R - 0.114 * B) / 0.587
        out.append(np.stack([R, G, B], -1))
    return np.array(out), checks, lines


if __name__ == '__main__':
    hs, vs, hb, vb = load_pins()
    std = int(sys.argv[1]) if len(sys.argv) > 1 else 0
    img = pattern('bars')
    st = stimulus(img, hs, vs, hb, vb)
    cvbs = np.array(model.run(st, std))
    cs = np.array([e[3] for e in st])
    # outputs are LAT clocks late; align sync to them
    cs = np.r_[np.zeros(model.LAT, int), cs[:-model.LAT]]
    rgb, chk, lines = decode(cvbs, cs)
    vis = rgb[:, 620 + 40:620 + 40 + 2600:5]                   # active area, 520 samples wide
    act = [i for i, l in enumerate(lines) if l[0] - 240 >= 0]
    pic = np.clip(vis, 0, 1) ** (1 / 1.0)
    # crop to the 192 active lines (VS, then 3 + 13 lines of blanking on SMS NTSC)
    ys = [i for i in range(len(lines))]
    Image.fromarray((pic * 255).astype(np.uint8)).resize((520 * 2, len(pic) * 4), Image.NEAREST).save('tv_bars%s.png' % ('_std' if std else ''))
    sync = np.median(chk['sync']); burst = np.median(chk['burst'])
    print('sync depth %.1f counts; burst %.1f IRE pp (fundamental, after 6 MHz pole); white %.1f IRE' %
          (sync, 2 * burst * 40 / sync, (cvbs[st.index(next(e for e in st if e[4] and e[5] == 255 and e[6] == 255))+60] - 64) * 40 / sync if True else 0))
