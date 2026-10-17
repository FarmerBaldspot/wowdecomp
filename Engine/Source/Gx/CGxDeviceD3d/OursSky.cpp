// Ours, not the game's (the World of Warcraft editor project). See OursSky.h. No function here has an OFFSET: none of
// them is in the game.
//
// The shader is drawn over all of the sky's viewport as two triangles, with Direct3D's own calls and everything that
// is set on the device kept in a block of settings before and put back after, so that the game's idea of what is set
// stays true (as the water's depth copy does it, OursWater.cpp). It is drawn at the very back with the depth test
// on: the game draws the sky after the world, and the test keeps it where nothing is. What it is handed:
//   c0  the sun (xyz, how much up)         c1  the sun's colour, its glow
//   c2  the clouds' lit colour, how lit     c3  their own colour, how much they cover
//   c4  their shade, the storm              c5  amount, speed, glow, 1 (the settings)
//   c6  seconds, the colour picture's size (around, up)
//   c7  the stars: how many are out, their brightness, the Milky Way's, the twinkling
//   c8  how many shooting stars             c9 to c11  into the turning sky of stars
//   s0  the colour picture
// Blending: what the shader gives is added over what is there (the sun, the moons, the stars) as the game's dome is,
// and its alpha is how much the clouds cover what is behind: one, inverse source alpha.

#include "Engine/Source/Gx/CGxDeviceD3d/OursSky.h"
#include "Engine/Source/Gx/CGxDeviceD3d/OursWater.h"
#include <windows.h>
#include <cstring>
#include <string>
#include <algorithm>
#include <atomic>
#include <cmath>
#include <thread>
#include <vector>

