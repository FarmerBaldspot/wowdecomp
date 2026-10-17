-- Ours, not the game's (the World of Warcraft editor project): a page of the game's Video options for what our
-- client draws anew. Loaded by the client itself right after the game's own interface (OursGraphics.cpp), so it is
-- part of that interface and not an addon. Every control is one of the game's console variables, registered by the
-- client (OursGraphics.cpp), saved in WTF\Config.wtf with the other graphics settings; it is set when Okay or Apply is
-- pressed, as on the game's own pages, and the Defaults button puts it back.

OursWaterPanelOptions = {
	oursWater = { text = "New Water", tooltip = "Clear water with waves, a mirror of what stands around it, light on its bed and foam along the shore. Off: the game's own water." },
	oursWaterWaves = { text = "Wave Height", minValue = 0, maxValue = 200, valueStep = 5, tooltip = "How high the water's waves are." },
	oursWaterClarity = { text = "Clarity", minValue = 25, maxValue = 300, valueStep = 5, tooltip = "How far down the bed is seen. Higher: clearer water." },
	oursWaterReflection = { text = "Reflection", minValue = 0, maxValue = 150, valueStep = 5, tooltip = "How much the water mirrors the sky and what stands around it." },
	oursWaterGlitter = { text = "Sun Glitter", minValue = 0, maxValue = 200, valueStep = 5, tooltip = "The sun's own image on the waves: the path of glitter toward the sun." },
	oursWaterBedLight = { text = "Light on the Bed", minValue = 0, maxValue = 150, valueStep = 5, tooltip = "The web of light that the waves throw on the ground under clear water." },
	oursWaterFoam = { text = "Foam", minValue = 0, maxValue = 150, valueStep = 5, tooltip = "How much foam lies along shores, walls and whatever stands in the water." },
	oursWaterFoamWidth = { text = "Foam Width", minValue = 25, maxValue = 300, valueStep = 5, tooltip = "How far out from the shore the foam reaches." },
};

local panel = CreateFrame("Frame", "OursWaterPanel", VideoOptionsFramePanelContainer);
panel:Hide();

local title = panel:CreateFontString("OursWaterPanelTitle", "ARTWORK", "GameFontNormalLarge");
title:SetPoint("TOPLEFT", 16, -16);
title:SetJustifyH("LEFT");
title:SetText("Water");

local subText = panel:CreateFontString("OursWaterPanelSubText", "ARTWORK", "GameFontHighlightSmall");
subText:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8);
subText:SetPoint("RIGHT", -32, 0);
subText:SetHeight(32);
subText:SetJustifyH("LEFT");
subText:SetJustifyV("TOP");
subText:SetNonSpaceWrap(true);
subText:SetText("How the water looks. Drawn by this client in place of the game's own water; the sliders are in percent of how it is made.");

-- The sliders, which only mean something while the new water is on.
local sliders = {};

local function showOn ()
	local on = OursWaterPanelWater:GetChecked();
	for _, slider in ipairs(sliders) do
		if ( on ) then
			slider:Enable();
		else
			slider:Disable();
		end
	end
end

local check = CreateFrame("CheckButton", "OursWaterPanelWater", panel, "VideoOptionsSmallCheckButtonTemplate");
check:SetPoint("TOPLEFT", subText, "BOTTOMLEFT", -2, -8);
check.type = CONTROLTYPE_CHECKBOX;
check.cvar = "oursWater";
check.setFunc = function () showOn(); end;
BlizzardOptionsPanel_RegisterControl(check, panel);

local function slider (cvar, name, column, row)
	local control = CreateFrame("Slider", "OursWaterPanel" .. name, panel, "OptionsSliderTemplate");
	control:SetWidth(170);
	control:SetHeight(17);
	control:SetPoint("TOPLEFT", check, "BOTTOMLEFT", 8 + column * 195, -28 - row * 48);
	control.type = CONTROLTYPE_SLIDER;
	control.cvar = cvar;
	control.SetDisplayValue = control.SetValue;
	control.SetValue = function (self, value)
		self:SetDisplayValue(value);
		BlizzardOptionsPanel_SetCVarSafe(self.cvar, value);
	end
	_G[control:GetName() .. "Text"]:SetFontObject("GameFontNormalSmall");
	_G[control:GetName() .. "Low"]:SetText("");
	_G[control:GetName() .. "High"]:SetText("");
	-- What it is set to, under its right end.
	local shown = control:CreateFontString(control:GetName() .. "Value", "ARTWORK", "GameFontHighlightSmall");
	shown:SetPoint("TOP", control, "BOTTOM", 0, 3);
	control:SetScript("OnValueChanged", function (self, value)
		shown:SetText(format("%d%%", value));
		self.newValue = value;
		if ( self:GetParent():IsVisible() ) then
			VideoOptionsFrameApply:Enable();
		end
	end);
	BlizzardOptionsPanel_RegisterControl(control, panel);
	tinsert(sliders, control);
	return control;
end

