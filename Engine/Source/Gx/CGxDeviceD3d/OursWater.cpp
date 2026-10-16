// Ours, not the game's (the World of Warcraft editor project): the water made anew. See OursWater.h. No function here
// has an OFFSET: none of them is in the game.
//
// What it hands the water's shader (the same as the DLL's core did, at the same places, so that one water.hlsl
// serves both):
//   c200  the clock: seconds gone by (an hour round), seconds since the last frame, the frame's number, 1
//   c201  one over the frame's width and height; 1 if the frame as drawn before the water is there; 1 if its depth is
//   c202  where the game's depths begin in nothing-to-one (its viewport's), and one over how much of it they take
//   c203  the dials, sixty-four of them in sixteen registers
//   s13   the picture of waves (Ours\Textures\waves.bmp, made by the editor's client\gfx\textures\make_waves.py)
//   s14   the frame as drawn before the water
//   s15   the depth of everything in it, as numbers (copied from the depth buffer, which is an INTZ picture)
// Where it finds its files: the fork's own Ours folder (two above the client, bin\Win), or one beside the client.
// What it did, and why not where it could not: OursWater.log beside the client.

#include "Engine/Source/Gx/CGxDeviceD3d/OursWater.h"
#include "Engine/Source/Gx/CGxDeviceD3d/OursSky.h"
#include "Engine/Source/Gx/CGxDevice/CGxDevice.h"
#include "Engine/Source/Gx/CGxDevice/CGxShader.h"
#include "Engine/Source/Gx/Gx.h"
#include <windows.h>
#include <d3dcompiler.h>
#include <algorithm>
#include <cmath>
#include <cstdarg>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