namespace OursSky {

namespace {

LPDIRECT3DDEVICE9 g_device = nullptr;
IDirect3DVertexShader9* g_vs = nullptr;
IDirect3DPixelShader9* g_ps = nullptr;
IDirect3DVertexDeclaration9* g_layout = nullptr;
IDirect3DStateBlock9* g_saved = nullptr;
IDirect3DTexture9* g_colours = nullptr;      // managed: it lives through resets
IDirect3DVolumeTexture9* g_noise = nullptr;  // the clouds' noise, made once (managed too)

// ---- The clouds' noise: a cube of 64 that repeats seamlessly on every side. Red: billowy cells (the inverse of the
// distance to the nearest of points scattered one to a cell, at 4, 8 and 16 cells across) worked into soft noise,
// which is what makes heaped clouds round (Schneider's "Perlin-Worley", Horizon Zero Dawn); green: the cells alone,
// finer, for eating at their edges. Made on a helper thread when the client starts (a fifth of a second or so), and
// until it is there the game's own sky is drawn.
const int NOISE = 64;
std::vector<uint32_t> g_voxels;
std::atomic<int> g_noiseState(0);           // 0 not begun, 1 being made, 2 made

uint32_t mix(uint32_t x) {
    x ^= x >> 16;
    x *= 0x7FEB352D;
    x ^= x >> 15;
    x *= 0x846CA68B;
    x ^= x >> 16;
    return x;
}

float lattice(int x, int y, int z, int seed) {
    return (mix(uint32_t(x) * 73856093u ^ uint32_t(y) * 19349663u ^ uint32_t(z) * 83492791u ^ uint32_t(seed) * 2654435761u) & 0xFFFFFF) / float(0x1000000);
}

// Smooth noise of "period" lattice points across the cube, repeating with it.
float soft(float x, float y, float z, int period, int seed) {
    x *= period;
    y *= period;
    z *= period;
    const int ix = int(std::floor(x)), iy = int(std::floor(y)), iz = int(std::floor(z));
    const float fx = x - ix, fy = y - iy, fz = z - iz;
    auto fade = [](float t) { return t * t * t * (t * (t * 6 - 15) + 10); };
    const float u = fade(fx), v = fade(fy), w = fade(fz);
    auto at = [&](int a, int b, int c) { return lattice(((ix + a) % period + period) % period, ((iy + b) % period + period) % period, ((iz + c) % period + period) % period, seed); };
    const float x00 = at(0, 0, 0) + (at(1, 0, 0) - at(0, 0, 0)) * u, x10 = at(0, 1, 0) + (at(1, 1, 0) - at(0, 1, 0)) * u;
    const float x01 = at(0, 0, 1) + (at(1, 0, 1) - at(0, 0, 1)) * u, x11 = at(0, 1, 1) + (at(1, 1, 1) - at(0, 1, 1)) * u;
    const float y0 = x00 + (x10 - x00) * v, y1 = x01 + (x11 - x01) * v;
    return y0 + (y1 - y0) * w;
}

// Billowy cells: one minus the distance (in cells) to the nearest point, "cells" across the cube, repeating.
float cells(float x, float y, float z, int count, int seed) {
    x *= count;
    y *= count;
    z *= count;
    const int ix = int(std::floor(x)), iy = int(std::floor(y)), iz = int(std::floor(z));
    float nearest = 9;
    for (int c = -1; c <= 1; ++c) {
        for (int b = -1; b <= 1; ++b) {
            for (int a = -1; a <= 1; ++a) {
                const int cx = ix + a, cy = iy + b, cz = iz + c;
                const int wx = (cx % count + count) % count, wy = (cy % count + count) % count, wz = (cz % count + count) % count;
                const float px = cx + lattice(wx, wy, wz, seed), py = cy + lattice(wx, wy, wz, seed + 1), pz = cz + lattice(wx, wy, wz, seed + 2);
                const float dx = px - x, dy = py - y, dz = pz - z;
                nearest = std::min(nearest, dx * dx + dy * dy + dz * dz);
            }
        }
    }
    return std::max(0.0f, 1.0f - std::sqrt(nearest));
}

void makeNoise() {
    std::vector<uint32_t> voxels(size_t(NOISE) * NOISE * NOISE);
    for (int k = 0; k < NOISE; ++k) {
        for (int j = 0; j < NOISE; ++j) {
            for (int i = 0; i < NOISE; ++i) {
                const float x = (i + 0.5f) / NOISE, y = (j + 0.5f) / NOISE, z = (k + 0.5f) / NOISE;
                const float smooth = soft(x, y, z, 4, 1) * 0.5f + soft(x, y, z, 8, 2) * 0.25f + soft(x, y, z, 16, 3) * 0.125f + soft(x, y, z, 32, 4) * 0.0625f;
                const float billows = cells(x, y, z, 4, 10) * 0.625f + cells(x, y, z, 8, 20) * 0.25f + cells(x, y, z, 16, 30) * 0.125f;
                // The soft noise lifted where the cells are: round heaps with soft ground between them.
                const float low = billows - 1.0f;
                const float shape = std::min(std::max((smooth / 0.9375f - low) / (1.0f - low), 0.0f), 1.0f);
                const float fine = cells(x, y, z, 8, 40) * 0.625f + cells(x, y, z, 16, 50) * 0.25f + cells(x, y, z, 32, 60) * 0.125f;
                const uint32_t r = uint32_t(std::min(std::max(shape, 0.0f), 1.0f) * 255.0f + 0.5f);
                const uint32_t g = uint32_t(std::min(std::max(fine, 0.0f), 1.0f) * 255.0f + 0.5f);
                voxels[(size_t(k) * NOISE + j) * NOISE + i] = 0xFF000000u | (r << 16) | (g << 8) | r;
            }
        }
    }
    g_voxels.swap(voxels);
    g_noiseState = 2;
}

// The cube of noise put into a picture of the device's, once it is made.
bool noiseReady() {
    if (g_noise) {
        return true;
    }
    if (g_noiseState == 0) {
        g_noiseState = 1;
        std::thread(makeNoise).detach();
        return false;
    }
    if (g_noiseState != 2) {
        return false;
    }
    if (FAILED(g_device->CreateVolumeTexture(NOISE, NOISE, NOISE, 1, 0, D3DFMT_A8R8G8B8, D3DPOOL_MANAGED, &g_noise, nullptr))) {
        g_noise = nullptr;
        return false;
    }
    D3DLOCKED_BOX box;
    if (FAILED(g_noise->LockBox(0, &box, nullptr, 0))) {
        g_noise->Release();
        g_noise = nullptr;
        return false;
    }
    for (int k = 0; k < NOISE; ++k) {
        for (int j = 0; j < NOISE; ++j) {
            std::memcpy(static_cast<uint8_t*>(box.pBits) + size_t(k) * box.SlicePitch + size_t(j) * box.RowPitch, &g_voxels[(size_t(k) * NOISE + j) * NOISE], NOISE * 4);
        }
    }
    g_noise->UnlockBox(0);
    OursWater::Log("the clouds' noise is made");
    return true;
}
int32_t g_around = 0, g_up = 0;
uint64_t g_written = 0;
DWORD g_checkedAt = 0;
bool g_tried = false, g_failed = false;

template <class T>
void release(T*& thing) {
    if (thing) {
        thing->Release();
        thing = nullptr;
    }
}

void say(const char* line) {
    OursWater::Log(line);
}

std::string skyPath() {
    return OursWater::Folder() + "Shaders\\sky.hlsl";
}

// The two shaders compiled and made; or nothing changed where either does not compile.
void compile() {
    if (!g_device || OursWater::Folder().empty()) {
        return;
    }
    const std::string path = skyPath();
    std::vector<uint8_t> vertexCode, pixelCode;
    if (!OursWater::CompileFile(path, { { "VERTEX", "1" } }, "vs_3_0", vertexCode) || !OursWater::CompileFile(path, { { "VERTEX", "0" } }, "ps_3_0", pixelCode)) {
        if (!g_vs || !g_ps) {
            g_failed = true;
        }
        say("sky.hlsl does not compile: the sky stays as it was");
        return;
    }
    IDirect3DVertexShader9* vs = nullptr;
    IDirect3DPixelShader9* ps = nullptr;
    if (FAILED(g_device->CreateVertexShader(reinterpret_cast<const DWORD*>(vertexCode.data()), &vs))
        || FAILED(g_device->CreatePixelShader(reinterpret_cast<const DWORD*>(pixelCode.data()), &ps))) {
        release(vs);
        release(ps);
        say("the sky's shaders could not be made");
        return;
    }
    release(g_vs);
    release(g_ps);
    g_vs = vs;
    g_ps = ps;
    g_failed = false;
    say("sky.hlsl compiled: the sky is ours");
}

void poll() {
    const DWORD now = GetTickCount();
    if (g_tried && now - g_checkedAt < 500) {
        return;
    }
    g_checkedAt = now;
    const uint64_t written = OursWater::WrittenAt(skyPath());
    if (!g_tried || written != g_written) {
        g_tried = true;
        g_written = written;
        compile();
    }
}

bool putColours(const Frame& frame) {
    if (g_colours && (g_around != frame.around || g_up != frame.up)) {
        release(g_colours);
    }
    bool fresh = false;
    if (!g_colours) {
        if (FAILED(g_device->CreateTexture(frame.around, frame.up, 1, 0, D3DFMT_A32B32G32R32F, D3DPOOL_MANAGED, &g_colours, nullptr))) {
            g_colours = nullptr;
            return false;
        }
        g_around = frame.around;
        g_up = frame.up;
        fresh = true;
    }
    if (fresh || frame.coloursChanged) {
        D3DLOCKED_RECT locked;
        if (FAILED(g_colours->LockRect(0, &locked, nullptr, 0))) {
            return false;
        }
        for (int32_t row = 0; row < frame.up; ++row) {
            std::memcpy(static_cast<uint8_t*>(locked.pBits) + size_t(row) * locked.Pitch, frame.colours + size_t(row) * frame.around * 4, size_t(frame.around) * 16);
        }
        g_colours->UnlockRect(0);
    }
    return true;
}

}  // namespace

void DeviceReady(LPDIRECT3DDEVICE9 device) {
    if (device != g_device) {
        // (Another device: everything of the old one goes, the managed picture and the shaders too.)
        release(g_colours);
        release(g_noise);
        release(g_vs);
        release(g_ps);
        release(g_layout);
        g_tried = false;
    }
    g_device = device;
    if (!device) {
        return;
    }
    if (!g_layout) {
        const D3DVERTEXELEMENT9 elements[] = {
            { 0, 0, D3DDECLTYPE_FLOAT4, D3DDECLMETHOD_DEFAULT, D3DDECLUSAGE_POSITION, 0 },
            { 0, 16, D3DDECLTYPE_FLOAT3, D3DDECLMETHOD_DEFAULT, D3DDECLUSAGE_TEXCOORD, 0 },
            D3DDECL_END(),
        };
        device->CreateVertexDeclaration(elements, &g_layout);
    }
    device->CreateStateBlock(D3DSBT_ALL, &g_saved);
}

void DeviceLost() {
    release(g_saved);
}

bool Ready() {
    if (!g_device) {
        return false;
    }
    poll();
    return g_vs && g_ps && g_layout && g_saved;
}

bool Draw(const Frame& frame) {
    if (!Ready() || !noiseReady() || !putColours(frame)) {
        return false;
    }
    const float constants[12][4] = {
        { frame.sun[0], frame.sun[1], frame.sun[2], frame.sun[3] },
        { frame.sunColour[0], frame.sunColour[1], frame.sunColour[2], frame.sunColour[3] },
        { frame.cloudLit[0], frame.cloudLit[1], frame.cloudLit[2], frame.cloudLit[3] },
        { frame.cloudBody[0], frame.cloudBody[1], frame.cloudBody[2], frame.cloudBody[3] },
        { frame.cloudShade[0], frame.cloudShade[1], frame.cloudShade[2], frame.cloudShade[3] },
        { frame.settings[0], frame.settings[1], frame.settings[2], frame.settings[3] },
        { frame.seconds, float(frame.around), float(frame.up), 0 },
        { frame.night[0], frame.night[1], frame.night[2], frame.night[3] },
        { frame.nightMore[0], frame.nightMore[1], frame.nightMore[2], frame.nightMore[3] },
        { frame.sphere[0][0], frame.sphere[0][1], frame.sphere[0][2], 0 },
        { frame.sphere[1][0], frame.sphere[1][1], frame.sphere[1][2], 0 },
        { frame.sphere[2][0], frame.sphere[2][1], frame.sphere[2][2], 0 },
    };
    struct Corner {
        float x, y, z, w;
        float way[3];
    };
    const float at[4][2] = { { -1, 1 }, { 1, 1 }, { -1, -1 }, { 1, -1 } };
    Corner corners[4];
    for (int i = 0; i < 4; ++i) {
        // (At the very back: the depth test then keeps the sky where nothing of the world is, as the game's dome.)
        corners[i] = { at[i][0], at[i][1], 0.9999f, 1.0f, { frame.corners[i][0], frame.corners[i][1], frame.corners[i][2] } };
    }

    g_saved->Capture();
    g_device->SetVertexDeclaration(g_layout);
    g_device->SetVertexShader(g_vs);
    g_device->SetPixelShader(g_ps);
    g_device->SetPixelShaderConstantF(0, &constants[0][0], 12);
    g_device->SetTexture(0, g_colours);
    g_device->SetSamplerState(0, D3DSAMP_ADDRESSU, D3DTADDRESS_WRAP);
    g_device->SetSamplerState(0, D3DSAMP_ADDRESSV, D3DTADDRESS_CLAMP);
    g_device->SetSamplerState(0, D3DSAMP_MINFILTER, D3DTEXF_LINEAR);
    g_device->SetSamplerState(0, D3DSAMP_MAGFILTER, D3DTEXF_LINEAR);
    g_device->SetSamplerState(0, D3DSAMP_MIPFILTER, D3DTEXF_NONE);
    g_device->SetSamplerState(0, D3DSAMP_SRGBTEXTURE, FALSE);
    g_device->SetTexture(1, g_noise);
    for (D3DSAMPLERSTATETYPE address : { D3DSAMP_ADDRESSU, D3DSAMP_ADDRESSV, D3DSAMP_ADDRESSW }) {
        g_device->SetSamplerState(1, address, D3DTADDRESS_WRAP);
    }
    g_device->SetSamplerState(1, D3DSAMP_MINFILTER, D3DTEXF_LINEAR);
    g_device->SetSamplerState(1, D3DSAMP_MAGFILTER, D3DTEXF_LINEAR);
    g_device->SetSamplerState(1, D3DSAMP_MIPFILTER, D3DTEXF_NONE);
    g_device->SetSamplerState(1, D3DSAMP_SRGBTEXTURE, FALSE);
    // The game draws the sky AFTER the world, and its depth test is what keeps the sky behind it: the first make had
    // the test off and laid the sky and its clouds over everything (the user's picture, Stormwind at dusk).
    g_device->SetRenderState(D3DRS_ZENABLE, TRUE);
    g_device->SetRenderState(D3DRS_ZFUNC, D3DCMP_LESSEQUAL);
    g_device->SetRenderState(D3DRS_ZWRITEENABLE, FALSE);
    g_device->SetRenderState(D3DRS_ALPHABLENDENABLE, TRUE);
    g_device->SetRenderState(D3DRS_SEPARATEALPHABLENDENABLE, FALSE);
    g_device->SetRenderState(D3DRS_BLENDOP, D3DBLENDOP_ADD);
    g_device->SetRenderState(D3DRS_SRCBLEND, D3DBLEND_ONE);
    g_device->SetRenderState(D3DRS_DESTBLEND, D3DBLEND_INVSRCALPHA);
    g_device->SetRenderState(D3DRS_ALPHATESTENABLE, FALSE);
    g_device->SetRenderState(D3DRS_STENCILENABLE, FALSE);
    g_device->SetRenderState(D3DRS_CULLMODE, D3DCULL_NONE);
    g_device->SetRenderState(D3DRS_FOGENABLE, FALSE);
    g_device->SetRenderState(D3DRS_SRGBWRITEENABLE, FALSE);
    g_device->SetRenderState(D3DRS_CLIPPLANEENABLE, 0);
    g_device->SetRenderState(D3DRS_COLORWRITEENABLE, 0xF);
    const bool drawn = SUCCEEDED(g_device->DrawPrimitiveUP(D3DPT_TRIANGLESTRIP, 2, corners, sizeof corners[0]));
    g_saved->Apply();
    return drawn;
}

}  // namespace OursSky
