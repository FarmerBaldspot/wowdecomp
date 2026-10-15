#ifndef WOW_SOURCE_OBJECT_OBJECTCLIENT_JEEPDRIVE_C_H
#define WOW_SOURCE_OBJECT_OBJECTCLIENT_JEEPDRIVE_C_H

// Ours, not the game's (the World of Warcraft editor project): the jeep, a vehicle with a body on four springs,
// tyres that grip and let go, and the world it drives on. While the player rides it, the game's own movement does
// nothing to the player's unit; this moves it, tells the server where it is, and has the game draw the jeep tilted
// with its wheels turned, sprung and steered. It was the gfx DLL's `drive.inc` (client\gfx\src in the editor's
// project), which did the same from outside the game; the numbers are the same.

#include <cstdint>

class CGUnit_C;
class CM2Model;

namespace JeepDrive {
    // The look of the jeep's mount (the editor's content\packs\jeep.json): riding a mount of that look is driving.
    constexpr int32_t JEEP_LOOK = 190000;

    // Once a frame, after the game has moved its units (MovementIdleMoveUnits).
    void Update(uint32_t now);
    // Whether this unit is the jeep being driven: the game's own movement leaves it alone then.
    bool Drives(const CGUnit_C* unit);
    // Whether this unit's own model (the rider) is not to be drawn: the player at the wheel.
    bool HidesRider(const CGUnit_C* unit);
    // In CGUnit_C::Animate: puts the jeep's model where the body is, tilted, and its wheels; false where the unit
    // is not the jeep being driven (the game then places the model itself).
    bool Animate(CGUnit_C* unit);
}

#endif
