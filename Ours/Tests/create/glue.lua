-- Ours: a stand-in for the parts of the game's GlueXML (CharacterCreate.lua / .xml) that OursCreate.lua takes over or
-- reads, run after the forge's frame stand-in (../forge/mock.lua) and before OursCreate.lua.

STUB = { selected = 1, created = 0, dialogs = {}, choices = {} };
MAX_CLASSES_PER_RACE = 10;
strupper = string.upper;
function PlaySound () end

for _, name in ipairs({ "CharacterCreateCharacterClass", "CharacterCreateClassScrollFrame", "CharacterCreateNameEdit" }) do
	Mock.newObject("Frame", name);
end
for _, name in ipairs({ "CharacterCreateClassLabel", "CharacterCreateClassName" }) do
	Mock.newObject("FontString", name);
end
for i = 1, MAX_CLASSES_PER_RACE do
	local b = Mock.newObject("CheckButton", "CharacterCreateClassButton" .. i);
	-- (where a button hangs from: the stand-in keeps the frame it is put by)
	b.SetPoint = function (self, point, relativeTo) self.anchor = relativeTo; end
end

-- the game's classes in the order of ChrClasses.dbc: name, file name, whether it may be had
STUB.CLASSES = { { "Warrior", "WARRIOR" }, { "Paladin", "PALADIN" }, { "Hunter", "HUNTER" }, { "Rogue", "ROGUE" },
	{ "Priest", "PRIEST" }, { "Death Knight", "DEATHKNIGHT" }, { "Shaman", "SHAMAN" }, { "Mage", "MAGE" },
	{ "Warlock", "WARLOCK" }, { "Druid", "DRUID" } };
function GetAvailableClasses ()
	local all = {};
	for _, c in ipairs(STUB.CLASSES) do
		table.insert(all, c[1]); table.insert(all, c[2]); table.insert(all, 1);
	end
	return unpack(all);
end
function GetSelectedClass ()
	local c = STUB.CLASSES[STUB.selected];
	return c[1], c[2], STUB.selected;
end

-- the game's own functions of the screen, which OursCreate.lua wraps
function CharacterCreateEnumerateClasses (...)
	STUB.enumerated = select("#", ...) / 3;
	for i = 1, STUB.enumerated do
		local b = _G["CharacterCreateClassButton" .. i];
		b:Show();
		b.name, b.tooltip = select(i * 3 - 2, ...), select(i * 3 - 2, ...);
	end
end
function SetCharacterClass (id) STUB.selected = id; end
function CharacterCreate_OnShow () STUB.shown = true; end
function CharacterCreate_Okay () STUB.created = STUB.created + 1; end
function CharacterCreate_Back () end
function GlueDialog_Show (which, text) table.insert(STUB.dialogs, { which = which, text = text }); end
function SpellforgeSetCreateChoice (power, name) table.insert(STUB.choices, { power = power, name = name }); end
