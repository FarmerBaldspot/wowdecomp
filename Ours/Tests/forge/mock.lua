-- Ours: a stand-in for the game's frames and functions, enough for OursForge.lua to run without the game. Every
-- frame takes any method; those whose answer matters (texts, shown, checked, scripts) keep what they are given.

Mock = { sent = {}, popups = {}, errors = {}, now = 100, menus = {} };

local function newObject (kind, name)
	local o = { kind = kind, name = name, scripts = {}, shown = true, text = "", checked = false, children = {} };
	local methods = {
		SetText = function (self, t) self.text = t; end,
		GetText = function (self) return self.text; end,
		SetScript = function (self, which, f) self.scripts[which] = f; end,
		GetScript = function (self, which) return self.scripts[which]; end,
		Show = function (self) self.shown = true; if ( self.scripts.OnShow ) then self.scripts.OnShow(self); end end,
		Hide = function (self) self.shown = false; end,
		IsShown = function (self) return self.shown; end,
		SetChecked = function (self, c) self.checked = c and true or false; end,
		GetChecked = function (self) return self.checked and 1 or nil; end,
		SetTexture = function (self, t) self.texture = t; end,
		GetTexture = function (self) return self.texture; end,
		GetFrameLevel = function () return 1; end,
		GetBackdrop = function () return {}; end,
		CreateFontString = function (self) return newObject("FontString"); end,
		CreateTexture = function (self) return newObject("Texture"); end,
		Enable = function (self) self.enabled = true; end,
		Disable = function (self) self.enabled = false; end,
		SetHyperlink = function (self, link) self.link = link; end,
		-- where a thing is put (the last SetPoint's offsets), how wide it is, and a word's width as the game's
		-- small font has it, near enough (6 a letter)
		SetPoint = function (self, point, a, b, c, d)
			if ( type(a) == "number" ) then self.x, self.y = a, b; elseif ( type(c) == "number" ) then self.x, self.y = c, d; end
		end,
		ClearAllPoints = function (self) self.x, self.y = nil, nil; end,
		SetWidth = function (self, w) self.width = w; end,
		GetWidth = function (self) return self.width or 0; end,
		GetStringWidth = function (self) return 6 * string.len(self.text or ""); end,
		RegisterEvent = function (self, event) end,
	};
	setmetatable(o, { __index = function (t, key)
		return methods[key] or function () end;
	end });
	if ( name ) then _G[name] = o; end
	return o;
end
Mock.newObject = newObject;

UIParent = newObject("Frame", "UIParent");
UIErrorsFrame = newObject("Frame", "UIErrorsFrame");
UIErrorsFrame.AddMessage = function (self, text) table.insert(Mock.errors, text); end;
GameTooltip = newObject("GameTooltip", "GameTooltip");
UISpecialFrames = {};
StaticPopupDialogs = {};
SlashCmdList = {};
ACCEPT, CANCEL = "Accept", "Cancel";
tinsert = table.insert;

function CreateFrame (kind, name, parent, template)
	local o = newObject(kind, name);
	o.template = template;
	if ( template == "UICheckButtonTemplate" ) then newObject("FontString", name .. "Text"); end
	return o;
end

function UIDropDownMenu_SetWidth () end
function UIDropDownMenu_SetText (frame, text) frame.menuText = text; end
function UIDropDownMenu_CreateInfo () return {}; end
function UIDropDownMenu_AddButton (info) table.insert(Mock.menuButtons, info); end
function UIDropDownMenu_Initialize (frame, init, mode)
	frame.initialize = init;
	Mock.menuButtons = {};
	init(frame, 1);
end
function ToggleDropDownMenu (level, value, frame) Mock.menuButtons = {}; frame.initialize(frame, 1); Mock.opened = frame; end
-- The entries of a dropdown, as opening it lists them
-- (with what the entries that open to the side hold, as the game asks for them: level 2, the entry's value in
-- UIDROPDOWNMENU_MENU_VALUE)
function Mock.entries (frame)
	Mock.menuButtons = {};
	frame.initialize(frame, 1);
	local all = {};
	for _, info in ipairs(Mock.menuButtons) do
		table.insert(all, info);
		if ( info.hasArrow ) then
			Mock.menuButtons = {};
			UIDROPDOWNMENU_MENU_VALUE = info.value;
			frame.initialize(frame, 2);
			UIDROPDOWNMENU_MENU_VALUE = nil;
			info.inside = Mock.menuButtons;
			for _, inner in ipairs(Mock.menuButtons) do table.insert(all, inner); end
		end
	end
	return all;
end
function CloseDropDownMenus () end
-- A click on an entry of a dropdown (by its value, or its place)
function Mock.pick (frame, value)
	for i, info in ipairs(Mock.entries(frame)) do
		if ( info.value == value or i == value ) then
			info.func({ value = info.value });
			return true;
		end
	end
	error("no entry " .. tostring(value) .. " in " .. tostring(frame.name));
end

function GetTime () return Mock.now; end
function UnitName () return "Test"; end
function GetSpellInfo (id) return "Spell " .. id, nil, "Interface\\Icons\\Spell"; end
function SendAddonMessage (prefix, body, channel, target) table.insert(Mock.sent, { prefix = prefix, body = body, channel = channel, target = target }); end
function StaticPopup_Show (which, a) table.insert(Mock.popups, { which = which, text = a }); end
function SpellforgeIconCount () return 3; end
function SpellforgeIcon (i) return 100 + i, "Interface\\Icons\\Icon_" .. i; end
function SpellforgeIconTexture (id) return "Interface\\Icons\\Icon_" .. id; end

-- Time passing, as frames are drawn
function Mock.wait (seconds)
	Mock.now = Mock.now + seconds;
	local update = OursForgeFrame.scripts.OnUpdate;
	if ( update ) then update(OursForgeFrame, seconds); end
end
-- A message from the server
function Mock.receive (body)
	OursForgeFrame.scripts.OnEvent(OursForgeFrame, "CHAT_MSG_ADDON", "SFRG", body, "WHISPER", "Test");
end
-- Typing into an edit box
function Mock.type (box, text)
	box.text = text;
	box.scripts.OnTextChanged(box, true);
end
-- The game's spells, as our client's search finds them: id, name, rank, icon
function SpellforgeFindSpells (words, most)
	if ( words == "fire" ) then
		return 133, "Fireball", "Rank 1", "Interface\\Icons\\Spell_Fire_FlameBolt", 2136, "Fire Blast", "Rank 1", "Interface\\Icons\\Spell_Fire_Fireball";
	end
end