slider("oursWaterWaves", "Waves", 0, 0);
slider("oursWaterClarity", "Clarity", 1, 0);
slider("oursWaterReflection", "Reflection", 0, 1);
slider("oursWaterGlitter", "Glitter", 1, 1);
slider("oursWaterBedLight", "BedLight", 0, 2);
slider("oursWaterFoam", "Foam", 1, 2);
slider("oursWaterFoamWidth", "FoamWidth", 0, 3);

local function refresh (self)
	BlizzardOptionsPanel_Refresh(self);
	showOn();
end

local function default (self)
	VideoOptionsPanel_Default(self);
	BlizzardOptionsPanel_Refresh(self);
	showOn();
end

panel.name = "Water";
panel.options = OursWaterPanelOptions;
VideoOptionsPanel_OnLoad(panel, nil, nil, default, refresh);

-- The page "Objects": how far the map's models are seen. The game sorts them into five classes by their size and
-- sees each up to a distance; its "Environment Detail" (the Effects page) scales all but the smallest, which stayed at
-- 30 yards: barrels, crates and mugs vanished as the camera was drawn back. The client takes that one from here.

OursObjectsPanelOptions = {
	oursSmallObjectDist = { text = "Small Objects Seen From", minValue = 30, maxValue = 500, valueStep = 10, tooltip = "How far the map's smallest models (under a yard across: barrels, crates, mugs, flowers in pots) are drawn, in yards. The game's own: 30. Environment Detail on the Effects page scales the larger ones." },
};

local objects = CreateFrame("Frame", "OursObjectsPanel", VideoOptionsFramePanelContainer);
objects:Hide();

local objectsTitle = objects:CreateFontString("OursObjectsPanelTitle", "ARTWORK", "GameFontNormalLarge");
objectsTitle:SetPoint("TOPLEFT", 16, -16);
objectsTitle:SetJustifyH("LEFT");
objectsTitle:SetText("Objects");

local objectsText = objects:CreateFontString("OursObjectsPanelSubText", "ARTWORK", "GameFontHighlightSmall");
objectsText:SetPoint("TOPLEFT", objectsTitle, "BOTTOMLEFT", 0, -8);
objectsText:SetPoint("RIGHT", -32, 0);
objectsText:SetHeight(32);
objectsText:SetJustifyH("LEFT");
objectsText:SetJustifyV("TOP");
objectsText:SetNonSpaceWrap(true);
objectsText:SetText("How far the world's models are seen. Farther costs more to draw.");

local smallSeen = CreateFrame("Slider", "OursObjectsPanelSmallSeen", objects, "OptionsSliderTemplate");
smallSeen:SetWidth(170);
smallSeen:SetHeight(17);
smallSeen:SetPoint("TOPLEFT", objectsText, "BOTTOMLEFT", 6, -36);
smallSeen.type = CONTROLTYPE_SLIDER;
smallSeen.cvar = "oursSmallObjectDist";
smallSeen.SetDisplayValue = smallSeen.SetValue;
smallSeen.SetValue = function (self, value)
	self:SetDisplayValue(value);
	BlizzardOptionsPanel_SetCVarSafe(self.cvar, value);
end
_G[smallSeen:GetName() .. "Text"]:SetFontObject("GameFontNormalSmall");
_G[smallSeen:GetName() .. "Low"]:SetText("");
_G[smallSeen:GetName() .. "High"]:SetText("");
local smallSeenShown = smallSeen:CreateFontString(smallSeen:GetName() .. "Value", "ARTWORK", "GameFontHighlightSmall");
smallSeenShown:SetPoint("TOP", smallSeen, "BOTTOM", 0, 3);
smallSeen:SetScript("OnValueChanged", function (self, value)
	smallSeenShown:SetText(format("%d yards", value));
	self.newValue = value;
	if ( self:GetParent():IsVisible() ) then
		VideoOptionsFrameApply:Enable();
	end
end);
BlizzardOptionsPanel_RegisterControl(smallSeen, objects);

objects.name = "Objects";
objects.options = OursObjectsPanelOptions;
VideoOptionsPanel_OnLoad(objects);

-- The page "Sky": the sky drawn anew in each zone's own colours, smooth, with a glow round the sun and clouds that
-- drift (OursSkyColours.cpp, sky.hlsl), and a night of stars.

