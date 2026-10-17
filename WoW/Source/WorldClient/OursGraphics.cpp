// Ours, not the game's (the World of Warcraft editor project). See OursGraphics.h. No function here has an OFFSET:
// none of them is in the game.

#include "WoW/Source/WorldClient/OursGraphics.h"
#include "Engine/Source/Base/Status.h"
#include "Engine/Source/ConsoleBase/ConsoleVar.h"
#include "Engine/Source/ConsoleBase/Types.h"
#include "Engine/Source/FrameXML/FrameXML.h"
#include "Engine/Source/Storm/H/storm.h"
#include "Engine/Source/Storm/Source/MD5.h"
#include "WoW/Source/WorldClient/World.h"
#include <algorithm>
#ifdef _WIN32
#include "Engine/Source/Gx/CGxDeviceD3d/OursWater.h"
#endif

namespace OursGraphics {

namespace {

// A setting: its name in the console and in Config.wtf, what it is, what it is at first, the dial of the water's
// shader it sets (the DLL's numbering, OursWater.cpp) and what the setting is divided by for the dial (the sliders
// are in percent).
struct Setting {
    const char* name;
    const char* help;
    const char* first;
    int32_t dial;
    float per;
};

const Setting SETTINGS[] = {
    { "oursWater",            "Ours: the new water (0: the game's own)",                  "1",   3,  1 },
    { "oursWaterWaves",       "Ours: the water's waves, in percent",                      "100", 5,  100 },
    { "oursWaterClarity",     "Ours: how clear the water is, in percent",                 "100", 21, 100 },
    { "oursWaterReflection",  "Ours: how much the water mirrors, in percent",             "100", 22, 100 },
    { "oursWaterGlitter",     "Ours: the sun's glitter on the water, in percent",         "100", 23, 100 },
    { "oursWaterBedLight",    "Ours: the web of light on the bed, in percent",            "100", 7,  100 },
    { "oursWaterFoam",        "Ours: the foam along shores and walls, in percent",        "100", 4,  100 },
    { "oursWaterFoamWidth",   "Ours: how far out the foam reaches, in percent",           "100", 20, 100 },
    // (Not a dial of the water's: SMALL_SEEN below.)
    { "oursSmallObjectDist",  "Ours: how far the map's small models (under a yard) are seen, in yards (the game's: 30)", "100", -1, 1 },
    // (Read by the sky itself every frame, OursSkyColours.cpp: READ_BY_SKY.)
    { "oursSky",              "Ours: the sky drawn anew in the zone's own colours (0: the game's own)", "1",   -2, 1 },
    { "oursSkyClouds",        "Ours: how much cloud the new sky has, in percent of the zone's own",   "100", -2, 1 },
    { "oursSkyCloudSpeed",    "Ours: how fast its clouds drift, in percent",                          "100", -2, 1 },
    { "oursSkySunGlow",       "Ours: how strongly the sun glows in it, in percent",                   "100", -2, 1 },
    { "oursSkyStars",         "Ours: how bright its stars are, in percent (0: the game's own stars)", "100", -2, 1 },
    { "oursSkyMilkyWay",      "Ours: how bright the Milky Way is, in percent",                         "100", -2, 1 },
    { "oursSkyTwinkle",       "Ours: how much the stars twinkle, in percent",                          "100", -2, 1 },
    { "oursSkyShootingStars", "Ours: how often a star shoots, in percent",                             "100", -2, 1 },
};
const int32_t SMALL_SEEN = -1, READ_BY_SKY = -2;

float g_smallSeen = 100.0f;

void give(const Setting* setting, const char* value) {
    const float number = SStrToFloat(value ? value : setting->first);
    if (setting->dial == READ_BY_SKY) {
        return;
    }
    if (setting->dial == SMALL_SEEN) {
        g_smallSeen = std::min(std::max(number, 30.0f), 500.0f);
        // (The table of distances worked out anew, with the scale "environmentDetail" has, as its own setting does.)
        CVar* detail = CVar::Lookup("environmentDetail");
        CWorldScene::ScaleFadeDist(detail ? std::min(std::max(detail->m_floatValue, 0.5f), 1.5f) : 1.0f);
        return;
    }
#ifdef _WIN32
    OursWater::SetDial(setting->dial, number / setting->per);
#endif
}

bool changed(CVar* var, const char* oldValue, const char* value, void* arg) {
    give(static_cast<const Setting*>(arg), value);
    return true;
}

}  // namespace

void RegisterCVars() {
    for (const Setting& setting : SETTINGS) {
        // (Flag 1 and the graphics category, as the game's own graphics settings: kept in Config.wtf.)
        CVar* var = CVar::Register(setting.name, setting.help, 1, setting.first, changed, CATEGORY_GRAPHICS, false,
                                   const_cast<Setting*>(&setting), false);
        if (var) {
            give(&setting, var->m_stringValue.m_str);
        }
    }
}

float SmallObjectsSeenFrom() {
    return g_smallSeen;
}

void LoadOptionsPage(CStatus* status) {
    // (Not counted into the game's own interface's signature: a digest of its own, thrown away.)
    MD5_CTX md5;
    MD5Init(&md5);
    FrameXML_ProcessFile("Ours\\Interface\\OursVideoOptions.lua", nullptr, &md5, status);
}

}  // namespace OursGraphics
