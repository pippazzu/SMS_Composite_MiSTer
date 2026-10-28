"""Bit-exact Python model of rtl/mark3_cvbs.sv, a float reference, and a stimulus generator."""
import coeffs as K

SQC = [2,2,2,1,-2,-2,-2,-2,-2,-2,-2,1,2,2,2]
SQS = [2]*7 + [0] + [-2]*7
LAT = 9
KV, KU = round(65536 / 1.14), round(65536 / 2.03)
BURST = 9766

def asr(x, n): return x >> n          # Python >> on ints is arithmetic (floor)
def wrap(x, bits):
    m = 1 << bits; x &= m - 1
    return x - m if x >> (bits - 1) else x
def q16(acc): return wrap((acc + 32768) >> 16, 19)

def run(stim, chroma_std=0, trace=None):
    """stim: list of (sc_ref, hs, vs, cs, de, r, g, b) per clock. Returns out8 per clock (after the edge)."""
    TA, TB, TC = K.QT_A, K.QT_B, K.QT_C
    S = dict(p=0, hs0=0, bok=0, bcnt=0x7FF, gate=[0]*5, r0=0,g0=0,b0=0, yq1=0,r1=0,b1=0, ry2=0,by2=0,y2=0,
             v3=0,u3=0,t=[0,0,0], vf=0,uf=0,y4=0, c5=0,y5=0, pre6=16384, o7=16384, out8=64)
    outs = []
    for (sc, hs, vs, cs, de, r, g, b) in stim:
        s = dict(S)
        p = S['p']
        s['p'] = 0 if sc else (0 if p == 14 else p + 1)
        s['hs0'] = hs
        if S['hs0'] and not hs: s['bcnt'] = 0
        elif S['bcnt'] != 0x7FF: s['bcnt'] = S['bcnt'] + 1
        if S['hs0'] and not hs: s['bok'] = not vs
        s['gate'] = S['gate'][1:] + [1 if 32 <= S['bcnt'] < 32 + 135 and S['bok'] and not vs else 0]
        s['r0'] = r if de else 0; s['g0'] = g if de else 0; s['b0'] = b if de else 0
        s['yq1'] = (77*S['r0'] + 151*S['g0'] + 28*S['b0']) & 0xFFFF
        s['r1'] = S['r0']; s['b1'] = S['b0']
        y16 = S['yq1'] + (S['yq1'] >> 8)
        s['ry2'] = S['r1']*257 - y16; s['by2'] = S['b1']*257 - y16; s['y2'] = y16
        s['v3'] = q16(KV*S['ry2']); s['u3'] = q16(KU*S['by2'])
        t = S['t']; u = S['y2']
        s['t'] = [q16(TA[i][0]*t[0] + TA[i][1]*t[1] + TA[i][2]*t[2] + TB[i]*u) for i in range(3)]
        s['vf'] = q16(K.QC_A*S['vf'] + K.QC_B*S['v3'])
        s['uf'] = q16(K.QC_A*S['uf'] + K.QC_B*S['u3'])
        s['y4'] = q16(TC*t[2])
        cm = wrap(asr(S['uf']*SQS[p] + S['vf']*SQC[p], 1), 19)
        cl = cm - asr(cm, 2) if chroma_std else cm
        cb = wrap(-asr(BURST*SQS[p], 1), 19)
        s['c5'] = cb if S['gate'][0] else cl
        s['y5'] = S['y4']
        s['pre6'] = 16384 + wrap(asr((S['y5'] + S['c5'])*255, 9), 19)
        s['o7'] = q16(K.QO_A*S['o7'] + K.QO_B*S['pre6'])
        o = S['o7'] + 128
        s['out8'] = 0 if o < 0 else 255 if (o >> 8) > 255 else (o >> 8) & 255
        S = s
        if trace is not None: trace.append((S['o7'], S['pre6'], S['c5'], S['y5'], S['vf'], max(abs(v) for v in S['t'])))
        outs.append(S['out8'])
    return outs


