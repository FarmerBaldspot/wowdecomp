// Ours, not the game's (the World of Warcraft editor project). See OursSpellDB.h. No function here has an
// OFFSET: none of them is in the game.

#include "WoW/Source/DB/OursSpellDB.h"
#include "Engine/Source/Base/CDataStore.h"
#include "Engine/Source/Storm/H/storm.h"
#include "WoW/Source/DB/DBClient/DBClient.h"
#include "WoW/Source/DB/Rec/SkillLineAbilityRec.h"
#include "WoW/Source/DB/Rec/SpellRec.h"
#include "WoW/Source/Magic/MagicClient/SpellTable.h"
#include <cstddef>
#include <cstdio>
#include <cstring>
#include <unordered_map>
#include <vector>

// SMSG_INIT_EXTRA_AURA_INFO_OBSOLETE (0x3A3): obsolete before 3.3.5; the server (AzerothCore) never sends it and
// the game has no handler for it. A server that is not the Spellforge realm's never sends it either.

namespace OursSpellDB {
namespace {
    // Records the index has room for beyond the game's (a crafted spell has up to 16)
    constexpr int32_t ROOM = 65536;

    bool s_reserved = false;
    int32_t s_room = 0;
    std::unordered_map<int32_t, int32_t> s_indexOf;   // a crafted record's place in the index by its number

    // Fields 0 to 135 of the table are the record's first 136 members, 204 to 233 its last 30: in between are the
    // texts (sixteen languages and a mark each in the table, one pointer each in the record)
    static_assert(offsetof(SpellRec, m_spellPriority) - offsetof(SpellRec, m_id) == 135 * sizeof(int32_t), "SpellRec's first fields");
    static_assert(offsetof(SpellRec, m_difficulty) - offsetof(SpellRec, m_manaCostPct) == 29 * sizeof(int32_t), "SpellRec's last fields");

    void Log(const char* format, uint32_t a = 0, uint32_t b = 0, uint32_t c = 0) {
        static FILE* file = nullptr;
        if (!file) {
            file = fopen("OursSpellforge.log", "a");
        }
        if (file) {
            fprintf(file, format, a, b, c);
            fputc('\n', file);
            fflush(file);
        }
    }

