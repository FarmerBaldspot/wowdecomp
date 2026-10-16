#ifndef WOW_SOURCE_WORLDCLIENT_OURSFOAM_H
#define WOW_SOURCE_WORLDCLIENT_OURSFOAM_H

// Ours, not the game's (the World of Warcraft editor project): where the world is solid, seen from above, around the
// camera, for the water's foam (OursWater.cpp, water.hlsl). The water's shader once found what stands out of the water
// by the depth of the pixels around a spot of it, so that whatever stood between the camera and the water (a pillar
// seen from above) made foam far out in the water. This is the world's own collision, the same triangles the jeep
// drives on (ground, buildings, the map's models, objects), laid out in squares of half a yard: for each square the
// heights at which something solid is (two stretches of height at the most). Nothing of the camera's view is in it.

namespace OursFoam {
    // CGWorldFrame, before the pass of liquids: made anew when the camera has gone far enough or a while has passed.
    void Update();
}

#endif
