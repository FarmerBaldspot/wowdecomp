// Ours, not the game's (the World of Warcraft editor project): the names characters of the Spellforge realm gave
// their classes when they were made. The class the game knows them by (the stat distribution they chose) is only
// underneath: wherever the game names a character's class (its tooltip, frames, the character screen, /who, the
// guild, friends and raid lists), it names this instead, if the character has one.
//
// The server (mod-spellforge) sends them in the message the crafted spells come in (OursSpellDB), under the mark
// "SFN1": a count, then each character's guid, name and class name.
#pragma once

#include <cstdint>

class CDataStore;

namespace OursClassNames {
    constexpr uint32_t MARK = 0x314E4653;   // "SFN1"

    // The message's body after the mark
    void Take(CDataStore* msg);

    // The class name a character gave its class: by its guid, or by its name (the who list knows names only).
    // nullptr if it has none.
    const char* Of(uint64_t guid);
    const char* OfName(const char* name);

    // The creation screen's choice (OursCreate.lua through SpellforgeSetCreateChoice): the resource (0 mana, 1 rage,
    // 2 energy) and the class's name, written after the game's own fields of the create packet ("SFC1", the
    // resource, the name), which the server reads before the game's handler does
    void SetCreateChoice(uint8_t power, const char* className);
    void AppendCreateChoice(CDataStore* msg);
}
