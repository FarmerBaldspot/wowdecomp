-- Ours: a stand-in for as much of the game's interface as its option panels and our page of Video options use, and
-- the check of that page. Run by check.py, which hands in the texts of the game's OptionsPanelTemplates.lua and
-- VideoOptionsPanels.lua (GAME_FILES) and of our page (OUR_PAGE).

local failures = 0
local function expect (what, ok)
	print((ok and "ok    " or "WRONG ") .. what)
	if ( not ok ) then failures = failures + 1 end
end

-- The game's console variables, as the client registers ours (OursGraphics.cpp).
local cvars, defaults = {}, {}
local function register (name, value) cvars[name] = value; defaults[name] = value end
register("oursWater", "1")
register("oursSky", "1")
for _, name in ipairs({ "oursWaterWaves", "oursWaterClarity", "oursWaterReflection", "oursWaterGlitter", "oursWaterBedLight", "oursWaterFoam", "oursWaterFoamWidth", "oursSmallObjectDist", "oursSkyClouds", "oursSkyCloudSpeed", "oursSkySunGlow", "oursSkyStars", "oursSkyMilkyWay", "oursSkyTwinkle", "oursSkyShootingStars" }) do
	register(name, "100")
end
function GetCVar (name) assert(cvars[name], "no CVar " .. tostring(name)); return cvars[name] end
function SetCVar (name, value) assert(cvars[name], "no CVar " .. tostring(name)); cvars[name] = tostring(value) end
function GetCVarDefault (name) return defaults[name] end
function GetCVarMin (name) assert(cvars[name]); return nil end
function GetCVarMax (name) assert(cvars[name]); return nil end
function GetCVarAbsoluteMin (name) return nil end
function GetCVarAbsoluteMax (name) return nil end

-- What the game has besides.
tinsert, tremove, gsub, format, strfind = table.insert, table.remove, string.gsub, string.format, string.find
function securecall (f, ...) return f(...) end
function issecure () return true end
function PlaySound () end
GRAY_FONT_COLOR = { r = 0.5, g = 0.5, b = 0.5 }
NORMAL_FONT_COLOR = { r = 1, g = 0.82, b = 0 }
HIGHLIGHT_FONT_COLOR = { r = 1, g = 1, b = 1 }

-- Frames: each a table whose methods are in its metatable's __index, as the game's widgets are (the option panels
-- call getmetatable(self).__index.Disable).
local methods = {}
local function new (kind, name, parent)
	local object = setmetatable({ kind = kind, parent = parent, scripts = {}, shown = true, enabled = true, checked = false,
	                              position = 0, least = 0, most = 1, events = {}, colour = {} }, { __index = methods })
	if ( name ) then
		if ( parent and parent.GetName and parent:GetName() ) then name = gsub(name, "%$parent", parent:GetName()) end
		object.name = name
		_G[name] = object
	end
	return object
end
function methods:GetName () return self.name end
function methods:GetParent () return self.parent end
function methods:Show () self.shown = true end
function methods:Hide () self.shown = false end
function methods:IsShown () return self.shown end
function methods:IsVisible () return self.shown and (not self.parent or not self.parent.IsVisible or self.parent:IsVisible()) end
function methods:SetScript (which, f) self.scripts[which] = f end
function methods:GetScript (which) return self.scripts[which] end
function methods:RegisterEvent (event) self.events[event] = true end
function methods:UnregisterEvent (event) self.events[event] = nil end
function methods:SetPoint () end
function methods:ClearAllPoints () end
function methods:SetWidth () end
function methods:SetHeight () end
function methods:SetJustifyH () end
function methods:SetJustifyV () end
function methods:SetNonSpaceWrap () end
function methods:SetFontObject () end
function methods:GetFontObject () return { GetTextColor = function () return 1, 1, 1 end } end
function methods:SetTextColor (r, g, b) self.colour = { r, g, b } end
function methods:SetVertexColor (r, g, b) self.colour = { r, g, b } end
function methods:SetText (text) self.text = text end
function methods:GetText () return self.text end
function methods:Enable () self.enabled = true end
function methods:Disable () self.enabled = false end
function methods:IsEnabled () return self.enabled and 1 or nil end
function methods:SetChecked (on) self.checked = on and true or false end
function methods:GetChecked () return self.checked and 1 or nil end
function methods:SetMinMaxValues (least, most) self.least, self.most = least, most end
function methods:GetMinMaxValues () return self.least, self.most end
function methods:SetValueStep (step) self.step = step end
function methods:GetValue () return self.position end
function methods:SetValue (value)                    -- as the game's slider: held within its ends; OnValueChanged when it is another
	value = math.max(self.least, math.min(self.most, value))
	if ( value ~= self.position ) then
		self.position = value
		if ( self.scripts.OnValueChanged ) then self.scripts.OnValueChanged(self, value) end
	end
