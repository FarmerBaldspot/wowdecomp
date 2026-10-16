#ifndef ENGINE_SOURCE_GX_CGXDEVICED3D_OURSWATER_H
#define ENGINE_SOURCE_GX_CGXDEVICED3D_OURSWATER_H

// Ours, not the game's (the World of Warcraft editor project): the water made anew. It was the gfx DLL's
// (client\gfx in the editor's project), which got at the game from outside; here the client gives the water's
// shader what it needs by itself:
//   - the shader: the project's water.hlsl, compiled in place of the game's vsLiquidWater / psLiquidWater (and their
//     NoSpec twins) as the game loads those, and again whenever the text changes, while the game runs;
//   - a picture of waves, the clock, the dials (what the Atmosphere addon sets);
//   - the frame as drawn before the water and the depth of everything in it: the device's depth buffer is an INTZ
//     picture, which can be read, and both are copied just before the game draws its water.
// Where something of it cannot be had (no shader compiler, the shader does not compile, a depth buffer that is
// multisampled), the shader goes without it, or the game's own water is drawn: never a broken frame.

#include <cstdint>
#include <d3d9.h>
#include <string>
#include <utility>
#include <vector>

class CGxShader;

namespace OursWater {
    // CGxDevice::ShaderCreate, after the game has loaded a shader file: ours in the place of the water's.
    void AfterShaderLoad(CGxShader** shaders, int32_t target, const char* name, uint32_t permutations);
    // CGxDeviceD3d::IStateSetD3DDefaults, before it takes the device's depth surface (made, or reset): ours there.
    void DeviceReady(LPDIRECT3DDEVICE9 device);
    // CGxDeviceD3d::IReleaseD3dResources: what has to go before a reset.
    void DeviceLost();
    // CGxWorldFrame, just before the game's pass of liquids: the frame and its depth kept.
    void BeforeLiquids();
    // Liquid::CMaterialWater::Render, before it draws: the numbers and the pictures for our shader. "toWorld" is the
    // water's own matrix from its model's space into the world's (the game's C44Matrix: four rows, the last the
    // shift), so that the shader knows where in the world a spot of the water is.
    void BindForWater(const float* toWorld);
    // A dial (the same numbering as the DLL's core, 0 to 67; set by the settings of OursGraphics.cpp).
    void SetDial(int32_t index, float value);
    // Where the world is solid around the camera, seen from above (OursFoam.cpp): "side" x "side" squares of "cell"
    // yards from (originX, originY), four numbers a square (two stretches of height, low and high, less "ownZ").
    void SetSolidMap(const float* squares, int32_t side, float originX, float originY, float cell, float ownZ);
    // Whether that map is wanted (the new water is on and its shaders are in).
    bool WantsSolidMap();
    // A line in OursWater.log.
    void Log(const char* line);

    // Shared with the sky (OursSky.cpp): the folder of our files (Ours\, with its backslash; empty if there is none),
    // a shader file compiled with Windows' own compiler (with switches, for a target such as "ps_3_0"), and when a
    // file was last written (to see that it changed).
    std::string Folder();
    bool CompileFile(const std::string& path, const std::vector<std::pair<std::string, std::string>>& switches, const char* target,
                     std::vector<uint8_t>& code);
    uint64_t WrittenAt(const std::string& path);
}

#endif
