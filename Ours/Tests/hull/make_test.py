import io
# The jeep's hull and its solver, held against made-up ground, a wall, a post and a slope, without the game:
#   python Ours\Tests\hull\make_test.py   (writes hulltest.cpp beside it), then build and run it, e.g. with
#   g++ -O2 -std=c++17 hulltest.cpp -o hulltest.exe  (C:/Qt/Tools/mingw1310_64/bin on the PATH).
# It takes the code as it is from JeepDrive_C.cpp, between markers, so it tests what the client has.
import os
here = os.path.dirname(os.path.abspath(__file__))
src = io.open(os.path.join(here, '..', '..', '..', 'WoW', 'Source', 'Object', 'ObjectClient', 'JeepDrive_C.cpp'), encoding='utf-8').read()


def between(a, b):
    i = src.index(a)
    j = src.index(b, i)
    return src[i:j]


consts = between('const float GRAVITY', 'const float REST = 0.47f;')
hull = between('struct HullBox {', 'const float REST = 0.47f;')
helpers = between('void cross(const float a[3]', '// Its axes kept upright')
straighten = between('// Its axes kept upright', '// What the line trace is to be asked')
code = between('// ---- The hull against the world.', 'void physics(Driving& d')

# The game's types, as little of them as the code uses.
stubs = r'''
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <vector>
struct C3Vector { float x = 0, y = 0, z = 0; C3Vector() {} C3Vector(float a, float b, float c) : x(a), y(b), z(c) {} };
struct C4Plane { C3Vector n; float d; };
struct CFacet { C4Plane plane; C3Vector v[3]; };
struct CAaBox { C3Vector b, t; };
template <class T> struct Array { std::vector<T> v; T* m_data = nullptr; uint32_t Count() const { return (uint32_t)v.size(); } };
namespace World {
struct FacetData { Array<CFacet> facets; };
std::vector<CFacet> g_world;
inline int GetFacets(CAaBox*, FacetData* out, uint32_t, uint32_t*) { out->facets.v = g_world; out->facets.m_data = out->facets.v.data(); return 1; }
}
'''
driving = r'''
const float MASS_HEIGHT_ = 0.95f;
struct Driving {
    float at[3] = {}, v[3] = {}, w[3] = {};
    float axes[3][3] = { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } };
    unsigned facetsNear = 0;
};
'''
body_point = r'''
void bodyPoint(const Driving& d, const float p[3], float out[3]) {
    const float q[3] = { p[0], p[1], p[2] - MASS_HEIGHT };
    for (int r = 0; r < 3; ++r) out[r] = d.at[r] + d.axes[r][0] * q[0] + d.axes[r][1] * q[1] + d.axes[r][2] * q[2];
}
'''
main = r'''
CFacet tri(C3Vector a, C3Vector b, C3Vector c) {
    CFacet f; f.v[0] = a; f.v[1] = b; f.v[2] = c;
    float e1[3] = { b.x - a.x, b.y - a.y, b.z - a.z }, e2[3] = { c.x - a.x, c.y - a.y, c.z - a.z }, n[3];
    cross(e1, e2, n); float l = std::sqrt(dot(n, n));
    f.plane.n = C3Vector(n[0] / l, n[1] / l, n[2] / l);
    f.plane.d = -(f.plane.n.x * a.x + f.plane.n.y * a.y + f.plane.n.z * a.z);
    return f;
}
// Ground at z = 0 in squares of 4 yards (as the game's terrain), a wall facing -x at x = 12.
void world(bool wall) {
    World::g_world.clear();
    for (int i = -10; i < 10; ++i) for (int j = -10; j < 10; ++j) {
        float x = i * 4.0f, y = j * 4.0f;
        World::g_world.push_back(tri(C3Vector(x, y, 0), C3Vector(x + 4, y, 0), C3Vector(x + 4, y + 4, 0)));
        World::g_world.push_back(tri(C3Vector(x, y, 0), C3Vector(x + 4, y + 4, 0), C3Vector(x, y + 4, 0)));
    }
    if (wall) for (int j = -5; j < 5; ++j) {
        float y = j * 4.0f;
        World::g_world.push_back(tri(C3Vector(12, y, 0), C3Vector(12, y + 4, 6), C3Vector(12, y + 4, 0)));
        World::g_world.push_back(tri(C3Vector(12, y, 0), C3Vector(12, y, 6), C3Vector(12, y + 4, 6)));
    }
}

void post() {
    // A post 0.4 yards across at x 12, y 0.6 (it meets the chassis's front off its middle).
    float x0 = 12.0f, x1 = 12.4f, y0 = 0.4f, y1 = 0.8f, top = 3.0f;
    C3Vector c[4] = { C3Vector(x0, y0, 0), C3Vector(x1, y0, 0), C3Vector(x1, y1, 0), C3Vector(x0, y1, 0) };
    for (int i = 0; i < 4; ++i) {
        C3Vector a = c[i], b = c[(i + 1) % 4], at(a.x, a.y, top), bt(b.x, b.y, top);
        World::g_world.push_back(tri(a, bt, b));
        World::g_world.push_back(tri(a, at, bt));
    }
}
void slope(float degrees) {
    World::g_world.clear();
    float t = std::tan(degrees * 3.14159265f / 180.0f);
    for (int i = -10; i < 10; ++i) for (int j = -10; j < 10; ++j) {
        float x = i * 4.0f, y = j * 4.0f;
        C3Vector a(x, y, -x * t), b(x + 4, y, -(x + 4) * t), cc(x + 4, y + 4, -(x + 4) * t), dd(x, y + 4, -x * t);
        World::g_world.push_back(tri(a, b, cc));
        World::g_world.push_back(tri(a, cc, dd));
    }
}
void turn(Driving& d, int axis, float angle) {
    float c = std::cos(angle), s = std::sin(angle), m[3][3] = { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } };
    int a = (axis + 1) % 3, b = (axis + 2) % 3;
    m[a][a] = c; m[a][b] = -s; m[b][a] = s; m[b][b] = c;
    float out[3][3];
    for (int r = 0; r < 3; ++r) for (int k = 0; k < 3; ++k) out[r][k] = m[r][0] * d.axes[0][k] + m[r][1] * d.axes[1][k] + m[r][2] * d.axes[2][k];
    std::memcpy(d.axes, out, sizeof out);
}
float lowest(const Driving& d) {
    float low = 1e9f;
    for (const HullBox& box : HULL) for (int i = 0; i < 8; ++i) {
        const float own[3] = { box.middle[0] + box.half[0] * (i & 1 ? 1 : -1), box.middle[1] + box.half[1] * (i & 2 ? 1 : -1), box.middle[2] + box.half[2] * (i & 4 ? 1 : -1) };
        float p[3]; bodyPoint(d, own, p); low = std::min(low, p[2]);
    }
    return low;
}
// The hull alone (no wheels), as the physics' step has it: gravity, then the contacts, then on.
int g_kind = 0;
void run(const char* what, Driving d, float seconds, bool wall) {
    if (g_kind == 1) { world(false); post(); } else if (g_kind == 2) slope(40.0f); else world(wall);
    std::vector<Contact> contacts;
    const float h = 1.0f / 60.0f / 8.0f;
    float lowestSeen = 1e9f, mostX = -1e9f, maxSpeedAfter = 0;
    bool bad = false;
    for (int step = 0; step < int(seconds / h); ++step) {
        if (step % 8 == 0) gatherFacets(d, 1.0f / 60.0f);
        d.v[2] -= GRAVITY * h;
        findContacts(d, contacts);
        if (!contacts.empty()) solveContacts(d, contacts, h);
        for (int k = 0; k < 3; ++k) d.at[k] += d.v[k] * h;
        float turned[3][3];
        for (int r = 0; r < 3; ++r) for (int c = 0; c < 3; ++c) turned[r][c] = d.axes[r][c] + (d.w[(r + 1) % 3] * d.axes[(r + 2) % 3][c] - d.w[(r + 2) % 3] * d.axes[(r + 1) % 3][c]) * h;
        std::memcpy(d.axes, turned, sizeof turned);
        straighten(d.axes);
        lowestSeen = std::min(lowestSeen, lowest(d));
        float front[3]; const float nose[3] = { 2.8f, 0, 1.1f }; bodyPoint(d, nose, front);
        mostX = std::max(mostX, front[0]);
        if (!(d.at[2] == d.at[2])) bad = true;
    }
    const float speed = std::sqrt(dot(d.v, d.v)), spin = std::sqrt(dot(d.w, d.w));
    std::printf("%-44s lowest point ever %6.3f, now %6.3f; middle at %6.2f %6.2f %6.2f; up %5.2f; speed %5.2f spin %5.2f; nose reached x %5.2f%s\n",
        what, lowestSeen, lowest(d), d.at[0], d.at[1], d.at[2], d.axes[2][2], speed, spin, mostX, bad ? "  NaN!" : "");
}
int main() {
    Driving d;
    d.at[2] = 3.0f;                       run("dropped flat from 2 yards (hull only)", d, 3, false);
    d = Driving(); d.at[2] = 4.0f; turn(d, 0, 0.5f); turn(d, 1, 0.3f); run("dropped tilted from 3 yards", d, 4, false);
    d = Driving(); d.at[2] = 4.0f; turn(d, 0, 3.0f); run("dropped on its roof", d, 4, false);
    d = Driving(); d.at[2] = 1.5f; d.v[0] = 15.0f; run("slid into a wall at 15 yd/s (wall at x 12)", d, 3, true);
    d = Driving(); d.at[2] = 1.5f; turn(d, 2, 0.6f); d.v[0] = 20.0f; run("into the wall at an angle, 20 yd/s", d, 3, true);
    d = Driving(); d.at[2] = 1.5f; d.v[0] = 10.0f; d.v[2] = -12.0f; run("slammed down at 12 yd/s while sliding", d, 3, false);
    g_kind = 1; d = Driving(); d.at[0] = 6.5f; d.at[2] = 1.5f; d.v[0] = 12.0f; run("into a thin post at 12 yd/s (post at x 12)", d, 3, false);
    g_kind = 2; d = Driving(); d.at[2] = 3.0f; turn(d, 1, 0.70f); run("put on a 40 degree slope (it should slide down)", d, 3, false);
    g_kind = 0; d = Driving(); d.at[2] = 2.0f; d.w[0] = 6.0f; d.v[1] = 8.0f; run("rolling sideways", d, 5, false);
}
'''
out = stubs + consts + driving.replace('const float MASS_HEIGHT_ = 0.95f;', '') + helpers + straighten + code + main
io.open(os.path.join(here, 'hulltest.cpp'), 'w', encoding='utf-8').write(out)
print('ok')
