-- Ours, not the game's (the World of Warcraft editor project): the Spellforge realm's character creation. Run by our
-- client right after the game's GlueXML (WoW\Source\Glue\OursCreate.cpp), over the game's own creation screen:
--
-- * the class buttons are the STAT DISTRIBUTIONS: what each raises, by the game's own classes' growth (the class is
--   kept underneath, for the server and the game; every race may be any of the nine, the death knight not);
-- * the class panel on the right is the character's OWN CLASS: the name the player gives it (which everyone sees
--   in its place: OursClassNames) and the resource it spends (mana, rage or energy: what its spells cost).
--
-- The choice goes to the server in the create packet (SpellforgeSetCreateChoice), where mod-spellforge keeps it.

OursCreate = {};
local C = OursCreate;

-- The distributions: what the game's classes raise, by their stats at level 80 (player_class_stats), Strength,
-- Agility, Stamina, Intellect and Spirit, and their health there
C.DISTRIBUTIONS = {
	WARRIOR = { title = "Strength and Stamina", stats = { 174, 113, 159, 36, 59 }, health = 8121 },
	PALADIN = { title = "Strength and Stamina, some Spirit", short = "Strength, Stamina, Spirit", stats = { 151, 90, 143, 98, 105 }, health = 6934 },
	HUNTER = { title = "Agility and Stamina", stats = { 74, 181, 128, 90, 97 }, health = 7324 },
	ROGUE = { title = "Agility and Strength", stats = { 113, 189, 105, 43, 67 }, health = 7604 },
	PRIEST = { title = "Spirit and Intellect", stats = { 43, 51, 67, 174, 181 }, health = 6960 },
	SHAMAN = { title = "Even: a little of everything", short = "A little of everything", stats = { 120, 74, 136, 128, 143 }, health = 6939 },
	MAGE = { title = "Intellect and Spirit", stats = { 36, 43, 59, 181, 174 }, health = 6963 },
	WARLOCK = { title = "Spirit and Intellect, some Stamina", short = "Spirit, Intellect, Stamina", stats = { 59, 67, 89, 159, 166 }, health = 7136 },
	DRUID = { title = "Spirit and Intellect, some of all", short = "All round, Spirit first", stats = { 89, 82, 98, 143, 159 }, health = 7417 },
};
C.STAT_NAMES = { "Strength", "Agility", "Stamina", "Intellect", "Spirit" };
C.POWERS = { { value = 0, label = "Mana" }, { value = 1, label = "Rage" }, { value = 2, label = "Energy" } };
C.POWER_TEXT = {
	[0] = "Mana: a large pool that fills slowly.",
	[1] = "Rage: built by fighting, gone at rest.",
	[2] = "Energy: a small pool that fills fast.",
};

C.power = 0;
C.className = "";

-- A class's name: two to twenty-four letters, words with a single space, hyphen or apostrophe between them
function C.CheckName (name)
	name = name or "";
	if ( string.len(name) < 2 ) then return nil, "Give your class a name: two letters at least."; end
	if ( string.len(name) > 24 ) then return nil, "Your class's name is too long: twenty-four letters at the most."; end
	if ( string.find(name, "^[ '%-]") or string.find(name, "[ '%-]$") ) then return nil, "Your class's name must begin and end with a letter."; end
	if ( string.find(name, "[^%a\128-\255 '%-]") ) then return nil, "Your class's name may only have letters, spaces, hyphens and apostrophes."; end
	if ( string.find(name, "[ '%-][ '%-]") ) then return nil, "Your class's name may not have two marks in a row."; end
	return name;
end

local function trim (text)
	return (string.gsub(text or "", "^%s*(.-)%s*$", "%1"));
end

------------------------------------------------------------------------------------------------------------------
-- The class panel: the character's own class

local panel = CharacterCreateCharacterClass;
local nameLabel = panel:CreateFontString(nil, "OVERLAY", "GlueFontNormalSmall");
nameLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 22, -54);
nameLabel:SetText("Name your class");

local nameEdit = CreateFrame("EditBox", "OursCreateClassName", panel);
nameEdit:SetWidth(222);
nameEdit:SetHeight(30);
nameEdit:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -64);
nameEdit:SetAutoFocus(false);
nameEdit:SetMaxLetters(24);
nameEdit:SetFontObject("GlueEditBoxFont");
nameEdit:SetTextInsets(12, 8, 0, 0);
nameEdit:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Glues\\Common\\Glue-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 16, insets = { left = 10, right = 5, top = 4, bottom = 9 } });
nameEdit:SetBackdropColor(0.09, 0.09, 0.19);
nameEdit:SetScript("OnTextChanged", function (self)
	C.className = self:GetText() or "";
	C.ShowClass();
end);
nameEdit:SetScript("OnEscapePressed", function () CharacterCreate_Back(); end);
nameEdit:SetScript("OnEnterPressed", function () CharacterCreate_Okay(); end);
nameEdit:SetScript("OnTabPressed", function () CharacterCreateNameEdit:SetFocus(); end);