namespace OursWater {

namespace {

const D3DFORMAT INTZ = static_cast<D3DFORMAT>(MAKEFOURCC('I', 'N', 'T', 'Z'));
const UINT PIXEL_CLOCK = 200, PIXEL_SCREEN = 201, PIXEL_DEPTH_PART = 202, PIXEL_DIALS = 203;
const int DIALS = 68;
// As the DLL's core has them at first (client\gfx\src\core.cpp, g_dials): 3 the new water on, 4 its foam, 5 the
// waves' height, 7 the web of light on the bed, 20 the foam's width, 21 how clear it is, 22 how much it mirrors, 23
// the sun's glitter; the others are the other effects', kept for when those come.
float g_dials[DIALS] = { 1, 0.40f, 0.25f, 1, 1, 1, 1, 1,  1, 1, 1.6f, 1.9f, 0.35f, 1, 1, 1,  1, 0.20f, 0.80f, 1.8f, 1, 1, 1, 1,
                         1, 1, 1, 1.2f, 2.0f, 0.3f, 1.2f, 0,  2.0f, 0.75f, 1, 1, 0.26f, 1, 1.2f, 0.51f,  1, 1, 1, 1, 1, 0, 1.2f, 0,
                         2.25f, 2.6f, 2.35f, 2.5f, 1, 1, 3.0f, 2.2f,  1, 2.5f, 2.7f, 1, 3.0f, 3.0f, 2.1f, 3.0f,  1, 1, 1, 1 };
const int WATER_DIAL = 3;

LPDIRECT3DDEVICE9 g_device = nullptr;
UINT g_width = 0, g_height = 0;
IDirect3DSurface9* g_autoDepth = nullptr;            // the device's own depth buffer, put back before a reset
IDirect3DTexture9* g_depthTexture = nullptr;         // the INTZ picture that is the depth buffer
IDirect3DSurface9* g_depthSurface = nullptr;
IDirect3DTexture9* g_sceneTexture = nullptr;         // the frame as drawn before the water
IDirect3DTexture9* g_depthCopy = nullptr;            // its depth, as numbers
IDirect3DPixelShader9* g_copyShader = nullptr;
IDirect3DStateBlock9* g_saved = nullptr;
IDirect3DTexture9* g_waves = nullptr;                // managed: it lives through resets
IDirect3DTexture9* g_solid = nullptr;                // where the world is solid, from above (OursFoam.cpp); managed too
int32_t g_solidSide = 0;
float g_solidNumbers[4] = {};                        // where it begins (x, y), one over how far it reaches, its own height
bool g_wavesTried = false;
bool g_sceneThere = false, g_depthThere = false;
LARGE_INTEGER g_started = {}, g_frequency = {};
double g_lastFrame = 0;
uint32_t g_frames = 0;

// ---- The log.
void say(const char* format, ...) {
    static FILE* log = nullptr;
    static bool opened = false;
    if (!opened) {
        opened = true;
        char path[MAX_PATH];
        GetModuleFileNameA(nullptr, path, MAX_PATH);
        char* slash = std::strrchr(path, '\\');
        std::strcpy(slash ? slash + 1 : path, "OursWater.log");
        log = std::fopen(path, "w");
    }
    if (!log) {
        return;
    }
    SYSTEMTIME now;
    GetLocalTime(&now);
    std::fprintf(log, "%02d:%02d:%02d ", now.wHour, now.wMinute, now.wSecond);
    va_list args;
    va_start(args, format);
    std::vfprintf(log, format, args);
    va_end(args);
    std::fputc('\n', log);
    std::fflush(log);
}

// ---- Where its files are: the fork's Ours folder, or one beside the client.
const std::string& oursFolder() {
    static std::string folder;
    static bool looked = false;
    if (looked) {
        return folder;
    }
    looked = true;
    char exe[MAX_PATH];
    GetModuleFileNameA(nullptr, exe, MAX_PATH);
    std::string dir = exe;
    dir = dir.substr(0, dir.find_last_of('\\') + 1);
    for (const std::string& candidate : { dir + "..\\..\\Ours\\", dir + "Ours\\" }) {
        if (GetFileAttributesA((candidate + "Shaders\\water.hlsl").c_str()) != INVALID_FILE_ATTRIBUTES) {
            char full[MAX_PATH];
            GetFullPathNameA(candidate.c_str(), MAX_PATH, full, nullptr);
            folder = full;
            break;
        }
    }
    say(folder.empty() ? "no Ours folder with Shaders\\water.hlsl beside the client or two above it: the game's own water" : "files from %s",
        folder.c_str());
    return folder;
}

bool readFile(const std::string& path, std::string& out) {
    FILE* file = std::fopen(path.c_str(), "rb");
    if (!file) {
        return false;
    }
    std::fseek(file, 0, SEEK_END);
    const long size = std::ftell(file);
    std::fseek(file, 0, SEEK_SET);
    out.resize(size > 0 ? size : 0);
    const size_t got = size > 0 ? std::fread(&out[0], 1, size, file) : 0;
    std::fclose(file);
    return got == out.size();
}

// ---- Windows' own shader compiler, as the DLL used it: d3dcompiler_47.dll, which Windows has.
typedef HRESULT(WINAPI* Compile)(LPCVOID, SIZE_T, LPCSTR, const D3D_SHADER_MACRO*, ID3DInclude*, LPCSTR, LPCSTR, UINT, UINT, ID3DBlob**, ID3DBlob**);

Compile compiler() {
    static Compile compile = nullptr;
    static bool looked = false;
    if (!looked) {
        looked = true;
        HMODULE library = LoadLibraryA("d3dcompiler_47.dll");
        compile = library ? reinterpret_cast<Compile>(GetProcAddress(library, "D3DCompile")) : nullptr;
        if (!compile) {
            say("Windows' shader compiler (d3dcompiler_47.dll) is not to be had: the game's own water");
        }
    }
    return compile;
}

bool compileText(const std::string& text, const char* name, const std::vector<std::pair<std::string, std::string>>& switches, const char* target,
                 std::vector<uint8_t>& code) {
    Compile compile = compiler();
    if (!compile) {
        return false;
    }
    std::vector<D3D_SHADER_MACRO> macros;
    for (const auto& one : switches) {
        macros.push_back({ one.first.c_str(), one.second.c_str() });
    }
    macros.push_back({ nullptr, nullptr });
    ID3DBlob* blob = nullptr;
    ID3DBlob* errors = nullptr;
    const HRESULT result = compile(text.data(), text.size(), name, macros.data(), nullptr, "main", target, D3DCOMPILE_OPTIMIZATION_LEVEL3, 0, &blob, &errors);
    if (errors) {
        if (FAILED(result)) {
            say("%s (%s) does not compile:\n%s", name, target, static_cast<const char*>(errors->GetBufferPointer()));
        }
        errors->Release();
    }
    if (FAILED(result) || !blob) {
        if (blob) {
            blob->Release();
        }
        return false;
    }
    code.assign(static_cast<const uint8_t*>(blob->GetBufferPointer()), static_cast<const uint8_t*>(blob->GetBufferPointer()) + blob->GetBufferSize());
    blob->Release();
    return true;
}

// ---- The water's shaders, ours in their place.
struct Swapped {
    CGxShader* shader;
    bool vertex;
    int lamps;                                   // (the vertex shader: one for each count of lights near, 0 to 3)
    std::vector<uint8_t> games, ours;
    bool showingOurs = false;
};
std::vector<Swapped> g_swapped;
FILETIME g_textWritten = {};
DWORD g_checkedAt = 0;

std::string waterPath() {
    return oursFolder() + "Shaders\\water.hlsl";
}

bool compileWater(const std::string& text, bool vertex, int lamps, std::vector<uint8_t>& code) {
    std::vector<std::pair<std::string, std::string>> switches;
    if (vertex) {
        switches = { { "VERTEX", "1" }, { "LAMPS", std::to_string(lamps) } };
    } else {
        switches = { { "VERTEX", "0" }, { "SCENE", "1" } };
    }
    return compileText(text, "water.hlsl", switches, vertex ? "vs_3_0" : "ps_3_0", code);
}

void putCode(Swapped& one, bool ours) {
    const std::vector<uint8_t>& code = ours ? one.ours : one.games;
    one.shader->m_code.SetCount(static_cast<uint32_t>(code.size()));
    if (!code.empty()) {
        std::memcpy(one.shader->m_code.m_data, code.data(), code.size());
    }
    // (Made anew from the new code the next time the game sets it: every frame, since other shaders are set between.)
    if (one.shader->m_apiSpecific) {
        static_cast<IUnknown*>(one.shader->m_apiSpecific)->Release();
        one.shader->m_apiSpecific = nullptr;
    }
    one.shader->m_loaded = 0;
    one.shader->m_valid = 0;
    one.showingOurs = ours;
}

FILETIME writtenAt(const std::string& path) {
    WIN32_FILE_ATTRIBUTE_DATA data = {};
    if (!GetFileAttributesExA(path.c_str(), GetFileExInfoStandard, &data)) {
        return FILETIME {};
    }
    return data.ftLastWriteTime;
}

// Twice a second: the text changed (compiled anew, and put in where it all compiles), or the water's dial.
void poll() {
    if (g_swapped.empty()) {
        return;
    }
    const DWORD now = GetTickCount();
    if (now - g_checkedAt < 500) {
        return;
    }
    g_checkedAt = now;
    const FILETIME written = writtenAt(waterPath());
    if (CompareFileTime(&written, &g_textWritten) != 0) {
        g_textWritten = written;
        std::string text;
        if (readFile(waterPath(), text)) {
            std::vector<std::vector<uint8_t>> made(g_swapped.size());
            bool all = true;
            for (size_t i = 0; i < g_swapped.size() && all; ++i) {
                all = compileWater(text, g_swapped[i].vertex, g_swapped[i].lamps, made[i]);
            }
            if (all) {
                for (size_t i = 0; i < g_swapped.size(); ++i) {
                    g_swapped[i].ours = made[i];
                    if (g_swapped[i].showingOurs) {
                        putCode(g_swapped[i], true);
                    }
                }
                say("water.hlsl changed: compiled anew and in place (%u shaders)", static_cast<unsigned>(g_swapped.size()));
            } else {
                say("water.hlsl changed but does not compile: the water stays as it was");
            }
        }
    }
    const bool wanted = g_dials[WATER_DIAL] >= 0.5f;
    for (Swapped& one : g_swapped) {
        if (one.showingOurs != wanted && !one.ours.empty()) {
            putCode(one, wanted);
        }
    }
}

// ---- The picture of waves: a .bmp of 32 bits whose sides are powers of two, with smaller versions made from it.
void loadWaves() {
    if (g_wavesTried || !g_device || oursFolder().empty()) {
        return;
    }
    g_wavesTried = true;
    const std::string path = oursFolder() + "Textures\\waves.bmp";
    std::string file;
    if (!readFile(path, file) || file.size() < 54 || file[0] != 'B' || file[1] != 'M') {
        say("no picture of waves at %s: the water's waves are flat", path.c_str());
        return;
    }
    const uint32_t start = *reinterpret_cast<const uint32_t*>(&file[10]);
    const int32_t width = *reinterpret_cast<const int32_t*>(&file[18]);
    const int32_t height = *reinterpret_cast<const int32_t*>(&file[22]);
    const uint16_t bits = *reinterpret_cast<const uint16_t*>(&file[28]);
    const int32_t rows = std::abs(height);
    if (bits != 32 || width <= 0 || rows <= 0 || (width & (width - 1)) || (rows & (rows - 1)) || file.size() < start + size_t(width) * rows * 4) {
        say("the picture of waves is no .bmp of 32 bits with sides that are powers of two: the water's waves are flat");
        return;
    }
    // (Top row first; a .bmp of a height above nothing has its bottom row first.)
    std::vector<uint32_t> pixels(size_t(width) * rows);
    for (int32_t y = 0; y < rows; ++y) {
        const int32_t from = height > 0 ? rows - 1 - y : y;
        std::memcpy(&pixels[size_t(y) * width], &file[start + size_t(from) * width * 4], size_t(width) * 4);
    }
    if (FAILED(g_device->CreateTexture(width, rows, 0, 0, D3DFMT_A8R8G8B8, D3DPOOL_MANAGED, &g_waves, nullptr))) {
        say("the picture of waves could not be made");
        g_waves = nullptr;
        return;
    }
    int32_t w = width, h = rows;
    for (DWORD level = 0; level < g_waves->GetLevelCount(); ++level) {
        D3DLOCKED_RECT locked;
        if (SUCCEEDED(g_waves->LockRect(level, &locked, nullptr, 0))) {
            for (int32_t y = 0; y < h; ++y) {
                std::memcpy(static_cast<uint8_t*>(locked.pBits) + size_t(y) * locked.Pitch, &pixels[size_t(y) * w], size_t(w) * 4);
            }
            g_waves->UnlockRect(level);
        }
        if (w == 1 && h == 1) {
            break;
        }
        // The next level: each pixel the middle of four (the picture repeats, so the edges wrap).
        const int32_t nw = std::max(1, w / 2), nh = std::max(1, h / 2);
        std::vector<uint32_t> next(size_t(nw) * nh);
        for (int32_t y = 0; y < nh; ++y) {
            for (int32_t x = 0; x < nw; ++x) {
                uint32_t sum[4] = {};
                for (int32_t dy = 0; dy < 2; ++dy) {
                    for (int32_t dx = 0; dx < 2; ++dx) {
                        const uint32_t p = pixels[size_t((2 * y + dy) % h) * w + (2 * x + dx) % w];
                        for (int k = 0; k < 4; ++k) {
                            sum[k] += (p >> (8 * k)) & 0xFF;
                        }
                    }
                }
                uint32_t q = 0;
                for (int k = 0; k < 4; ++k) {
                    q |= ((sum[k] + 2) / 4) << (8 * k);
                }
                next[size_t(y) * nw + x] = q;
            }
        }
        pixels.swap(next);
        w = nw;
        h = nh;
    }
    say("the picture of waves: %d x %d, %u levels", width, rows, static_cast<unsigned>(g_waves->GetLevelCount()));
}

void releaseOne(IUnknown*& thing) {
    if (thing) {
        thing->Release();
        thing = nullptr;
    }
}

template <class T>
void release(T*& thing) {
    IUnknown* as = thing;
    releaseOne(as);
    thing = nullptr;
}

double seconds() {
    if (!g_frequency.QuadPart) {
        QueryPerformanceFrequency(&g_frequency);
        QueryPerformanceCounter(&g_started);
    }
    LARGE_INTEGER now;
    QueryPerformanceCounter(&now);
    return double(now.QuadPart - g_started.QuadPart) / double(g_frequency.QuadPart);
}

}  // namespace

void AfterShaderLoad(CGxShader** shaders, int32_t target, const char* name, uint32_t permutations) {
    const bool vertex = target == GxSh_Vertex;
    const bool ours = vertex ? (!_stricmp(name, "vsLiquidWater") || !_stricmp(name, "vsLiquidWaterNoSpec"))
                             : (target == GxSh_Pixel && (!_stricmp(name, "psLiquidWater") || !_stricmp(name, "psLiquidWaterNoSpec")));
    if (!ours || !g_theGxDevicePtr || (g_theGxDevicePtr->DeviceApi() != GxApi_D3d9 && g_theGxDevicePtr->DeviceApi() != GxApi_D3d9Ex)) {
        return;
    }
    // (Only where the game draws with the 3_0 set, which is what water.hlsl is.)
    const int32_t profile = g_theGxDevicePtr->Caps().m_shaderTargets[target];
    if (profile != (vertex ? 3 : 4)) {
        say("%s: the game draws with %s, not the 3_0 set: its own water", name, vertex ? CGxDevice::s_vertexShaderTargetNames[profile] : CGxDevice::s_pixelShaderTargetNames[profile]);
        return;
    }
    if (oursFolder().empty()) {
        return;
    }
    std::string text;
    if (!readFile(waterPath(), text)) {
        say("water.hlsl could not be read: the game's own water");
        return;
    }
    g_textWritten = writtenAt(waterPath());
    for (uint32_t i = 0; i < permutations; ++i) {
        CGxShader* shader = shaders[i];
        if (!shader || std::any_of(g_swapped.begin(), g_swapped.end(), [&](const Swapped& s) { return s.shader == shader; })) {
            continue;
        }
        Swapped one;
        one.shader = shader;
        one.vertex = vertex;
        one.lamps = static_cast<int>(i);
        one.games.assign(shader->m_code.m_data, shader->m_code.m_data + shader->m_code.Count());
        if (!compileWater(text, vertex, one.lamps, one.ours)) {
            say("%s:%u: the game's own", name, i);
            continue;
        }
        shader->m_refCount++;                    // (kept: the list holds it, and it is swapped again when the text changes)
        g_swapped.push_back(one);
        putCode(g_swapped.back(), g_dials[WATER_DIAL] >= 0.5f);
        say("%s:%u: ours (%u bytes, the game's had %u)", name, i, static_cast<unsigned>(one.ours.size()), static_cast<unsigned>(one.games.size()));
    }
}

void DeviceReady(LPDIRECT3DDEVICE9 device) {
    DeviceLost();
    // (A device made anew, not reset: the pictures that live through resets are the old device's.)
    if (device != g_device) {
        release(g_waves);
        release(g_solid);
        g_solidSide = 0;
        g_wavesTried = false;
    }
    g_device = device;
    if (!device) {
        return;
    }
    OursSky::DeviceReady(device);
    IDirect3DSurface9* back = nullptr;
    if (FAILED(device->GetBackBuffer(0, 0, D3DBACKBUFFER_TYPE_MONO, &back)) || !back) {
        say("no back buffer: no frame kept for the water");
        return;
    }
    D3DSURFACE_DESC desc;
    back->GetDesc(&desc);
    back->Release();
    g_width = desc.Width;
    g_height = desc.Height;
    // The frame as drawn before the water.
    if (FAILED(device->CreateTexture(g_width, g_height, 1, D3DUSAGE_RENDERTARGET, desc.Format, D3DPOOL_DEFAULT, &g_sceneTexture, nullptr))) {
        g_sceneTexture = nullptr;
    }
    // The depth buffer as an INTZ picture, which can be read (not where the frame is multisampled: such a depth
    // buffer cannot be a picture).
    bool intz = desc.MultiSampleType == D3DMULTISAMPLE_NONE;
    if (intz) {
        IDirect3D9* d3d = nullptr;
        D3DDEVICE_CREATION_PARAMETERS made = {};
        D3DDISPLAYMODE mode = {};
        device->GetDirect3D(&d3d);
        device->GetCreationParameters(&made);
        device->GetDisplayMode(0, &mode);
        intz = d3d && SUCCEEDED(d3d->CheckDeviceFormat(made.AdapterOrdinal, made.DeviceType, mode.Format, D3DUSAGE_DEPTHSTENCIL, D3DRTYPE_TEXTURE, INTZ));
        if (d3d) {
            d3d->Release();
        }
    }
    if (intz && SUCCEEDED(device->CreateTexture(g_width, g_height, 1, D3DUSAGE_DEPTHSTENCIL, INTZ, D3DPOOL_DEFAULT, &g_depthTexture, nullptr))
        && SUCCEEDED(g_depthTexture->GetSurfaceLevel(0, &g_depthSurface))
        && SUCCEEDED(device->CreateTexture(g_width, g_height, 1, D3DUSAGE_RENDERTARGET, D3DFMT_R32F, D3DPOOL_DEFAULT, &g_depthCopy, nullptr))) {
        device->GetDepthStencilSurface(&g_autoDepth);
        device->SetDepthStencilSurface(g_depthSurface);
        std::vector<uint8_t> code;
        const std::string copy = "sampler2D depth : register(s0);\nfloat4 main(float2 at : TEXCOORD0) : COLOR0 { return tex2D(depth, at).r; }\n";
        if (compileText(copy, "depth copy", {}, "ps_3_0", code)) {
            device->CreatePixelShader(reinterpret_cast<const DWORD*>(code.data()), &g_copyShader);
        }
        device->CreateStateBlock(D3DSBT_ALL, &g_saved);
    } else {
        release(g_depthSurface);
        release(g_depthTexture);
        release(g_depthCopy);
        intz = false;
    }
    loadWaves();
    say("the device is ready: %u x %u, the frame %s, its depth %s", g_width, g_height, g_sceneTexture ? "kept" : "NOT kept",
        g_depthSurface && g_copyShader && g_saved ? "an INTZ picture, read" : desc.MultiSampleType != D3DMULTISAMPLE_NONE ? "not read (the frame is multisampled)" : "NOT read");
}

void DeviceLost() {
    OursSky::DeviceLost();
    if (g_device && g_autoDepth) {
        g_device->SetDepthStencilSurface(g_autoDepth);
    }
    release(g_autoDepth);
    release(g_depthSurface);
    release(g_depthTexture);
    release(g_sceneTexture);
    release(g_depthCopy);
    release(g_copyShader);
    release(g_saved);
    g_sceneThere = g_depthThere = false;
}

void BeforeLiquids() {
    poll();
    g_sceneThere = g_depthThere = false;
    if (!g_device || g_swapped.empty() || g_dials[WATER_DIAL] < 0.5f) {
        return;
    }
    IDirect3DSurface9* target = nullptr;
    if (FAILED(g_device->GetRenderTarget(0, &target)) || !target) {
        return;
    }
    // (Only for the frame itself, of the size the copies are.)
    D3DSURFACE_DESC desc;
    target->GetDesc(&desc);
    if (desc.Width == g_width && desc.Height == g_height) {
        if (g_sceneTexture) {
            IDirect3DSurface9* kept = nullptr;
            if (SUCCEEDED(g_sceneTexture->GetSurfaceLevel(0, &kept))) {
                g_sceneThere = SUCCEEDED(g_device->StretchRect(target, nullptr, kept, nullptr, D3DTEXF_NONE));
                kept->Release();
            }
        }
        IDirect3DSurface9* depthNow = nullptr;
        g_device->GetDepthStencilSurface(&depthNow);
        IDirect3DSurface9* copy = nullptr;
        if (depthNow && depthNow == g_depthSurface && g_copyShader && g_saved && SUCCEEDED(g_depthCopy->GetSurfaceLevel(0, &copy))) {
            // The depth's numbers drawn into a picture of plain numbers, with everything that is set on the device
            // kept before and put back after, so that the game's own idea of what is set stays true.
            g_saved->Capture();
            g_device->SetRenderTarget(0, copy);
            g_device->SetDepthStencilSurface(nullptr);
            const D3DVIEWPORT9 whole = { 0, 0, g_width, g_height, 0.0f, 1.0f };
            g_device->SetViewport(&whole);
            g_device->SetVertexShader(nullptr);
            g_device->SetPixelShader(g_copyShader);
            g_device->SetTexture(0, g_depthTexture);
            g_device->SetSamplerState(0, D3DSAMP_MINFILTER, D3DTEXF_POINT);
            g_device->SetSamplerState(0, D3DSAMP_MAGFILTER, D3DTEXF_POINT);
            g_device->SetSamplerState(0, D3DSAMP_MIPFILTER, D3DTEXF_NONE);
            g_device->SetSamplerState(0, D3DSAMP_ADDRESSU, D3DTADDRESS_CLAMP);
            g_device->SetSamplerState(0, D3DSAMP_ADDRESSV, D3DTADDRESS_CLAMP);
            g_device->SetSamplerState(0, D3DSAMP_SRGBTEXTURE, FALSE);
            g_device->SetRenderState(D3DRS_ZENABLE, FALSE);
            g_device->SetRenderState(D3DRS_ZWRITEENABLE, FALSE);
            g_device->SetRenderState(D3DRS_ALPHABLENDENABLE, FALSE);
            g_device->SetRenderState(D3DRS_ALPHATESTENABLE, FALSE);
            g_device->SetRenderState(D3DRS_STENCILENABLE, FALSE);
            g_device->SetRenderState(D3DRS_CULLMODE, D3DCULL_NONE);
            g_device->SetRenderState(D3DRS_FOGENABLE, FALSE);
            g_device->SetRenderState(D3DRS_SCISSORTESTENABLE, FALSE);
            g_device->SetRenderState(D3DRS_COLORWRITEENABLE, 0xF);
            g_device->SetRenderState(D3DRS_SRGBWRITEENABLE, FALSE);
            g_device->SetRenderState(D3DRS_CLIPPLANEENABLE, 0);
            g_device->SetFVF(D3DFVF_XYZRHW | D3DFVF_TEX1);
            const float w = float(g_width) - 0.5f, h = float(g_height) - 0.5f;
            const float corners[4][6] = { { -0.5f, -0.5f, 0, 1, 0, 0 }, { w, -0.5f, 0, 1, 1, 0 }, { -0.5f, h, 0, 1, 0, 1 }, { w, h, 0, 1, 1, 1 } };
            g_depthThere = SUCCEEDED(g_device->DrawPrimitiveUP(D3DPT_TRIANGLESTRIP, 2, corners, sizeof corners[0]));
            // The targets back BEFORE the kept settings: setting a render target sets the viewport to all of it, with
            // depths 0 to 1, and the game draws its world into 0 to 0.94 and does not set its viewport again. Put
            // back the other way round, the water lay behind everything and was not seen at all.
            g_device->SetRenderTarget(0, target);
            g_device->SetDepthStencilSurface(depthNow);
            g_saved->Apply();
            copy->Release();
        }
        if (depthNow) {
            depthNow->Release();
        }
    }
    target->Release();
    const double now = seconds();
    g_lastFrame = g_lastFrame > 0 ? g_lastFrame : now;
    ++g_frames;
}

void BindForWater(const float* toWorld) {
    if (!g_device || g_swapped.empty() || !g_swapped.front().showingOurs) {
        return;
    }
    const double now = seconds();
    float numbers[3 + DIALS / 4 + 5][4] = {};
    numbers[0][0] = float(std::fmod(now, 3600.0));
    numbers[0][1] = float(std::min(now - g_lastFrame, 0.5));
    numbers[0][2] = float(g_frames % 65536);
    numbers[0][3] = 1;
    g_lastFrame = now;
    numbers[1][0] = g_width ? 1.0f / g_width : 0;
    numbers[1][1] = g_height ? 1.0f / g_height : 0;
    numbers[1][2] = g_sceneThere ? 1.0f : 0.0f;
    numbers[1][3] = g_depthThere ? 1.0f : 0.0f;
    const float nearest = g_theGxDevicePtr->m_viewport.m_z.m_l, farthest = g_theGxDevicePtr->m_viewport.m_z.m_h;
    numbers[2][0] = nearest;
    numbers[2][1] = farthest > nearest ? 1.0f / (farthest - nearest) : 1.0f;
    std::memcpy(numbers[3], g_dials, sizeof(float) * 64);
    // c219: the solid map's place; c220 to c222: from the water's own space into the world's, a row for each of the
    // world's x, y and z (the matrix's rows are the model's axes); c223.x: 1 if the map is there.
    std::memcpy(numbers[19], g_solidNumbers, sizeof g_solidNumbers);
    for (int r = 0; r < 3; ++r) {
        for (int k = 0; k < 4; ++k) {
            numbers[20 + r][k] = toWorld ? toWorld[k * 4 + r] : (k == r ? 1.0f : 0.0f);
        }
    }
    numbers[23][0] = g_solid && g_solidSide ? 1.0f : 0.0f;
    GxShaderConstantsSet(GxSh_Pixel, PIXEL_CLOCK, &numbers[0][0], 3 + 16 + 5);
    g_device->SetTexture(12, g_solid);
    g_device->SetSamplerState(12, D3DSAMP_ADDRESSU, D3DTADDRESS_CLAMP);
    g_device->SetSamplerState(12, D3DSAMP_ADDRESSV, D3DTADDRESS_CLAMP);
    g_device->SetSamplerState(12, D3DSAMP_MINFILTER, D3DTEXF_POINT);
    g_device->SetSamplerState(12, D3DSAMP_MAGFILTER, D3DTEXF_POINT);
    g_device->SetSamplerState(12, D3DSAMP_MIPFILTER, D3DTEXF_NONE);
    // The three pictures, at stages the game never uses (it uses 0 to 8).
    g_device->SetTexture(13, g_waves);
    g_device->SetSamplerState(13, D3DSAMP_ADDRESSU, D3DTADDRESS_WRAP);
    g_device->SetSamplerState(13, D3DSAMP_ADDRESSV, D3DTADDRESS_WRAP);
    g_device->SetSamplerState(13, D3DSAMP_MINFILTER, D3DTEXF_LINEAR);
    g_device->SetSamplerState(13, D3DSAMP_MAGFILTER, D3DTEXF_LINEAR);
    g_device->SetSamplerState(13, D3DSAMP_MIPFILTER, D3DTEXF_LINEAR);
    g_device->SetTexture(14, g_sceneThere ? g_sceneTexture : nullptr);
    g_device->SetTexture(15, g_depthThere ? g_depthCopy : nullptr);
    for (DWORD stage : { 14u, 15u }) {
        g_device->SetSamplerState(stage, D3DSAMP_ADDRESSU, D3DTADDRESS_CLAMP);
        g_device->SetSamplerState(stage, D3DSAMP_ADDRESSV, D3DTADDRESS_CLAMP);
        g_device->SetSamplerState(stage, D3DSAMP_MINFILTER, stage == 15 ? D3DTEXF_POINT : D3DTEXF_LINEAR);
        g_device->SetSamplerState(stage, D3DSAMP_MAGFILTER, stage == 15 ? D3DTEXF_POINT : D3DTEXF_LINEAR);
        g_device->SetSamplerState(stage, D3DSAMP_MIPFILTER, D3DTEXF_NONE);
    }
}

void SetDial(int32_t index, float value) {
    if (index >= 0 && index < DIALS) {
        g_dials[index] = value;
    }
}

bool WantsSolidMap() {
    return g_device && !g_swapped.empty() && g_dials[WATER_DIAL] >= 0.5f;
}

void SetSolidMap(const float* squares, int32_t side, float originX, float originY, float cell, float ownZ) {
    if (!g_device || side <= 0) {
        return;
    }
    if (g_solid && g_solidSide != side) {
        release(g_solid);
    }
    if (!g_solid) {
        if (FAILED(g_device->CreateTexture(side, side, 1, 0, D3DFMT_A32B32G32R32F, D3DPOOL_MANAGED, &g_solid, nullptr))) {
            g_solid = nullptr;
            say("no picture of 32-bit numbers for the solid world could be made: the foam goes by the screen");
            g_solidSide = 0;
            return;
        }
        g_solidSide = side;
    }
    D3DLOCKED_RECT locked;
    if (FAILED(g_solid->LockRect(0, &locked, nullptr, 0))) {
        return;
    }
    // (A32B32G32R32F keeps red first: the four numbers as they are.)
    for (int32_t row = 0; row < side; ++row) {
        std::memcpy(static_cast<uint8_t*>(locked.pBits) + size_t(row) * locked.Pitch, squares + size_t(row) * side * 4, size_t(side) * 16);
    }
    g_solid->UnlockRect(0);
    g_solidNumbers[0] = originX;
    g_solidNumbers[1] = originY;
    g_solidNumbers[2] = 1.0f / (side * cell);
    g_solidNumbers[3] = ownZ;
}

void Log(const char* line) {
    say("%s", line);
}

// ---- Shared with the sky (OursSky.cpp).

std::string Folder() {
    return oursFolder();
}

bool CompileFile(const std::string& path, const std::vector<std::pair<std::string, std::string>>& switches, const char* target,
                 std::vector<uint8_t>& code) {
    std::string text;
    if (!readFile(path, text)) {
        say("%s could not be read", path.c_str());
        return false;
    }
    const size_t slash = path.find_last_of('\\');
    return compileText(text, slash == std::string::npos ? path.c_str() : path.c_str() + slash + 1, switches, target, code);
}

uint64_t WrittenAt(const std::string& path) {
    const FILETIME written = writtenAt(path);
    return (uint64_t(written.dwHighDateTime) << 32) | written.dwLowDateTime;
}

}  // namespace OursWater