    const char* Keep(const char* text) {
        return SStrDupA(text ? text : "", __FILE__, __LINE__);
    }
}

void Reserve() {
    WowClientDB_RLE<SpellRec>& db = g_spellDB;
    if (s_reserved || !db.m_loaded || db.m_numRecords <= 0 || db.m_maxID >= LAST_ID) {
        return;
    }

    // One block as the game's: the records by their place, room for more, then the records by their number
    int32_t const oldSpan = db.m_maxID - db.m_minID + 1;
    int32_t const newSpan = LAST_ID - db.m_minID + 1;
    size_t const count = static_cast<size_t>(db.m_numRecords) + ROOM + newSpan;
    SpellRec** index = static_cast<SpellRec**>(SMemAlloc(sizeof(SpellRec*) * count, __FILE__, __LINE__, 0));
    if (!index) {
        Log("Spellforge: no memory for the spell table's index; crafted spells stay unknown");
        return;
    }
    memset(index, 0, sizeof(SpellRec*) * count);
    memcpy(index, db.m_records, sizeof(SpellRec*) * db.m_numRecords);
    SpellRec** byId = index + db.m_numRecords + ROOM;
    memcpy(byId, db.m_recordsById, sizeof(SpellRec*) * oldSpan);

    SMemFree(db.m_records, __FILE__, __LINE__, 0);
    db.m_records = index;
    db.m_recordsById = byId;
    db.m_maxID = LAST_ID;
    s_room = ROOM;
    s_reserved = true;
    Log("Spellforge: the spell table reaches %u (it had %u records)", LAST_ID, db.m_numRecords);
}

bool Add(const uint32_t* fields, const char* name, const char* rank, const char* description, const char* auraDescription) {
    WowClientDB_RLE<SpellRec>& db = g_spellDB;
    int32_t const id = static_cast<int32_t>(fields[0]);
    if (!s_reserved || id < FIRST_ID || id > LAST_ID) {
        return false;
    }

    SpellRec rec;
    memset(&rec, 0, sizeof(rec));
    memcpy(&rec.m_id, fields, 136 * sizeof(int32_t));
    rec.m_name = Keep(name);
    rec.m_nameSubtext = Keep(rank);
    rec.m_description = Keep(description);
    rec.m_auraDescription = Keep(auraDescription);
    memcpy(&rec.m_manaCostPct, fields + 204, 30 * sizeof(int32_t));

    // Kept as the game keeps its own: packed if the table is packed (dbCompress), so that GetRecord unpacks it
    SpellRec* kept;
    if (g_clientDbPerformCompress) {
        uint32_t const size = CompressRow(reinterpret_cast<const uint8_t*>(&rec), sizeof(SpellRec), nullptr);
        kept = static_cast<SpellRec*>(SMemAlloc(size, __FILE__, __LINE__, 0));
        CompressRow(reinterpret_cast<const uint8_t*>(&rec), sizeof(SpellRec), reinterpret_cast<uint8_t*>(kept));
    } else {
        kept = static_cast<SpellRec*>(SMemAlloc(sizeof(SpellRec), __FILE__, __LINE__, 0));
        memcpy(kept, &rec, sizeof(SpellRec));
    }

    SpellRec*& slot = db.m_recordsById[id - db.m_minID];
    auto const found = s_indexOf.find(id);
    if (found != s_indexOf.end()) {
        // A record sent again (a login after another): the new one takes its place (the old one is kept, in case
        // something still holds it)
        db.m_records[found->second] = kept;
    } else {
        if (s_room <= 0) {
            Log("Spellforge: no room for crafted spell %u", static_cast<uint32_t>(id));
            return false;
        }
        db.m_records[db.m_numRecords] = kept;
        s_indexOf[id] = db.m_numRecords;
        db.m_numRecords++;
        s_room--;
    }
    slot = kept;
    return true;
}

void AddAbilities(const uint32_t* rows, uint32_t count) {
    static_assert(sizeof(SkillLineAbilityRec) == 14 * sizeof(int32_t), "SkillLineAbilityRec is its 14 fields");
    WowClientDB<SkillLineAbilityRec>& db = g_skillLineAbilityDB;
    if (!db.m_loaded || !count) {
        return;
    }

    // Those there already are written over where they are; the others are put in below
    std::vector<SkillLineAbilityRec> fresh;
    for (uint32_t i = 0; i < count; i++) {
        SkillLineAbilityRec rec;
        memcpy(&rec, rows + 14 * i, sizeof(rec));
        SkillLineAbilityRec* there = rec.m_id >= db.m_minID && rec.m_id <= db.m_maxID ? db.m_recordsById[rec.m_id - db.m_minID] : nullptr;
        if (there) {
            *there = rec;
        } else {
            fresh.push_back(rec);
        }
    }

    if (!fresh.empty()) {
        // Each new row right after the last row of its skill line (or at the end if its skill line has none)
        std::unordered_map<int32_t, int32_t> lastOf;
        for (int32_t i = 0; i < db.m_numRecords; i++) {
            lastOf[db.m_records[i].m_skillLine] = i;
        }
        int32_t const total = db.m_numRecords + static_cast<int32_t>(fresh.size());
        SkillLineAbilityRec* records = static_cast<SkillLineAbilityRec*>(SMemAlloc(sizeof(SkillLineAbilityRec) * total, __FILE__, __LINE__, 0));
        int32_t at = 0;
        std::vector<bool> placed(fresh.size(), false);
        for (int32_t i = 0; i < db.m_numRecords; i++) {
            records[at++] = db.m_records[i];
            if (lastOf[db.m_records[i].m_skillLine] != i) {
                continue;
            }
            for (size_t f = 0; f < fresh.size(); f++) {
                if (!placed[f] && fresh[f].m_skillLine == db.m_records[i].m_skillLine) {
                    records[at++] = fresh[f];
                    placed[f] = true;
                }
            }
        }
        for (size_t f = 0; f < fresh.size(); f++) {
            if (!placed[f]) {
                records[at++] = fresh[f];
            }
        }

        int32_t minID = db.m_minID;
        int32_t maxID = db.m_maxID;
        for (const SkillLineAbilityRec& rec : fresh) {
            minID = rec.m_id < minID ? rec.m_id : minID;
            maxID = rec.m_id > maxID ? rec.m_id : maxID;
        }
        SkillLineAbilityRec** byId = new (__FILE__, __LINE__) SkillLineAbilityRec*[maxID - minID + 1];
        memset(byId, 0, sizeof(SkillLineAbilityRec*) * (maxID - minID + 1));
        for (int32_t i = 0; i < total; i++) {
            byId[records[i].m_id - minID] = &records[i];
        }

        // The old arrays are kept: something may still hold a row of them until it asks again
        db.m_records = records;
        db.m_recordsById = byId;
        db.m_numRecords = total;
        db.m_minID = minID;
        db.m_maxID = maxID;
    }

    SpellTableAbilitiesChanged();
    Log("Spellforge: %u skill row(s) taken, %u of them new", count, static_cast<uint32_t>(fresh.size()));
}

int32_t OnCraftedSpells(void* param, NETMESSAGE msgId, uint32_t time, CDataStore* msg) {
    uint32_t mark = 0;
    uint32_t count = 0;
    msg->Get(mark);
    if (mark == ABILITIES_MARK) {
        msg->Get(count);
        std::vector<uint32_t> rows(static_cast<size_t>(count) * 14);
        if (count) {
            msg->GetArray(rows.data(), static_cast<uint32_t>(rows.size()));
        }
        if (msg->m_read <= msg->m_size) {
            AddAbilities(rows.data(), count);
        } else {
            Log("Spellforge: a message of skill rows ends early");
        }
        msg->m_read = msg->m_size;
        return 1;
    }
    if (mark != MARK) {
        msg->m_read = msg->m_size;
        return 1;
    }
    msg->Get(count);

    static char texts[4][4096];
    uint32_t added = 0;
    for (uint32_t i = 0; i < count; i++) {
        uint32_t fields[234];
        msg->GetArray(fields, 234);
        for (auto& text : texts) {
            msg->GetString(text, sizeof(text));
            text[sizeof(text) - 1] = '\0';
        }
        if (msg->m_read > msg->m_size) {
            Log("Spellforge: a message of crafted spells ends early (record %u of %u)", i, count);
            break;
        }
        if (Add(fields, texts[0], texts[1], texts[2], texts[3])) {
            added++;
        } else {
            Log("Spellforge: crafted spell %u not taken", fields[0]);
        }
    }
    Log("Spellforge: %u of %u crafted spell record(s) taken", added, count);
    msg->m_read = msg->m_size;
    return 1;
}
}