local powerLabel = panel:CreateFontString(nil, "OVERLAY", "GlueFontNormalSmall");
powerLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 22, -98);
powerLabel:SetText("Its resource");

C.powerButtons = {};
for i, power in ipairs(C.POWERS) do
	local b = CreateFrame("Button", "OursCreatePower" .. i, panel, "GlueButtonSmallTemplate");
	b:SetWidth(72);
	b:SetHeight(22);
	b:SetPoint("TOPLEFT", panel, "TOPLEFT", 18 + (i - 1) * 76, -112);
	b:SetText(power.label);
	b.value = power.value;
	b:SetScript("OnClick", function (self)
		PlaySound("gsCharacterCreationClass");
		C.power = self.value;
		C.ShowClass();
	end);
	C.powerButtons[i] = b;
end

local powerText = panel:CreateFontString(nil, "OVERLAY", "GlueFontNormalSmall");
powerText:SetPoint("TOPLEFT", panel, "TOPLEFT", 22, -138);
powerText:SetWidth(222);
powerText:SetJustifyH("LEFT");

local statsText = panel:CreateFontString(nil, "OVERLAY", "GlueFontNormalSmall");
statsText:SetTextColor(1, 1, 1);
statsText:SetPoint("TOPLEFT", powerText, "BOTTOMLEFT", 0, -8);
statsText:SetWidth(222);
statsText:SetJustifyH("LEFT");

local gearText = panel:CreateFontString(nil, "OVERLAY", "GlueFontNormalSmall");
gearText:SetPoint("TOPLEFT", statsText, "BOTTOMLEFT", 0, -8);
gearText:SetWidth(222);
gearText:SetJustifyH("LEFT");
gearText:SetText("Any armor, any weapon. Its spells are crafted at the forge.");

C.frames = { nameEdit = nameEdit, powerText = powerText, statsText = statsText, nameLabel = nameLabel };

-- What the panel says: the class's name, its resource, the distribution's stats
function C.ShowClass ()
	local name = trim(C.className);
	CharacterCreateClassLabel:SetText(name ~= "" and name or "Your class");
	for _, b in ipairs(C.powerButtons) do
		if ( b.value == C.power ) then b:LockHighlight(); else b:UnlockHighlight(); end
	end
	powerText:SetText(C.POWER_TEXT[C.power] or "");
	local _, file = GetSelectedClass();
	local d = file and C.DISTRIBUTIONS[file];
	if ( d ) then
		local parts = {};
		for i, stat in ipairs(C.STAT_NAMES) do
			table.insert(parts, stat .. " " .. d.stats[i]);
		end
		statsText:SetText("At level 80: " .. table.concat(parts, ", ") .. "; health " .. d.health .. ".");
		CharacterCreateClassName:SetText(d.short or d.title);
	else
		statsText:SetText("");
	end
end

------------------------------------------------------------------------------------------------------------------
-- Over the game's own functions of the screen

-- The class buttons: the distributions (the death knight's hidden)
local enumerateClasses = CharacterCreateEnumerateClasses;
function CharacterCreateEnumerateClasses (...)
	enumerateClasses(...);
	local index = 1;
	for i = 1, select("#", ...), 3 do
		local file = select(i + 1, ...);
		local button = _G["CharacterCreateClassButton" .. index];
		local d = file and C.DISTRIBUTIONS[strupper(file)];
		if ( button ) then
			if ( d ) then
				button.name = d.title;
				button.tooltip = d.title;
			elseif ( file and strupper(file) == "DEATHKNIGHT" ) then
				button:Hide();
				-- the row under it moves up a place (the buttons under the first row hang from the ones above)
				for j = index + 1, MAX_CLASSES_PER_RACE do
					local below = _G["CharacterCreateClassButton" .. j];
					local above = _G["CharacterCreateClassButton" .. (j - 6)];
					if ( below and above ) then
						below:ClearAllPoints();
						below:SetPoint("TOP", above, "BOTTOM", 0, -6);
					end
				end
			end
		end
		index = index + 1;
	end
end

local setClass = SetCharacterClass;
function SetCharacterClass (id)
	setClass(id);
	-- the class panel is the character's own class, not the game's class's text
	CharacterCreateClassScrollFrame:Hide();
	C.ShowClass();
end

local onShow = CharacterCreate_OnShow;
function CharacterCreate_OnShow (...)
	C.power = 0;
	C.className = "";
	nameEdit:SetText("");
	onShow(...);
	C.ShowClass();
end

-- Accept: the class's name has to be one, then the choice goes with the create packet
local okay = CharacterCreate_Okay;
function CharacterCreate_Okay (...)
	if ( PAID_SERVICE_TYPE ) then
		return okay(...);
	end
	local name, why = C.CheckName(trim(C.className));
	if ( not name ) then
		GlueDialog_Show("OKAY", why);
		return;
	end
	SpellforgeSetCreateChoice(C.power, name);
	okay(...);
end
