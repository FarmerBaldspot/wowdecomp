// Ours, not the game's (the World of Warcraft editor project). See OursFoam.h. No function here has an OFFSET: none
// of them is in the game.

#include "WoW/Source/WorldClient/OursFoam.h"
#include "Engine/Source/Tempest/CAaBox.h"
#include "Engine/Source/Tempest/CFacet.h"
#include "WoW/Source/WorldClient/World.h"
#ifdef _WIN32
#include "Engine/Source/Gx/CGxDeviceD3d/OursWater.h"
#include <windows.h>
#endif
#include <algorithm>
#include <cmath>
#include <condition_variable>
#include <cstdio>
#include <mutex>
#include <thread>
#include <vector>

namespace OursFoam {

namespace {

const int SIDE = 512;                    // squares a side
const float CELL = 0.5f;                 // yards a square
const float SNAP = 8.0f;                 // the map's middle is kept on a grid of so many yards
const float MOVED = 24.0f;               // made anew when the camera is so far from the map's middle
const double EVERY = 3.0;                // or so many seconds have passed (doors, ships)
const float BELOW = 120.0f, ABOVE = 40.0f;  // the heights asked for, under and over the camera
const float JOIN = 0.25f;                // two stretches of height closer than this are one
const float NONE_LO = 1e4f, NONE_HI = -1e4f;
const uint32_t FACET_FLAGS = 0x100111;   // as the jeep asks: ground, buildings, the map's models, objects

World::FacetData g_facetData;
std::vector<float> g_map;                // four numbers a square: two stretches (low, high), less the map's own height
float g_middleX = 1e9f, g_middleY = 1e9f, g_ownZ = 0;
double g_madeAt = -1e9;

double now() {
#ifdef _WIN32
    static LARGE_INTEGER frequency = {};
    if (!frequency.QuadPart) {
        QueryPerformanceFrequency(&frequency);
    }
    LARGE_INTEGER count;
    QueryPerformanceCounter(&count);
    return double(count.QuadPart) / double(frequency.QuadPart);
#else
    return 0;
#endif
}

// How far a point lies from a triangle, seen from above (nothing inside it).
float distanceFromAbove(float px, float py, const C3Vector* v) {
    float signs[3];
    float nearest = 1e9f;
    for (int k = 0; k < 3; ++k) {
        const C3Vector& a = v[k];
        const C3Vector& b = v[(k + 1) % 3];
        const float ex = b.x - a.x, ey = b.y - a.y;
        signs[k] = ex * (py - a.y) - ey * (px - a.x);
        const float length = ex * ex + ey * ey;
        const float t = length > 1e-8f ? std::clamp(((px - a.x) * ex + (py - a.y) * ey) / length, 0.0f, 1.0f) : 0.0f;
        const float dx = a.x + ex * t - px, dy = a.y + ey * t - py;
        nearest = std::min(nearest, std::sqrt(dx * dx + dy * dy));
    }
    const bool inside = (signs[0] >= 0 && signs[1] >= 0 && signs[2] >= 0) || (signs[0] <= 0 && signs[1] <= 0 && signs[2] <= 0);
    return inside ? 0.0f : nearest;
}

// The heights a triangle has within a square of the map: the triangle cut to the square's column (a little wider),
// its lowest and highest point. (For a steep triangle: a gentle one is its plane at the square's middle, and the slope.)
bool heightsIn(const CFacet& facet, float x0, float y0, float x1, float y1, float& lo, float& hi) {
    thread_local std::vector<C3Vector> polygon, next;
    polygon.assign(facet.v, facet.v + 3);
    auto cut = [&](int axis, float edge, bool keepBelow) {
        next.clear();
        for (size_t i = 0; i < polygon.size(); ++i) {
            const C3Vector& a = polygon[i];
            const C3Vector& b = polygon[(i + 1) % polygon.size()];
            const float da = (axis ? a.y : a.x) - edge, db = (axis ? b.y : b.x) - edge;
            const bool inA = keepBelow ? da <= 0 : da >= 0, inB = keepBelow ? db <= 0 : db >= 0;
            if (inA) {
                next.push_back(a);
            }
            if (inA != inB && std::fabs(da - db) > 1e-9f) {
                const float t = da / (da - db);
                next.push_back(C3Vector(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t));
            }
        }
        polygon.swap(next);
    };
    cut(0, x0, false);
    cut(0, x1, true);
    cut(1, y0, false);
    cut(1, y1, true);
    if (polygon.empty()) {
        return false;
    }
    lo = 1e9f;
    hi = -1e9f;
    for (const C3Vector& p : polygon) {
        lo = std::min(lo, p.z);
        hi = std::max(hi, p.z);
    }
    return true;
}

// A stretch of height put into a square: joined to one it touches, or kept beside it, or (where two are there
// already) joined to the nearer.
void putIn(float* square, float lo, float hi) {
    float* stretches[2] = { square, square + 2 };
    for (float* s : stretches) {
        if (s[0] <= s[1] && lo <= s[1] + JOIN && hi >= s[0] - JOIN) {
            s[0] = std::min(s[0], lo);
            s[1] = std::max(s[1], hi);
            // (It may now touch the other one.)
            float* o = s == square ? square + 2 : square;
            if (o[0] <= o[1] && s[0] <= o[1] + JOIN && s[1] >= o[0] - JOIN) {
                s[0] = std::min(s[0], o[0]);
                s[1] = std::max(s[1], o[1]);
                o[0] = NONE_LO;
                o[1] = NONE_HI;
            }
            return;
        }
    }
    for (float* s : stretches) {
        if (s[0] > s[1]) {
            s[0] = lo;
            s[1] = hi;
            return;
        }
    }
    const float gap0 = std::max(lo - square[1], square[0] - hi), gap1 = std::max(lo - square[3], square[2] - hi);
    float* s = gap0 <= gap1 ? square : square + 2;
    s[0] = std::min(s[0], lo);
    s[1] = std::max(s[1], hi);
}

// What the helper thread is given: the triangles (copied out of the game's own list, which the next question to the
// world overwrites) and where the map lies.
struct Job {
    std::vector<CFacet> facets;
    float originX = 0, originY = 0, ownZ = 0, middleX = 0, middleY = 0;
    double gatherMs = 0;
};

// Shared between the drawing thread and the helper. Made once and never freed: the helper is never waited for, so
// that leaving the game does not wait on it (or fall over on a thread nobody joined).
struct Shared {
    std::mutex lock;
    std::condition_variable wake;
    bool hasJob = false, busy = false, done = false;
    Job job, finished;
    std::vector<float> result;
    double layMs = 0;
};
Shared* g_shared = nullptr;

// The laying out, on the helper thread: nothing of the game is touched here, only the copied triangles.
void layOut(const Job& job, std::vector<float>& map) {
    map.assign(size_t(SIDE) * SIDE * 4, 0.0f);
    for (size_t i = 0; i < map.size(); i += 2) {
        map[i] = NONE_LO;
        map[i + 1] = NONE_HI;
    }
    const float originX = job.originX, originY = job.originY, cameraZ = job.ownZ;
    const float margin = CELL * 0.6f;
    for (const CFacet& facet : job.facets) {
        const C3Vector* v = facet.v;
        const float loX = std::min(v[0].x, std::min(v[1].x, v[2].x)), hiX = std::max(v[0].x, std::max(v[1].x, v[2].x));
        const float loY = std::min(v[0].y, std::min(v[1].y, v[2].y)), hiY = std::max(v[0].y, std::max(v[1].y, v[2].y));
        const float loZ = std::min(v[0].z, std::min(v[1].z, v[2].z)), hiZ = std::max(v[0].z, std::max(v[1].z, v[2].z));
        const int i0 = std::max(0, int(std::floor((loX - margin - originX) / CELL)));
        const int i1 = std::min(SIDE - 1, int(std::floor((hiX + margin - originX) / CELL)));
        const int j0 = std::max(0, int(std::floor((loY - margin - originY) / CELL)));
        const int j1 = std::min(SIDE - 1, int(std::floor((hiY + margin - originY) / CELL)));
        if (i0 > i1 || j0 > j1) {
            continue;
        }
        const float nz = facet.plane.n.z;
        const bool gentle = std::fabs(nz) > 0.5f;
        const float slope = gentle ? std::sqrt(facet.plane.n.x * facet.plane.n.x + facet.plane.n.y * facet.plane.n.y) / std::fabs(nz) * CELL * 0.71f : 0;
        for (int j = j0; j <= j1; ++j) {
            const float y0 = originY + j * CELL;
            for (int i = i0; i <= i1; ++i) {
                const float x0 = originX + i * CELL;
                float lo, hi;
                if (gentle) {
                    const float cx = x0 + CELL * 0.5f, cy = y0 + CELL * 0.5f;
                    if (distanceFromAbove(cx, cy, v) > margin) {
                        continue;
                    }
                    const float z = -(facet.plane.n.x * cx + facet.plane.n.y * cy + facet.plane.d) / nz;
                    lo = std::max(loZ, z - slope);
                    hi = std::min(hiZ, z + slope);
                    if (lo > hi) {
                        lo = hi = std::clamp(z, loZ, hiZ);
                    }
                } else if (!heightsIn(facet, x0 - CELL * 0.25f, y0 - CELL * 0.25f, x0 + CELL * 1.25f, y0 + CELL * 1.25f, lo, hi)) {
                    continue;
                }
                putIn(&map[(size_t(j) * SIDE + i) * 4], lo - cameraZ, hi - cameraZ);
            }
        }
    }
}

void helper(Shared* shared) {
    std::vector<float> map;
    for (;;) {
        Job job;
        {
            std::unique_lock<std::mutex> hold(shared->lock);
            shared->wake.wait(hold, [&] { return shared->hasJob; });
            job = std::move(shared->job);
            shared->hasJob = false;
            shared->busy = true;
        }
        const double started = now();
        layOut(job, map);
        const double took = (now() - started) * 1000;
        {
            std::lock_guard<std::mutex> hold(shared->lock);
            shared->result.swap(map);
            job.facets.clear();
            shared->finished = std::move(job);
            shared->layMs = took;
            shared->done = true;
            shared->busy = false;
        }
    }
}

// On the drawing thread: the world asked for its triangles (the game's own code, which is not to be called from
// another thread), and those handed to the helper.
void ask(float middleX, float middleY, float cameraZ) {
    if (!g_shared) {
        g_shared = new Shared;
        std::thread(helper, g_shared).detach();
    }
    const double started = now();
    const float half = SIDE * CELL * 0.5f;
    Job job;
    job.originX = middleX - half;
    job.originY = middleY - half;
    job.ownZ = cameraZ;
    job.middleX = middleX;
    job.middleY = middleY;
    CAaBox query;
    query.b = C3Vector(job.originX, job.originY, cameraZ - BELOW);
    query.t = C3Vector(job.originX + 2 * half, job.originY + 2 * half, cameraZ + ABOVE);
    if (World::GetFacets(&query, &g_facetData, FACET_FLAGS, nullptr)) {
        job.facets.assign(g_facetData.facets.m_data, g_facetData.facets.m_data + g_facetData.facets.Count());
    }
    job.gatherMs = (now() - started) * 1000;
    std::lock_guard<std::mutex> hold(g_shared->lock);
    g_shared->job = std::move(job);
    g_shared->hasJob = true;
    g_shared->wake.notify_one();
}

// On the drawing thread: a map the helper has finished, handed to the water.
void takeFinished() {
    if (!g_shared) {
        return;
    }
    Job finished;
    double layMs;
    {
        std::lock_guard<std::mutex> hold(g_shared->lock);
        if (!g_shared->done) {
            return;
        }
        g_shared->done = false;
        g_map.swap(g_shared->result);
        finished = std::move(g_shared->finished);
        layMs = g_shared->layMs;
    }
#ifdef _WIN32
    const double started = now();
    OursWater::SetSolidMap(g_map.data(), SIDE, finished.originX, finished.originY, CELL, finished.ownZ);
    static int told = 0;
    if (told < 6) {
        ++told;
        char line[240];
        std::snprintf(line, sizeof line, "the solid world for the foam around %.0f, %.0f: asked for in %.1f ms, laid out in %.1f ms on the helper thread, handed over in %.1f ms",
                      finished.middleX, finished.middleY, finished.gatherMs, layMs, (now() - started) * 1000);
        OursWater::Log(line);
    }
#endif
}

}  // namespace

void Update() {
    takeFinished();
#ifdef _WIN32
    if (!OursWater::WantsSolidMap()) {
        return;
    }
#endif
    const C3Vector* camera = World::GetCamPos();
    if (!camera) {
        return;
    }
    // (One map at a time: while the helper works on one, the next waits.)
    if (g_shared) {
        std::lock_guard<std::mutex> hold(g_shared->lock);
        if (g_shared->hasJob || g_shared->busy) {
            return;
        }
    }
    const float middleX = std::round(camera->x / SNAP) * SNAP, middleY = std::round(camera->y / SNAP) * SNAP;
    const bool movedOff = std::fabs(camera->x - g_middleX) > MOVED || std::fabs(camera->y - g_middleY) > MOVED || std::fabs(camera->z - g_ownZ) > 30;
    const double t = now();
    if (movedOff || t - g_madeAt > EVERY) {
        g_madeAt = t;
        g_middleX = middleX;
        g_middleY = middleY;
        g_ownZ = camera->z;
        ask(middleX, middleY, camera->z);
    }
}

}  // namespace OursFoam
