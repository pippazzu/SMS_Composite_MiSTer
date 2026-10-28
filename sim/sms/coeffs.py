"""Master System board networks between the CXA1145's Y/C outputs and its
Y/C MIX inputs, as exact zero-order-hold state-space systems at the master
clock (53.693175 MHz), and their Q16 fixed-point coefficients.

  A = exp(Ac T), B = Ac^-1 (A - I) Bc

Topology from the Master System IC board schematic (171-5534, PAL VA1):
  luma    Y OUT -R33 1.5k- (L34 100u || C35) -+- C36 180p -> GND
                                              +- R37 1k   -> GND (VREF), -> Y IN
  chroma  C OUT -R38 1k- A, A -L39 12u- GND, A -C40- GND,
          A -C41- L42 100u- B, B -R43 1k- GND, B -C44 0.01u- C IN
The PAL board's tuned (CH-type) capacitors C35 12p, C40 100p and C41 12p put
the luma trap and both chroma resonators at 4.59 MHz, just above PAL's 4.43.
This core's composite is NTSC, so they are taken x1.5 (18p, 150p, 18p): all
three land at 3.75 MHz, just above NTSC's 3.58, where Sega put the same
100u || 18p trap on the NTSC Mega Drive. C36 stays 180p, as on that board.
Currents are carried as volts across 1k.
"""
import sys
import numpy as np
from scipy.linalg import expm

FS = 53.693175e6
T = 1 / FS
Q = 1 << 16
K = 1e3      # current scale: i * 1k

TUNE = 1.5 if '--pal' not in sys.argv else 1.0
R33, L34, C35, C36, R37 = 1.5e3, 100e-6, 12e-12 * TUNE, 180e-12, 1e3
R38, L39, C40, C41, L42, R43 = 1e3, 12e-6, 100e-12 * TUNE, 12e-12 * TUNE, 100e-6, 1e3


def zoh(Ac, Bc):
    A = expm(Ac * T)
    B = np.linalg.solve(Ac, (A - np.eye(len(A))) @ Bc)
    return A, B


def luma_continuous():
    # x0 = tank voltage (a - b), x1 = K * iL34, x2 = Y IN voltage.
    # i = (u - x0 - x2)/R33; C35 x0' = i - iL; L34 iL' = x0; C36 x2' = i - x2/R37
    g = 1 / R33
    Ac = np.array([
        [-g / C35,     -1 / (K * C35), -g / C35],
        [K / L34,       0,              0],
        [-g / C36,      0,             -g / C36 - 1 / (R37 * C36)],
    ])
    Bc = np.array([g / C35, 0, g / C36])
    return Ac, Bc


def chroma_continuous():
    # x0 = K * iL39, x1 = vA (C40), x2 = vC41, x3 = K * iL42; out = R43 iL42.
    # C40 vA' = (u - vA)/R38 - iL39 - iL42; L39 iL39' = vA
    # C41 vC41' = iL42; L42 iL42' = vA - vC41 - R43 iL42
    Ac = np.array([
        [0,             K / L39,                 0,          0],
        [-1 / (K * C40), -1 / (R38 * C40),        0,         -1 / (K * C40)],
        [0,             0,                       0,          1 / (K * C41)],
        [0,             K / L42,                -K / L42,   -R43 / L42],
    ])
    Bc = np.array([0, 1 / (R38 * C40), 0, 0])
    return Ac, Bc


LA, LB = zoh(*luma_continuous())
CA, CB = zoh(*chroma_continuous())
C_OUT = R43 / K               # B = x3 * R43 / K = x3


def q(x): return int(np.round(x * Q))


def resp(Ac, Bc, c, f):
    s = 2j * np.pi * f
    return c @ np.linalg.solve(s * np.eye(len(Ac)) - Ac, Bc)


if __name__ == '__main__':
    np.set_printoptions(precision=6, suppress=True)
    print('luma trap %.3f MHz, chroma tank %.3f MHz, chroma series %.3f MHz' % (
        1 / (2 * np.pi * np.sqrt(L34 * C35)) / 1e6, 1 / (2 * np.pi * np.sqrt(L39 * C40)) / 1e6,
        1 / (2 * np.pi * np.sqrt(L42 * C41)) / 1e6))
    la, ca = luma_continuous(), chroma_continuous()
    for f in (0, 1e6, 2e6, 3e6, 3.579545e6, 4.43362e6, 5e6):
        yl = resp(*la, np.array([0, 0, 1.0]), max(f, 1))
        yc = resp(*ca, np.array([0, 0, 0, 1.0]), max(f, 1))
        print('%5.2f MHz  luma %7.4f %7.1f deg  chroma %7.4f %7.1f deg' % (
            f / 1e6, abs(yl), np.angle(yl, True), abs(yc), np.angle(yc, True)))
    for name, A, B in (('L', LA, LB), ('C', CA, CB)):
        for i, row in enumerate(A):
            print(' '.join('localparam signed [17:0] %sA%d%d = %s;' % (name, i, j, q(v)) for j, v in enumerate(row)))
        print(' '.join('localparam signed [17:0] %sB%d = %s;' % (name, i, q(v)) for i, v in enumerate(B)))
