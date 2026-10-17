// Ours, not the game's (the World of Warcraft editor project): the Spellforge realm's character creation. The game's
// creation screen (GlueXML) with our Lua over it (Ours\Interface\OursCreate.lua): the class buttons are the stat
// distributions (the class underneath), and the class panel is the character's own class: its name and its
// resource. Loaded by CGlueMgr right after the game's GlueXML.
#pragma once

class CStatus;

namespace OursCreate {
    // Registers SpellforgeSetCreateChoice(resource, className) for the glue Lua and runs OursCreate.lua
    void Load(CStatus* status);
}
