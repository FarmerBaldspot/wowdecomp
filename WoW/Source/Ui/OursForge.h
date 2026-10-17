// Ours, not the game's (the World of Warcraft editor project): the Spellforge realm's forge window.
//
// The window is Lua (Ours\Interface\OursForge.lua, loaded with the game's own interface right after our page of
// Video options); it talks to the server's mod-spellforge by addon messages, and shows the server's preview of a
// recipe through the game's own spell tooltip (OursSpellDB takes the preview's records). What Lua cannot know by
// itself is given here: the game's spell icons, for the window's icon picker.
#ifndef WOW_SOURCE_UI_OURSFORGE_H
#define WOW_SOURCE_UI_OURSFORGE_H

class CStatus;

namespace OursForge {
    // The window's Lua functions registered, and its file read (with each load of the interface)
    void LoadWindow(CStatus* status);
}

#endif
