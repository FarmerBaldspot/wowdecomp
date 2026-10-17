// Ours, not the game's (the World of Warcraft editor project). See OursCreate.h. No function here has an OFFSET:
// none of them is in the game.

#include "WoW/Source/Glue/OursCreate.h"
#include "Engine/Source/Base/Status.h"
#include "Engine/Source/FrameScript/FrameScript.h"
#include "Engine/Source/FrameXML/FrameXML.h"
#include "Engine/Source/Storm/Source/MD5.h"
#include "Engine/Source/lua-5.1/src/lauxlib.h"
#include "Engine/Source/lua-5.1/src/lua.h"
#include "WoW/Source/DB/OursClassNames.h"

namespace OursCreate {
namespace {
    // SpellforgeSetCreateChoice(resource, className): resource 0 mana, 1 rage, 2 energy
    int32_t Script_SpellforgeSetCreateChoice(lua_State* L) {
        int32_t const power = lua_isnumber(L, 1) ? static_cast<int32_t>(lua_tonumber(L, 1)) : 0;
        const char* name = lua_isstring(L, 2) ? lua_tolstring(L, 2, nullptr) : "";
        OursClassNames::SetCreateChoice(static_cast<uint8_t>(power < 0 || power > 2 ? 0 : power), name);
        return 0;
    }
}

void Load(CStatus* status) {
    FrameScript_RegisterFunction("SpellforgeSetCreateChoice", Script_SpellforgeSetCreateChoice);

    // (Not counted into the game's own interface's signature: a digest of its own, thrown away.)
    MD5_CTX md5;
    MD5Init(&md5);
    FrameXML_ProcessFile("Ours\\Interface\\OursCreate.lua", nullptr, &md5, status);
}
}
