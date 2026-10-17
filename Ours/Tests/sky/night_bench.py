"""The decomp's sky.hlsl drawn on the Direct3D bench, as the client hands it its numbers, to see the night sky."""
import ctypes, math, random, struct, sys
from ctypes import byref, c_uint, c_ulong, c_void_p, POINTER
sys.dont_write_bytecode = True
sys.path.insert(0, r'C:\WOW_MODS\Project_WOW_Editor\client\shaders')
import bls, bench

OUT = r'C:\WOW_MODS\Project_WOW_Editor\build\sky'
import os
os.makedirs(OUT, exist_ok=True)
W, H = 1280, 720

source = open(r'C:\World Of Warcraft decomp\wowdecomp\Ours\Shaders\sky.hlsl', encoding='utf-8').read()
pixel_code = bls.compile_shader(source, 'ps_3_0', {'VERTEX': '0'})
vertex_text = r'''
struct In { float4 at : POSITION; float3 way : NORMAL; };
struct Out { float4 at : POSITION; float3 way : TEXCOORD0; };
Out main(In i) { Out o; o.at = float4(i.at.xyz, 1); o.way = i.way; return o; }
'''
vertex_code = bls.compile_shader(vertex_text, 'vs_3_0')

b = bench.Bench(W, H)
vs = b.vertex_shader(vertex_code)
ps = b.pixel_shader(pixel_code)

# s0: a night sky's colours (dark blue at the top, a little lighter at the horizon), as the client lays them out.
AROUND, UP = 128, 96
def zone(k):
    t = (k + 0.5) / UP           # 0 the top, 1 the horizon
    top, low = (0.010, 0.016, 0.045), (0.045, 0.060, 0.110)
    s = t ** 3
    return tuple(top[i] + (low[i] - top[i]) * s for i in range(3)) + (1.0,)
colours = b.picture(AROUND, UP, [zone(k) for k in range(UP) for j in range(AROUND)])

# s1: a noise volume of 32 that repeats (red heaped, green finer), as a stand-in for the client's Perlin-Worley one.
N = 32
random.seed(4)
def lattice(period):
    return [[[random.random() for _ in range(period)] for _ in range(period)] for _ in range(period)]
L8, L4, L16 = lattice(8), lattice(4), lattice(16)
def sample(L, period, x, y, z):
    fx, fy, fz = x * period / N, y * period / N, z * period / N
    ix, iy, iz = int(fx), int(fy), int(fz)
    tx, ty, tz = fx - ix, fy - iy, fz - iz
    sm = lambda t: t * t * (3 - 2 * t)
    tx, ty, tz = sm(tx), sm(ty), sm(tz)
    v = 0
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                w = (tx if dx else 1 - tx) * (ty if dy else 1 - ty) * (tz if dz else 1 - tz)
                v += w * L[(ix + dx) % period][(iy + dy) % period][(iz + dz) % period]
    return v
volume = c_void_p()
dev = b.device
bench._method(dev, 24, c_uint, c_uint, c_uint, c_uint, c_ulong, c_uint, c_uint, POINTER(c_void_p), c_void_p)(
    dev, N, N, N, 1, 0, 21, 1, byref(volume), None)
class Box(ctypes.Structure):
    _fields_ = [('RowPitch', ctypes.c_int), ('SlicePitch', ctypes.c_int), ('pBits', c_void_p)]
box = Box()
bench._method(volume, 19, c_uint, POINTER(Box), c_void_p, c_ulong)(volume, 0, byref(box), None, 0)
for z in range(N):
    for y in range(N):
        line = bytearray(N * 4)
        for x in range(N):
            red = 0.5 * sample(L4, 4, x, y, z) + 0.35 * sample(L8, 8, x, y, z) + 0.15 * sample(L16, 16, x, y, z)
            green = sample(L16, 16, x, y, z)
            line[x * 4:x * 4 + 4] = bytes((0, int(green * 255), int(red * 255), 255))
        ctypes.memmove(box.pBits + z * box.SlicePitch + y * box.RowPitch, bytes(line), len(line))
