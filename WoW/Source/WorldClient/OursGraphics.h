#ifndef WOW_SOURCE_WORLDCLIENT_OURSGRAPHICS_H
#define WOW_SOURCE_WORLDCLIENT_OURSGRAPHICS_H

// Ours, not the game's (the World of Warcraft editor project): the settings of what we draw anew, as console
// variables of the game's own (saved in WTF\Config.wtf with the rest of the graphics), and the page of the game's
// Video options that sets them (Ours\Interface\OursVideoOptions.lua, put beside the client by the build).

class CStatus;

namespace OursGraphics {
    // CWorldParam's registration of the graphics settings: ours registered beside them.
    void RegisterCVars();
    // CGGameUI, right after the game's own interface (FrameXML) is made: our page of Video options.
    void LoadOptionsPage(CStatus* status);
    // CWorldScene::ScaleFadeDist: how far the map's smallest models (under a yard across: barrels, crates, mugs) are
    // seen, in yards, in place of the game's 30, which no setting of the game's changed ("oursSmallObjectDist").
    float SmallObjectsSeenFrom();
}

#endif
