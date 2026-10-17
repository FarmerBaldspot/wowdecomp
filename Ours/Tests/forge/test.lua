-- Ours: checks of OursForge.lua, run by check.py after mock.lua and the window. CHECK(cond, what) counts; the texts
-- the window writes are left in FORGE_TEXTS for check.py to hand to the server's reader.

local R = OursForgeRecipe;
FORGE_TEXTS = {};

-- 1. The recipe, written and read back, for every kind of effect
for _, kind in ipairs(R.KINDS) do
	local recipe = R.New();
	recipe.name = "Kind " .. kind.key;
	recipe.effects = { R.NewEffect(kind.key) };
	if ( kind.key == "resurrect" ) then recipe.target = "friend"; end
	if ( kind.conjures ) then recipe.effects[1].item = 5350; end
	if ( kind.picks == "imbue" ) then recipe.target = "self"; recipe.effects[1].item = 283; end
	if ( kind.creature ) then recipe.effects[1].creature = 416; end
	if ( kind.aura ) then
		local link = { when = "expire", effects = { R.NewEffect("damage"), R.NewEffect("slow") } };
		table.insert(recipe.effects[1].links, link);
		-- and what it watches for while it lasts (all a watch does)
		table.insert(recipe.effects[1].links, { event = "struck", chance = 25, cooldown = 2, effects = { R.NewEffect("damage") } });
	end
	local text = R.Text(recipe);
	local back, dropped = R.FromText(text);
	CHECK(back ~= nil, kind.key .. ": read back (" .. tostring(dropped) .. ")");
	CHECK(back and R.Text(back) == text, kind.key .. ": the same text again\n    " .. text .. "\n    " .. (back and R.Text(back) or ""));
	CHECK(back and #dropped == 0, kind.key .. ": nothing left out");
	table.insert(FORGE_TEXTS, text);
end

-- 1b. Every setting of the new kinds written and read back the same, and taken by the server
do
	local recipe = R.New();
	recipe.name = "Pets and shapes";
	recipe.target = "enemy";
	recipe.only = { beast = true, humanoid = true };
	local tame = R.NewEffect("tame"); tame.above = 2; tame.elites = true;
	local thrall = R.NewEffect("thrall"); thrall.above = -1; thrall.health = 30; thrall.elites = true; thrall.outside = true;
	local charm = R.NewEffect("charm"); charm.above = 1; charm.seconds = 45;
	recipe.effects = { tame, thrall, charm };
	local text = R.Text(recipe);
	local back = R.FromText(text);
	CHECK(back and R.Text(back) == text, "tame, thrall, charm: the same text again\n    " .. text);
	CHECK(string.find(text, "%(only beast humanoid%)"), "only some kinds of creature: " .. text);
	table.insert(FORGE_TEXTS, text);

	recipe = R.New();
	recipe.name = "Summons";
	recipe.target = "self";
	local pet = R.NewEffect("summon_pet"); pet.creature = 416;
	local helpers = R.NewEffect("summon"); helpers.creature = 29264; helpers.low = 3; helpers.seconds = 40;
	local totem = R.NewEffect("totem"); totem.element = "water"; totem.seconds = 25; totem.every = 3; totem.radius = 12;
	local heal = R.NewEffect("heal"); heal.low, heal.high = 10, 12;
	totem.inner = { heal, R.NewEffect("slow") };
	recipe.effects = { pet, helpers, totem };
	text = R.Text(recipe);
	back = R.FromText(text);
	CHECK(back and R.Text(back) == text, "summons and a totem: the same text again\n    " .. text .. "\n    " .. (back and R.Text(back) or ""));
	CHECK(back and back.effects[3] and #back.effects[3].inner == 2, "the totem's two effects read back");
	table.insert(FORGE_TEXTS, text);

	recipe = R.New();
	recipe.name = "Shapes";
	recipe.target = "self";
	local cat = R.NewEffect("shape_form"); cat.form = "bear"; cat.power = "rage"; cat.as = "beast";
	local armor = R.NewEffect("armor"); armor.seconds = 0;
	recipe.effects = { cat, armor };
	text = R.Text(recipe);
	back = R.FromText(text);
	CHECK(back and R.Text(back) == text, "a lasting form with a buff that lasts as long: the same text again\n    " .. text);
	CHECK(not string.find(text, "%(armor 10 %(for"), "the buff has no length of its own: " .. text);
	table.insert(FORGE_TEXTS, text);
	local wolf = R.NewEffect("shape_creature"); wolf.creature = 299; wolf.power = "energy"; wolf.seconds = 60;
	recipe.effects = { wolf };
	text = R.Text(recipe);
	back = R.FromText(text);
	CHECK(back and R.Text(back) == text and back.effects[1].kind == "shape_creature", "a creature's shape: the same text again\n    " .. text);
	table.insert(FORGE_TEXTS, text);
end

-- 2. Shapes and casts
local shapes = {
	{ target = "self", shape = "area", cast = "instant" },
	{ target = "ground", shape = "area", cast = "cast", castSeconds = 2 },
	{ target = "enemy", shape = "cone", cast = "instant", target2 = nil },
	{ target = "enemy", shape = "chain", cast = "cast", castSeconds = 2.5 },
	{ target = "enemy", shape = "single", cast = "channel", castSeconds = 3 },
	{ target = "friend", shape = "area", cast = "instant" },
	{ target = "enemy", shape = "single", cast = "instant", melee = true },
};
for i, s in ipairs(shapes) do
	local recipe = R.New();
	recipe.name = "Shape " .. i;
	for k, v in pairs(s) do recipe[k] = v; end
	if ( s.shape == "cone" ) then recipe.target = "self"; end
	if ( s.cast == "channel" ) then recipe.effects = { R.NewEffect("dot") }; recipe.effects[1].seconds = 3; recipe.effects[1].every = 1; end
	local text = R.Text(recipe);
	local back = R.FromText(text);
	CHECK(back and R.Text(back) == text, "shape " .. i .. ": the same text again\n    " .. text);
	table.insert(FORGE_TEXTS, text);
end

-- 3. A recipe written by hand (the module's ember-curse.sf) read and written back the same
if ( EMBER_CURSE ) then
	local recipe, dropped = R.FromText(EMBER_CURSE);
	CHECK(recipe ~= nil, "ember-curse.sf read");
	CHECK(recipe and #recipe.effects == 4, "ember-curse.sf: four effects");
	CHECK(recipe and #recipe.effects[2].links == 1 and #recipe.effects[2].links[1].effects == 2, "ember-curse.sf: the burn's link with two effects");
	CHECK(recipe and recipe.effects[4].on == "self", "ember-curse.sf: the buff is on the caster");
	local text = recipe and R.Text(recipe);
	local again = text and R.Text(R.FromText(text));
	CHECK(text and text == again, "ember-curse.sf: steady when written again");
	table.insert(FORGE_TEXTS, text or "");
end

-- 4. A name with quotes and a backslash
local odd = R.New();
odd.name = 'The "Big" one \\ more';
local back = R.FromText(R.Text(odd));
CHECK(back and back.name == odd.name, "a name with quotes comes back: " .. tostring(back and back.name));

-- 5. The window: shown, edited, previewed, answered
Mock.sent = {};
SlashCmdList["OURSFORGE"]();
CHECK(OursForgeFrame.shown, "/forge shows the window");
CHECK(Mock.sent[1] and Mock.sent[1].body == "L" and Mock.sent[1].prefix == "SFRG" and Mock.sent[1].target == "Test", "it asks for the character's spells");
Mock.type(OursForgeName, "Fire Lance");
Mock.wait(0.1);
CHECK(#Mock.sent == 1, "no preview while typing");
Mock.wait(0.5);
local preview = Mock.sent[#Mock.sent];
CHECK(preview and string.find(preview.body, "^P%d+:1:1:%(spell %(name \"Fire Lance\"%)"), "a preview is asked for: " .. tostring(preview and preview.body));
local req = preview and tonumber(string.match(preview.body, "^P(%d+):"));

Mock.receive("n" .. req .. ":a cast of 1.4 seconds is 1.5");
Mock.receive("p" .. req .. ":42:mana:1");
CHECK(OursForgeTooltip.link == "spell:1199984", "the preview's tooltip is the preview record: " .. tostring(OursForgeTooltip.link));
CHECK(OursForgeForge.enabled ~= false, "Forge can be pressed");

-- an old preview's answer is not taken
OursForgeTooltip.link = "none";   -- (not nil: the stand-in answers a missing key with a function)
Mock.receive("p" .. (req - 1) .. ":1:mana:1");
CHECK(OursForgeTooltip.link == "none", "an answer to an older preview is left alone");

-- an error
Mock.receive("e" .. req .. ":line 1: the spell does nothing");
CHECK(OursForgeForge.enabled == false, "after an error Forge cannot be pressed");

-- 6. Effects: kind changed, one added, a link stepped into and out of
-- the kinds come in groups that fit the screen, and every kind is in one
local groups, inGroups, longest = 0, {}, 0;
for _, info in ipairs(Mock.entries(OursForgeKind1)) do
	if ( info.hasArrow ) then
		groups = groups + 1;
		longest = math.max(longest, #info.inside);
		for _, inner in ipairs(info.inside) do inGroups[inner.value] = true; end
	end
end
local missing = {};
for _, kind in ipairs(R.KINDS) do if ( not inGroups[kind.key] ) then table.insert(missing, kind.key); end end
CHECK(groups >= 4 and longest <= 12, "the kinds in " .. groups .. " groups, " .. longest .. " at the most");
CHECK(#missing == 0, "every kind is in a group: " .. table.concat(missing, ", "));

-- every kind's numbers in a row: nothing over what comes after it, nothing over When..., nothing out of the form
local row1 = OursForgeFrame.effectRows[1];
local FORM_RIGHT = 596;           -- (the form's part of the window ends there)
local layouts = {};
for _, kind in ipairs(R.KINDS) do
	table.insert(layouts, { kind = kind });
	if ( kind.aura ) then table.insert(layouts, { kind = kind, on = "group" }); end
end
for _, layout in ipairs(layouts) do
	local kind = layout.kind;
	Mock.pick(OursForgeKind1, kind.key);
	if ( layout.on ) then Mock.pick(OursForgeOn1, layout.on); end
	local order = { row1.power, row1.as, row1.lowLabel, row1.low, row1.highLabel, row1.high, row1.aboveLabel, row1.above,
		row1.healthLabel, row1.health, row1.forLabel, row1.seconds, row1.alwaysLabel, row1.everyLabel, row1.every,
		row1.radiusLabel, row1.radius, row1.elites };
	local words = { [row1.lowLabel] = true, [row1.highLabel] = true, [row1.aboveLabel] = true, [row1.healthLabel] = true,
		[row1.forLabel] = true, [row1.alwaysLabel] = true, [row1.everyLabel] = true, [row1.radiusLabel] = true };
	local right, bad = nil, nil;
	for _, w in ipairs(order) do
		if ( w.shown ) then
			local left, width;
			if ( w == row1.power or w == row1.as ) then left, width = w.x + 16, w.layoutWidth - 16;
			elseif ( w == row1.elites ) then left, width = w.x, 22 + 36;
			elseif ( words[w] ) then left, width = w.x, w:GetStringWidth();
			else left, width = w.x - 5, w.width + 5; end              -- an edit box's frame reaches 5 to its left
			if ( right and left < right ) then bad = "something at " .. left .. " over what ends at " .. right; end
			right = left + width + 2;
		end
	end
	if ( row1.when.shown and right and right > row1.when.x ) then bad = "the numbers reach " .. right .. ", When... begins at " .. row1.when.x; end
	if ( right and right > FORM_RIGHT ) then bad = "the numbers reach " .. right .. ", past the form's edge at " .. FORM_RIGHT; end
	CHECK(not bad, kind.label .. (layout.on and (" on " .. layout.on) or "") .. ": " .. tostring(bad));
	if ( layout.on ) then Mock.pick(OursForgeOn1, "default"); end
end

-- what stands in the place of "on"
Mock.pick(OursForgeKind1, "summon_pet");
CHECK(OursForgeCreature1.shown and not OursForgeOn1.shown and OursForgeCreature1.text == "Choose creature...", "a pet: a creature to choose, in the place of on");
Mock.pick(OursForgeKind1, "shape_form");
CHECK(OursForgeForm1.shown and OursForgePower1.shown and OursForgeAs1.shown and not OursForgeOn1.shown, "a form: its form, what it spends and counts as");
Mock.pick(OursForgeKind1, "totem");
CHECK(OursForgeElement1.shown and OursForgeRadius1.shown and OursForgeWhen1.text == "Effects (1)", "a totem: its element, reach and effects");
Mock.pick(OursForgeKind1, "thrall");
CHECK(OursForgeAbove1.shown and OursForgeHealth1.shown and OursForgeElites1.shown and OursForgeOn1.shown, "a thrall: levels, health, elites");

Mock.pick(OursForgeKind1, "dot");
CHECK(OursForgeFor1.shown and OursForgeEvery1.shown and OursForgeWhen1.shown, "a damage over time has its length, ticks and When...");
CHECK(not OursForgeHigh1.shown, "and one amount");
OursForgeAdd.scripts.OnClick(OursForgeAdd);
CHECK(OursForgeKind2.shown, "Add effect adds a row");
OursForgeWhen1.scripts.OnClick(OursForgeWhen1);
Mock.pick(OursForgeWhenMenu, 1);
CHECK(OursForgeBack.shown, "in a link there is Back");
OursForgeAdd.scripts.OnClick(OursForgeAdd);
Mock.pick(OursForgeKind1, "slow");
OursForgeBack.scripts.OnClick(OursForgeBack);
CHECK(not OursForgeBack.shown, "back at the spell's effects");
Mock.wait(1);
preview = Mock.sent[#Mock.sent];
CHECK(preview and string.find(preview.body, "%(dot 10 %(for 12%) %(every 3%) %(when expire %(slow 40 %(for 6%)%)%)%)"),
	"the link is in the recipe: " .. tostring(preview and preview.body));

-- 7. A long recipe goes in parts
for i = 3, 8 do OursForgeAdd.scripts.OnClick(OursForgeAdd); end
Mock.type(OursForgeName, string.rep("Long Name ", 20));
Mock.sent = {};
Mock.wait(1);
local parts = {};
for _, m in ipairs(Mock.sent) do
	local n, total = string.match(m.body, "^P%d+:(%d+):(%d+):");
	if ( n ) then table.insert(parts, tonumber(total)); end
	CHECK(string.len(m.body) <= 250, "a part fits an addon message: " .. string.len(m.body));
end
CHECK(#parts >= 2 and #parts == parts[1], "the long recipe goes in " .. tostring(parts[1]) .. " part(s)");

-- 8. The list, and a crafted spell's recipe loaded
Mock.receive("l1000000:12:Fireball");
Mock.receive("l1000016:64:Ember Curse");
Mock.receive("L2");
CHECK(OursForgeSpell1.shown and OursForgeSpell2.shown and not OursForgeSpell3.shown, "two spells in the list");
Mock.sent = {};
OursForgeSpell2.scripts.OnClick(OursForgeSpell2);
CHECK(Mock.sent[1] and Mock.sent[1].body == "G1000016", "a click asks for its recipe");
if ( EMBER_CURSE ) then
	-- (as the server sends it: written anew, without its notes)
	local text = R.Text(R.FromText(EMBER_CURSE));
	local a, b = string.sub(text, 1, 150), string.sub(text, 151);
	Mock.receive("r1000016:2:2:" .. b);
	Mock.receive("r1000016:1:2:" .. a);
	CHECK(OursForgeName.text == "Ember Curse", "its recipe is in the form: " .. tostring(OursForgeName.text));
	CHECK(OursForgeKind4.shown and not OursForgeKind5.shown, "with its four effects");
end

-- 8b. A spell of yours in the form: Save forges it anew in its place, Save as new beside it
CHECK(OursForgeForge.text == "Save" and OursForgeSaveNew.shown, "a loaded spell is saved, not forged anew: " .. tostring(OursForgeForge.text));
Mock.type(OursForgeName, "Ember Curse");
Mock.sent = {};
OursForgeForge.scripts.OnClick(OursForgeForge);
CHECK(Mock.popups[#Mock.popups].which == "OURSFORGE_SAVE", "Save asks first");
StaticPopupDialogs.OURSFORGE_SAVE.OnAccept();
CHECK(Mock.sent[1] and string.find(Mock.sent[1].body, "^U1000016:%d+:1:%d+:%(spell"), "Save sends the spell's own number: " .. tostring(Mock.sent[1] and Mock.sent[1].body));
local saveReq = Mock.sent[1] and tonumber(string.match(Mock.sent[1].body, "^U%d+:(%d+):"));
Mock.sent = {};
Mock.receive("u" .. tostring(saveReq) .. ":1000016");
CHECK(Mock.sent[1] and Mock.sent[1].body == "L", "after saving the list is asked for anew");
CHECK(OursForgeForge.text == "Save", "and the form still holds that spell");
Mock.sent = {};
OursForgeSaveNew.scripts.OnClick(OursForgeSaveNew);
CHECK(Mock.popups[#Mock.popups].which == "OURSFORGE_FORGE", "Save as new asks first");
StaticPopupDialogs.OURSFORGE_FORGE.OnAccept();
CHECK(Mock.sent[1] and string.find(Mock.sent[1].body, "^F%d+:1:%d+:%(spell"), "Save as new forges a new one");
local newReq = Mock.sent[1] and tonumber(string.match(Mock.sent[1].body, "^F(%d+):"));
Mock.receive("f" .. tostring(newReq) .. ":1000032");
Mock.sent = {};
OursForgeForge.scripts.OnClick(OursForgeForge);
StaticPopupDialogs.OURSFORGE_SAVE.OnAccept();
CHECK(Mock.sent[1] and string.find(Mock.sent[1].body, "^U1000032:"), "after that, Save changes the new one");

-- back to Ember Curse, and forgotten
Mock.receive("r1000016:1:1:" .. R.Text(R.FromText(EMBER_CURSE or "(spell (name \"Ember Curse\") (damage 1))")));
Mock.sent = {};
OursForgeForget.scripts.OnClick(OursForgeForget);
CHECK(Mock.popups[#Mock.popups].which == "OURSFORGE_FORGET", "Forget asks first");
StaticPopupDialogs.OURSFORGE_FORGET.OnAccept();
CHECK(Mock.sent[1] and Mock.sent[1].body == "X1000016", "and forgets the one picked");
Mock.receive("x1000016");
CHECK(OursForgeForge.text == "Forge" and not OursForgeSaveNew.shown, "once forgotten, what is in the form is a new spell");

-- 9. Forge
Mock.sent = {};
OursForgeForge.scripts.OnClick(OursForgeForge);
StaticPopupDialogs.OURSFORGE_FORGE.OnAccept();
CHECK(Mock.sent[1] and string.find(Mock.sent[1].body, "^F%d+:1:%d+:%(spell"), "Forge sends the recipe");

-- 10. The icon picker
OursForgeIcon.scripts.OnClick(OursForgeIcon);
CHECK(OursForgeIconChoice1.shown and OursForgeIconChoice3.shown and not OursForgeIconChoice4.shown, "the picker shows the game's icons");
OursForgeIconChoice2.scripts.OnClick(OursForgeIconChoice2);
Mock.sent = {};
Mock.wait(1);
CHECK(Mock.sent[1] and string.find(Mock.sent[1].body, "%(icon 102%)"), "the icon picked is the recipe's");

-- 11. Works on: some kinds of creature, then every kind again
OursForgeFrame.newOne(false);
Mock.pick(OursForgeOnlyMenu, "beast");
Mock.pick(OursForgeOnlyMenu, "humanoid");
CHECK(OursForgeOnly.text == "Beast, Humanoid", "works on beasts and humanoids: " .. tostring(OursForgeOnly.text));
Mock.sent = {};
Mock.wait(1);
CHECK(Mock.sent[1] and string.find(Mock.sent[1].body, "%(only beast humanoid%)"), "and the recipe says so");
Mock.pick(OursForgeOnlyMenu, "any");
CHECK(OursForgeOnly.text == "Every kind", "every kind again");

-- 11b. Protections: immune to kinds of control ticked in a menu, written and read back
OursForgeFrame.newOne(false);
Mock.pick(OursForgeKind1, "immune");
CHECK(OursForgeMechanics1.shown and OursForgeMechanics1.text == "Stun", "an immunity is of stuns at first: " .. tostring(OursForgeMechanics1.text));
OursForgeMechanics1.scripts.OnClick(OursForgeMechanics1);
Mock.pick(OursForgeMechanicsMenu, "fear");
Mock.pick(OursForgeMechanicsMenu, "knockout");
CHECK(OursForgeMechanics1.text == "Stun, Fear, Incapacitate", "three kinds ticked: " .. tostring(OursForgeMechanics1.text));
Mock.pick(OursForgeMechanicsMenu, "stun");
CHECK(OursForgeMechanics1.text == "Fear, Incapacitate", "one unticked: " .. tostring(OursForgeMechanics1.text));
Mock.sent = {};
Mock.wait(1);
CHECK(Mock.sent[1] and string.find(Mock.sent[1].body, "%(immune fear knockout %(for 6%)%)"), "and the recipe says so: "
	.. tostring(Mock.sent[1] and Mock.sent[1].body));
do
	local back = R.FromText('(spell (name "Freed") (target self) (immune sap stun (for 4)) (break fear root) (tenacity silence 30 (for 0)) (immune magic (for 12)))');
	CHECK(back and back.effects[1].kind == "immune" and table.concat(back.effects[1].mechanics, ",") == "sap,stun", "an immunity's kinds read back");
	CHECK(back and back.effects[2].kind == "break" and table.concat(back.effects[2].mechanics, ",") == "fear,root", "a breaking free read back");
	CHECK(back and back.effects[3].kind == "tenacity" and back.effects[3].low == 30, "a shortening read back");
	CHECK(back and back.effects[4].kind == "immune_magic", "an immunity to magic read back");
	local text = back and R.Text(back) or "";
	CHECK(string.find(text, "%(immune stun sap %(for 4%)%)") and string.find(text, "%(break fear root%)"), "and written again: " .. text);
	table.insert(FORGE_TEXTS, text);
end

-- 11c. A spell that changes spells: its kind of spell in the place of "on", what it changes, the next so many
OursForgeFrame.newOne(false);
Mock.pick(OursForgeKind1, "modify_spells");
CHECK(OursForgeTag1.shown and OursForgeChange1.shown and OursForgeCharges1.shown and not OursForgeOn1.shown,
	"a change of spells: its kind of spell, what it changes and how many spells, no \"on\"");
Mock.pick(OursForgeTag1, "fire");
Mock.pick(OursForgeChange1, "cast-time");
Mock.type(OursForgeLow1, "-100");
Mock.type(OursForgeCharges1, "1");
Mock.sent = {};
Mock.wait(1);
CHECK(Mock.sent[1] and string.find(Mock.sent[1].body, "%(modify fire cast%-time %-100 %(charges 1%)"), "the recipe says so: "
	.. tostring(Mock.sent[1] and Mock.sent[1].body));
do
	local back = R.FromText('(spell (name "Focus") (target self) (modify (spells 1000016) crit 25 (charges 2)) '
		.. '(vulnerable over-time 20 (for 12)) (spell-haste 20 magic (for 15)) (threat -30 (for 10)))');
	CHECK(back and back.effects[1].kind == "modify_spells" and back.effects[1].change == "crit" and back.effects[1].charges == 2
		and back.effects[1].spells[1] == 1000016, "a change of a spell of yours read back");
	CHECK(back and back.effects[2].kind == "vulnerable" and back.effects[2].tag == "over-time" and back.effects[2].low == 20,
		"more damage from you read back");
	CHECK(back and back.effects[4].kind == "threat" and back.effects[4].low == -30, "threat read back");
	local text = back and R.Text(back) or "";
	CHECK(string.find(text, "%(modify %(spells 1000016%) crit 25 %(charges 2%)%)") and string.find(text, "%(vulnerable over%-time 20"),
		"and written again: " .. text);
	table.insert(FORGE_TEXTS, text);
end

-- 11d. Stealth and senses: what is tracked in the place of "on"; a stealth read back
OursForgeFrame.newOne(false);
Mock.pick(OursForgeKind1, "track");
CHECK(OursForgeTrack1.shown and not OursForgeOn1.shown, "tracking: what it finds in the place of \"on\"");
Mock.pick(OursForgeTrack1, "herbs");
Mock.sent = {};
Mock.wait(1);
CHECK(Mock.sent[1] and string.find(Mock.sent[1].body, "%(track herbs%)"), "the recipe says so: " .. tostring(Mock.sent[1] and Mock.sent[1].body));
Mock.pick(OursForgeKind1, "damage_versus");
local onlyTypes = true;
for _, item in ipairs(OursForgeTrack1.items) do if ( item.value == "herbs" ) then onlyTypes = false; end end
CHECK(OursForgeTrack1.shown and onlyTypes, "more damage to a type offers creature types only");
do
	local back = R.FromText('(spell (name "Shade") (target self) (cooldown 10) (stealth 5) (slow 30) (shape stealth) '
		.. '(see-stealth 30) (damage-versus demon 4))');
	CHECK(back and back.effects[1].kind == "stealth" and back.effects[3].kind == "shape_form" and back.effects[3].form == "stealth",
		"a stealth with its own bar read back");
	CHECK(back and back.effects[5].kind == "damage_versus" and back.effects[5].track == "demon" and back.effects[5].low == 4,
		"more damage to demons read back");
	local text = back and R.Text(back) or "";
	CHECK(string.find(text, "%(stealth 5%)") and string.find(text, "%(shape stealth%)")
		and string.find(text, "%(damage%-versus demon 4"), "and written again: " .. text);
	table.insert(FORGE_TEXTS, text);
end

-- 11e. Travel: a teleport home, or here (where the character stands); a mount that flies
OursForgeFrame.newOne(false);
Mock.pick(OursForgeKind1, "teleport");
CHECK(OursForgePlace1.shown and not OursForgeOn1.shown, "a teleport: where it goes in the place of \"on\"");
Mock.sent = {};
Mock.wait(1);
CHECK(Mock.sent[1] and string.find(Mock.sent[1].body, "%(teleport home%)"), "home at first: " .. tostring(Mock.sent[1] and Mock.sent[1].body));
SpellforgeWhereAmI = function () return 0, -9105.43, -1674.18, 112.61, 3.14159; end
Mock.pick(OursForgePlace1, "here");
Mock.sent = {};
Mock.wait(1);
CHECK(Mock.sent[1] and string.find(Mock.sent[1].body, "%(teleport 0 %-9105%.4 %-1674%.2 112%.6 3%.1%)"),
	"here is where the character stands: " .. tostring(Mock.sent[1] and Mock.sent[1].body));
CHECK(OursForgePlace1.menuText and string.find(OursForgePlace1.menuText, "Map 0"), "and the menu says the place: " .. tostring(OursForgePlace1.menuText));
SpellforgeWhereAmI = nil;
do
	local back = R.FromText('(spell (name "Away") (target self) (cast 10) (teleport 571 5804.1 624.7 647.8 1.6) '
		.. '(mount 18363 60 150) (water-walk (for 600)) (leap-back 20 7.5))');
	CHECK(back and back.effects[1].kind == "teleport" and back.effects[1].map == 571 and back.effects[1].home == false,
		"a teleport to a place read back");
	CHECK(back and back.effects[2].kind == "mount" and back.effects[2].creature == 18363 and back.effects[2].low == 60
		and back.effects[2].high == 150, "a flying mount read back");
	local text = back and R.Text(back) or "";
	CHECK(string.find(text, "%(teleport 571 5804%.1 624%.7 647%.8 1%.6%)") and string.find(text, "%(mount 18363 60 150%)")
		and string.find(text, "%(leap%-back 20 7%.5%)"), "and written again: " .. text);
	table.insert(FORGE_TEXTS, text);
end

-- 11f. Resurrection: picking one aims the spell at a friend; in combat; a stored soul with a cooldown
OursForgeFrame.newOne(false);
Mock.pick(OursForgeKind1, "resurrect");
CHECK(OursForgeInCombat1.shown and OursForgeHigh1.shown, "a resurrection: health, mana and \"in combat\"");
OursForgeInCombat1:SetChecked(true);
OursForgeInCombat1.scripts.OnClick(OursForgeInCombat1);
Mock.sent = {};
Mock.wait(1);
CHECK(Mock.sent[1] and string.find(Mock.sent[1].body, "%(target friend%)") and string.find(Mock.sent[1].body, "%(resurrect 500 500 %(in%-combat%)%)"),
	"aimed at a friend, also in combat: " .. tostring(Mock.sent[1] and Mock.sent[1].body));
do
	local back = R.FromText('(passive (name "Undying") (soulstone 20 (cooldown 1800)))');
	CHECK(back and back.effects[1].kind == "soulstone" and back.effects[1].low == 20 and back.effects[1].resEvery == 1800,
		"a stored soul with its cooldown read back");
	local text = back and R.Text(back) or "";
	CHECK(string.find(text, "%(soulstone 20 %(cooldown 1800%)%)"), "and written again: " .. text);
	table.insert(FORGE_TEXTS, text);
end

-- 11g. Conjuring: the server's list asked for once, an item picked from it
OursForgeFrame.newOne(false);
Mock.sent = {};
Mock.pick(OursForgeKind1, "conjure");
local askedFor = 0;
for _, m in ipairs(Mock.sent) do if ( m.body == "I" ) then askedFor = askedFor + 1; end end
CHECK(askedFor <= 1 and OursForgeItem1.shown and not OursForgeOn1.shown, "conjuring shows the item's menu (the list asked for once in the run: " .. askedFor .. " here)");
Mock.receive("i5350:5:Conjured Water");
Mock.receive("i5232:18:Minor Soulstone");
Mock.receive("j2");
CHECK(OursForgeItem1.menuText == "Choose an item", "nothing chosen yet: " .. tostring(OursForgeItem1.menuText));
local effect = nil;
for _, info in ipairs(Mock.entries(OursForgeItem1, 2, 1)) do
	if ( info.value == 5232 ) then info.func(info); end
end
CHECK(OursForgeItem1.menuText == "Minor Soulstone", "picked from the menu: " .. tostring(OursForgeItem1.menuText));
Mock.type(OursForgeLow1, "1");
Mock.sent = {};
Mock.wait(1);
CHECK(Mock.sent[1] and string.find(Mock.sent[1].body, "%(conjure 5232 1%)"), "the recipe says so: " .. tostring(Mock.sent[1] and Mock.sent[1].body));
Mock.sent = {};
Mock.pick(OursForgeKind1, "conjure");
local again = false;
for _, m in ipairs(Mock.sent) do if ( m.body == "I" ) then again = true; end end
CHECK(not again, "and not asked for again");

-- 11i. Resistances and imbues: a school's own kind, read wherever the school is written; an imbue from the server's list
do
	local back = R.FromText('(spell (name "Warding") (target friend) (range 30) (resist 30 frost (for 600)) (resist fire 20) '
		.. '(resist 10))');
	CHECK(back and back.effects[1].kind == "resist_frost" and back.effects[1].low == 30 and back.effects[2].kind == "resist_fire"
		and back.effects[3].kind == "resist", "resistances by school read back");
	local text = back and R.Text(back) or "";
	CHECK(string.find(text, "%(resist frost 30") and string.find(text, "%(resist fire 20") and string.find(text, "%(resist 10"),
		"and written again: " .. text);
end
OursForgeFrame.newOne(false);
Mock.sent = {};
Mock.pick(OursForgeKind1, "imbue");
local askedImbues = 0;
for _, m in ipairs(Mock.sent) do if ( m.body == "W" ) then askedImbues = askedImbues + 1; end end
CHECK(askedImbues <= 1 and OursForgeItem1.shown and not OursForgeOn1.shown and OursForgeItem1.menuText == "Choose an imbue",
	"an imbue shows the server's list, asked for: " .. askedImbues .. ", " .. tostring(OursForgeItem1.menuText));
Mock.receive("h283:30:Windfury 1");
Mock.receive("h5:10:Flametongue 1");
Mock.receive("H2");
local bands = {};
for _, info in ipairs(Mock.entries(OursForgeItem1, 1)) do if ( info.hasArrow ) then table.insert(bands, info.text); end end
CHECK(bands[1] == "Level 1-20" and bands[2] == "Level 21-40" and #bands == 2, "by bands of level: " .. table.concat(bands, ", "));
for _, info in ipairs(Mock.entries(OursForgeItem1, 2, 21)) do
	if ( info.value == 283 ) then info.func(info); end
end
CHECK(OursForgeItem1.menuText == "Windfury 1", "picked from the menu: " .. tostring(OursForgeItem1.menuText));
Mock.sent = {};
Mock.wait(1);
CHECK(Mock.sent[1] and string.find(Mock.sent[1].body, "%(imbue 283%)"), "the recipe says so: " .. tostring(Mock.sent[1] and Mock.sent[1].body));
Mock.pick(OursForgeKind1, "conjure");
CHECK(OursForgeItem1.menuText == "Choose an item", "and the conjure's list is its own: " .. tostring(OursForgeItem1.menuText));

-- 11h. Polymorph and drains: a creature's shape on an enemy, health and mana drained with what comes back
do
	local back = R.FromText('(spell (name "Toad") (target enemy) (range 30) (cast 1.5) (polymorph 13321 (for 20)) '
		.. '(drain 19 (every 3) (for 24) (heals 15)) (drain-mana 1 (every 2) (for 8) (gives 300)))');
	CHECK(back and back.effects[1].kind == "polymorph" and back.effects[1].creature == 13321 and back.effects[1].seconds == 20,
		"a polymorph read back");
	CHECK(back and back.effects[2].kind == "drain" and back.effects[2].share == 15 and back.effects[3].kind == "drain_mana"
		and back.effects[3].share == 300, "drains with what comes back read back");
	local text = back and R.Text(back) or "";
	CHECK(string.find(text, "%(polymorph 13321 %(for 20%)%)") and string.find(text, "%(heals 15%)") and string.find(text, "%(gives 300%)"),
		"and written again: " .. text);
	table.insert(FORGE_TEXTS, text);
end
OursForgeFrame.newOne(false);
Mock.pick(OursForgeKind1, "drain");
CHECK(OursForgeShare1.shown and OursForgeEvery1.shown, "a drain has its ticks and what of it heals");
Mock.type(OursForgeShare1, "50");
Mock.sent = {};
Mock.wait(1);
CHECK(Mock.sent[1] and string.find(Mock.sent[1].body, "%(heals 50%)"), "the recipe says so: " .. tostring(Mock.sent[1] and Mock.sent[1].body));

-- 12. A pet: the creature chooser asks the server, a creature is picked, the recipe names it
Mock.pick(OursForgeKind1, "summon_pet");
OursForgeCreature1.scripts.OnClick(OursForgeCreature1);
CHECK(OursForgeCreaturePicker.shown, "the creature chooser opens");
Mock.sent = {};
Mock.type(OursForgeCreatureSearch, "imp");
OursForgeCreaturePicker.scripts.OnUpdate(OursForgeCreaturePicker, 0);
CHECK(#Mock.sent == 0, "not while typing");
Mock.now = Mock.now + 0.5;
OursForgeCreaturePicker.scripts.OnUpdate(OursForgeCreaturePicker, 0);
local ask = Mock.sent[1] and Mock.sent[1].body;
CHECK(ask and string.find(ask, "^C%d+:imp$"), "it asks for creatures: " .. tostring(ask));
local creq = ask and string.match(ask, "^C(%d+):");
Mock.receive("c" .. tostring(creq) .. ":416:1:3:Imp");
Mock.receive("c" .. tostring(creq) .. ":12922:50:3:Imp Minion");
Mock.receive("k" .. tostring(creq) .. ":2");
CHECK(OursForgeCreatureChoice1.shown and OursForgeCreatureChoice2.shown and not OursForgeCreatureChoice3.shown, "two creatures found");
OursForgeCreatureChoice1.scripts.OnClick(OursForgeCreatureChoice1);
CHECK(not OursForgeCreaturePicker.shown and OursForgeCreature1.text == "Imp", "the one picked is the pet's: " .. tostring(OursForgeCreature1.text));
Mock.sent = {};
Mock.wait(1);
CHECK(Mock.sent[1] and string.find(Mock.sent[1].body, "%(summon%-pet 416%)"), "and the recipe names it: " .. tostring(Mock.sent[1] and Mock.sent[1].body));
-- an old search's answer is left alone
Mock.receive("c" .. tostring((tonumber(creq) or 0) - 1) .. ":99:1:1:Old");
CHECK(not OursForgeCreatureChoice3.shown, "an older search's answer is not shown");

-- 13. A recipe that names creatures: their names are asked for
Mock.sent = {};
Mock.receive("r1000048:1:1:(spell (name \"Pack\") (target self) (summon 29264 2 (for 30)))");
local asked = false;
for _, m in ipairs(Mock.sent) do if ( m.body == "Cn29264:#29264" ) then asked = true; end end
CHECK(asked, "the name of creature 29264 is asked for");
Mock.receive("cn29264:29264:80:1:Spirit Wolf");
Mock.receive("kn29264:1");
CHECK(OursForgeCreature1.text == "Spirit Wolf", "and shown: " .. tostring(OursForgeCreature1.text));

-- 14. A totem's own effects are stepped into, and the recipe holds them
Mock.pick(OursForgeKind1, "totem");
OursForgeWhen1.scripts.OnClick(OursForgeWhen1);
CHECK(OursForgeBack.shown and OursForgeKind1.shown, "into the totem's effects");
Mock.pick(OursForgeKind1, "heal");
OursForgeBack.scripts.OnClick(OursForgeBack);
Mock.sent = {};
Mock.wait(1);
CHECK(Mock.sent[1] and string.find(Mock.sent[1].body, "%(totem %(element fire%) %(for 30%) %(every 2%) %(radius 10%) %(heal 20 30%)%)"),
	"the totem heals around it: " .. tostring(Mock.sent[1] and Mock.sent[1].body));

-- 15. What it costs: the character's own, or what a form of theirs spends
OursForgeFrame.newOne(false);
Mock.receive("wmana,energy");
local costs = Mock.entries(OursForgeCost);
CHECK(#costs == 2 and costs[1].value == "mana" and costs[2].value == "energy", "own mana and a form's energy to choose from");
Mock.pick(OursForgeCost, "energy");
Mock.sent = {};
Mock.wait(1);
CHECK(Mock.sent[1] and string.find(Mock.sent[1].body, "%(power energy%)"), "a spell for the form costs energy: " .. tostring(Mock.sent[1] and Mock.sent[1].body));
local back = R.FromText(string.match(Mock.sent[1] and Mock.sent[1].body or "", "^P%d+:%d+:%d+:(.*)$") or "");
CHECK(back and back.power == "energy", "and reads back so");
Mock.pick(OursForgeCost, "mana");
Mock.sent = {};
Mock.wait(1);
CHECK(Mock.sent[1] and not string.find(Mock.sent[1].body, "%(power"), "its own resource is not written");

-- 16. Its look: a game spell of its kind by itself, or one picked
OursForgeFrame.newOne(false);
OursForgeLook.scripts.OnClick(OursForgeLook);
CHECK(OursForgeLookPicker.shown, "the look chooser opens");
Mock.type(OursForgeLookSearch, "fire");
Mock.now = Mock.now + 0.5;
OursForgeLookPicker.scripts.OnUpdate(OursForgeLookPicker, 0);
CHECK(OursForgeLookChoice1.shown and OursForgeLookChoice2.shown and not OursForgeLookChoice3.shown, "two spells to look like");
OursForgeLookChoice2.scripts.OnClick(OursForgeLookChoice2);
Mock.sent = {};
Mock.wait(1);
CHECK(Mock.sent[1] and string.find(Mock.sent[1].body, "%(look 2136%)"), "the look picked is in the recipe: " .. tostring(Mock.sent[1] and Mock.sent[1].body));
OursForgeLook.scripts.OnClick(OursForgeLook);
OursForgeLookAuto.scripts.OnClick(OursForgeLookAuto);
Mock.sent = {};
Mock.wait(1);
CHECK(Mock.sent[1] and not string.find(Mock.sent[1].body, "%(look"), "and back to the look of its kind");

-- 17. A buff for good, an aura on one's group, one at a time
do
	local recipe = R.New();
	recipe.name = "Devotion";
	recipe.target = "self";
	recipe.oneAtATime = true;
	local armor = R.NewEffect("armor"); armor.seconds = 0; armor.on = "group";
	local stamina = R.NewEffect("stat_stamina"); stamina.seconds = 0;
	recipe.effects = { armor, stamina };
	local text = R.Text(recipe);
	CHECK(not string.find(text, "%(for"), "lasting until cancelled: no length written: " .. text);
	CHECK(string.find(text, "%(armor 10 %(on group%)%)") and string.find(text, "%(one%-at%-a%-time%)"), "on one's group, one at a time: " .. text);
	local back = R.FromText(text);
	CHECK(back and R.Text(back) == text and back.oneAtATime == true, "and read back the same");
	table.insert(FORGE_TEXTS, text);
end
OursForgeFrame.newOne(false);
OursForgeOneAtATime:SetChecked(true);
OursForgeOneAtATime.scripts.OnClick(OursForgeOneAtATime);
Mock.sent = {};
Mock.wait(1);
CHECK(Mock.sent[1] and string.find(Mock.sent[1].body, "%(one%-at%-a%-time%)"), "the window's one at a time is in the recipe");
OursForgeOneAtATime:SetChecked(false);
OursForgeOneAtATime.scripts.OnClick(OursForgeOneAtATime);
Mock.sent = {};
Mock.wait(1);
CHECK(Mock.sent[1] and not string.find(Mock.sent[1].body, "one%-at%-a%-time"), "and taken out again");

-- 18. An aura on one's group reaches as far as it says
OursForgeFrame.newOne(false);
Mock.pick(OursForgeKind1, "armor");
CHECK(not OursForgeRadius1.shown, "no reach for a buff on the target");
Mock.pick(OursForgeOn1, "group");
CHECK(OursForgeRadius1.shown and OursForgeRadius1.text == "40", "on one's group: its reach, 40 at first: " .. tostring(OursForgeRadius1.text));
Mock.sent = {};
Mock.wait(1);
CHECK(Mock.sent[1] and string.find(Mock.sent[1].body, "%(on group%)") and not string.find(Mock.sent[1].body, "%(radius"), "40 is not written");
Mock.type(OursForgeRadius1, "100");
Mock.sent = {};
Mock.wait(1);
CHECK(Mock.sent[1] and string.find(Mock.sent[1].body, "%(on group%) %(radius 100%)"), "another reach is: " .. tostring(Mock.sent[1] and Mock.sent[1].body));
local back = R.FromText(string.match(Mock.sent[1] and Mock.sent[1].body or "", "^P%d+:%d+:%d+:(.*)$") or "");
CHECK(back and back.effects[1].reach == 100 and back.effects[1].on == "group", "and read back so");
table.insert(FORGE_TEXTS, back and R.Text(back) or "");

-- 19. A passive: its parts written and read back the same, and taken by the server
do
	local recipe = R.NewPassive();
	recipe.name = "Fire Mastery";
	local change = R.NewEffect("modify"); change.tag = "fire"; change.change = "crit"; change.low = 4;
	local crit = R.NewEffect("crit"); crit.low = 2;
	local onhit = R.NewEffect("onhit"); onhit.tag = "damage"; onhit.low = 10; onhit.inner = { R.NewEffect("slow") };
	local when = R.NewEffect("when_crit"); when.tag = "fire"; when.low = 30; when.seconds = 6; when.inner = { R.NewEffect("dot") };
	local shield = R.NewEffect("absorb"); shield.on = "self";
	local struck = R.NewEffect("when_struck"); struck.low = 10; struck.inner = { shield };
	local taken = R.NewEffect("damage-taken"); taken.low = 5;
	local group = R.NewEffect("armor"); group.on = "group";
	recipe.effects = { change, crit, onhit, when, struck, taken, group };
	local text = R.Text(recipe);
	CHECK(string.find(text, '^%(passive %(name "Fire Mastery"%) %(icon %d+%) %(modify fire crit 4%) %(crit 2%)'), "a passive's text: " .. text);
	CHECK(string.find(text, "%(on%-hit damage 10 %(slow 40 %(for 6%)%)%)"), "an on-hit with what it does, which has a length: " .. text);
	CHECK(string.find(text, "%(when crit 30 %(cooldown 6%) %(spells fire%) %(dot 10 %(for 12%) %(every 3%)%)%)"), "a when: " .. text);
	CHECK(string.find(text, "%(when struck 10 %(absorb 10 %(for 6%) %(on self%)%)%)"), "a when of anything: no spells named: " .. text);
	CHECK(string.find(text, "%(damage%-taken 5%)") and string.find(text, "%(armor 10 %(on group%)%)"), "what is always on has no length: " .. text);
	local back, dropped = R.FromText(text);
	CHECK(back and back.passive and R.Text(back) == text, "read back the same\n    " .. text .. "\n    " .. (back and R.Text(back) or ""));
	CHECK(back and #dropped == 0, "nothing left out");
	table.insert(FORGE_TEXTS, text);
	-- every part on its own
	for _, kind in ipairs(R.PARTS) do
		local one = R.NewPassive();
		one.name = "Part " .. kind.key;
		one.effects = { R.NewEffect(kind.key) };
		local t = R.Text(one);
		local b = R.FromText(t);
		CHECK(b and R.Text(b) == t, kind.key .. ": read back the same: " .. t);
		table.insert(FORGE_TEXTS, t);
	end
end

-- 20. The window's passive: New... offers both, a passive hides a spell's fields and has its parts
local newEntries = Mock.entries(OursForgeNewMenu);
CHECK(#newEntries == 2 and newEntries[1].text == "A spell" and newEntries[2].text == "A passive", "New... offers a spell or a passive");
newEntries[2].func();
CHECK(not OursForgeSpellPart.shown and OursForgeFrame.passiveText.shown, "a passive hides a spell's fields");
CHECK(OursForgeFrame.effectsTitle.text == "Parts" and OursForgeAdd.text == "Add part", "its effects are parts");
CHECK(OursForgeKind1.shown and OursForgeTag1.shown and OursForgeChange1.shown and not OursForgeOn1.shown, "a change: its kind of spell and what it changes");
do
	local labels = {};
	for _, info in ipairs(Mock.entries(OursForgeKind1)) do if ( info.hasArrow ) then table.insert(labels, info.text); end end
	CHECK(table.concat(labels, ",") == "Always on,Always on: combat,Always on: resistances,Always on: protection,Always on: speed,Always on: senses,Always on: travel,Your spells,When...", "a passive's kinds: " .. table.concat(labels, ","));
end
Mock.pick(OursForgeChange1, "cost");
Mock.pick(OursForgeTag1, "fire");
Mock.type(OursForgeLow1, "-10");
Mock.sent = {};
Mock.wait(1);
local passiveBody = Mock.sent[1] and Mock.sent[1].body or "";
CHECK(string.find(passiveBody, '^P%d+:1:1:%(passive %(name "New Passive"%)') and string.find(passiveBody, "%(modify fire cost %-10%)"),
	"its preview: " .. passiveBody);
local passiveReq = tonumber(string.match(passiveBody, "^P(%d+):"));
Mock.receive("s40:55");
CHECK(string.find(OursForgeFrame.passiveText.text, "40 of 55 taken, 15 left"), "the points: " .. tostring(OursForgeFrame.passiveText.text));
Mock.receive("p" .. tostring(passiveReq) .. ":12:points:1");
CHECK(string.find(OursForgeFrame.costText.text, "Takes 12 points of 15 left"), "what it takes: " .. tostring(OursForgeFrame.costText.text));
Mock.receive("p" .. tostring(passiveReq) .. ":20:points:1");
CHECK(string.find(OursForgeFrame.costText.text, "a00000"), "more than is left: in red: " .. tostring(OursForgeFrame.costText.text));

-- a "when": how often at most, and its effects stepped into, of what it may do
OursForgeAdd.scripts.OnClick(OursForgeAdd);
Mock.pick(OursForgeKind2, "when_crit");
CHECK(OursForgeWhen2.shown and OursForgeWhen2.text == "Effects (1)" and OursForgeFor2.shown, "a when: its effects and how often: " .. tostring(OursForgeWhen2.text));
CHECK(not OursForgeChange2.shown and OursForgeTag2.shown, "a when names a kind of spell, and changes nothing");
Mock.type(OursForgeFor2, "8");
OursForgeWhen2.scripts.OnClick(OursForgeWhen2);
CHECK(OursForgeBack.shown and OursForgeFrame.effectsTitle.text == "Effects", "stepped into what it does");
do
	local labels = {};
	for _, info in ipairs(Mock.entries(OursForgeKind1)) do if ( info.hasArrow ) then table.insert(labels, info.text); end end
	local joined = table.concat(labels, ",");
	CHECK(not string.find(joined, "Pets") and not string.find(joined, "Shapes") and string.find(joined, "Damage"), "what it may do: " .. joined);
	CHECK(OursForgeOn1.shown and not OursForgeTag1.shown, "an effect inside has its own whom");
end
Mock.pick(OursForgeKind1, "heal");
OursForgeBack.scripts.OnClick(OursForgeBack);
Mock.sent = {};
Mock.wait(1);
passiveBody = Mock.sent[1] and Mock.sent[1].body or "";
CHECK(string.find(passiveBody, "%(when crit 20 %(cooldown 8%) %(heal 20 30%)%)"), "the when in the recipe: " .. passiveBody);
table.insert(FORGE_TEXTS, string.match(passiveBody, "^P%d+:%d+:%d+:(.*)$") or "");

-- always on: no length
Mock.pick(OursForgeKind1, "stat_stamina");
CHECK(not OursForgeFor1.shown and not OursForgeWhen1.shown, "what is always on has no length and no links");

-- a passive in the list, and a spell again hides the passive's text
Mock.receive("a1000048:12:Fire Mastery");
Mock.receive("L1");
do
	local found = false;
	for i = 1, 16 do
		local b = _G["OursForgeSpell" .. i];
		if ( b.shown and b.id == 1000048 and string.find(b.text.text, "passive, 12 points") ) then found = true; end
	end
	CHECK(found, "a passive in the list, with its points");
end
OursForgeFrame.newOne(false);
CHECK(OursForgeSpellPart.shown and not OursForgeFrame.passiveText.shown and OursForgeFrame.effectsTitle.text == "Effects", "a spell has its fields again");

-- 21. A part names spells of yours (ticked, any number), or a kind again; a passive's rows stand under its text
OursForgeFrame.newOne(true);
Mock.receive("l1000096:20:Flame Lance");
Mock.receive("l1000112:30:Frost Lance");
Mock.receive("a1000128:12:Some Passive");
Mock.receive("L3");
do
	local offered, passiveOffered = 0, false;
	for _, info in ipairs(Mock.entries(OursForgeTag1)) do
		if ( info.value == 1000096 or info.value == 1000112 ) then offered = offered + 1; info.func({ value = info.value }); end
		if ( info.value == 1000128 ) then passiveOffered = true; end
	end
	CHECK(offered == 2 and not passiveOffered, "your spells are offered, your passives not");
end
CHECK(OursForgeTag1.menuText == "Spell 1000096, Spell 1000112", "the menu says the spells named: " .. tostring(OursForgeTag1.menuText));
Mock.sent = {};
Mock.wait(1);
local namedBody = Mock.sent[1] and Mock.sent[1].body or "";
CHECK(string.find(namedBody, "%(modify %(spells 1000096 1000112%) damage 5%)"), "the recipe names them: " .. namedBody);
do
	local text = string.match(namedBody, "^P%d+:%d+:%d+:(.*)$") or "";
	local back = R.FromText(text);
	CHECK(back and #back.effects[1].spells == 2 and R.Text(back) == text, "and is read back the same");
	table.insert(FORGE_TEXTS, text);
	local when = R.FromText('(passive (name "W") (icon 1) (when crit 20 (spells 1000096) (heal 5)) (on-hit (spells 1000112) 10 (slow 30 (for 4))))');
	CHECK(when and #when.effects[1].spells == 1 and #when.effects[2].spells == 1, "a when and an on-hit that name a spell are read");
	table.insert(FORGE_TEXTS, when and R.Text(when) or "");
end
Mock.pick(OursForgeTag1, "fire");
Mock.sent = {};
Mock.wait(1);
namedBody = Mock.sent[1] and Mock.sent[1].body or "";
CHECK(string.find(namedBody, "%(modify fire damage 5%)"), "a kind picked takes the spells' place: " .. namedBody);
CHECK(OursForgeKind1.y == -196 and OursForgeFrame.effectsTitle.y == -178, "a passive's parts stand under its text: " .. tostring(OursForgeKind1.y));
CHECK((OursForgeBack.x or 0) + 56 <= 596, "Back is inside the form");
OursForgeFrame.newOne(false);
CHECK(OursForgeKind1.y == -308, "a spell's effects stand where they did: " .. tostring(OursForgeKind1.y));

-- 22. A stat, armor or attack power by percent (a passive's and a spell's alike)
OursForgeFrame.newOne(true);
Mock.pick(OursForgeKind1, "stat_stamina");
CHECK(OursForgePercent1.shown and not OursForgeFor1.shown, "a stat has its percent tick");
OursForgePercent1:SetChecked(true);
OursForgePercent1.scripts.OnClick(OursForgePercent1);
Mock.type(OursForgeLow1, "10");
Mock.sent = {};
Mock.wait(1);
local pctBody = Mock.sent[1] and Mock.sent[1].body or "";
CHECK(string.find(pctBody, "%(stat stamina 10 %(percent%)%)"), "by percent in the recipe: " .. pctBody);
do
	local text = string.match(pctBody, "^P%d+:%d+:%d+:(.*)$") or "";
	local back = R.FromText(text);
	CHECK(back and back.effects[1].percent and R.Text(back) == text, "and read back the same");
	table.insert(FORGE_TEXTS, text);
	local spell = R.New();
	spell.target = "self";
	local ap = R.NewEffect("attack-power"); ap.percent = true; ap.low = 5;
	local armor = R.NewEffect("armor"); armor.percent = true;
	spell.effects = { ap, armor };
	local t = R.Text(spell);
	CHECK(string.find(t, "%(attack%-power 5 %(percent%) %(for 6%)%)"), "a spell's buff by percent: " .. t);
	table.insert(FORGE_TEXTS, t);
end
Mock.pick(OursForgeKind1, "spell-power");
CHECK(not OursForgePercent1.shown, "spell power has none");

-- the slots: spells and passives taken, of how many there may be; a full one stands out
Mock.receive("o3:5:2:2");
CHECK(string.find(OursForgeFrame.listTitle.text, "Spells 3/5") and string.find(OursForgeFrame.listTitle.text, "Passives |cffff8040" .. "2/2"),
	"the slots: " .. tostring(OursForgeFrame.listTitle.text));
Mock.receive("o9:x");
CHECK(string.find(OursForgeFrame.listTitle.text, "Spells 3/5"), "a garbled answer changes nothing");

-- a forged character's Talents button is the Spellforge's, there from level 1 on; N opens the forge
for _, name in ipairs({ "TalentMicroButton", "AchievementMicroButton", "SpellbookMicroButton" }) do Mock.newObject("Button", name); end
TalentMicroButton.SetButtonState = function (self, state) self.state = state; end
TalentMicroButton.CreateTexture = function (self, name) return Mock.newObject("Texture", name); end
TalentMicroButton.SetScript = function (self, what, f) self.scripts[what] = f; end
SpellforgeIsForged = function () return false; end
OursForgeFrame.forgeButton();
CHECK(not OursForgeFrame.forgeTurned(), "a character of the old make keeps its Talents button");
SpellforgeIsForged = function () return true; end
OursForgeFrame:Hide();
OursForgeFrame.forgeButton();
CHECK(OursForgeFrame.forgeTurned() and TalentMicroButton.minLevel == 1 and TalentMicroButton.shown, "a forged one's is the forge's, from level 1");
CHECK(TalentMicroButton.tooltipText == "Spellforge" and TalentMicroButton.state == "NORMAL", "named, not pressed: " .. tostring(TalentMicroButton.tooltipText));
OursForgeMicroIcon.SetAlpha = function (self, a) self.alpha = a; end
TalentMicroButton.scripts.OnClick(TalentMicroButton);
CHECK(OursForgeFrame.shown, "a click opens the forge");
OursForgeFrame.forgeButton();
CHECK(TalentMicroButton.state == "PUSHED" and OursForgeMicroIcon.alpha == 0.5, "pressed while it is open");
ToggleTalentFrame();
CHECK(not OursForgeFrame.shown, "N closes it again");
ToggleTalentFrame();
CHECK(OursForgeFrame.shown, "and opens it");
OursForgeFrame:Hide();

-- a buff on one's party and raid, its reach; a weapon strike by its own speed; written and read back
local R = OursForgeRecipe;
local party = R.FromText('(spell (name "Brilliance") (target self) (stat intellect 60 (for 3600) (on party) (radius 80)) (weapon 100 495 (unnormalized)))');
CHECK(party and party.effects[1].on == "party" and party.effects[1].reach == 80 and party.effects[2].unnormalized, "a party buff and an own-speed strike are read");
local again = R.Text(party);
CHECK(string.find(again, "%(on party%) %(radius 80%)") and string.find(again, "%(weapon 100 495 %(unnormalized%)%)"), "and written again: " .. again);
party.effects[1].reach = 100;
CHECK(not string.find(R.Text(party), "radius"), "100 yards is a party buff's own reach, not written");

-- a lasting effect's proc and a watch, read and written back; the When menu's events and the chance beside Add
local cheetah = R.FromText('(spell (name "Cheetah") (target self) (speed 30 (when struck 100 (slow 50 (for 4) (on self)))))');
CHECK(cheetah and cheetah.effects[1].links[1].event == "struck" and cheetah.effects[1].links[1].chance == 100, "a proc of a buff is read");
CHECK(string.find(R.Text(cheetah), "%(when struck 100 %(slow 50 %(for 4%) %(on self%)%)%)"), "and written again: " .. R.Text(cheetah));
local seal = R.FromText('(spell (name "Seal") (target self) (watch (for 30) (when hit 20 (cooldown 1) (damage 50 fire))))');
CHECK(seal and seal.effects[1].kind == "watch" and seal.effects[1].links[1].cooldown == 1, "a watch with a cooldown is read");
CHECK(string.find(R.Text(seal), "%(watch %(for 30%) %(when hit 20 %(cooldown 1%) %(damage 50%)%)%)"), "and written again (fire is the spell's own school): " .. R.Text(seal));

-- a builder and a finisher: combo points, the spell's (finisher), its effects' growth with points
local bite = R.FromText('(spell (name "Bite") (target enemy) (range melee) (finisher) (damage 14 30 (per-combo 36)) (stun (for 0.1) (per-combo-for 1)))');
CHECK(bite and bite.finisher and bite.effects[1].perCombo == 36 and bite.effects[2].perComboFor == 1, "a finisher and its growth are read");
local biteText = R.Text(bite);
CHECK(string.find(biteText, "%(finisher%)") and string.find(biteText, "%(damage 14 30 %(per%-combo 36%)%)") and string.find(biteText, "%(per%-combo%-for 1%)"),
	"and written again: " .. biteText);
table.insert(FORGE_TEXTS, biteText);
local strike = R.FromText('(spell (name "Strike") (target enemy) (range melee) (weapon 100 3) (combo-points 1))');
CHECK(strike and strike.effects[2].kind == "combo" and strike.effects[2].low == 1, "a builder's combo points are read");
table.insert(FORGE_TEXTS, R.Text(strike));
bite.finisher = nil;
CHECK(not string.find(R.Text(bite), "per%-combo"), "without (finisher) no growth is written");