def run_float(stim, chroma_std=0):
    """Same chain in floating point with the unquantised ZOH matrices. Returns o7-equivalent (8-bit x 256)."""
    import numpy as np
    A, B = K.TRAP_A, K.TRAP_B
    pip = [dict(r0=0,g0=0,b0=0,y1=0,r1=0,b1=0)]
    st = dict(p=0, hs0=0, bok=0, bcnt=0x7FF, gate=[0]*5, r0=0,g0=0,b0=0, y1=0,r1=0,b1=0, ry2=0,by2=0,y2=0,
              v3=0,u3=0,t=np.zeros(3), vf=0,uf=0,y4=0,c5=0,y5=0,pre6=64.0,o7=64.0)
    outs = []
    for (sc, hs, vs, cs, de, r, g, b) in stim:
        S = st; s = dict(S); p = S['p']
        s['p'] = 0 if sc else (0 if p == 14 else p + 1)
        s['hs0'] = hs
        if S['hs0'] and not hs: s['bcnt'] = 0
        elif S['bcnt'] != 0x7FF: s['bcnt'] = S['bcnt'] + 1
        if S['hs0'] and not hs: s['bok'] = not vs
        s['gate'] = S['gate'][1:] + [1 if 32 <= S['bcnt'] < 32 + 135 and S['bok'] and not vs else 0]
        s['r0'], s['g0'], s['b0'] = (r/255, g/255, b/255) if de else (0, 0, 0)
        s['y1'] = 0.30078125*S['r0'] + 0.58984375*S['g0'] + 0.109375*S['b0']
        s['r1'] = S['r0']; s['b1'] = S['b0']
        s['ry2'] = S['r1'] - S['y1']; s['by2'] = S['b1'] - S['y1']; s['y2'] = S['y1']
        s['v3'] = S['ry2']/1.14; s['u3'] = S['by2']/2.03
        s['t'] = A @ S['t'] + B * S['y2']
        s['vf'] = K.CHR_A*S['vf'] + K.CHR_B*S['v3']; s['uf'] = K.CHR_A*S['uf'] + K.CHR_B*S['u3']
        s['y4'] = K.TRAP_C*S['t'][2]
        cm = (S['uf']*SQS[p] + S['vf']*SQC[p])/2
        cl = cm*0.75 if chroma_std else cm
        cb = -BURST/65536*SQS[p]/2
        s['c5'] = cb if S['gate'][0] else cl
        s['y5'] = S['y4']
        s['pre6'] = 64 + 127.5*(S['y5'] + S['c5'])
        s['o7'] = K.OUT_A*S['o7'] + K.OUT_B*S['pre6']
        st = s
        outs.append(st['o7'])
    return outs


# SMS-like raster: 3420 clocks/line, pixel every 10 clocks, HS 240 clocks.
def stimulus(lines=6, seed=1):
    import random
    rnd = random.Random(seed)
    lvls = [0, 85, 170, 255]
    st = []; t = 0
    for ln in range(lines):
        for x in range(3420):
            hs = 1 if x < 240 else 0
            de = 1 if 620 <= x < 3180 else 0
            if x % 10 == 0:
                if ln < 2: col = [(255,0,0),(0,255,0),(0,0,255),(255,255,0),(0,255,255),(255,0,255),(255,255,255),(0,0,0)][(x//320) % 8]
                else: col = (rnd.choice(lvls), rnd.choice(lvls), rnd.choice(lvls))
            sc = 1 if t % 15 == 9 else 0
            st.append((sc, hs, 0, hs, de) + tuple(col)); t += 1
    return st

if __name__ == '__main__':
    st = stimulus()
    with open('stim.txt', 'w') as f:
        for e in st: f.write(' '.join('%x' % v for v in e) + '\n')
    for cs in (0, 1):
        with open('expect%d.txt' % cs, 'w') as f:
            f.write('\n'.join(str(v) for v in run(st, cs)) + '\n')
    print(len(st), 'clocks')
