-- Ours: checks of OursCreate.lua (the Spellforge realm's creation screen), run by check.py after the stand-ins.

local C = OursCreate;

-- 1. The class buttons are the distributions; the death knight's is hidden and the row under it moves up
CharacterCreateEnumerateClasses(GetAvailableClasses());
CHECK(STUB.enumerated == 10, "the game's own enumeration still runs");
CHECK(CharacterCreateClassButton1.tooltip == "Strength and Stamina", "Warrior is Strength and Stamina: " .. tostring(CharacterCreateClassButton1.tooltip));
CHECK(CharacterCreateClassButton8.tooltip == "Intellect and Spirit", "Mage is Intellect and Spirit: " .. tostring(CharacterCreateClassButton8.tooltip));
CHECK(not CharacterCreateClassButton6.shown, "the death knight's button is hidden");
CHECK(CharacterCreateClassButton7.anchor == CharacterCreateClassButton1 and CharacterCreateClassButton10.anchor == CharacterCreateClassButton4,
	"the row under it moves up a place");
for file, d in pairs(C.DISTRIBUTIONS) do
	CHECK(#d.stats == 5 and d.health > 0 and d.title ~= "", file .. ": a whole distribution");
end

-- 2. A distribution picked: the class panel is the character's own class
CharacterCreate_OnShow();
CHECK(STUB.shown and OursCreateClassName:GetText() == "" and C.power == 0, "shown: no name yet, mana");
CHECK(CharacterCreateClassLabel.text == "Your class", "the panel's title before a name: " .. tostring(CharacterCreateClassLabel.text));
SetCharacterClass(4);
CHECK(not CharacterCreateClassScrollFrame.shown, "the game's class text is hidden");
CHECK(CharacterCreateClassName.text == "Agility and Strength", "the label under the buttons says the distribution: " .. tostring(CharacterCreateClassName.text));
CHECK(string.find(C.frames.statsText.text, "Agility 189") and string.find(C.frames.statsText.text, "health 7604"), "its stats: " .. tostring(C.frames.statsText.text));

-- 3. The class's name and its resource
Mock.type(OursCreateClassName, "Shadow Dancer");
CHECK(CharacterCreateClassLabel.text == "Shadow Dancer", "the panel's title is the class's name: " .. tostring(CharacterCreateClassLabel.text));
OursCreatePower3.scripts.OnClick(OursCreatePower3);
CHECK(C.power == 2 and string.find(C.frames.powerText.text, "Energy"), "energy picked: " .. tostring(C.frames.powerText.text));

-- 4. What a class's name may be
local good = { "Spellblade", "Shadow Dancer", "Shadow-Knight", "O'Brien", "\195\137p\195\169e" };
local bad = { "", "A", "Bad1", "-Bad", "Bad'", "Two  Spaces", "Too--Many", "Abcdefghijklmnopqrstuvwxy", "Under_score" };
for _, name in ipairs(good) do CHECK(C.CheckName(name), "a good name: " .. name); end
for _, name in ipairs(bad) do
	local ok, why = C.CheckName(name);
	CHECK(not ok and why, "a bad name, with why: " .. name);
end

-- 5. Accept: a bad name stops it with a message; a good one sends the choice, then the game's own accept runs
Mock.type(OursCreateClassName, "X");
CharacterCreate_Okay();
CHECK(#STUB.dialogs == 1 and STUB.dialogs[1].which == "OKAY" and STUB.created == 0 and #STUB.choices == 0, "a bad name: a message, nothing made");
Mock.type(OursCreateClassName, "  Shadow Dancer ");
CharacterCreate_Okay();
CHECK(STUB.created == 1 and #STUB.choices == 1 and STUB.choices[1].power == 2 and STUB.choices[1].name == "Shadow Dancer",
	"a good name: the choice (trimmed) and the game's accept");

-- 6. Shown again: the choice starts anew; a paid change of an old character passes without a class name
CharacterCreate_OnShow();
CHECK(OursCreateClassName:GetText() == "" and C.power == 0, "shown again: nothing chosen");
PAID_SERVICE_TYPE = 1;
CharacterCreate_Okay();
CHECK(STUB.created == 2 and #STUB.choices == 1, "a paid change: the game's accept, no choice");
PAID_SERVICE_TYPE = nil;
