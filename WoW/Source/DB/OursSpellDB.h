// Ours, not the game's (the World of Warcraft editor project): the Spellforge realm's crafted spells in the
// client's spell table.
//
// The server makes a crafted spell into records of the game's spell table (Spell.dbc's 234 fields) and sends them
// in a message of their own (SMSG_INIT_EXTRA_AURA_INFO_OBSOLETE, which nothing else sends: see the cpp). Here they
// are put into g_spellDB as if the table had always had them, so that the spell book, the action bar, tooltips,
// cast bars and the combat log know them.
//
// The table is made to reach the forge's last number once, when the client starts (Reserve), and not when a spell
// comes: the spell book sizes its bits of known spells by the table's highest number when the game starts
// (CGSpellBook::InitializeGame), and every lookup holds a number against that highest number first.
#ifndef WOW_SOURCE_DB_OURSSPELLDB_H
#define WOW_SOURCE_DB_OURSSPELLDB_H

#include <cstdint>
#include "WoW/Source/Net/Types.h"

class CDataStore;

namespace OursSpellDB {
    // The numbers the table is made to reach (FIRST_ID to LAST_ID): the forge's crafted spells (to CRAFTED_LAST_ID)
    // and the world editor's own (from 1200000), which the server sends the same way (mod-spellforge)
    constexpr int32_t FIRST_ID = 1000000;
    constexpr int32_t CRAFTED_LAST_ID = 1199999;
    constexpr int32_t LAST_ID = 1999999;

    // After the client's tables are loaded (ClientDBInitialize)
    void Reserve();

    // A record of the server's: the 234 fields as in Spell.dbc (its text fields not used) and its four texts.
    // A record of that number that is there is replaced. False if it is not one of the forge's numbers or there
    // is no room.
    bool Add(const uint32_t* fields, const char* name, const char* rank, const char* description, const char* auraDescription);

    // Rows of SkillLineAbility (14 fields each: a recipe's place in its profession). One whose number is there is
    // written over; a new one goes right after the last row of its skill line, since the game takes a skill line's
    // rows as one run (SpellTable.cpp's link info).
    void AddAbilities(const uint32_t* rows, uint32_t count);

    // The message's handler, registered with every realm connection (from the character screen on)
    int32_t OnCraftedSpells(void* param, NETMESSAGE msgId, uint32_t time, CDataStore* msg);

    inline bool IsCrafted(int32_t spellId) { return spellId >= FIRST_ID && spellId <= CRAFTED_LAST_ID; }

    // The family of the forge's spells (no class has it): the passives' spell modifiers reach them, whatever the
    // player's own class family (Spell_C_GetSpellModifiers)
    constexpr int32_t CRAFTED_FAMILY = 14;

    // The spell book's tab of crafted spells: a skill line no row of SkillLine.dbc has, which the spell book's
    // tab code takes as the Spellforge's (SpellBookFrame.cpp, SpellBookFrame_Scripts.cpp: "Ours")
    constexpr int32_t SPELLBOOK_TAB = 0x5F000001;
    constexpr const char* SPELLBOOK_TAB_NAME = "Spellforge";
    constexpr const char* SPELLBOOK_TAB_ICON = "Interface\\Icons\\INV_Misc_Book_11";

    // The message's number, and the marks its data begins with: "SFG1" spell records, "SFA1" skill rows
    constexpr NETMESSAGE MESSAGE = SMSG_INIT_EXTRA_AURA_INFO_OBSOLETE;
    constexpr uint32_t MARK = 0x31474653;
    constexpr uint32_t ABILITIES_MARK = 0x31414653;
}

#endif
