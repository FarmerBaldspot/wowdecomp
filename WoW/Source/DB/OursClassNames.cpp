// Ours, not the game's: see OursClassNames.h.
#include "WoW/Source/DB/OursClassNames.h"
#include "Engine/Source/Base/CDataStore.h"

#include <cctype>
#include <map>
#include <string>

namespace OursClassNames {
namespace {
    uint8_t s_power = 0;
    std::string s_className;
    std::map<uint64_t, std::string> s_byGuid;
    std::map<std::string, std::string> s_byName;    // (by the name in lower case)

    std::string Lowered(const char* name) {
        std::string out = name ? name : "";
        for (char& c : out) {
            c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
        }
        return out;
    }
}

void Take(CDataStore* msg) {
    uint32_t count = 0;
    msg->Get(count);
    char name[64];
    char className[64];
    for (uint32_t i = 0; i < count; i++) {
        uint64_t guid = 0;
        msg->Get(guid);
        msg->GetString(name, sizeof(name));
        msg->GetString(className, sizeof(className));
        name[sizeof(name) - 1] = className[sizeof(className) - 1] = '\0';
        if (msg->m_read > msg->m_size) {
            break;
        }
        s_byGuid[guid] = className;
        s_byName[Lowered(name)] = className;
    }
    msg->m_read = msg->m_size;
}

const char* Of(uint64_t guid) {
    auto const found = s_byGuid.find(guid);
    return found != s_byGuid.end() && !found->second.empty() ? found->second.c_str() : nullptr;
}

const char* OfName(const char* name) {
    if (!name || !*name) {
        return nullptr;
    }
    auto const found = s_byName.find(Lowered(name));
    return found != s_byName.end() && !found->second.empty() ? found->second.c_str() : nullptr;
}

void SetCreateChoice(uint8_t power, const char* className) {
    s_power = power <= 2 ? power : 0;
    s_className = className ? className : "";
    if (s_className.size() > 32) {
        s_className.resize(32);
    }
}

void AppendCreateChoice(CDataStore* msg) {
    if (s_className.empty()) {
        return;     // (no choice made: the character is made as the game makes it)
    }
    msg->Put(static_cast<uint32_t>(0x31434653));   // "SFC1"
    msg->Put(s_power);
    msg->PutString(s_className.c_str());
}
}
