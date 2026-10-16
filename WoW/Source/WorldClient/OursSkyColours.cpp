// Ours, not the game's (the World of Warcraft editor project). See OursSkyColours.h. No function here has an OFFSET:
// none of them is in the game.

#include "WoW/Source/WorldClient/OursSkyColours.h"
#include "Engine/Source/ConsoleBase/ConsoleVar.h"
#include "Engine/Source/Gx/CGxDevice/CGxDevice.h"
#include "Engine/Source/Tempest/C44Matrix.h"
#include "WoW/Source/WorldClient/DayNight.h"
#include "WoW/Source/WorldClient/DayNight__DNInfo.h"
#ifdef _WIN32
#include "Engine/Source/Gx/CGxDeviceD3d/OursSky.h"
#include "Engine/Source/Gx/CGxDeviceD3d/OursWater.h"
#include <windows.h>
#endif
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <vector>

namespace OursSkyColours {

namespace {

const int AROUND = 128, UP = 96;             // the picture of the sky's colours
const int COLUMNS = 24, ROWS = 6;            // the game's dome: 24 columns, and six rows of colour from the top
// The rows' angles from the top of the dome (DayNight.cpp, s_skyThetaTable, in halves of a circle); the sixth is
// the horizon (the fog's colour, also all below it).
const float THETA[ROWS] = { 0.0f, 0.17f, 0.2f, 0.23f, 0.24f, 0.25f };
const float PI = 3.14159265f;

std::vector<float> g_picture(size_t(AROUND) * UP * 4);
CImVector g_was[1 + 5 * COLUMNS];
bool g_haveWas = false;

// The colour at row "row" (0 the top) and column "column" of the game's dome, from its vertex colours: the top, then
// four rows of 24, then the horizon's row of 24 (DayNight::DNSky::SetColors).
const CImVector& vertexColour(const CImVector* colours, int row, int column) {
    column = ((column % COLUMNS) + COLUMNS) % COLUMNS;
    return row == 0 ? colours[0] : colours[1 + (row - 1) * COLUMNS + column];
}

// Around: a curve through the columns (Catmull and Rom's, the dome being round), held within what the colours are.
void around(const CImVector* colours, int row, float at, float out[4]) {
    const int column = int(std::floor(at));
    const float t = at - column;
    for (int k = 0; k < 4; ++k) {
        float p[4];
        for (int i = 0; i < 4; ++i) {
            const CImVector& c = vertexColour(colours, row, column - 1 + i);
            const uint8_t channel = k == 0 ? c.r : k == 1 ? c.g : k == 2 ? c.b : c.a;
            p[i] = channel / 255.0f;
        }
        const float value = 0.5f * (2 * p[1] + (p[2] - p[0]) * t + (2 * p[0] - 5 * p[1] + 4 * p[2] - p[3]) * t * t + (3 * p[1] - p[0] - 3 * p[2] + p[3]) * t * t * t);
        out[k] = std::min(std::max(value, std::min(p[1], p[2]) - 0.02f), std::max(p[1], p[2]) + 0.02f);
    }
}

// Up and down: a curve through the rows that never overshoots (Fritsch and Butland), for one channel.
float upAndDown(const float* x, const float* y, int n, float at) {
    if (at <= x[0]) {
        return y[0];
    }
    if (at >= x[n - 1]) {
        return y[n - 1];
    }
    int k = 0;
    while (k < n - 2 && at > x[k + 1]) {
        ++k;
    }
    auto slope = [&](int i) { return (y[i + 1] - y[i]) / (x[i + 1] - x[i]); };
    auto tangent = [&](int i) {
        if (i == 0) {
            return slope(0);
        }
        if (i == n - 1) {
            return slope(n - 2);
        }
        const float d0 = slope(i - 1), d1 = slope(i);
        if (d0 * d1 <= 0) {
            return 0.0f;
        }
        const float h0 = x[i] - x[i - 1], h1 = x[i + 1] - x[i];
        return 3 * (h0 + h1) / ((2 * h1 + h0) / d0 + (h1 + 2 * h0) / d1);
    };
    const float h = x[k + 1] - x[k], t = (at - x[k]) / h;
    const float m0 = tangent(k) * h, m1 = tangent(k + 1) * h;
    const float t2 = t * t, t3 = t2 * t;
    return (2 * t3 - 3 * t2 + 1) * y[k] + (t3 - 2 * t2 + t) * m0 + (-2 * t3 + 3 * t2) * y[k + 1] + (t3 - t2) * m1;
}

void layOut(const CImVector* colours) {
    float rowAngle[ROWS];
    for (int r = 0; r < ROWS; ++r) {
        rowAngle[r] = THETA[r] * PI;
    }
    for (int j = 0; j < AROUND; ++j) {
        // (The picture's column j is the way round of (j + 0.5) / AROUND, as the shader reads it.)
        const float at = (j + 0.5f) / AROUND * COLUMNS;
        float rows[ROWS][4];
        for (int r = 0; r < ROWS; ++r) {
            around(colours, r, at, rows[r]);
        }
        for (int k = 0; k < UP; ++k) {
            const float theta = (k + 0.5f) / UP * 0.25f * PI;
            float* out = &g_picture[(size_t(k) * AROUND + j) * 4];
            for (int c = 0; c < 4; ++c) {
                float y[ROWS];
                for (int r = 0; r < ROWS; ++r) {
                    y[r] = rows[r][c];
                }
                out[c] = std::min(std::max(upAndDown(rowAngle, y, ROWS, theta), 0.0f), 1.0f);
            }
        }
    }
}

void colourOf(const CImVector& c, float out[3]) {
    out[0] = c.r / 255.0f;
    out[1] = c.g / 255.0f;
    out[2] = c.b / 255.0f;
}

double seconds() {
#ifdef _WIN32
    static LARGE_INTEGER frequency = {}, started = {};
    if (!frequency.QuadPart) {
        QueryPerformanceFrequency(&frequency);
        QueryPerformanceCounter(&started);
    }
    LARGE_INTEGER now;
    QueryPerformanceCounter(&now);
    return double(now.QuadPart - started.QuadPart) / double(frequency.QuadPart);
#else
    return 0;
#endif
}

float setting(const char* name, float otherwise) {
    CVar* var = CVar::Lookup(name);
    return var ? var->m_floatValue : otherwise;
}

}  // namespace

bool Render() {
#ifdef _WIN32
    if (setting("oursSky", 1) < 0.5f || !OursSky::Ready()) {
        return false;
    }
    DayNight::DNSky& sky = DayNight::g_sky;
    if (sky.m_sphThetaTess != COLUMNS || sky.m_clrVerts.Count() < uint32_t(1 + 5 * COLUMNS)) {
        return false;
    }
    const CImVector* colours = sky.m_clrVerts.m_data;
    const bool changed = !g_haveWas || std::memcmp(g_was, colours, sizeof g_was) != 0;
    if (changed) {
        layOut(colours);
        std::memcpy(g_was, colours, sizeof g_was);
        g_haveWas = true;
    }

    OursSky::Frame frame = {};
    frame.colours = g_picture.data();
    frame.around = AROUND;
    frame.up = UP;
    frame.coloursChanged = changed;

    // The ways through the corners of the view. The eye's own axes in the world are the view matrix's columns (its
    // third the way ahead, as the game's sun and moons take it, DayNight::DNPlanet::Render); how wide the view is, the
    // projection's first two numbers on its diagonal; which way of the eye's z is ahead, the sign of what the
    // projection makes w of. (The first make put the corners back through the inverse of view and projection, and
    // looked below the horizon whichever way the camera looked: the user's picture, a sky all of one colour.)
    const CGxMatrixStack& viewStack = g_theGxDevicePtr->m_xforms[GxXform_View];
    const C44Matrix& view = viewStack.m_mtx[viewStack.m_level];
    const C44Matrix& projection = g_theGxDevicePtr->m_projNative;
    const float right[3] = { view.a0, view.b0, view.c0 }, up[3] = { view.a1, view.b1, view.c1 }, ahead[3] = { view.a2, view.b2, view.c2 };
    const float wide = projection.a0 != 0 ? 1.0f / projection.a0 : 1.0f, high = projection.b1 != 0 ? 1.0f / projection.b1 : 1.0f;
    const float forward = projection.c3 < 0 ? -1.0f : 1.0f;
    const float corner[4][2] = { { -1, 1 }, { 1, 1 }, { -1, -1 }, { 1, -1 } };
    for (int i = 0; i < 4; ++i) {
        for (int k = 0; k < 3; ++k) {
            frame.corners[i][k] = corner[i][0] * wide * right[k] + corner[i][1] * high * up[k] + forward * ahead[k];
        }
    }
    static int told = 0;
    if (told < 3) {
        ++told;
        char line[300];
        const C3Vector& camera = DayNight::g_dnInfo.m_cameraDir;
        std::snprintf(line, sizeof line, "sky: the middle of the view goes %.2f %.2f %.2f (the game's camera: %.2f %.2f %.2f); wide %.2f, high %.2f, ahead is %s z",
                      forward * ahead[0], forward * ahead[1], forward * ahead[2], camera.x, camera.y, camera.z, wide, high, forward < 0 ? "-" : "+");
        OursWater::Log(line);
    }

    // What lights the clouds: the sun by day and the moon by night, as the game's own clouds have it
    // (DayNight::DNClouds::SetupBumpMap); how much of it is up is its picture's alpha.
    DayNight::DNInfo& info = DayNight::g_dnInfo;
    const bool night = info.m_dayProgression < 0.2013889f || info.m_dayProgression > 0.9236111f;
    const DayNight::DNPlanet& light = night ? DayNight::g_planets.m_moon : DayNight::g_planets.m_sun;
    float way[3] = { light.m_position.x - info.m_cameraPos.x, light.m_position.y - info.m_cameraPos.y, light.m_position.z - info.m_cameraPos.z };
    const float length = std::sqrt(way[0] * way[0] + way[1] * way[1] + way[2] * way[2]);
    for (float& k : way) {
        k = length > 1e-4f ? k / length : 0.0f;
    }
    frame.sun[0] = way[0];
    frame.sun[1] = way[1];
    frame.sun[2] = way[2];
    frame.sun[3] = light.m_color.a / 255.0f;

    const DayNight::CurrentLight& bands = info.m_bands;
    colourOf(bands.m_sunCloudColors[0], frame.sunColour);
    frame.sunColour[3] = night ? 0.35f : 1.0f;
    colourOf(bands.m_sunCloudColors[1], frame.cloudLit);
    frame.cloudLit[3] = 1.0f - info.m_stormBlend * 0.75f;
    colourOf(bands.m_sunCloudColors[3], frame.cloudBody);
    const DayNight::DNClouds& clouds = DayNight::g_clouds;
    const float density = clouds.m_densityOverride != 0.0f ? clouds.m_densityOverride : bands.m_cloudDensity;
    frame.cloudBody[3] = clouds.m_enabled ? std::min(std::max(density, 0.0f), 1.0f) : 0.0f;
    colourOf(bands.m_sunCloudColors[2], frame.cloudShade);
    frame.cloudShade[3] = info.m_stormBlend;

    frame.settings[0] = setting("oursSkyClouds", 100) / 100.0f;
    frame.settings[1] = setting("oursSkyCloudSpeed", 100) / 100.0f;
    frame.settings[2] = setting("oursSkySunGlow", 100) / 100.0f;
    frame.settings[3] = 1;
    frame.seconds = float(std::fmod(seconds(), 20000.0));
    return OursSky::Draw(frame);
#else
    return false;
#endif
}

}  // namespace OursSkyColours
