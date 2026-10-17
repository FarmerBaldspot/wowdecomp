// Ours, not the game's (the World of Warcraft editor project). See OursForge.h. No function here has an OFFSET: none
// of them is in the game.

#include "WoW/Source/Ui/OursForge.h"
#include "Engine/Source/Base/Status.h"
#include "Engine/Source/FrameScript/FrameScript.h"
#include "Engine/Source/FrameXML/FrameXML.h"
#include "Engine/Source/Storm/Source/MD5.h"
#include "Engine/Source/lua-5.1/src/lauxlib.h"
#include "Engine/Source/lua-5.1/src/lua.h"
#include "WoW/Source/DB/DBClient/DBClient.h"
#include "WoW/Source/DB/OursClassNames.h"
#include "WoW/Source/ObjectMgrClient/ObjectMgrClient.h"
#include "WoW/Source/DB/Rec/SpellIconRec.h"
#include "WoW/Source/DB/Rec/SpellRec.h"

#include <cctype>
#include <set>
#include <string>
#include <utility>

namespace OursForge {
namespace {
    // SpellforgeIconCount(): how many rows SpellIcon.dbc has
    int32_t Script_SpellforgeIconCount(lua_State* L) {
        lua_pushnumber(L, g_spellIconDB.m_numRecords);
        return 1;
    }

    // SpellforgeIcon(index): the index-th row's number and texture (as "Interface\Icons\Spell_Fire_FireBolt02"), from 1
    int32_t Script_SpellforgeIcon(lua_State* L) {
        int32_t const index = static_cast<int32_t>(luaL_checknumber(L, 1)) - 1;
        SpellIconRec* rec = g_spellIconDB.GetRecordByIndex(index);
        if (!rec || !rec->m_textureFilename) {
            lua_pushnil(L);
            return 1;
        }
        lua_pushnumber(L, rec->m_id);
        lua_pushstring(L, rec->m_textureFilename);
        return 2;
    }

    std::string Lowered(const char* text) {
        std::string out = text ? text : "";
        for (char& c : out) {
            c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
        }
        return out;
    }

    // SpellforgeFindSpells(words, most): the game's spells whose name has the words, for a crafted spell to take
    // the look of: id, name, rank and icon texture of each, one after the other (at most `most`). Not passives, not
    // what has no look, and each look once (a spell's ranks share theirs).
    int32_t Script_SpellforgeFindSpells(lua_State* L) {
        std::string const words = Lowered(luaL_checkstring(L, 1));
        int32_t const most = lua_isnumber(L, 2) ? static_cast<int32_t>(lua_tonumber(L, 2)) : 40;
        int32_t found = 0;
        if (words.size() < 2) {
            return 0;
        }
        std::set<std::pair<std::string, int32_t>> seen;
        SpellRec rec;
        for (int32_t i = 0; i < g_spellDB.m_numRecords && found < most; ++i) {
            if (!g_spellDB.GetRecordByIndex(i, &rec) || !rec.m_name || !rec.m_spellVisualID[0] || (rec.m_attributes & 0x40)) {
                continue;
            }
            std::string const name = Lowered(rec.m_name);
            if (name.find(words) == std::string::npos || !seen.insert({ name, rec.m_spellVisualID[0] }).second) {
                continue;
            }
            SpellIconRec* icon = g_spellIconDB.GetRecord(rec.m_spellIconID);
            lua_checkstack(L, 4);
            lua_pushnumber(L, rec.m_id);
            lua_pushstring(L, rec.m_name);
            lua_pushstring(L, rec.m_nameSubtext ? rec.m_nameSubtext : "");
            lua_pushstring(L, icon && icon->m_textureFilename ? icon->m_textureFilename : "Interface\\Icons\\INV_Misc_QuestionMark");
            ++found;
        }
        return found * 4;
    }

    // SpellforgeIsForged(): whether the character played is one the realm's creation screen made (it has a class
    // name of its own): the class underneath is then only its stats, and its talents are not shown
    int32_t Script_SpellforgeIsForged(lua_State* L) {
        lua_pushboolean(L, OursClassNames::Of(ClntObjMgrGetActivePlayer().m_guid) != nullptr);
        return 1;
    }

    // SpellforgeIconTexture(id): the texture of the SpellIcon row of that number, nil if there is none
    int32_t Script_SpellforgeIconTexture(lua_State* L) {
        int32_t const id = static_cast<int32_t>(luaL_checknumber(L, 1));
        SpellIconRec* rec = g_spellIconDB.GetRecord(id);
        if (!rec || !rec->m_textureFilename) {
            lua_pushnil(L);
            return 1;
        }
        lua_pushstring(L, rec->m_textureFilename);
        return 1;
    }
}

void LoadWindow(CStatus* status) {
    FrameScript_RegisterFunction("SpellforgeIconCount", Script_SpellforgeIconCount);
    FrameScript_RegisterFunction("SpellforgeIcon", Script_SpellforgeIcon);
    FrameScript_RegisterFunction("SpellforgeIconTexture", Script_SpellforgeIconTexture);
    FrameScript_RegisterFunction("SpellforgeFindSpells", Script_SpellforgeFindSpells);
    FrameScript_RegisterFunction("SpellforgeIsForged", Script_SpellforgeIsForged);

    // (Not counted into the game's own interface's signature: a digest of its own, thrown away.)
    MD5_CTX md5;
    MD5Init(&md5);
    FrameXML_ProcessFile("Ours\\Interface\\OursForge.lua", nullptr, &md5, status);
}
}