end
function methods:CreateFontString (name) return new("FontString", name, self) end
function methods:Click ()
	if ( not self.enabled ) then return end
	self.checked = not self.checked
	if ( self.scripts.OnClick ) then self.scripts.OnClick(self, "LeftButton") end
end

function CreateFrame (kind, name, parent, template)
	local frame = new(kind, name, parent)
	if ( template == "OptionsSliderTemplate" ) then
		for _, part in ipairs({ "Text", "Low", "High" }) do new("FontString", frame.name .. part, frame) end
	elseif ( template == "VideoOptionsSmallCheckButtonTemplate" ) then
		new("FontString", frame.name .. "Text", frame)
		frame:SetScript("OnClick", function (self)          -- the template's own OnClick (VideoOptionsPanels.xml)
			BlizzardOptionsPanel_CheckButton_OnClick(self)
			VideoOptionsFrameApply:Enable()
		end)
	elseif ( template ) then
		error("the stand-in has no template " .. template)
	end
	return frame
end

-- The Video options frame, and its list of pages (OptionsFrame_AddCategory is the game's OptionsFrameTemplates.lua,
-- which needs the list's own frames: a stand-in here).
VideoOptionsFrame = new("Frame", "VideoOptionsFrame")
VideoOptionsFrame.categoryList = {}
VideoOptionsFramePanelContainer = new("Frame", "VideoOptionsFramePanelContainer", VideoOptionsFrame)
VideoOptionsFrameApply = new("Button", "VideoOptionsFrameApply", VideoOptionsFrame)
function OptionsFrame_AddCategory (frame, panel) tinsert(frame.categoryList, panel) end

-- The game's own option code, then our page.
for _, file in ipairs(GAME_FILES) do
	local chunk, fault = loadstring(file.text, file.name)
	assert(chunk, fault)
	chunk()
end
local chunk, fault = loadstring(OUR_PAGE, "OursVideoOptions.lua")
assert(chunk, fault)
chunk()

-- The checks.
local panel = OursWaterPanel
expect("the page is made", panel ~= nil)
expect("it is in the Video options' list of pages, called Water", VideoOptionsFrame.categoryList[1] == panel and panel.name == "Water")
expect("it is not shown until it is picked", not panel:IsShown())

-- As the game does it when the world is entered, and when the Video options are opened with this page.
panel.scripts.OnEvent(panel, "PLAYER_ENTERING_WORLD")
panel:Show()
VideoOptionsFrameApply:Disable()
panel.refresh(panel)

local check, waves, foam = OursWaterPanelWater, OursWaterPanelWaves, OursWaterPanelFoam
expect("seven sliders and a tick, all the game's controls of the page", #panel.controls == 8)
expect("the tick says New Water and is ticked", OursWaterPanelWaterText.text == "New Water" and check:GetChecked())
expect("a slider's name is its setting's", OursWaterPanelWavesText.text == "Wave Height" and OursWaterPanelFoamWidthText.text == "Foam Width")
expect("it has its tooltip", waves.tooltipText == OursWaterPanelOptions.oursWaterWaves.tooltip)
expect("its ends are the page's", waves.least == 0 and waves.most == 200 and OursWaterPanelClarity.least == 25 and OursWaterPanelClarity.most == 300)
expect("it shows its setting, 100%", waves.position == 100 and OursWaterPanelWavesValue.text == "100%")
expect("nothing is to be applied yet", not VideoOptionsFrameApply:IsEnabled())

-- A slider moved, as the mouse moves it (the widget's own SetValue, not the page's): nothing is set until Okay.
methods.SetValue(waves, 150)
expect("moved: it says 150%", OursWaterPanelWavesValue.text == "150%")
expect("moved: Apply can be pressed", VideoOptionsFrameApply:IsEnabled())
expect("moved: the setting is not changed yet", cvars.oursWaterWaves == "100")
panel.okay(panel)
expect("Okay: the setting is 150", cvars.oursWaterWaves == "150")

-- Cancel puts a moved slider back.
methods.SetValue(foam, 40)
panel.cancel(panel)
expect("Cancel: the foam's setting is still 100", cvars.oursWaterFoam == "100" and foam.position == 100)

-- The tick off: the sliders greyed, the setting 0 once Okay is pressed; and on again.
check:Click()
expect("unticked: the sliders are greyed", not waves.enabled and not foam.enabled)
expect("unticked: the setting is not changed yet", cvars.oursWater == "1")
panel.okay(panel)
expect("Okay: New Water is 0", cvars.oursWater == "0")
panel:Hide(); panel:Show(); panel.refresh(panel)
expect("opened again: unticked, the sliders greyed", not check:GetChecked() and not waves.enabled)
check:Click()
panel.okay(panel)
expect("ticked and Okay: New Water is 1, the sliders work", cvars.oursWater == "1" and waves.enabled)

-- Defaults.
methods.SetValue(OursWaterPanelClarity, 250)
panel.okay(panel)
check:Click(); panel.okay(panel)
panel.default(panel)
local all = true
for name, value in pairs(cvars) do if ( value ~= defaults[name] ) then all = false; print("      " .. name .. " is " .. value) end end
expect("Defaults: every setting as it was at first", all)
expect("Defaults: ticked, the sliders work, waves at 100%", check:GetChecked() and waves.enabled and OursWaterPanelWavesValue.text == "100%")

-- The page "Objects".
local objects, seen = OursObjectsPanel, OursObjectsPanelSmallSeen
expect("Objects: a page after Water, called Objects", VideoOptionsFrame.categoryList[2] == objects and objects.name == "Objects")
objects.scripts.OnEvent(objects, "PLAYER_ENTERING_WORLD")
objects:Show()
VideoOptionsFrameApply:Disable()
objects.refresh(objects)
expect("Objects: one slider, named, with its tooltip", #objects.controls == 1 and OursObjectsPanelSmallSeenText.text == "Small Objects Seen From" and seen.tooltipText ~= nil)
expect("Objects: 30 to 500 yards, showing 100 yards", seen.least == 30 and seen.most == 500 and OursObjectsPanelSmallSeenValue.text == "100 yards")
methods.SetValue(seen, 250)
expect("Objects: moved, says 250 yards, not set yet", OursObjectsPanelSmallSeenValue.text == "250 yards" and cvars.oursSmallObjectDist == "100" and VideoOptionsFrameApply:IsEnabled())
objects.okay(objects)
expect("Objects: Okay sets it to 250", cvars.oursSmallObjectDist == "250")
objects.default(objects)
expect("Objects: Defaults puts it back to 100", cvars.oursSmallObjectDist == "100" and OursObjectsPanelSmallSeenValue.text == "100 yards")

-- The page "Sky".
local skyPage, skyTick, clouds = OursSkyPanel, OursSkyPanelSky, OursSkyPanelClouds
expect("Sky: a page after Objects, called Sky", VideoOptionsFrame.categoryList[3] == skyPage and skyPage.name == "Sky")
skyPage.scripts.OnEvent(skyPage, "PLAYER_ENTERING_WORLD")
skyPage:Show()
VideoOptionsFrameApply:Disable()
skyPage.refresh(skyPage)
expect("Sky: a tick and seven sliders (clouds, speed, glow, stars, Milky Way, twinkle, shooting stars), the tick on", #skyPage.controls == 8 and skyTick:GetChecked() and OursSkyPanelSkyText.text == "New Sky")
expect("Sky: the sliders' names and ends", OursSkyPanelCloudsText.text == "Clouds" and OursSkyPanelSunGlowText.text == "Sun Glow" and clouds.most == 200 and OursSkyPanelCloudSpeed.most == 300)
expect("Sky: the night's sliders' names and ends", OursSkyPanelStarsText.text == "Stars" and OursSkyPanelMilkyWayText.text == "Milky Way"
    and OursSkyPanelTwinkleText.text == "Twinkle" and OursSkyPanelShootingStarsText.text == "Shooting Stars" and OursSkyPanelStars.most == 300
    and OursSkyPanelShootingStars.most == 400)
methods.SetValue(clouds, 60)
methods.SetValue(OursSkyPanelStars, 150)
skyPage.okay(skyPage)
expect("Sky: Okay sets the clouds to 60", cvars.oursSkyClouds == "60")
expect("Sky: Okay sets the stars to 150", cvars.oursSkyStars == "150")
skyTick:Click()
expect("Sky: unticked, the sliders are greyed", not clouds.enabled)
skyPage.okay(skyPage)
expect("Sky: Okay: New Sky is 0", cvars.oursSky == "0")
skyPage.default(skyPage)
expect("Sky: Defaults: on, the clouds 100, the sliders work", cvars.oursSky == "1" and cvars.oursSkyClouds == "100" and clouds.enabled)

print(failures == 0 and "ALL RIGHT" or (failures .. " WRONG"))