bench._method(volume, 20, c_uint)(volume, 0)

def unit(v):
    l = math.sqrt(sum(c * c for c in v))
    return tuple(c / l for c in v)
def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])

def sphere(progression):
    tilt = math.radians(40)
    pole = (math.cos(tilt), 0, math.sin(tilt))
    first = (-math.sin(tilt), 0, math.cos(tilt))
    second = cross(pole, first)
    t = progression * 2 * math.pi
    c, s = math.cos(t), math.sin(t)
    return ([c * first[k] - s * second[k] for k in range(3)], [s * first[k] + c * second[k] for k in range(3)], list(pole))

def shot(name, yaw, pitch, night=1.0, settings=(1, 1, 1, 1), cover=0.0, progression=0.0, seconds=12.3, moon=(-0.3, 0.6, 0.45), shooting=1.0,
         fov=90):
    ahead = unit((math.cos(math.radians(pitch)) * math.cos(math.radians(yaw)), math.cos(math.radians(pitch)) * math.sin(math.radians(yaw)),
                  math.sin(math.radians(pitch))))
    right = unit(cross(ahead, (0, 0, 1)))
    up = cross(right, ahead)
    wide = math.tan(math.radians(fov / 2))
    high = wide * H / W
    corners = []
    for x, y in ((-1, 1), (1, 1), (-1, -1), (1, -1)):
        way = tuple(ahead[k] + x * wide * right[k] + y * high * up[k] for k in range(3))
        corners.append((x, y, 0.5, way[0], way[1], way[2], 0xFFFFFFFF, 0, 0, 0, 0))
    rows = sphere(progression)
    m = unit(moon)
    numbers = {
        0: (m[0], m[1], m[2], 0.9),
        1: (0.55, 0.62, 0.80, 0.35),
        2: (0.35, 0.40, 0.55, 0.6),
        3: (0.10, 0.12, 0.18, cover),
        4: (0.02, 0.02, 0.04, 0.0),
        5: (1, 1, 1, 1),
        6: (seconds, AROUND, UP, 0),
        7: (night,) + tuple(settings[:3]),
        8: (shooting, 0, 0, 0),
        9: tuple(rows[0]) + (0,), 10: tuple(rows[1]) + (0,), 11: tuple(rows[2]) + (0,),
    }
    picture = b.draw(vs, ps, {}, numbers, [colours, volume], corners, smooth=True)
    bench.save_png(os.path.join(OUT, name + '.png'), picture)
    print(name, 'drawn')

shot('night_up', 30, 45)
shot('night_horizon', 200, 12)
shot('night_overhead', 0, 85, fov=100)
shot('dusk_half', 30, 45, night=0.35)
shot('night_clouds', 30, 45, cover=0.45)
shot('night_later', 30, 45, progression=0.08)
# A shooting star: find a slot that has one and draw it halfway through.
for slot in range(400):
    def h3(p):
        p = [x * 0.1031 - math.floor(x * 0.1031) for x in p]
        d = p[0] * (p[2] + 31.32) + p[1] * (p[1] + 31.32) + p[2] * (p[0] + 31.32)
        p = [x + d for x in p]
        v = (p[0] + p[1]) * p[2]
        return v - math.floor(v)
    if h3((slot, 4.1, 9.7)) <= 0.22:
        start = slot * 7.0 + h3((slot, 2.3, 1.1)) * (7.0 - 0.8)
        rnd = h3((slot, 7.7, 3.3)) * 6.283
        up = 0.45 + 0.6 * h3((slot, 5.5, 8.8))
        yaw = math.degrees(rnd)
        shot('shooting_star', yaw, math.degrees(up) - 5, seconds=start + 0.5, fov=100)
        break
