#ifndef WOW_SOURCE_WORLDCLIENT_OURSSKYCOLOURS_H
#define WOW_SOURCE_WORLDCLIENT_OURSSKYCOLOURS_H

// Ours, not the game's (the World of Warcraft editor project): what the sky of ours (Engine\Source\Gx\CGxDeviceD3d\
// OursSky.cpp) is drawn from. The colours are the zone's own, exactly as the game works them out every frame for its
// dome (DayNight::DNSky::SetColors: six rows from the top to the horizon, 24 columns around, brighter toward the
// sun, the lightning's flashes): taken from there and laid out smoothly, up and down by a curve through the rows that
// never overshoots (Fritsch and Butland's), around by one through the columns, into a picture the shader reads.

namespace OursSkyColours {
    // DayNight::RenderSky, in place of the dome and the clouds: true if ours was drawn ("oursSky" is on and it could).
    bool Render();
}

#endif
