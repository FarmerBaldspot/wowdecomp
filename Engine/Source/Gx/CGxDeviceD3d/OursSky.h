#ifndef ENGINE_SOURCE_GX_CGXDEVICED3D_OURSSKY_H
#define ENGINE_SOURCE_GX_CGXDEVICED3D_OURSSKY_H

// Ours, not the game's (the World of Warcraft editor project): the sky drawn anew, by a shader of ours over all of it
// (Ours\Shaders\sky.hlsl), in the place of the game's dome of colours and its clouds. The colours stay the zone's own:
// the dome's own colours, which the game works out every frame, drawn smoothly (DayNight's side: WoW\Source\
// WorldClient\OursSkyColours.cpp). The sun and the moons are the game's, drawn before it; the stars are ours too.

#include <cstdint>
#include <d3d9.h>

namespace OursSky {
    // What one frame of the sky needs.
    struct Frame {
        float corners[4][3];          // the way from the eye through each corner of the view (top left, top right,
                                      // bottom left, bottom right), in the world's axes
        const float* colours;         // the sky's colours: rgba, "around" x "up" (see OursSkyColours.cpp)
        int32_t around, up;
        bool coloursChanged;
        float sun[4];                 // the way to the sun (or the moon at night: what lights the clouds), and how much it is up
        float sunColour[4];           // the sun's colour, and how strongly it glows in the sky
        float cloudLit[4];            // the clouds where the light falls on them (the zone's "cloud sun" colour), and how lit
        float cloudBody[4];           // their own colour (the zone's first cloud layer), and how much of the sky they cover
        float cloudShade[4];          // their shade (the zone's "cloud emissive"), and the storm
        float settings[4];            // the clouds' amount, their speed, the sun's glow, 1
        float seconds;
        float night[4];               // how much of the night's stars are out, and the stars' brightness, the Milky
                                      // Way's, how much they twinkle (the settings)
        float nightMore[4];           // how many shooting stars (a setting), 0, 0, 0
        float sphere[3][3];           // the rows that take a way in the world's axes into the turning sky of stars
    };

    // OursWater::DeviceReady / DeviceLost (the device made or reset, and before a reset).
    void DeviceReady(LPDIRECT3DDEVICE9 device);
    void DeviceLost();
    // Whether the sky can be drawn by us now (its shader compiled, the device there).
    bool Ready();
    // DayNight::RenderSky, in place of the dome and the clouds: false if it could not, and the game's are drawn.
    bool Draw(const Frame& frame);
}

#endif
