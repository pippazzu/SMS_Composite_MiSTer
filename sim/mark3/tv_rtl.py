"""Stimulus for tb_tv.sv from the real raster, and a PNG of its decoded output.
   python3 tv_rtl.py stim   -> tv_stim.txt (3 frames of the bars pattern)
   python3 tv_rtl.py png NAME -> NAME.png from tv_rtl_out.txt, plus checks"""
import sys, numpy as np
from PIL import Image
import tv

if sys.argv[1] == 'stim':
    hs, vs, hb, vb = tv.load_pins()
    img = tv.pattern('bars')
    with open('tv_stim.txt', 'w') as f:
        line = -1; x0 = 0
        for t in range(len(hs)):
            de = not (hb[t] or vb[t])
            if de and (t == 0 or hb[t-1] or vb[t-1]): line += 1; x0 = t
            if vs[t] and not vs[t-1]: line = -1
            c = (0, 0, 0)
            if de and 0 <= line < 192 and (t - x0) // 10 < 256: c = img[line, (t - x0) // 10]
            f.write('%x %x %x %x %x %x %x %x\n' % (1 if t % 15 == 9 else 0, int(hs[t]), int(vs[t]), int(hb[t]), int(vb[t]), *(int(x) for x in c)))
else:
    rows = np.array([[int(v) if v != 'x' else 0 for v in l.split()] for l in open(sys.argv[3] if len(sys.argv) > 3 else 'tv_rtl_out.txt')], dtype=np.int64)
    t, hs, vs, hb, vb, rgb = rows[:, 0], rows[:, 1], rows[:, 2], rows[:, 3], rows[:, 4], rows[:, 5:8]
    # last complete frame between two vs rises
    vr = np.flatnonzero(vs[1:] & ~vs[:-1]) + 1
    a, b = vr[-2], vr[-1]
    lines = []; cur = []
    for i in range(a, b):
        if hs[i] and not hs[i-1]:
            if cur: lines.append(cur)
            cur = []
        cur.append(i)
    act = [[i for i in ln if not (hb[i] or vb[i])] for ln in lines]
    act = [l for l in act if l]
    w = max(len(l) for l in act)
    print('decoded frame: %d lines, %d px per line, active %d lines x %s px' %
          (len(lines), int(np.median([len(l) for l in lines])), len(act), sorted(set(len(l) for l in act))))
    pic = np.zeros((len(act), w, 3), np.uint8)
    for y, l in enumerate(act): pic[y, :len(l)] = rgb[l]
    Image.fromarray(pic).resize((w * 2, len(act) * 4), Image.NEAREST).save(sys.argv[2] + '.png')
    # crop alignment: first/last active pixel against the picture edges (bars start white at x=0)
    mid = act[60]
    print('row 60 first px', rgb[mid[0]], 'second', rgb[mid[1]], 'last', rgb[mid[-1]])
    np.save(sys.argv[2] + '.npy', pic)