OursSkyPanelOptions = {
	oursSky = { text = "New Sky", tooltip = "The sky in each zone's own colours, drawn smoothly, with a glow round the sun and clouds that drift and are lit from the sun's side. Off: the game's own sky. Zones with a sky of their own (Outland, Nagrand) keep it." },
	oursSkyClouds = { text = "Clouds", minValue = 0, maxValue = 200, valueStep = 5, tooltip = "How much cloud, in percent of what the zone has." },
	oursSkyCloudSpeed = { text = "Cloud Speed", minValue = 0, maxValue = 300, valueStep = 5, tooltip = "How fast the clouds drift." },
	oursSkySunGlow = { text = "Sun Glow", minValue = 0, maxValue = 200, valueStep = 5, tooltip = "How strongly the sun glows in the sky, in the zone's own sun colour." },
	oursSkyStars = { text = "Stars", minValue = 0, maxValue = 300, valueStep = 5, tooltip = "How bright the stars of the night are: thousands of them, white, blue and warm, wheeling slowly with the hour. At 0 the game's own stars are back." },
	oursSkyMilkyWay = { text = "Milky Way", minValue = 0, maxValue = 300, valueStep = 5, tooltip = "How bright the band of the Milky Way is across the night sky, with its dark lanes of dust." },
	oursSkyTwinkle = { text = "Twinkle", minValue = 0, maxValue = 200, valueStep = 5, tooltip = "How much the stars twinkle: more the lower they stand." },
	oursSkyShootingStars = { text = "Shooting Stars", minValue = 0, maxValue = 400, valueStep = 10, tooltip = "How often a star shoots across the sky. At 100 about one every half minute." },
};

local skyPanel = CreateFrame("Frame", "OursSkyPanel", VideoOptionsFramePanelContainer);
skyPanel:Hide();

local skyTitle = skyPanel:CreateFontString("OursSkyPanelTitle", "ARTWORK", "GameFontNormalLarge");
skyTitle:SetPoint("TOPLEFT", 16, -16);
skyTitle:SetJustifyH("LEFT");
skyTitle:SetText("Sky");

local skyText = skyPanel:CreateFontString("OursSkyPanelSubText", "ARTWORK", "GameFontHighlightSmall");
skyText:SetPoint("TOPLEFT", skyTitle, "BOTTOMLEFT", 0, -8);
skyText:SetPoint("RIGHT", -32, 0);
skyText:SetHeight(32);
skyText:SetJustifyH("LEFT");
skyText:SetJustifyV("TOP");
skyText:SetNonSpaceWrap(true);
skyText:SetText("The sky in each zone's own colours, drawn by this client in place of the game's own; the sliders are in percent of how it is made.");

local skySliders = {};

local function skyShowOn ()
	local on = OursSkyPanelSky:GetChecked();
	for _, slider in ipairs(skySliders) do
		if ( on ) then
			slider:Enable();
		else
			slider:Disable();
		end
	end
end

local skyCheck = CreateFrame("CheckButton", "OursSkyPanelSky", skyPanel, "VideoOptionsSmallCheckButtonTemplate");
skyCheck:SetPoint("TOPLEFT", skyText, "BOTTOMLEFT", -2, -8);
skyCheck.type = CONTROLTYPE_CHECKBOX;
skyCheck.cvar = "oursSky";
skyCheck.setFunc = function () skyShowOn(); end;
BlizzardOptionsPanel_RegisterControl(skyCheck, skyPanel);

local function skySlider (cvar, name, column, row)
	local control = CreateFrame("Slider", "OursSkyPanel" .. name, skyPanel, "OptionsSliderTemplate");
	control:SetWidth(170);
	control:SetHeight(17);
	control:SetPoint("TOPLEFT", skyCheck, "BOTTOMLEFT", 8 + column * 195, -28 - row * 48);
	control.type = CONTROLTYPE_SLIDER;
	control.cvar = cvar;
	control.SetDisplayValue = control.SetValue;
	control.SetValue = function (self, value)
		self:SetDisplayValue(value);
		BlizzardOptionsPanel_SetCVarSafe(self.cvar, value);
	end
	_G[control:GetName() .. "Text"]:SetFontObject("GameFontNormalSmall");
	_G[control:GetName() .. "Low"]:SetText("");
	_G[control:GetName() .. "High"]:SetText("");
	local shown = control:CreateFontString(control:GetName() .. "Value", "ARTWORK", "GameFontHighlightSmall");
	shown:SetPoint("TOP", control, "BOTTOM", 0, 3);
	control:SetScript("OnValueChanged", function (self, value)
		shown:SetText(format("%d%%", value));
		self.newValue = value;
		if ( self:GetParent():IsVisible() ) then
			VideoOptionsFrameApply:Enable();
		end
	end);
	BlizzardOptionsPanel_RegisterControl(control, skyPanel);
	tinsert(skySliders, control);
	return control;
end

skySlider("oursSkyClouds", "Clouds", 0, 0);
skySlider("oursSkyCloudSpeed", "CloudSpeed", 1, 0);
skySlider("oursSkySunGlow", "SunGlow", 0, 1);
skySlider("oursSkyStars", "Stars", 1, 1);
skySlider("oursSkyMilkyWay", "MilkyWay", 0, 2);
skySlider("oursSkyTwinkle", "Twinkle", 1, 2);
skySlider("oursSkyShootingStars", "ShootingStars", 0, 3);

skyPanel.name = "Sky";
skyPanel.options = OursSkyPanelOptions;
VideoOptionsPanel_OnLoad(skyPanel, nil, nil,
	function (self) VideoOptionsPanel_Default(self); BlizzardOptionsPanel_Refresh(self); skyShowOn(); end,
	function (self) BlizzardOptionsPanel_Refresh(self); skyShowOn(); end);
