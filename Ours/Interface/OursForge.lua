-- Ours, not the game's (the World of Warcraft editor project): the Spellforge realm's forge window, where a player
-- crafts spells. Loaded by the client itself right after the game's own interface (OursForge.cpp), so it is part of
-- that interface and not an addon. Opened with /forge.
--
-- The window makes a RECIPE, the text the server's mod-spellforge makes spells of (its README has every word), and
-- talks to the server by whispering itself on the addon channel (prefix "SFRG"): each change asks for a preview,
-- which the server answers with the spell's records (OursSpellDB takes them, as numbers 1199984 on) and its cost;
-- the preview is the game's own spell tooltip of those records. "Forge" makes it a spell of the character's.
--
-- Two parts: OursForgeRecipe (the recipe's model, its text and back: nothing of the window) and the window.

------------------------------------------------------------------------------------------------------------------
-- The recipe

OursForgeRecipe = {};
local R = OursForgeRecipe;

R.PREVIEW_ID = 1199984;

R.SCHOOLS = { "physical", "holy", "fire", "nature", "frost", "shadow", "arcane" };
R.TARGETS = { "enemy", "friend", "self", "ground", "any" };
R.WHOM = { "default", "target", "self", "enemies", "allies", "group", "party" };
-- spells of one of these groups are one at a time (casting one ends its maker's others of the group)
R.ONE_AT_A_TIME = { "none", "aura", "armor", "seal", "stance" };
R.WHENS = { "expire", "dispelled", "dies" };
-- what a lasting effect watches for while it lasts: (when <event> <chance> [(cooldown s)] ...)
R.EVENTS = { "hit", "crit", "heal", "struck", "kill" };
R.EVENT_WORDS = { "Each time it deals damage", "Each time it crits", "Each time it heals", "Each time it is struck", "Each time it kills" };

-- The kinds of effect the window offers. word: the recipe's word; extra: the word after it (a stat, a power...);
-- amount: what its numbers are ("range" low and high, "one", "count", "two": low and high as two numbers, "none");
-- aura: lasts a while (needs a length); every: ticks; lock: its length is a lockout (interrupt).
R.KINDS = {
	{ key = "damage", label = "Damage", word = "damage", amount = "range" },
	{ key = "heal", label = "Heal", word = "heal", amount = "range" },
	{ key = "weapon", label = "Weapon strike", word = "weapon", amount = "two", lowLabel = "%", highLabel = "+", unnormalized = true },
	{ key = "dot", label = "Damage over time", word = "dot", amount = "one", aura = true, every = true, lowLabel = "a tick" },
	{ key = "hot", label = "Heal over time", word = "hot", amount = "one", aura = true, every = true, lowLabel = "a tick" },
	{ key = "absorb", label = "Absorb shield", word = "absorb", amount = "one", aura = true },
	{ key = "energize_mana", label = "Restore mana", word = "energize", extra = "mana", amount = "one" },
	{ key = "energize_rage", label = "Give rage", word = "energize", extra = "rage", amount = "one" },
	{ key = "energize_energy", label = "Give energy", word = "energize", extra = "energy", amount = "one" },
	{ key = "combo", label = "Combo points", word = "combo-points", amount = "one", lowLabel = "+" },
	{ key = "slow", label = "Slow", word = "slow", amount = "one", aura = true, lowLabel = "%" },
	{ key = "root", label = "Root", word = "root", amount = "none", aura = true },
	{ key = "stun", label = "Stun", word = "stun", amount = "none", aura = true },
	{ key = "silence", label = "Silence", word = "silence", amount = "none", aura = true },
	{ key = "fear", label = "Fear", word = "fear", amount = "none", aura = true },
	{ key = "disorient", label = "Disorient", word = "disorient", amount = "none", aura = true },
	{ key = "watch", label = "Watch (a proc)", word = "watch", amount = "none", aura = true },
	{ key = "disarm", label = "Disarm", word = "disarm", amount = "none", aura = true },
	{ key = "taunt", label = "Taunt", word = "taunt", amount = "none", aura = true },
	{ key = "interrupt", label = "Interrupt", word = "interrupt", amount = "none", lock = true },
	{ key = "knockback", label = "Knock back", word = "knockback", amount = "two", lowLabel = "away", highLabel = "up" },
	{ key = "charge", label = "Charge", word = "charge", amount = "none" },
	{ key = "dispel_magic", label = "Dispel magic", word = "dispel", extra = "magic", amount = "count" },
	{ key = "dispel_curse", label = "Remove curse", word = "dispel", extra = "curse", amount = "count" },
	{ key = "dispel_disease", label = "Cure disease", word = "dispel", extra = "disease", amount = "count" },
	{ key = "dispel_poison", label = "Cure poison", word = "dispel", extra = "poison", amount = "count" },
	{ key = "stat_strength", label = "Strength", word = "stat", extra = "strength", amount = "one", aura = true, percent = true, lowLabel = "by" },
	{ key = "stat_agility", label = "Agility", word = "stat", extra = "agility", amount = "one", aura = true, percent = true, lowLabel = "by" },
	{ key = "stat_stamina", label = "Stamina", word = "stat", extra = "stamina", amount = "one", aura = true, percent = true, lowLabel = "by" },
	{ key = "stat_intellect", label = "Intellect", word = "stat", extra = "intellect", amount = "one", aura = true, percent = true, lowLabel = "by" },
	{ key = "stat_spirit", label = "Spirit", word = "stat", extra = "spirit", amount = "one", aura = true, percent = true, lowLabel = "by" },
	{ key = "stat_all", label = "All stats", word = "stat", extra = "all", amount = "one", aura = true, percent = true, lowLabel = "by" },
	{ key = "armor", label = "Armor", word = "armor", amount = "one", aura = true, percent = true, lowLabel = "by" },
	{ key = "speed", label = "Run speed", word = "speed", amount = "one", aura = true, lowLabel = "%" },
	{ key = "attack-power", label = "Attack power", word = "attack-power", amount = "one", aura = true, percent = true, lowLabel = "by" },
	{ key = "spell-power", label = "Spell power", word = "spell-power", amount = "one", aura = true },
	{ key = "damage-done", label = "Damage done", word = "damage-done", amount = "one", aura = true, lowLabel = "%" },
	{ key = "crit", label = "Critical strike chance", word = "crit", amount = "one", aura = true, lowLabel = "%" },
	{ key = "haste", label = "Haste", word = "haste", amount = "one", aura = true, lowLabel = "%" },
	{ key = "hit", label = "Hit chance (attacks)", word = "hit", amount = "one", aura = true, lowLabel = "%" },
	{ key = "spell-hit", label = "Hit chance (spells)", word = "spell-hit", amount = "one", aura = true, lowLabel = "%" },
	{ key = "dodge", label = "Dodge", word = "dodge", amount = "one", aura = true, lowLabel = "%" },
	{ key = "parry", label = "Parry", word = "parry", amount = "one", aura = true, lowLabel = "%" },
	{ key = "block", label = "Block", word = "block", amount = "one", aura = true, lowLabel = "%" },
	{ key = "regen", label = "Mana every 5 sec.", word = "regen", amount = "one", aura = true },
	{ key = "health", label = "Health", word = "health", amount = "one", aura = true, lowLabel = "%" },
	{ key = "damage-taken", label = "Damage taken", word = "damage-taken", amount = "one", aura = true, lowLabel = "%" },
	{ key = "resist", label = "Resist all magic", word = "resist", amount = "one", aura = true },
	-- protections; mechanics: kinds of control are ticked (immune to, freed of, shortened)
	{ key = "immune_all", label = "Immune to all damage", word = "immune", extra = "all", amount = "none", aura = true },
	{ key = "immune_magic", label = "Immune to magic", word = "immune", extra = "magic", amount = "none", aura = true },
	{ key = "immune_physical", label = "Immune to physical", word = "immune", extra = "physical", amount = "none", aura = true },
	{ key = "immune", label = "Immune to control", word = "immune", amount = "none", aura = true, mechanics = true },
	{ key = "break", label = "Break free of control", word = "break", amount = "none", mechanics = true },
	{ key = "tenacity", label = "Shorter control", word = "tenacity", amount = "one", aura = true, mechanics = true, lowLabel = "%" },
	{ key = "reflect", label = "Reflect spells", word = "reflect", amount = "one", aura = true, lowLabel = "%" },
	{ key = "thorns", label = "Thorns", word = "thorns", amount = "one", aura = true },
	{ key = "mana_shield", label = "Mana shield", word = "mana-shield", amount = "one", aura = true },
	{ key = "share_damage", label = "Take its damage", word = "share-damage", amount = "one", aura = true, lowLabel = "%" },
	{ key = "pushback", label = "Less pushback", word = "pushback-resist", amount = "one", aura = true, lowLabel = "%" },
	-- what changes spells for a while: tagged: a kind of spell (or yours) in the place of "on"; changes: what of
	-- them; charges: gone after so many
	{ key = "modify_spells", label = "Change spells", word = "modify", amount = "one", aura = true, tagged = true, changes = true,
		charges = true, lowLabel = "%" },
	{ key = "spell_haste", label = "Casting speed", word = "spell-haste", amount = "one", aura = true, lowLabel = "%" },
	{ key = "attack_speed", label = "Attack speed", word = "attack-speed", amount = "one", aura = true, lowLabel = "%" },
	{ key = "melee_speed", label = "Melee speed", word = "melee-speed", amount = "one", aura = true, lowLabel = "%" },
	{ key = "power_cost", label = "Cost of spells", word = "power-cost", amount = "one", aura = true, lowLabel = "%" },
	{ key = "healing_taken", label = "Healing taken", word = "healing-taken", amount = "one", aura = true, lowLabel = "%" },
	{ key = "threat", label = "Threat", word = "threat", amount = "one", aura = true, lowLabel = "%" },
	{ key = "vulnerable", label = "More damage from you", word = "vulnerable", amount = "one", aura = true, tagged = true, lowLabel = "%" },
	-- pets, minds, summons: above: levels above you it may be; creature: a creature is chosen; lasting: lasts for good
	-- without a length; needsFor: needs one; totem: has effects of its own
	{ key = "tame", label = "Tame as a pet", word = "tame", amount = "none", above = true, elites = true },
	{ key = "thrall", label = "Take its mind for good", word = "thrall", amount = "none", above = true, health = true, elites = true },
	{ key = "charm", label = "Control it for a while", word = "charm", amount = "none", aura = true, above = true },
	{ key = "summon_pet", label = "Summon a pet", word = "summon-pet", amount = "none", creature = true, lasting = true },
	{ key = "summon", label = "Summon helpers", word = "summon", amount = "count", creature = true, needsFor = true, lowLabel = "how many" },
	{ key = "totem", label = "Place a totem", word = "totem", amount = "none", totem = true, needsFor = true, every = true },
	-- shapes: on yourself; what you spend in it and what you count as
	{ key = "shape_form", label = "Take a form", word = "shape", amount = "none", form = true, shape = true, lasting = true },
	{ key = "shape_creature", label = "Take a creature's shape", word = "shape", amount = "none", creature = true, shape = true, lasting = true },
};
R.FORMS = { "cat", "bear", "tree", "moonkin", "travel", "aquatic", "ghost-wolf", "shadow", "metamorphosis" };
R.FORM_LABELS = { "Cat", "Bear", "Tree of Life", "Moonkin", "Travel", "Aquatic", "Ghost Wolf", "Shadowform", "Metamorphosis" };
R.POWERS = { "keep", "mana", "rage", "energy" };
R.POWER_LABELS = { "Your own", "Mana", "Rage", "Energy" };
R.CREATURE_TYPES = { "beast", "dragonkin", "demon", "elemental", "giant", "undead", "humanoid", "critter", "mechanical" };
R.CREATURE_TYPE_LABELS = { "Beast", "Dragonkin", "Demon", "Elemental", "Giant", "Undead", "Humanoid", "Critter", "Mechanical" };
R.ELEMENTS = { "fire", "earth", "water", "air" };
-- The kinds of control (the game's mechanics) one may be immune to, freed of or have shortened
R.MECHANICS = { "stun", "fear", "root", "snare", "silence", "polymorph", "disorient", "charm", "sleep", "horror", "knockout",
	"sap", "disarm", "freeze", "banish", "shackle", "daze", "bleed", "grip" };
R.MECHANIC_LABELS = { "Stun", "Fear", "Root", "Slowing", "Silence", "Polymorph", "Disorient", "Charm", "Sleep", "Horror",
	"Incapacitate", "Sap", "Disarm", "Freeze", "Banish", "Shackle", "Daze", "Bleeding", "Grip" };
R.MECHANIC = {};
for i, m in ipairs(R.MECHANICS) do R.MECHANIC[m] = i; end
-- A passive's parts that are not effects: a change to one's spells of a kind, an "on hit" that adds effects to
-- them, and "when" something happens (part: what it is; trigger: has effects of its own, stepped into)
R.PARTS = {
	{ key = "modify", label = "Change your spells", word = "modify", amount = "one", part = "modify", lowLabel = "%" },
	{ key = "onhit", label = "Add to your spells", word = "on-hit", amount = "one", part = "onhit", trigger = true, lowLabel = "% chance" },
	{ key = "when_crit", label = "When you crit", word = "when", extra = "crit", amount = "one", part = "when", trigger = true, lowLabel = "% chance" },
	{ key = "when_hit", label = "When you deal damage", word = "when", extra = "hit", amount = "one", part = "when", trigger = true, lowLabel = "% chance" },
	{ key = "when_heal", label = "When you heal", word = "when", extra = "heal", amount = "one", part = "when", trigger = true, lowLabel = "% chance" },
	{ key = "when_struck", label = "When you are hit", word = "when", extra = "struck", amount = "one", part = "when", trigger = true, lowLabel = "% chance" },
	{ key = "when_kill", label = "When you kill", word = "when", extra = "kill", amount = "one", part = "when", trigger = true, lowLabel = "% chance" },
};
-- The kinds of spell a part goes with (the server's tags); "any" only for "when": anything, attacks too
R.TAGS = { "all", "damage", "heal", "over-time", "area", "control", "buff", "debuff", "instant", "channel", "melee", "missile",
	"absorb", "pet", "summon", "shape", "physical", "holy", "fire", "nature", "frost", "shadow", "arcane" };
R.TAG_LABELS = { "All your spells", "Damaging spells", "Healing spells", "Spells over time", "Area spells", "Spells of control",
	"Buffs", "Debuffs", "Instant spells", "Channelled spells", "Melee abilities", "Missiles", "Shields", "Pet spells", "Summons",
	"Shapes", "Physical spells", "Holy spells", "Fire spells", "Nature spells", "Frost spells", "Shadow spells", "Arcane spells" };
-- What a change changes
R.CHANGES = { "damage", "cost", "cast-time", "cooldown", "crit", "duration", "range", "radius", "crit-damage", "pushback" };
R.CHANGE_LABELS = { "Damage and healing", "Cost", "Cast time", "Cooldown", "Critical chance", "Duration", "Range", "Radius",
	"Critical damage", "Pushback" };

R.KIND = {};
for _, kind in ipairs(R.KINDS) do
	R.KIND[kind.key] = kind;
end
for _, kind in ipairs(R.PARTS) do
	R.KIND[kind.key] = kind;
end

-- The menu of kinds in groups (one list of them all is taller than the screen)
R.KIND_GROUPS = {
	{ label = "Damage and healing", keys = { "damage", "heal", "weapon", "dot", "hot", "absorb" } },
	{ label = "Power", keys = { "energize_mana", "energize_rage", "energize_energy", "combo" } },
	{ label = "Control", keys = { "slow", "root", "stun", "silence", "fear", "disorient", "disarm", "taunt", "interrupt", "knockback", "charge" } },
	{ label = "Removing", keys = { "dispel_magic", "dispel_curse", "dispel_disease", "dispel_poison" } },
	{ label = "Protection", keys = { "immune", "immune_all", "immune_magic", "immune_physical", "break", "tenacity", "reflect",
		"thorns", "mana_shield", "share_damage", "pushback" } },
	{ label = "Changing spells", keys = { "modify_spells", "spell_haste", "attack_speed", "melee_speed", "power_cost", "healing_taken",
		"threat", "vulnerable" } },
	{ label = "Buffs", keys = { "watch", "stat_strength", "stat_agility", "stat_stamina", "stat_intellect", "stat_spirit", "stat_all",
		"armor", "speed", "attack-power", "spell-power", "damage-done" } },
	{ label = "Combat", keys = { "crit", "haste", "hit", "spell-hit", "dodge", "parry", "block", "regen", "health", "damage-taken",
		"resist" } },
	{ label = "Pets and summons", keys = { "tame", "thrall", "charm", "summon_pet", "summon", "totem" } },
	{ label = "Shapes", keys = { "shape_form", "shape_creature" } },
};
-- A passive's own: what is always on, and its parts
R.PASSIVE_GROUPS = {
	{ label = "Always on", keys = { "stat_strength", "stat_agility", "stat_stamina", "stat_intellect", "stat_spirit", "stat_all",
		"armor", "speed", "attack-power", "spell-power", "damage-done" } },
	{ label = "Always on: combat", keys = { "crit", "haste", "hit", "spell-hit", "dodge", "parry", "block", "regen", "health",
		"damage-taken", "resist" } },
	{ label = "Always on: protection", keys = { "immune", "tenacity", "reflect", "thorns", "pushback" } },
	{ label = "Always on: speed", keys = { "spell_haste", "attack_speed", "melee_speed", "power_cost", "threat" } },
	{ label = "Your spells", keys = { "modify", "onhit" } },
	{ label = "When...", keys = { "when_crit", "when_hit", "when_heal", "when_struck", "when_kill" } },
};
-- What a passive's "on hit" or "when" may do (no pets, minds, shapes, totems or charges)
R.TRIGGER_GROUPS = {};
for _, group in ipairs(R.KIND_GROUPS) do
	if ( group.label ~= "Pets and summons" and group.label ~= "Shapes" ) then
		local keys = {};
		for _, key in ipairs(group.keys) do
			if ( key ~= "charge" ) then table.insert(keys, key); end
		end
		table.insert(R.TRIGGER_GROUPS, { label = group.label, keys = keys });
	end
end

function R.NewEffect (key)
	local kind = R.KIND[key] or R.KIND.damage;
	local effect = { kind = kind.key, low = 10, high = 10, on = "default", links = {} };
	if ( kind.amount == "range" ) then effect.low, effect.high = 20, 30; end
	if ( kind.amount == "count" ) then effect.low = 1; end
	if ( kind.key == "weapon" ) then effect.low, effect.high = 100, 0; end
	if ( kind.key == "combo" ) then effect.low, effect.high = 1, 1; end
	if ( kind.key == "knockback" ) then effect.low, effect.high = 15, 5; end
	if ( kind.key == "slow" ) then effect.low = 40; end
	if ( kind.mechanics ) then effect.mechanics = { kind.key == "break" and "fear" or "stun" }; end
	if ( kind.key == "tenacity" or kind.key == "share_damage" ) then effect.low = 20; end
	if ( kind.key == "pushback" ) then effect.low = 35; end
	if ( kind.key == "reflect" ) then effect.low = 100; end
	if ( kind.key == "mana_shield" ) then effect.low = 150; end
	if ( kind.tagged ) then effect.tag, effect.spells = "all", {}; end
	if ( kind.changes ) then effect.change, effect.low, effect.charges = "damage", 10, 0; end
	if ( kind.key == "spell_haste" or kind.key == "attack_speed" or kind.key == "melee_speed" ) then effect.low = 20; end
	if ( kind.key == "power_cost" or kind.key == "healing_taken" ) then effect.low = -20; end
	if ( kind.key == "threat" ) then effect.low = 50; end
	if ( kind.aura ) then effect.seconds = kind.every and 12 or 6; end
	if ( kind.every ) then effect.every = 3; end
	if ( kind.lock ) then effect.seconds = 4; end
	effect.above, effect.health, effect.elites, effect.outside = 0, 0, false, false;
	effect.creature, effect.form, effect.power, effect.as = 0, "cat", "keep", "none";
	effect.element, effect.radius = "fire", 10;
	if ( kind.key == "charm" ) then effect.seconds = 60; end
	if ( kind.lasting ) then effect.seconds = 0; end
	if ( kind.needsFor ) then effect.seconds = 30; end
	if ( kind.key == "summon" ) then effect.low = 1; end
	if ( kind.totem ) then effect.every = 2; effect.inner = { R.NewEffect("damage") }; end
	if ( kind.part ) then
		effect.tag = kind.part == "when" and "any" or (kind.part == "onhit" and "damage" or "all");
		effect.change = "damage";
		effect.low = kind.part == "modify" and 5 or (kind.part == "onhit" and 10 or 20);
		effect.high = effect.low;
		effect.seconds = 0;          -- a "when": at most every so many seconds (0: whenever)
		effect.spells = {};          -- or the spells of the character's it names (in the place of the kind)
		if ( kind.trigger ) then effect.inner = { R.NewEffect("damage") }; end
	end
	return effect;
end

-- A new passive
function R.NewPassive ()
	local recipe = R.New();
	recipe.name = "New Passive";
	recipe.passive = true;
	recipe.effects = { R.NewEffect("modify") };
	return recipe;
end

function R.New ()
	return {
		name = "New Spell", icon = 185, school = "fire", target = "enemy", range = 30, melee = false,
		cast = "cast", castSeconds = 1.5, cooldown = 0, shape = "single", radius = 8, around = "target", jumps = 2,
		speed = 0, only = {}, effects = { R.NewEffect("damage") },
	};
end

local function number (value)
	value = tonumber(value) or 0;
	if ( value == math.floor(value) ) then
		return tostring(value);
	end
	return (string.format("%.2f", value):gsub("0+$", ""):gsub("%.$", ""));
end

local function quote (text)
	return '"' .. tostring(text or ""):gsub("\\", "\\\\"):gsub('"', '\\"') .. '"';
end

local effectText;

-- The words of the kinds the generic rule does not write
local function specialText (effect, kind)
	local parts = { kind.word };
	local seconds = tonumber(effect.seconds) or 0;
	if ( kind.shape ) then
		table.insert(parts, kind.creature and number(effect.creature) or effect.form);
		if ( effect.power and effect.power ~= "keep" ) then table.insert(parts, "(power " .. effect.power .. ")"); end
		if ( effect.as and effect.as ~= "none" ) then table.insert(parts, "(as " .. effect.as .. ")"); end
		if ( seconds > 0 ) then table.insert(parts, "(for " .. number(seconds) .. ")"); end
	elseif ( kind.key == "summon_pet" ) then
		table.insert(parts, number(effect.creature));
		if ( seconds > 0 ) then table.insert(parts, "(for " .. number(seconds) .. ")"); end
	elseif ( kind.key == "summon" ) then
		table.insert(parts, number(effect.creature));
		table.insert(parts, number(effect.low));
		table.insert(parts, "(for " .. number(seconds) .. ")");
	elseif ( kind.totem ) then
		table.insert(parts, "(element " .. (effect.element or "fire") .. ")");
		table.insert(parts, "(for " .. number(seconds) .. ")");
		table.insert(parts, "(every " .. number(effect.every) .. ")");
		table.insert(parts, "(radius " .. number(effect.radius) .. ")");
		for _, inner in ipairs(effect.inner or {}) do
			table.insert(parts, effectText(inner));
		end
	else
		-- tame, thrall, charm
		if ( (tonumber(effect.above) or 0) ~= 0 ) then table.insert(parts, "(above " .. number(effect.above) .. ")"); end
		if ( kind.health and (tonumber(effect.health) or 0) > 0 ) then table.insert(parts, "(health " .. number(effect.health) .. ")"); end
		if ( kind.elites and effect.elites ) then table.insert(parts, "(elites)"); end
		if ( kind.key == "thrall" and effect.outside ) then table.insert(parts, "(outside-dungeons)"); end
		if ( kind.aura ) then table.insert(parts, "(for " .. number(seconds) .. ")"); end
		if ( effect.on and effect.on ~= "default" ) then table.insert(parts, "(on " .. effect.on .. ")"); end
	end
	return "(" .. table.concat(parts, " ") .. ")";
end

-- What a part names: "(spells <number>...)" for spells of the character's, else its kind
local function namedSpells (effect)
	local numbers = {};
	for _, id in ipairs(effect.spells or {}) do table.insert(numbers, number(id)); end
	return #numbers > 0 and ("(spells " .. table.concat(numbers, " ") .. ")") or nil;
end

-- A passive's part
local function partText (effect, kind)
	local parts = { kind.word };
	local named = namedSpells(effect);
	if ( kind.part == "modify" ) then
		table.insert(parts, named or effect.tag or "all");
		table.insert(parts, effect.change or "damage");
		table.insert(parts, number(effect.low));
		return "(" .. table.concat(parts, " ") .. ")";
	end
	if ( kind.part == "onhit" ) then
		table.insert(parts, named or effect.tag or "all");
	else
		table.insert(parts, kind.extra);
	end
	table.insert(parts, number(effect.low));
	if ( kind.part == "when" ) then
		if ( (tonumber(effect.seconds) or 0) > 0 ) then table.insert(parts, "(cooldown " .. number(effect.seconds) .. ")"); end
		if ( named ) then
			table.insert(parts, named);
		elseif ( effect.tag and effect.tag ~= "any" ) then
			table.insert(parts, "(spells " .. effect.tag .. ")");
		end
	end
	local noLength = R.NoLength;
	R.NoLength = nil;
	for _, inner in ipairs(effect.inner or {}) do
		table.insert(parts, effectText(inner));
	end
	R.NoLength = noLength;
	return "(" .. table.concat(parts, " ") .. ")";
end

effectText = function (effect)
	local kind = R.KIND[effect.kind];
	if ( not kind ) then
		return "";
	end
	if ( kind.part ) then
		return partText(effect, kind);
	end
	if ( kind.creature or kind.shape or kind.totem or kind.above ) then
		return specialText(effect, kind);
	end
	local parts = { kind.word };
	if ( kind.extra ) then
		table.insert(parts, kind.extra);
	end
	if ( kind.tagged ) then
		table.insert(parts, namedSpells(effect) or effect.tag or "all");
	end
	if ( kind.changes ) then
		table.insert(parts, effect.change or "damage");
	end
	if ( kind.mechanics ) then
		local any = false;
		for _, m in ipairs(R.MECHANICS) do
			for _, had in ipairs(effect.mechanics or {}) do
				if ( had == m ) then table.insert(parts, m); any = true; end
			end
		end
		if ( not any ) then table.insert(parts, "stun"); end
	end
	local low, high = tonumber(effect.low) or 0, tonumber(effect.high) or 0;
	if ( kind.amount == "range" ) then
		table.insert(parts, number(low));
		if ( high > low ) then
			table.insert(parts, number(high));
		end
	elseif ( kind.amount == "one" or kind.amount == "count" ) then
		table.insert(parts, number(low));
	elseif ( kind.amount == "two" ) then
		table.insert(parts, number(low));
		if ( high ~= 0 ) then
			table.insert(parts, number(high));
		end
	end
	-- a stat, armor or attack power by percent
	if ( kind.percent and effect.percent ) then
		table.insert(parts, "(percent)");
	end
	if ( kind.charges and (tonumber(effect.charges) or 0) > 0 ) then
		table.insert(parts, "(charges " .. number(effect.charges) .. ")");
	end
	-- a weapon strike by the weapon's own speed (Heroic Strike), not normalized to its kind
	if ( kind.unnormalized and effect.unnormalized ) then
		table.insert(parts, "(unnormalized)");
	end
	-- a finisher's: more, and longer, for each combo point spent
	if ( R.Finisher and kind.amount ~= "none" and kind.key ~= "combo" and (tonumber(effect.perCombo) or 0) ~= 0 ) then
		table.insert(parts, "(per-combo " .. number(effect.perCombo) .. ")");
	end
	if ( R.Finisher and kind.aura and (tonumber(effect.perComboFor) or 0) > 0 ) then
		table.insert(parts, "(per-combo-for " .. number(effect.perComboFor) .. ")");
	end
	if ( kind.lock ) then
		table.insert(parts, "(lock " .. number(effect.seconds) .. ")");
	elseif ( kind.aura and (tonumber(effect.seconds) or 0) > 0 and not R.NoLength ) then
		-- (without a length it lasts until cancelled, or as long as the spell's shape; a passive's always)
		table.insert(parts, "(for " .. number(effect.seconds) .. ")");
	end
	if ( kind.every ) then
		table.insert(parts, "(every " .. number(effect.every) .. ")");
	end
	if ( effect.on and effect.on ~= "default" ) then
		table.insert(parts, "(on " .. effect.on .. ")");
	end
	-- an aura on one's group: how far it reaches, if not the 40 yards of Devotion Aura
	if ( effect.on == "group" and (tonumber(effect.reach) or 40) ~= 40 ) then
		table.insert(parts, "(radius " .. number(effect.reach) .. ")");
	end
	-- a buff on one's party and raid: how far it reaches, if not the 100 yards of Arcane Brilliance
	if ( effect.on == "party" and (tonumber(effect.reach) or 100) ~= 100 ) then
		table.insert(parts, "(radius " .. number(effect.reach) .. ")");
	end
	if ( kind.aura and not R.NoLength ) then
		for _, link in ipairs(effect.links or {}) do
			if ( #link.effects > 0 ) then
				local inner = { "when", link.when };
				if ( link.event ) then
					inner = { "when", link.event, number(tonumber(link.chance) or 100) };
					if ( (tonumber(link.cooldown) or 0) > 0 ) then table.insert(inner, "(cooldown " .. number(link.cooldown) .. ")"); end
				end
				for _, other in ipairs(link.effects) do
					table.insert(inner, effectText(other));
				end
				table.insert(parts, "(" .. table.concat(inner, " ") .. ")");
			end
		end
	end
	return "(" .. table.concat(parts, " ") .. ")";
end

-- Whether a recipe's effects have a shape that lasts until cancelled
local function lastingShape (recipe)
	for _, effect in ipairs(recipe.effects) do
		if ( R.KIND[effect.kind] and R.KIND[effect.kind].shape and (tonumber(effect.seconds) or 0) <= 0 ) then return true; end
	end
	return false;
end

-- The recipe's text, on one line
function R.Text (recipe)
	if ( recipe.passive ) then
		-- a passive: its name and icon, and its parts; what is always on has no length
		local parts = { "passive", "(name " .. quote(recipe.name) .. ")", "(icon " .. number(recipe.icon) .. ")" };
		R.Finisher = nil;
		for _, effect in ipairs(recipe.effects) do
			R.NoLength = true;
			table.insert(parts, effectText(effect));
			R.NoLength = nil;
		end
		return "(" .. table.concat(parts, " ") .. ")";
	end
	R.LastingShape = lastingShape(recipe);
	R.Finisher = recipe.finisher and true or nil;
	local parts = { "spell", "(name " .. quote(recipe.name) .. ")", "(icon " .. number(recipe.icon) .. ")",
		"(school " .. recipe.school .. ")", "(target " .. recipe.target .. ")" };
	local only = {};
	for _, t in ipairs(R.CREATURE_TYPES) do
		if ( recipe.only and recipe.only[t] ) then table.insert(only, t); end
	end
	if ( #only > 0 ) then table.insert(parts, "(only " .. table.concat(only, " ") .. ")"); end
	if ( recipe.oneAtATime ) then table.insert(parts, "(one-at-a-time)"); end
	if ( recipe.finisher ) then table.insert(parts, "(finisher)"); end
	-- the game's spell whose look it takes, if not the one the forge chooses by what it does
	if ( (tonumber(recipe.look) or 0) > 0 ) then table.insert(parts, "(look " .. number(recipe.look) .. ")"); end
	-- what it costs, if not the maker's own resource (one a form of theirs spends)
	if ( recipe.power ) then table.insert(parts, "(power " .. recipe.power .. ")"); end
	if ( recipe.target ~= "self" ) then
		table.insert(parts, recipe.melee and "(range melee)" or "(range " .. number(recipe.range) .. ")");
	end
	if ( recipe.cast == "cast" and (tonumber(recipe.castSeconds) or 0) > 0 ) then
		table.insert(parts, "(cast " .. number(recipe.castSeconds) .. ")");
	elseif ( recipe.cast == "channel" ) then
		table.insert(parts, "(channel " .. number(recipe.castSeconds) .. ")");
	end
	if ( (tonumber(recipe.cooldown) or 0) > 0 ) then
		table.insert(parts, "(cooldown " .. number(recipe.cooldown) .. ")");
	end
	if ( recipe.shape == "area" ) then
		local around = recipe.around;
		if ( recipe.target == "ground" ) then around = "ground"; elseif ( recipe.target == "self" ) then around = "caster"; end
		table.insert(parts, "(area " .. number(recipe.radius) .. " around " .. around .. ")");
	elseif ( recipe.shape == "cone" ) then
		table.insert(parts, "(cone " .. number(recipe.radius) .. ")");
	elseif ( recipe.shape == "chain" ) then
		table.insert(parts, "(chain " .. number(recipe.jumps) .. ")");
	end
	if ( (tonumber(recipe.speed) or 0) > 0 ) then
		table.insert(parts, "(missile " .. number(recipe.speed) .. ")");
	end
	for _, effect in ipairs(recipe.effects) do
		table.insert(parts, effectText(effect));
	end
	R.LastingShape = nil;
	return "(" .. table.concat(parts, " ") .. ")";
end

-- The recipe's text read: lists in brackets, words and "strings". Returns the items, or nil and why.
function R.Read (text)
	local at, length = 1, string.len(text);
	local function skip ()
		while ( at <= length ) do
			local c = string.sub(text, at, at);
			if ( c == ";" ) then
				while ( at <= length and string.sub(text, at, at) ~= "\n" ) do at = at + 1; end
			elseif ( c == " " or c == "\t" or c == "\n" or c == "\r" ) then
				at = at + 1;
			else
				return;
			end
		end
	end
	local item;
	item = function ()
		skip();
		local c = string.sub(text, at, at);
		if ( c == "" ) then return nil, "the text ends early"; end
		if ( c == ")" ) then return nil, "a ')' that closes nothing"; end
		if ( c == "(" ) then
			at = at + 1;
			local list = { list = true };
			while ( true ) do
				skip();
				local d = string.sub(text, at, at);
				if ( d == "" ) then return nil, "a list is never closed"; end
				if ( d == ")" ) then at = at + 1; return list; end
				local child, why = item();
				if ( not child ) then return nil, why; end
				table.insert(list, child);
			end
		end
		if ( c == '"' ) then
			at = at + 1;
			local out = {};
			while ( at <= length and string.sub(text, at, at) ~= '"' ) do
				local d = string.sub(text, at, at);
				if ( d == "\\" ) then at = at + 1; d = string.sub(text, at, at); end
				table.insert(out, d);
				at = at + 1;
			end
			if ( at > length ) then return nil, "a string is never closed"; end
			at = at + 1;
			return { string = table.concat(out) };
		end
		local start = at;
		while ( at <= length and not string.find(string.sub(text, at, at), "[%s%(%)\";]") ) do at = at + 1; end
		return { word = string.sub(text, start, at - 1) };
	end
	local top, why = item();
	if ( not top ) then return nil, why; end
	return top;
end

local function wordOf (node) return node and (node.word or node.string); end
local function numberOf (node) return node and tonumber(node.word); end

local readEffect;
readEffect = function (node, dropped)
	local word = wordOf(node[1]);
	local extra = wordOf(node[2]);
	local kind;
	if ( word == "shape" ) then
		kind = R.KIND[numberOf(node[2]) and "shape_creature" or "shape_form"];
	end
	for _, k in ipairs(R.KINDS) do
		if ( not kind and k.word == word and (not k.extra or k.extra == extra) ) then
			kind = k;
			break;
		end
	end
	if ( not kind ) then
		table.insert(dropped, "(" .. tostring(word) .. " ...)");
		return nil;
	end
	local effect = R.NewEffect(kind.key);
	effect.low, effect.high = nil, nil;
	if ( kind.totem ) then effect.inner = {}; end
	if ( kind.aura or kind.lasting ) then effect.seconds = 0; end     -- (what it says, or none: lasting as its shape)
	local numbers = {};
	local from = 2;
	-- a kind of spell, or (spells ...) of the character's, first; then what of them a change changes
	if ( kind.tagged ) then
		local first = node[2];
		if ( first and first.list and wordOf(first[1]) == "spells" ) then
			effect.spells = {};
			for j = 2, #first do
				local n = numberOf(first[j]);
				if ( n ) then table.insert(effect.spells, n); else effect.tag = wordOf(first[j]) or effect.tag; end
			end
			from = 3;
		elseif ( first and not first.list and not tonumber(first.word) ) then
			effect.tag = wordOf(first) or "all";
			from = 3;
		end
	end
	if ( kind.changes ) then
		effect.change = wordOf(node[from]) or "damage";
		from = from + 1;
	end
	for i = from, #node do
		local child = node[i];
		if ( child.list ) then
			local key = wordOf(child[1]);
			local isEffect = false;
			for _, k in ipairs(R.KINDS) do if ( k.word == key ) then isEffect = true; end end
			if ( kind.totem and isEffect ) then
				local inner = readEffect(child, dropped);
				if ( inner ) then table.insert(effect.inner, inner); end
			elseif ( key == "above" ) then effect.above = numberOf(child[2]) or 0;
			elseif ( key == "health" ) then effect.health = numberOf(child[2]) or 0;
			elseif ( key == "elites" ) then effect.elites = true;
			elseif ( key == "percent" ) then effect.percent = true;
			elseif ( key == "unnormalized" ) then effect.unnormalized = true;
			elseif ( key == "charges" and kind.charges ) then effect.charges = numberOf(child[2]) or 0;
			elseif ( key == "per-combo" ) then effect.perCombo = numberOf(child[2]) or 0;
			elseif ( key == "per-combo-for" ) then effect.perComboFor = numberOf(child[2]) or 0;
			elseif ( key == "outside-dungeons" ) then effect.outside = true;
			elseif ( key == "power" ) then effect.power = wordOf(child[2]) or "keep";
			elseif ( key == "as" ) then effect.as = wordOf(child[2]) or "none";
			elseif ( key == "element" ) then effect.element = wordOf(child[2]) or "fire";
			elseif ( key == "radius" and kind.totem ) then effect.radius = numberOf(child[2]) or 10;
			elseif ( key == "radius" ) then effect.reach = numberOf(child[2]) or 40;
			elseif ( key == "for" or key == "lock" ) then effect.seconds = numberOf(child[2]);
			elseif ( key == "every" ) then effect.every = numberOf(child[2]);
			elseif ( key == "on" ) then effect.on = wordOf(child[2]);
			elseif ( key == "when" ) then
				local link = { when = wordOf(child[2]), effects = {} };
				local from = 3;
				for _, event in ipairs(R.EVENTS) do
					if ( link.when == event ) then
						link = { event = event, chance = numberOf(child[3]) or 100, cooldown = 0, effects = {} };
						from = 4;
						if ( child[4] and child[4].list and wordOf(child[4][1]) == "cooldown" ) then
							link.cooldown = numberOf(child[4][2]) or 0;
							from = 5;
						end
					end
				end
				for j = from, #child do
					local inner = readEffect(child[j], dropped);
					if ( inner ) then table.insert(link.effects, inner); end
				end
				table.insert(effect.links, link);
			else
				table.insert(dropped, "(" .. tostring(key) .. " ...) in " .. kind.label);
			end
		elseif ( tonumber(child.word) ) then
			table.insert(numbers, tonumber(child.word));
		elseif ( kind.form and child.word ) then
			effect.form = child.word;
		elseif ( kind.mechanics and child.word and R.MECHANIC[child.word] ) then
			if ( not effect.readMechanics ) then effect.mechanics = {}; effect.readMechanics = true; end
			table.insert(effect.mechanics, child.word);
		end
	end
	if ( kind.creature ) then
		-- the creature, then (summon) how many
		effect.creature = table.remove(numbers, 1) or 0;
	end
	if ( kind.lasting ) then effect.seconds = effect.seconds or 0; end
	if ( kind.amount == "range" ) then
		effect.low = numbers[1] or 1;
		effect.high = numbers[2] or effect.low;
	elseif ( kind.amount == "two" ) then
		effect.low = numbers[1] or (kind.key == "weapon" and 100 or 15);
		effect.high = numbers[2] or 0;
	elseif ( kind.amount ~= "none" ) then
		effect.low = numbers[1] or 1;
		effect.high = effect.low;
	else
		effect.low, effect.high = 0, 0;
		if ( numbers[1] and (kind.aura or kind.lock) ) then effect.seconds = numbers[1]; end
	end
	effect.readMechanics = nil;
	return effect;
end

-- A passive's part read
local function readPart (node, dropped)
	local word = wordOf(node[1]);
	local kind;
	if ( word == "modify" ) then
		kind = R.KIND.modify;
	elseif ( word == "on-hit" ) then
		kind = R.KIND.onhit;
	else
		kind = R.KIND["when_" .. tostring(wordOf(node[2]))];
	end
	if ( not kind ) then
		table.insert(dropped, "(" .. tostring(word) .. " " .. tostring(wordOf(node[2])) .. " ...)");
		return nil;
	end
	local effect = R.NewEffect(kind.key);
	-- a kind, or (spells ...) with spells of the character's by their number (or a kind: the window has one of
	-- the two)
	local function which (item, otherwise)
		if ( item and item.list and wordOf(item[1]) == "spells" ) then
			local tag;
			for j = 2, #item do
				local n = numberOf(item[j]);
				if ( n ) then table.insert(effect.spells, n); elseif ( wordOf(item[j]) ) then tag = tag or wordOf(item[j]); end
			end
			if ( #effect.spells > 0 and tag ) then table.insert(dropped, "a kind of spell beside the spells named"); end
			effect.tag = (#effect.spells > 0) and otherwise or (tag or otherwise);
		else
			effect.tag = wordOf(item) or otherwise;
		end
	end
	if ( kind.part == "modify" ) then
		which(node[2], "all");
		effect.change = wordOf(node[3]) or "damage";
		effect.low = numberOf(node[4]) or 5;
		effect.high = effect.low;
		return effect;
	end
	if ( kind.part == "onhit" ) then which(node[2], "all"); else effect.tag = "any"; end
	effect.low = numberOf(node[3]) or 100;
	effect.high = effect.low;
	effect.inner = {};
	for i = 4, #node do
		local child = node[i];
		local key = child.list and wordOf(child[1]);
		if ( key == "cooldown" ) then effect.seconds = numberOf(child[2]) or 0;
		elseif ( key == "spells" ) then which(child, "any");
		elseif ( child.list ) then
			local inner = readEffect(child, dropped);
			if ( inner ) then table.insert(effect.inner, inner); end
		end
	end
	return effect;
end

-- A recipe from its text. Returns the recipe and a list of what the window has no place for (left out), or nil and why.
function R.FromText (text)
	local top, why = R.Read(text);
	if ( not top ) then return nil, why; end
	if ( top.list and wordOf(top[1]) == "passive" ) then
		local recipe = R.NewPassive();
		recipe.effects = {};
		local dropped = {};
		for i = 2, #top do
			local node = top[i];
			local key = node.list and wordOf(node[1]);
			if ( key == "name" ) then recipe.name = wordOf(node[2]) or "";
			elseif ( key == "icon" ) then recipe.icon = numberOf(node[2]) or 1;
			elseif ( key == "modify" or key == "on-hit" or key == "when" ) then
				local part = readPart(node, dropped);
				if ( part ) then table.insert(recipe.effects, part); end
			elseif ( node.list ) then
				local effect = readEffect(node, dropped);
				if ( effect ) then effect.seconds = 0; table.insert(recipe.effects, effect); end
			end
		end
		return recipe, dropped;
	end
	if ( not top.list or wordOf(top[1]) ~= "spell" ) then return nil, "a recipe is (spell ...) or (passive ...)"; end
	local recipe = R.New();
	recipe.effects = {};
	recipe.cast, recipe.castSeconds, recipe.cooldown, recipe.shape, recipe.speed = "instant", 0, 0, "single", 0;
	local dropped = {};
	local rangeGiven = false;
	for i = 2, #top do
		local node = top[i];
		local key = node.list and wordOf(node[1]);
		local value = node.list and node[2];
		if ( key == "name" ) then recipe.name = wordOf(value) or "";
		elseif ( key == "icon" ) then recipe.icon = numberOf(value) or 1;
		elseif ( key == "school" ) then recipe.school = wordOf(value);
		elseif ( key == "target" ) then recipe.target = wordOf(value);
		elseif ( key == "range" ) then
			rangeGiven = true;
			if ( wordOf(value) == "melee" ) then recipe.melee = true; else recipe.melee = false; recipe.range = numberOf(value) or 30; end
		elseif ( key == "cast" ) then
			if ( wordOf(value) == "instant" ) then recipe.cast = "instant"; else recipe.cast = "cast"; recipe.castSeconds = numberOf(value) or 0; end
		elseif ( key == "channel" ) then recipe.cast = "channel"; recipe.castSeconds = numberOf(value) or 1;
		elseif ( key == "cooldown" ) then recipe.cooldown = numberOf(value) or 0;
		elseif ( key == "missile" or (key == "speed" and #node == 2 and numberOf(value)) ) then recipe.speed = numberOf(value) or 0;
		elseif ( key == "area" ) then
			recipe.shape = "area";
			recipe.radius = numberOf(value) or 8;
			if ( wordOf(node[3]) == "around" ) then recipe.around = wordOf(node[4]) or "target"; end
		elseif ( key == "cone" ) then recipe.shape = "cone"; recipe.radius = numberOf(value) or 10;
		elseif ( key == "chain" ) then recipe.shape = "chain"; recipe.jumps = numberOf(value) or 2;
		elseif ( key == "power" ) then recipe.power = wordOf(value);
		elseif ( key == "look" ) then recipe.look = numberOf(value);
		elseif ( key == "one-at-a-time" ) then recipe.oneAtATime = true;
		elseif ( key == "finisher" ) then recipe.finisher = true;
		elseif ( key == "only" ) then
			recipe.only = {};
			for j = 2, #node do
				if ( wordOf(node[j]) ) then recipe.only[wordOf(node[j])] = true; end
			end
		elseif ( node.list ) then
			local effect = readEffect(node, dropped);
			if ( effect ) then table.insert(recipe.effects, effect); end
		end
	end
	if ( not rangeGiven ) then recipe.range = 30; end
	return recipe, dropped;
end

------------------------------------------------------------------------------------------------------------------
-- The window

local PREFIX = "SFRG";
local PART = 200;
local ROWS = 5;

local recipe = R.New();
local path = {};               -- the effects shown: { { effect = <effect>, link = <link> }, ... } from the spell down
local request = 0;
local lastPreview = 0;
local changedAt = nil;
local pendingRecipe = {};      -- a crafted spell's recipe coming in parts
local spells = {};             -- the character's crafted spells: { id, cost, name }
local selected = nil;          -- the one picked in the list
local editing = nil;           -- the crafted spell the form holds (Save forges it anew in its place); nil: a new one

local frame = CreateFrame("Frame", "OursForgeFrame", UIParent);
frame:Hide();
frame:SetWidth(900);
frame:SetHeight(612);
frame:SetPoint("CENTER");
frame:SetFrameStrata("DIALOG");
frame:SetToplevel(true);
frame:EnableMouse(true);
frame:SetMovable(true);
frame:RegisterForDrag("LeftButton");
frame:SetScript("OnDragStart", frame.StartMoving);
frame:SetScript("OnDragStop", frame.StopMovingOrSizing);
frame:SetBackdrop({
	bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
	tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 },
});
tinsert(UISpecialFrames, "OursForgeFrame");

local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge");
title:SetPoint("TOP", 0, -18);
title:SetText("Spellforge");

local close = CreateFrame("Button", "OursForgeClose", frame, "UIPanelCloseButton");
close:SetPoint("TOPRIGHT", -6, -6);

-- The three parts of the window, each framed: the list on the quest log's own dark pane, the form on a darker
-- ground, the preview on the quest log's parchment (cut out of its frame art, which has it painted in)
local TOP, BOTTOM = -40, -598;
local function section (name, x, width)
	local s = CreateFrame("Frame", name, frame);
	s:SetPoint("TOPLEFT", x, TOP);
	s:SetWidth(width);
	s:SetHeight(TOP - BOTTOM);
	s:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } });
	s:SetBackdropBorderColor(0.6, 0.5, 0.35);
	return s;
end
-- (the window's own: drawn over its backdrop and under its words, which a child frame's would cover)
local function piece (s, file, left, right, top, bottom, x, y, width, height)
	local t = frame:CreateTexture(nil, "BORDER");
	t:SetTexture(file);
	t:SetTexCoord(left, right, top, bottom);
	t:SetPoint("TOPLEFT", s, "TOPLEFT", x, y);
	t:SetWidth(width);
	t:SetHeight(height);
	return t;
end

local listPane = section("OursForgeListPane", 16, 196);
do  -- the quest log's empty list: 302 x 362 in four pieces
	local w, h = 196 - 8, (TOP - BOTTOM) - 8;
	local sx, sy = w / 302, h / 362;
	piece(listPane, "Interface\\QuestFrame\\UI-QuestLog-Empty-TopLeft", 0, 1, 0, 1, 4, -4, 256 * sx, 256 * sy);
	piece(listPane, "Interface\\QuestFrame\\UI-QuestLog-Empty-TopRight", 0, 0.71875, 0, 1, 4 + 256 * sx, -4, 46 * sx, 256 * sy);
	piece(listPane, "Interface\\QuestFrame\\UI-QuestLog-Empty-BotLeft", 0, 1, 0, 0.828125, 4, -4 - 256 * sy, 256 * sx, 106 * sy);
	piece(listPane, "Interface\\QuestFrame\\UI-QuestLog-Empty-BotRight", 0, 0.71875, 0, 0.828125, 4 + 256 * sx, -4 - 256 * sy, 46 * sx, 106 * sy);
end

local formPane = section("OursForgeFormPane", 216, 380);
do
	local t = frame:CreateTexture(nil, "BORDER");
	t:SetTexture(0, 0, 0, 0.45);
	t:SetPoint("TOPLEFT", formPane, "TOPLEFT", 4, -4);
	t:SetPoint("BOTTOMRIGHT", formPane, "BOTTOMRIGHT", -4, 4);
end

local previewPane = section("OursForgePreviewPane", 600, 284);
do  -- the parchment of the quest log's right side: x 350 to 512 of its left picture, 0 to 137 of its right one
	local w, h = 284 - 8, (TOP - BOTTOM) - 8;
	local leftWidth = w * 162 / 299;
	piece(previewPane, "Interface\\QuestFrame\\UI-QuestLogDualPane-Left", 350 / 512, 1, 78 / 512, 412 / 512, 4, -4, leftWidth, h);
	piece(previewPane, "Interface\\QuestFrame\\UI-QuestLogDualPane-RIGHT", 0, 137 / 256, 78 / 512, 412 / 512, 4 + leftWidth, -4, w - leftWidth, h);
end

local function label (parent, text, x, y, font)
	local fs = parent:CreateFontString(nil, "ARTWORK", font or "GameFontNormalSmall");
	fs:SetPoint("TOPLEFT", x, y);
	fs:SetText(text);
	return fs;
end

local function changed ()
	changedAt = GetTime();
end

local function editBox (name, parent, width, x, y, onChange)
	local box = CreateFrame("EditBox", name, parent, "InputBoxTemplate");
	box:SetAutoFocus(false);
	box:SetWidth(width);
	box:SetHeight(20);
	box:SetPoint("TOPLEFT", x, y);
	box:SetScript("OnEnterPressed", box.ClearFocus);
	box:SetScript("OnEscapePressed", box.ClearFocus);
	box:SetScript("OnTextChanged", function (self, userInput)
		if ( userInput ) then
			onChange(self:GetText());
			changed();
		end
	end);
	return box;
end

local function dropDown (name, parent, width, x, y, items, onPick)
	local menu = CreateFrame("Frame", name, parent, "UIDropDownMenuTemplate");
	menu:SetPoint("TOPLEFT", x - 16, y + 4);
	UIDropDownMenu_SetWidth(menu, width);
	menu.layoutWidth = width + 34;     -- (what it takes on the screen, from where it is put: it reaches 16 to the left)
	menu.items = items;
	menu.pick = onPick;
	function menu:SetValue (value)
		self.value = value;
		for _, item in ipairs(self.items) do
			if ( item.value == value ) then
				UIDropDownMenu_SetText(self, item.label);
			end
		end
	end
	UIDropDownMenu_Initialize(menu, function (self, level)
		for _, item in ipairs(menu.items) do
			local info = UIDropDownMenu_CreateInfo();
			info.text = item.label;
			info.value = item.value;
			info.checked = item.value == menu.value;
			info.func = function (button)
				menu:SetValue(button.value);
				onPick(button.value);
				changed();
			end;
			UIDropDownMenu_AddButton(info, level);
		end
	end);
	return menu;
end

local function button (name, parent, text, width, x, y, onClick)
	local b = CreateFrame("Button", name, parent, "UIPanelButtonTemplate");
	b:SetWidth(width);
	b:SetHeight(22);
	b:SetPoint("TOPLEFT", x, y);
	b:SetText(text);
	b:SetScript("OnClick", onClick);
	return b;
end

local function itemsOf (values, labels)
	local items = {};
	for i, value in ipairs(values) do
		table.insert(items, { value = value, label = labels and labels[i] or (string.upper(string.sub(value, 1, 1)) .. string.sub(value, 2)) });
	end
	return items;
end

-- Messages to the server
local function send (body)
	SendAddonMessage(PREFIX, body, "WHISPER", UnitName("player"));
end

-- The character's crafted spells, asked anew
local function askList ()
	spells = {};
	send("L");
end

-- P (preview), F (forge a new spell), or U with the spell to forge anew in its place
local function sendRecipe (command, spell)
	request = request + 1;
	local text = R.Text(recipe);
	local parts = math.max(1, math.ceil(string.len(text) / PART));
	local head = command .. (spell and (spell .. ":") or "") .. request;
	for i = 1, parts do
		send(head .. ":" .. i .. ":" .. parts .. ":" .. string.sub(text, (i - 1) * PART + 1, i * PART));
	end
	return request;
end

------------------------------------------------------------------------------------------------------------------
-- Left: the character's crafted spells

local listTitle = label(frame, "Your spells", 28, -52, "GameFontNormal");
local listButtons = {};
for i = 1, 16 do
	local b = CreateFrame("Button", "OursForgeSpell" .. i, frame);
	b:SetWidth(172);
	b:SetHeight(26);
	b:SetPoint("TOPLEFT", 26, -74 - (i - 1) * 29);
	b.icon = b:CreateTexture(nil, "ARTWORK");
	b.icon:SetWidth(24);
	b.icon:SetHeight(24);
	b.icon:SetPoint("LEFT");
	b.text = b:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall");
	b.text:SetPoint("LEFT", b.icon, "RIGHT", 4, 0);
	b.text:SetWidth(140);
	b.text:SetJustifyH("LEFT");
	b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD");
	b:SetScript("OnClick", function (self)
		selected = self.id;
		send("G" .. self.id);
	end);
	b:SetScript("OnEnter", function (self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
		GameTooltip:SetHyperlink("spell:" .. self.id);
		GameTooltip:Show();
	end);
	b:SetScript("OnLeave", function () GameTooltip:Hide(); end);
	b:Hide();
	listButtons[i] = b;
end

-- the character's slots (the server says, "o"): spells and passives taken, of how many there may be
local slots;
local function showSlots ()
	if ( not slots ) then
		listTitle:SetText("Your spells (" .. #spells .. ")");
		return;
	end
	local function part (what, taken, of)
		return what .. " " .. (taken >= of and "|cffff8040" or "") .. taken .. "/" .. of .. (taken >= of and "|r" or "");
	end
	listTitle:SetText(part("Spells", slots.spells, slots.spellSlots) .. "  " .. part("Passives", slots.passives, slots.passiveSlots));
end

local function showList ()
	for i, b in ipairs(listButtons) do
		local spell = spells[i];
		if ( spell ) then
			b.id = spell.id;
			local name, _, texture = GetSpellInfo(spell.id);
			b.icon:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark");
			b.text:SetText((name or spell.name) .. "\n|cff808080" .. (spell.passive and ("passive, " .. spell.cost .. " points") or spell.cost) .. "|r");
			if ( spell.id == editing ) then b:LockHighlight(); else b:UnlockHighlight(); end
			b:Show();
		else
			b:Hide();
		end
	end
	showSlots();
end

------------------------------------------------------------------------------------------------------------------
-- Middle: the spell, then its effects

local showLook;
local nameBox, iconButton, schoolMenu, targetMenu, castMenu, castBox, rangeBox, meleeCheck, cooldownBox;
local shapeMenu, sizeBox, sizeLabel, aroundMenu, speedBox;
local effectRows = {};
local rowY = {};          -- where each row of effects stands (kept apart: a row holds only its widgets)
local crumbs, backButton, addButton;
local showEffects;

local M = 232;     -- where the middle begins

-- the fields of a spell (a passive has none: it is not cast)
local spellPart = CreateFrame("Frame", "OursForgeSpellPart", frame);
spellPart:SetAllPoints(frame);
-- in their place for a passive: what it is, and the character's points
local passiveText = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall");
passiveText:SetPoint("TOPLEFT", M, -96);
passiveText:SetWidth(346);
passiveText:SetJustifyH("LEFT");
passiveText:Hide();
local pointsSpent, pointsPool = 0, 0;
local function showPoints ()
	passiveText:SetText("A passive is always on and costs nothing to keep: it takes points of your pool, which grows with your "
		.. "level. Drawbacks give some back.\n\n|cffffd100Your points:|r " .. pointsSpent .. " of " .. pointsPool .. " taken, "
		.. math.max(0, pointsPool - pointsSpent) .. " left.");
end

label(frame, "Name", M, -48);
nameBox = editBox("OursForgeName", frame, 118, M + 6, -60, function (text) recipe.name = text; end);
-- its look: the game's spell it looks like (chosen by what it does, or picked)
local lookButton = button("OursForgeLook", spellPart, "Look...", 62, M + 130, -59, function () end);
-- one at a time: casting it ends one's other spells that are (cheaper)
local oneCheck = CreateFrame("CheckButton", "OursForgeOneAtATime", spellPart, "UICheckButtonTemplate");
oneCheck:SetWidth(24);
oneCheck:SetHeight(24);
oneCheck:SetPoint("TOPLEFT", M + 244, -56);
OursForgeOneAtATimeText:SetText("One at a time");
oneCheck:SetScript("OnClick", function (self) recipe.oneAtATime = self:GetChecked() and true or nil; changed(); end);

-- a finisher: needs combo points and spends them; its effects grow with them
local finisherCheck = CreateFrame("CheckButton", "OursForgeFinisher", spellPart, "UICheckButtonTemplate");
finisherCheck:SetWidth(24);
finisherCheck:SetHeight(24);
finisherCheck:SetPoint("TOPLEFT", M + 270, -96);
OursForgeFinisherText:SetText("Finisher");
finisherCheck:SetScript("OnClick", function (self) recipe.finisher = self:GetChecked() and true or nil; changed(); showEffects(); end);

iconButton = CreateFrame("Button", "OursForgeIcon", frame);
iconButton:SetWidth(36);
iconButton:SetHeight(36);
iconButton:SetPoint("TOPLEFT", M + 198, -48);
iconButton.texture = iconButton:CreateTexture(nil, "ARTWORK");
iconButton.texture:SetAllPoints();
iconButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD");

label(spellPart, "School", M, -88);
schoolMenu = dropDown("OursForgeSchool", spellPart, 100, M, -100, itemsOf(R.SCHOOLS), function (v) recipe.school = v; end);
label(spellPart, "Aimed at", M + 150, -88);
targetMenu = dropDown("OursForgeTarget", spellPart, 100, M + 150, -100, itemsOf(R.TARGETS, { "An enemy", "A friend", "Yourself", "The ground", "Anyone" }),
	function (v) recipe.target = v; showEffects(); end);

label(spellPart, "Cast", M, -132);
castMenu = dropDown("OursForgeCast", spellPart, 100, M, -144, itemsOf({ "instant", "cast", "channel" }, { "Instant", "Cast time", "Channel" }),
	function (v) recipe.cast = v; if ( v ~= "instant" and (tonumber(recipe.castSeconds) or 0) <= 0 ) then recipe.castSeconds = 1.5; end showEffects(); end);
castBox = editBox("OursForgeCastSeconds", spellPart, 36, M + 140, -146, function (t) recipe.castSeconds = tonumber(t) or 0; end);
local castLabel = label(spellPart, "seconds", M + 182, -150, "GameFontHighlightSmall");
label(spellPart, "Cooldown", M + 250, -132);
cooldownBox = editBox("OursForgeCooldown", spellPart, 36, M + 256, -146, function (t) recipe.cooldown = tonumber(t) or 0; end);
label(spellPart, "s", M + 298, -150, "GameFontHighlightSmall");

local rangeLabel = label(spellPart, "Range", M, -176);
rangeBox = editBox("OursForgeRange", spellPart, 36, M + 6, -190, function (t) recipe.range = tonumber(t) or 0; end);
local yardsLabel = label(spellPart, "yards", M + 48, -194, "GameFontHighlightSmall");
meleeCheck = CreateFrame("CheckButton", "OursForgeMelee", spellPart, "UICheckButtonTemplate");
meleeCheck:SetWidth(24);
meleeCheck:SetHeight(24);
meleeCheck:SetPoint("TOPLEFT", M + 84, -186);
OursForgeMeleeText:SetText("Melee");
meleeCheck:SetScript("OnClick", function (self) recipe.melee = self:GetChecked() and true or false; showEffects(); changed(); end);
label(spellPart, "Missile speed", M + 170, -176);
speedBox = editBox("OursForgeSpeed", spellPart, 36, M + 176, -190, function (t) recipe.speed = tonumber(t) or 0; end);
label(spellPart, "yd/s (0: at once)", M + 218, -194, "GameFontHighlightSmall");

label(spellPart, "Shape", M, -220);
shapeMenu = dropDown("OursForgeShape", spellPart, 100, M, -232, itemsOf({ "single", "area", "cone", "chain" }, { "One target", "An area", "A cone", "A chain" }),
	function (v) recipe.shape = v; showEffects(); end);
sizeLabel = label(spellPart, "Radius", M + 150, -220);
sizeBox = editBox("OursForgeSize", spellPart, 36, M + 156, -234, function (t)
	if ( recipe.shape == "chain" ) then recipe.jumps = tonumber(t) or 1; else recipe.radius = tonumber(t) or 1; end
end);
aroundMenu = dropDown("OursForgeAround", spellPart, 90, M + 210, -232, itemsOf({ "target", "caster" }, { "Around the target", "Around you" }),
	function (v) recipe.around = v; end);

-- The kinds of creature it works on (every kind if none is ticked)
local function onlyWords ()
	local words = {};
	for i, t in ipairs(R.CREATURE_TYPES) do
		if ( recipe.only and recipe.only[t] ) then table.insert(words, R.CREATURE_TYPE_LABELS[i]); end
	end
	return #words > 0 and table.concat(words, ", ") or "Every kind";
end
label(spellPart, "Works on", M, -262);
local onlyButton, onlyMenu;
onlyButton = button("OursForgeOnly", spellPart, "Every kind", 136, M + 74, -258, function (self)
	ToggleDropDownMenu(1, nil, onlyMenu, self, 0, 0);
end);
onlyMenu = CreateFrame("Frame", "OursForgeOnlyMenu", spellPart, "UIDropDownMenuTemplate");
UIDropDownMenu_Initialize(onlyMenu, function (self, level)
	local info = UIDropDownMenu_CreateInfo();
	info.text = "Every kind";
	info.value = "any";
	info.checked = onlyWords() == "Every kind";
	info.func = function () recipe.only = {}; onlyButton:SetText(onlyWords()); changed(); CloseDropDownMenus(); end;
	UIDropDownMenu_AddButton(info, level);
	for i, t in ipairs(R.CREATURE_TYPES) do
		info = UIDropDownMenu_CreateInfo();
		info.text = R.CREATURE_TYPE_LABELS[i];
		info.value = t;
		info.checked = recipe.only and recipe.only[t];
		info.isNotRadio = true;
		info.keepShownOnClick = true;
		info.func = function ()
			recipe.only = recipe.only or {};
			recipe.only[t] = not recipe.only[t] or nil;
			onlyButton:SetText(onlyWords());
			changed();
		end;
		UIDropDownMenu_AddButton(info, level);
	end
end, "MENU");

-- What it costs: the character's own resource (the server says it, first), or one a form of theirs spends
local allowedPowers = { "mana" };
local costMenu;
local function costItems ()
	local items = {};
	for i, power in ipairs(allowedPowers) do
		local word = string.upper(string.sub(power, 1, 1)) .. string.sub(power, 2);
		table.insert(items, { value = power, label = i == 1 and (word .. " (own)") or (word .. " (a form's)") });
	end
	return items;
end
label(spellPart, "Spends", M + 222, -262);
costMenu = dropDown("OursForgeCost", spellPart, 70, M + 262, -258, costItems(), function (v)
	recipe.power = (v ~= allowedPowers[1]) and v or nil;
end);

-- The kinds of control of the effect whose button was pressed (ticks; one at the least)
local mechanicsEffect;
local mechanicsMenu = CreateFrame("Frame", "OursForgeMechanicsMenu", frame, "UIDropDownMenuTemplate");
UIDropDownMenu_Initialize(mechanicsMenu, function (self, level)
	local effect = mechanicsEffect;
	if ( not effect ) then return; end
	for i, m in ipairs(R.MECHANICS) do
		local info = UIDropDownMenu_CreateInfo();
		info.text = R.MECHANIC_LABELS[i];
		info.value = m;
		local has = false;
		for _, had in ipairs(effect.mechanics or {}) do if ( had == m ) then has = true; end end
		info.checked = has;
		info.isNotRadio = true;
		info.keepShownOnClick = true;
		info.func = function ()
			local list = {};
			local was = false;
			for _, had in ipairs(effect.mechanics or {}) do
				if ( had == m ) then was = true; else table.insert(list, had); end
			end
			if ( not was ) then table.insert(list, m); end
			if ( #list > 0 ) then effect.mechanics = list; end
			changed();
			showEffects();
		end;
		UIDropDownMenu_AddButton(info, level);
	end
end, "MENU");

-- The effects
local EFFECTS_TOP = -312;
local effectsTitle = label(frame, "Effects", M, -290, "GameFontNormal");
frame.effectsTitle = effectsTitle;
crumbs = label(frame, "", M + 60, -291, "GameFontHighlightSmall");
backButton = button("OursForgeBack", frame, "Back", 56, M + 292, -286, function ()
	table.remove(path);
	showEffects();
end);

local function effectsShown ()
	local last = path[#path];
	return last and last.link.effects or recipe.effects;
end

local whenMenu = CreateFrame("Frame", "OursForgeWhenMenu", frame, "UIDropDownMenuTemplate");
local whenEffect;
UIDropDownMenu_Initialize(whenMenu, function (self, level)
	for i, when in ipairs(R.WHENS) do
		local info = UIDropDownMenu_CreateInfo();
		local words = { "When it ends", "If it is dispelled", "If the target dies with it" };
		local count = 0;
		for _, link in ipairs(whenEffect and whenEffect.links or {}) do
			if ( link.when == when ) then count = #link.effects; end
		end
		info.text = words[i] .. (count > 0 and (" (" .. count .. ")") or "");
		info.notCheckable = true;
		info.func = function ()
			local link;
			for _, l in ipairs(whenEffect.links) do
				if ( l.when == when ) then link = l; end
			end
			if ( not link ) then
				link = { when = when, effects = {} };
				table.insert(whenEffect.links, link);
			end
			table.insert(path, { effect = whenEffect, link = link, words = words[i] });
			showEffects();
		end;
		UIDropDownMenu_AddButton(info, level);
	end
	for i, event in ipairs(R.EVENTS) do
		local info = UIDropDownMenu_CreateInfo();
		local count, had = 0, nil;
		for _, link in ipairs(whenEffect and whenEffect.links or {}) do
			if ( link.event ) then had = link; if ( link.event == event ) then count = #link.effects; end end
		end
		info.text = R.EVENT_WORDS[i] .. (count > 0 and (" (" .. count .. ")") or "");
		info.notCheckable = true;
		info.func = function ()
			-- one to an effect: choosing another changes what the one there is watches for
			local link = had;
			if ( link ) then
				link.event = event;
			else
				link = { event = event, chance = 100, cooldown = 0, effects = {} };
				table.insert(whenEffect.links, link);
			end
			table.insert(path, { effect = whenEffect, link = link, words = R.EVENT_WORDS[i] });
			showEffects();
		end;
		UIDropDownMenu_AddButton(info, level);
	end
end, "MENU");

-- Creatures: names the server told, and the chooser (opened from a row)
local creatureNames = {};
local openCreaturePicker;
local function creatureText (entry)
	entry = tonumber(entry) or 0;
	if ( entry <= 0 ) then return "Choose creature..."; end
	return creatureNames[entry] or ("Creature " .. entry);
end

local kindItems = {};
for _, kind in ipairs(R.KINDS) do
	table.insert(kindItems, { value = kind.key, label = kind.label });
end
for _, kind in ipairs(R.PARTS) do
	table.insert(kindItems, { value = kind.key, label = kind.label });
end
local tagItems = itemsOf(R.TAGS, R.TAG_LABELS);
local whenTagItems = { { value = "any", label = "Anything" } };
for _, item in ipairs(tagItems) do table.insert(whenTagItems, item); end

for i = 1, ROWS do
	local y = EFFECTS_TOP - (i - 1) * 52;
	local row = {};
	row.kind = dropDown("OursForgeKind" .. i, frame, 130, M, y, kindItems, function (v)
		local effects = effectsShown();
		local old = effects[i];
		local fresh = R.NewEffect(v);
		fresh.on = old.on;
		effects[i] = fresh;
		showEffects();
	end);
	-- in groups: the groups first, each opening to the side with its kinds
	local pickKind = row.kind.pick;
	UIDropDownMenu_Initialize(row.kind, function (self, level)
		level = level or 1;
		-- a passive's own parts at its top, what a part of it does inside one, a spell's effects elsewhere
		local last = path[#path];
		local groups = R.KIND_GROUPS;
		if ( last and R.KIND[last.effect.kind].trigger ) then groups = R.TRIGGER_GROUPS;
		elseif ( not last and recipe.passive ) then groups = R.PASSIVE_GROUPS; end
		for _, group in ipairs(groups) do
			if ( level == 1 ) then
				local info = UIDropDownMenu_CreateInfo();
				info.text = group.label;
				info.value = group.label;
				info.hasArrow = true;
				info.notCheckable = true;
				UIDropDownMenu_AddButton(info, level);
			elseif ( UIDROPDOWNMENU_MENU_VALUE == group.label ) then
				for _, key in ipairs(group.keys) do
					local info = UIDropDownMenu_CreateInfo();
					info.text = R.KIND[key].label;
					info.value = key;
					info.checked = key == row.kind.value;
					info.func = function (b)
						row.kind:SetValue(b.value);
						pickKind(b.value);
						changed();
						CloseDropDownMenus();
					end;
					UIDropDownMenu_AddButton(info, level);
				end
			end
		end
	end);
	row.on = dropDown("OursForgeOn" .. i, frame, 80, M + 172, y, itemsOf(R.WHOM, { "As aimed", "The target", "You", "Enemies", "Allies", "Your group", "Your party" }),
		function (v) effectsShown()[i].on = v; showEffects(); end);
	row.remove = button("OursForgeRemove" .. i, frame, "X", 24, M + 300, y - 2, function ()
		table.remove(effectsShown(), i);
		showEffects();
		changed();
	end);
	row.lowLabel = label(frame, "", M + 4, y - 30, "GameFontHighlightSmall");
	row.low = editBox("OursForgeLow" .. i, frame, 34, M + 40, y - 26, function (t)
		local effect = effectsShown()[i];
		effect.low = tonumber(t) or 0;
		if ( R.KIND[effect.kind].amount ~= "range" and R.KIND[effect.kind].amount ~= "two" ) then effect.high = effect.low; end
	end);
	row.highLabel = label(frame, "", M + 80, y - 30, "GameFontHighlightSmall");
	row.high = editBox("OursForgeHigh" .. i, frame, 34, M + 100, y - 26, function (t) effectsShown()[i].high = tonumber(t) or 0; end);
	row.chargesLabel = label(frame, "next", M + 80, y - 30, "GameFontHighlightSmall");
	row.charges = editBox("OursForgeCharges" .. i, frame, 22, M + 100, y - 26, function (t) effectsShown()[i].charges = tonumber(t) or 0; end);
	row.perComboLabel = label(frame, "+/pt", M + 80, y - 30, "GameFontHighlightSmall");
	row.perCombo = editBox("OursForgePerCombo" .. i, frame, 30, M + 100, y - 26, function (t) effectsShown()[i].perCombo = tonumber(t) or 0; end);
	row.perComboForLabel = label(frame, "+s/pt", M + 80, y - 30, "GameFontHighlightSmall");
	row.perComboFor = editBox("OursForgePerComboFor" .. i, frame, 26, M + 100, y - 26, function (t) effectsShown()[i].perComboFor = tonumber(t) or 0; end);
	row.forLabel = label(frame, "for", M + 142, y - 30, "GameFontHighlightSmall");
	row.seconds = editBox("OursForgeFor" .. i, frame, 30, M + 162, y - 26, function (t) effectsShown()[i].seconds = tonumber(t) or 0; end);
	row.everyLabel = label(frame, "every", M + 198, y - 30, "GameFontHighlightSmall");
	row.every = editBox("OursForgeEvery" .. i, frame, 26, M + 230, y - 26, function (t) effectsShown()[i].every = tonumber(t) or 0; end);
	rowY[row] = y;
	row.when = button("OursForgeWhen" .. i, frame, "When...", 60, M + 290, y - 26, function (self)
		local effect = effectsShown()[i];
		if ( R.KIND[effect.kind].totem or R.KIND[effect.kind].trigger ) then
			-- a totem's own effects, or what a passive's part does, as a link's are stepped into
			effect.inner = effect.inner or {};
			table.insert(path, { effect = effect, link = { effects = effect.inner },
				words = R.KIND[effect.kind].totem and "around it" or "what it does" });
			showEffects();
			return;
		end
		whenEffect = effect;
		ToggleDropDownMenu(1, nil, whenMenu, self, 0, 0);
	end);
	-- the kinds of control an immunity, a breaking free or a shortening is of
	row.mechanics = button("OursForgeMechanics" .. i, frame, "Stun", 80, M + 4, y - 26, function (self)
		mechanicsEffect = effectsShown()[i];
		ToggleDropDownMenu(1, nil, mechanicsMenu, self, 0, 0);
	end);
	-- in the place of "on" for what is made at you: the creature, the form, the totem's element
	row.creature = button("OursForgeCreature" .. i, frame, "Choose creature...", 140, M + 156, y - 2, function ()
		openCreaturePicker(effectsShown()[i]);
	end);
	row.form = dropDown("OursForgeForm" .. i, frame, 100, M + 172, y, itemsOf(R.FORMS, R.FORM_LABELS),
		function (v) effectsShown()[i].form = v; end);
	row.element = dropDown("OursForgeElement" .. i, frame, 80, M + 172, y, itemsOf(R.ELEMENTS),
		function (v) effectsShown()[i].element = v; end);
	-- and under it
	row.aboveLabel = label(frame, "levels above you", M, y - 30, "GameFontHighlightSmall");
	row.above = editBox("OursForgeAbove" .. i, frame, 26, M, y - 26, function (t) effectsShown()[i].above = tonumber(t) or 0; end);
	row.healthLabel = label(frame, "worn to %", M, y - 30, "GameFontHighlightSmall");
	row.health = editBox("OursForgeHealth" .. i, frame, 26, M, y - 26, function (t) effectsShown()[i].health = tonumber(t) or 0; end);
	row.radiusLabel = label(frame, "yd", M, y - 30, "GameFontHighlightSmall");
	-- a totem's reach, or an aura's on one's group
	row.radius = editBox("OursForgeRadius" .. i, frame, 26, M, y - 26, function (t)
		local effect = effectsShown()[i];
		if ( R.KIND[effect.kind].totem ) then effect.radius = tonumber(t) or 10; else effect.reach = tonumber(t) or 40; end
	end);
	row.elites = CreateFrame("CheckButton", "OursForgeElites" .. i, frame, "UICheckButtonTemplate");
	row.elites:SetWidth(22);
	row.elites:SetHeight(22);
	_G["OursForgeElites" .. i .. "Text"]:SetText("elites");
	row.elites:SetScript("OnClick", function (self) effectsShown()[i].elites = self:GetChecked() and true or false; changed(); end);
	-- by percent (a stat, armor, attack power) in place of points
	row.percent = CreateFrame("CheckButton", "OursForgePercent" .. i, frame, "UICheckButtonTemplate");
	row.percent:SetWidth(22);
	row.percent:SetHeight(22);
	_G["OursForgePercent" .. i .. "Text"]:SetText("%");
	row.percent:SetScript("OnClick", function (self) effectsShown()[i].percent = self:GetChecked() and true or nil; changed(); end);
	-- a weapon strike by the weapon's own speed
	row.ownSpeed = CreateFrame("CheckButton", "OursForgeOwnSpeed" .. i, frame, "UICheckButtonTemplate");
	row.ownSpeed:SetWidth(22);
	row.ownSpeed:SetHeight(22);
	_G["OursForgeOwnSpeed" .. i .. "Text"]:SetText("own speed");
	row.ownSpeed:SetScript("OnClick", function (self) effectsShown()[i].unnormalized = self:GetChecked() and true or nil; changed(); end);
	row.power = dropDown("OursForgePower" .. i, frame, 70, M, y - 22, itemsOf(R.POWERS, { "Own resource", "Mana", "Rage", "Energy" }),
		function (v) effectsShown()[i].power = v; end);
	local asValues, asLabels = { "none" }, { "Own type" };
	for j, t in ipairs(R.CREATURE_TYPES) do table.insert(asValues, t); table.insert(asLabels, "A " .. string.lower(R.CREATURE_TYPE_LABELS[j])); end
	row.as = dropDown("OursForgeAs" .. i, frame, 70, M, y - 22, itemsOf(asValues, asLabels), function (v) effectsShown()[i].as = v; end);
	row.alwaysLabel = label(frame, "(0: always)", M, y - 30, "GameFontDisableSmall");
	-- a passive's part: the kind of spell it goes with (in the place of "on"), and what a change changes
	row.tag = dropDown("OursForgeTag" .. i, frame, 90, M + 172, y, tagItems, function (v)
		local effect = effectsShown()[i];
		effect.tag = v;
		effect.spells = {};
	end);
	-- a kind of spell (one), or spells of yours (any number, ticked), each to the side; "Anything" for a "when"
	UIDropDownMenu_Initialize(row.tag, function (self, level)
		level = level or 1;
		local effect = effectsShown()[i];
		if ( not effect ) then return; end
		local isWhen = R.KIND[effect.kind] and R.KIND[effect.kind].part == "when";
		local named = effect.spells or {};
		if ( level == 1 ) then
			if ( isWhen ) then
				local info = UIDropDownMenu_CreateInfo();
				info.text = "Anything";
				info.value = "any";
				info.checked = #named == 0 and effect.tag == "any";
				info.func = function ()
					effect.tag, effect.spells = "any", {};
					showEffects();
					changed();
					CloseDropDownMenus();
				end;
				UIDropDownMenu_AddButton(info, level);
			end
			for _, side in ipairs({ "Kinds of spell", "Your spells" }) do
				local info = UIDropDownMenu_CreateInfo();
				info.text = side;
				info.value = side;
				info.hasArrow = true;
				info.notCheckable = true;
				UIDropDownMenu_AddButton(info, level);
			end
		elseif ( UIDROPDOWNMENU_MENU_VALUE == "Kinds of spell" ) then
			for _, item in ipairs(tagItems) do
				local info = UIDropDownMenu_CreateInfo();
				info.text = item.label;
				info.value = item.value;
				info.checked = #named == 0 and effect.tag == item.value;
				info.func = function (b)
					effect.tag, effect.spells = b.value, {};
					showEffects();
					changed();
					CloseDropDownMenus();
				end;
				UIDropDownMenu_AddButton(info, level);
			end
		elseif ( UIDROPDOWNMENU_MENU_VALUE == "Your spells" ) then
			local any = false;
			for _, spell in ipairs(spells) do
				if ( not spell.passive ) then
					any = true;
					local info = UIDropDownMenu_CreateInfo();
					info.text = GetSpellInfo(spell.id) or spell.name;
					info.value = spell.id;
					info.isNotRadio = true;
					info.keepShownOnClick = true;
					local ticked = false;
					for _, id in ipairs(named) do if ( id == spell.id ) then ticked = true; end end
					info.checked = ticked;
					info.func = function (b)
						effect.spells = effect.spells or {};
						local at;
						for j, id in ipairs(effect.spells) do if ( id == b.value ) then at = j; end end
						if ( at ) then table.remove(effect.spells, at); else table.insert(effect.spells, b.value); end
						if ( #effect.spells == 0 ) then effect.tag = isWhen and "any" or "all"; end
						showEffects();
						changed();
					end;
					UIDropDownMenu_AddButton(info, level);
				end
			end
			if ( not any ) then
				local info = UIDropDownMenu_CreateInfo();
				info.text = "(no spells of yours yet)";
				info.notCheckable = true;
				info.disabled = true;
				UIDropDownMenu_AddButton(info, level);
			end
		end
	end);
	row.change = dropDown("OursForgeChange" .. i, frame, 100, M, y - 22, itemsOf(R.CHANGES, R.CHANGE_LABELS),
		function (v) effectsShown()[i].change = v; end);
	effectRows[i] = row;
end

frame.effectRows = effectRows;   -- (for the window's tests)

-- in an effect's (when <event> ...): its chance, and how often at most
local eventChanceLabel = label(frame, "chance", M + 110, EFFECTS_TOP - ROWS * 52 - 6, "GameFontHighlightSmall");
local eventChance = editBox("OursForgeEventChance", frame, 34, M + 152, EFFECTS_TOP - ROWS * 52 - 2, function (text)
	local last = path[#path];
	if ( last and last.link.event ) then last.link.chance = tonumber(text) or 100; end
end);
local eventCooldownLabel = label(frame, "% at most every", M + 192, EFFECTS_TOP - ROWS * 52 - 6, "GameFontHighlightSmall");
local eventCooldown = editBox("OursForgeEventCooldown", frame, 30, M + 282, EFFECTS_TOP - ROWS * 52 - 2, function (text)
	local last = path[#path];
	if ( last and last.link.event ) then last.link.cooldown = tonumber(text) or 0; end
end);
local eventSecondsLabel = label(frame, "s", M + 316, EFFECTS_TOP - ROWS * 52 - 6, "GameFontHighlightSmall");
frame.eventChance, frame.eventCooldown = eventChance, eventCooldown;
local function showEventFields ()
	local last = path[#path];
	local shown = last and last.link.event;
	for _, widget in ipairs({ eventChanceLabel, eventChance, eventCooldownLabel, eventCooldown, eventSecondsLabel }) do
		if ( shown ) then widget:Show(); else widget:Hide(); end
	end
	if ( shown ) then
		eventChance:SetText(number(tonumber(last.link.chance) or 100));
		eventCooldown:SetText(number(tonumber(last.link.cooldown) or 0));
	end
end
addButton = button("OursForgeAdd", frame, "Add effect", 100, M, EFFECTS_TOP - ROWS * 52, function ()
	local effects = effectsShown();
	if ( #effects < 8 ) then
		table.insert(effects, R.NewEffect((recipe.passive and #path == 0) and "modify" or "damage"));
		showEffects();
		changed();
	end
end);

local function setRow (row, effect)
	local kind = R.KIND[effect.kind];
	row.kind:SetValue(effect.kind);
	row.on:SetValue(effect.on or "default");
	local amount = kind.amount;
	local function show (widget, on) if ( on ) then widget:Show(); else widget:Hide(); end end
	show(row.low, amount ~= "none");
	show(row.lowLabel, amount ~= "none");
	show(row.high, amount == "range" or amount == "two");
	show(row.highLabel, amount == "range" or amount == "two");
	row.lowLabel:SetText(kind.lowLabel or (amount == "count" and "how many" or (amount == "range" and "from" or "amount")));
	row.highLabel:SetText(kind.highLabel or "to");
	row.low:SetText(number(effect.low));
	row.high:SetText(number(effect.high));
	-- what is always on (a passive's own) has no length; a "when" has how often at most in its place
	local always = recipe.passive and #path == 0 and not kind.part;
	local timed = (kind.aura or kind.lock or kind.lasting or kind.needsFor or kind.part == "when") and not always;
	show(row.seconds, timed);
	show(row.forLabel, timed);
	local finishes = recipe.finisher and #path == 0;
	local grows = finishes and kind.amount ~= "none" and kind.key ~= "combo" and not kind.creature;
	show(row.perCombo, grows);
	show(row.perComboLabel, grows);
	row.perCombo:SetText(number(tonumber(effect.perCombo) or 0));
	local longer = finishes and timed and kind.aura;
	show(row.perComboFor, longer);
	show(row.perComboForLabel, longer);
	row.perComboFor:SetText(number(tonumber(effect.perComboFor) or 0));
	show(row.alwaysLabel, (kind.lasting or (kind.aura and not kind.every and kind.key ~= "charm") or kind.part == "when") and not always
		and not (kind.mechanics and (effect.on == "group" or effect.on == "party")) and not kind.charges);
	row.alwaysLabel:SetText(kind.part == "when" and "s (0: any time)" or "(0: always)");
	row.forLabel:SetText(kind.lock and "lock" or (kind.part == "when" and "at most every" or "for"));
	row.seconds:SetText(number(effect.seconds or 0));
	show(row.every, kind.every);
	show(row.everyLabel, kind.every);
	row.every:SetText(number(effect.every or 0));

	-- what is made at you has no "on": a creature, a form or an element in its place
	show(row.on, not (kind.creature or kind.form or kind.totem or kind.part or kind.tagged));
	show(row.tag, kind.part or kind.tagged);
	row.tag.items = kind.part == "when" and whenTagItems or tagItems;
	row.tag:SetValue(effect.tag or "all");
	if ( (kind.part or kind.tagged) and effect.spells and #effect.spells > 0 ) then
		local names = {};
		for _, id in ipairs(effect.spells) do
			local name = GetSpellInfo(id);
			for _, spell in ipairs(spells) do if ( spell.id == id ) then name = name or spell.name; end end
			table.insert(names, name or ("Spell " .. id));
		end
		UIDropDownMenu_SetText(row.tag, table.concat(names, ", "));
	end
	show(row.change, kind.part == "modify" or kind.changes);
	show(row.charges, kind.charges and not always);
	show(row.chargesLabel, kind.charges and not always);
	row.charges:SetText(number(tonumber(effect.charges) or 0));
	row.change:SetValue(effect.change or "damage");
	show(row.creature, kind.creature);
	row.creature:SetText(creatureText(effect.creature));
	show(row.form, kind.form);
	row.form:SetValue(effect.form or "cat");
	show(row.element, kind.totem);
	row.element:SetValue(effect.element or "fire");
	show(row.above, kind.above);
	show(row.aboveLabel, kind.above);
	row.above:SetText(number(effect.above or 0));
	show(row.health, kind.health);
	show(row.healthLabel, kind.health);
	row.health:SetText(number(effect.health or 0));
	local reaches = kind.totem or (kind.aura and not kind.shape and not kind.tagged and (effect.on == "group" or effect.on == "party"));
	show(row.radius, reaches);
	show(row.radiusLabel, reaches);
	row.radius:SetText(number(kind.totem and (effect.radius or 10) or (effect.reach or (effect.on == "party" and 100 or 40))));
	show(row.elites, kind.elites);
	row.elites:SetChecked(effect.elites);
	show(row.percent, kind.percent);
	row.percent:SetChecked(effect.percent);
	show(row.ownSpeed, kind.unnormalized);
	row.ownSpeed:SetChecked(effect.unnormalized);
	show(row.power, kind.shape);
	row.power:SetValue(effect.power or "keep");
	show(row.mechanics, kind.mechanics);
	if ( kind.mechanics ) then
		local words = {};
		for _, had in ipairs(effect.mechanics or {}) do table.insert(words, R.MECHANIC_LABELS[R.MECHANIC[had] or 1]); end
		row.mechanics:SetText(#words > 0 and table.concat(words, ", ") or "Stun");
	end
	show(row.as, kind.shape);
	row.as:SetValue(effect.as or "none");

	-- What is shown, one after the other by how wide each is: a word, a box (whose frame reaches 5 to the left of
	-- it), a menu (16), a tick with its word
	local x = M + 4;
	local order = { row.mechanics, row.change, row.power, row.as, row.lowLabel, row.low, row.percent, row.highLabel, row.high, row.perComboLabel, row.perCombo, row.ownSpeed,
		row.aboveLabel, row.above, row.healthLabel, row.health, row.forLabel, row.seconds, row.chargesLabel, row.charges, row.perComboForLabel, row.perComboFor, row.alwaysLabel,
		row.everyLabel, row.every, row.radiusLabel, row.radius, row.elites };
	local words = { [row.lowLabel] = true, [row.highLabel] = true, [row.aboveLabel] = true, [row.healthLabel] = true,
		[row.forLabel] = true, [row.alwaysLabel] = true, [row.everyLabel] = true, [row.radiusLabel] = true,
		[row.perComboLabel] = true, [row.perComboForLabel] = true, [row.chargesLabel] = true };
	local menus = { [row.change] = true, [row.power] = true, [row.as] = true };
	for _, widget in ipairs(order) do
		if ( widget:IsShown() ) then
			widget:ClearAllPoints();
			if ( menus[widget] ) then
				widget:SetPoint("TOPLEFT", frame, "TOPLEFT", x - 16, rowY[row] - 22);
				x = x + widget.layoutWidth;
			elseif ( widget == row.elites or widget == row.percent or widget == row.ownSpeed ) then
				widget:SetPoint("TOPLEFT", frame, "TOPLEFT", x, rowY[row] - 24);
				x = x + 22 + (widget == row.percent and 10 or widget == row.ownSpeed and 56 or 40);
			elseif ( words[widget] ) then
				widget:SetPoint("TOPLEFT", frame, "TOPLEFT", x, rowY[row] - 30);
				x = x + (widget:GetStringWidth() or 0) + 8;
			else
				widget:SetPoint("TOPLEFT", frame, "TOPLEFT", x, rowY[row] - 26);
				x = x + (widget:GetWidth() or 0) + 10;
			end
		end
	end
	show(row.when, (kind.aura and #path < 3 and not always) or (kind.totem and #path < 3) or (kind.trigger and #path == 0));
	if ( kind.totem or kind.trigger ) then
		row.when:SetText("Effects (" .. #(effect.inner or {}) .. ")");
	else
		local links = 0;
		for _, link in ipairs(effect.links or {}) do links = links + #link.effects; end
		row.when:SetText(links > 0 and ("When (" .. links .. ")") or "When...");
	end
end

-- Where the effects stand: under the spell's fields, or a passive's text (which takes less room)
local placedAt;
local function placeRows (top)
	if ( placedAt == top ) then return; end
	placedAt = top;
	local function at (widget, x, y) widget:ClearAllPoints(); widget:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y); end
	at(effectsTitle, M, top + 22);
	at(crumbs, M + 60, top + 21);
	at(backButton, M + 292, top + 26);
	for i, row in ipairs(effectRows) do
		local y = top - (i - 1) * 52;
		rowY[row] = y;
		for _, menu in ipairs({ row.kind, row.on, row.form, row.element, row.tag }) do at(menu, (menu == row.kind and M or M + 172) - 16, y + 4); end
		at(row.remove, M + 300, y - 2);
		at(row.when, M + 290, y - 26);
		at(row.creature, M + 156, y - 2);
	end
	at(addButton, M, top - ROWS * 52);
end

showEffects = function ()
	placeRows(recipe.passive and -200 or EFFECTS_TOP);
	local effects = effectsShown();
	for i, row in ipairs(effectRows) do
		local effect = effects[i];
		for _, widget in pairs(row) do
			if ( effect ) then widget:Show(); else widget:Hide(); end
		end
		if ( effect ) then setRow(row, effect); end
	end
	if ( #effects < 8 ) then addButton:Show(); else addButton:Hide(); end
	if ( showEventFields ) then showEventFields(); end
	if ( #path > 0 ) then
		local words = {};
		for _, step in ipairs(path) do
			table.insert(words, R.KIND[step.effect.kind].label .. ": " .. (step.words or ""));
		end
		crumbs:SetText("> " .. table.concat(words, " > "));
		backButton:Show();
	else
		crumbs:SetText("");
		backButton:Hide();
	end
	-- a passive has none of a spell's fields
	if ( recipe.passive ) then spellPart:Hide(); passiveText:Show(); showPoints(); else spellPart:Show(); passiveText:Hide(); end
	effectsTitle:SetText((recipe.passive and #path == 0) and "Parts" or "Effects");
	addButton:SetText((recipe.passive and #path == 0) and "Add part" or "Add effect");
	-- what the spell's own fields mean depends on others
	if ( recipe.target == "self" ) then rangeBox:Hide(); meleeCheck:Hide(); rangeLabel:Hide(); yardsLabel:Hide(); else rangeBox:Show(); meleeCheck:Show(); rangeLabel:Show(); yardsLabel:Show(); end
	if ( recipe.cast == "instant" ) then castBox:Hide(); castLabel:Hide(); else castBox:Show(); castLabel:Show(); end
	if ( recipe.shape == "single" ) then sizeBox:Hide(); sizeLabel:Hide(); else sizeBox:Show(); sizeLabel:Show(); end
	sizeLabel:SetText(recipe.shape == "chain" and "Jumps" or (recipe.shape == "cone" and "Yards" or "Radius"));
	sizeBox:SetText(number(recipe.shape == "chain" and recipe.jumps or recipe.radius));
	if ( recipe.shape == "area" and recipe.target ~= "self" and recipe.target ~= "ground" ) then aroundMenu:Show(); else aroundMenu:Hide(); end
end

local function showRecipe ()
	nameBox:SetText(recipe.name or "");
	iconButton.texture:SetTexture(SpellforgeIconTexture and SpellforgeIconTexture(recipe.icon) or "Interface\\Icons\\INV_Misc_QuestionMark");
	schoolMenu:SetValue(recipe.school);
	targetMenu:SetValue(recipe.target);
	castMenu:SetValue(recipe.cast);
	castBox:SetText(number(recipe.castSeconds));
	cooldownBox:SetText(number(recipe.cooldown));
	rangeBox:SetText(number(recipe.range));
	meleeCheck:SetChecked(recipe.melee);
	speedBox:SetText(number(recipe.speed));
	shapeMenu:SetValue(recipe.shape);
	aroundMenu:SetValue(recipe.around);
	onlyButton:SetText(onlyWords());
	costMenu:SetValue(recipe.power or allowedPowers[1]);
	oneCheck:SetChecked(recipe.oneAtATime);
	finisherCheck:SetChecked(recipe.finisher);
	if ( showLook ) then showLook(); end
	path = {};
	showEffects();
	changed();
	-- the names of the creatures it names, from the server
	local function ask (effects)
		for _, effect in ipairs(effects or {}) do
			local entry = tonumber(effect.creature) or 0;
			if ( entry > 0 and not creatureNames[entry] ) then send("Cn" .. entry .. ":#" .. entry); end
			ask(effect.inner);
			for _, link in ipairs(effect.links or {}) do ask(link.effects); end
		end
	end
	ask(recipe.effects);
end

------------------------------------------------------------------------------------------------------------------
-- Right: the preview

local P = 614;
-- Written on the parchment with the quest log's own fonts (black and brown, without the dark shadow the game's
-- other fonts have, which on parchment smears)
label(frame, "Preview", P, -52, "QuestTitleFont");
local editingText = label(frame, "", P, -76, "QuestFontNormalSmall");
editingText:SetWidth(258);
editingText:SetJustifyH("LEFT");
local lookText = label(frame, "", P, -104, "QuestFontNormalSmall");
lookText:SetWidth(258);
lookText:SetJustifyH("LEFT");
showLook = function ()
	local name = recipe.look and GetSpellInfo(recipe.look);
	lookText:SetText(name and ("Looks like " .. name .. ".") or "Looks like the game's spells of its kind.");
end
local tip = CreateFrame("GameTooltip", "OursForgeTooltip", frame, "GameTooltipTemplate");
local costText = label(frame, "", P, -350, "QuestFont");
frame.costText = costText;
frame.passiveText = passiveText;
frame.listTitle = listTitle;
local notesText = frame:CreateFontString(nil, "ARTWORK", "QuestFontNormalSmall");
notesText:SetPoint("TOPLEFT", P, -372);
notesText:SetWidth(258);
notesText:SetJustifyH("LEFT");
notesText:SetJustifyV("TOP");
local notes = {};
local previewShown = false;    -- a preview has come and may be shown
local picker;                  -- (the icon picker, below)

-- The game's tooltips are drawn above everything (their strata); this one is part of the window, and goes away
-- while the icon picker is open over it
local function showPreview ()
	previewShown = true;
	if ( picker and picker:IsShown() ) then return; end
	tip:SetOwner(frame, "ANCHOR_NONE");
	tip:SetFrameStrata("DIALOG");
	tip:SetFrameLevel(frame:GetFrameLevel() + 5);
	tip:ClearAllPoints();
	tip:SetPoint("TOPLEFT", frame, "TOPLEFT", P - 4, -124);
	tip:SetHyperlink("spell:" .. R.PREVIEW_ID);
	tip:Show();
end

-- Forge: a new spell, or with a spell of yours in the form, that one saved as it is now (its place in the spell
-- book and on the bars stays). "Save as new" forges a copy beside it.
local forgeButton, saveNewButton;
local function showEditing ()
	if ( editing ) then
		forgeButton:SetText("Save");
		saveNewButton:Show();
		editingText:SetText("Changing " .. (GetSpellInfo(editing) or ("spell " .. editing)) .. ". Save keeps it in its place.");
	else
		forgeButton:SetText("Forge");
		saveNewButton:Hide();
		editingText:SetText(recipe.passive and "A new passive." or "A new spell.");
	end
	for _, b in ipairs(listButtons) do
		if ( b.id and b.id == editing ) then b:LockHighlight(); else b:UnlockHighlight(); end
	end
end

forgeButton = button("OursForgeForge", frame, "Forge", 120, P, -566, function ()
	if ( editing ) then
		StaticPopup_Show("OURSFORGE_SAVE", recipe.name);
	else
		StaticPopup_Show("OURSFORGE_FORGE", recipe.name);
	end
end);
saveNewButton = button("OursForgeSaveNew", frame, "Save as new", 120, P + 136, -566, function ()
	StaticPopup_Show("OURSFORGE_FORGE", recipe.name);
end);
local newMenu = CreateFrame("Frame", "OursForgeNewMenu", frame, "UIDropDownMenuTemplate");
local function newOne (passive)
	recipe = passive and R.NewPassive() or R.New();
	selected = nil;
	editing = nil;
	showEditing();
	showRecipe();
end
UIDropDownMenu_Initialize(newMenu, function (self, level)
	for _, item in ipairs({ { "A spell", false }, { "A passive", true } }) do
		local info = UIDropDownMenu_CreateInfo();
		info.text = item[1];
		info.notCheckable = true;
		info.func = function () newOne(item[2]); CloseDropDownMenus(); end;
		UIDropDownMenu_AddButton(info, level);
	end
end, "MENU");
frame.newOne = newOne;   -- (for the window's tests)
button("OursForgeNew", frame, "New...", 90, 24, -566, function (self)
	ToggleDropDownMenu(1, nil, newMenu, self, 0, 0);
end);
local forgetButton = button("OursForgeForget", frame, "Forget", 84, 118, -566, function ()
	if ( selected ) then
		StaticPopup_Show("OURSFORGE_FORGET", GetSpellInfo(selected) or selected);
	end
end);

StaticPopupDialogs["OURSFORGE_FORGE"] = {
	text = "Forge %s as a new spell of yours?", button1 = ACCEPT, button2 = CANCEL,
	OnAccept = function () sendRecipe("F"); end, timeout = 0, whileDead = true, hideOnEscape = true,
};
StaticPopupDialogs["OURSFORGE_SAVE"] = {
	text = "Save the changes to %s? It stays where it is in your spell book and on your bars.", button1 = ACCEPT, button2 = CANCEL,
	OnAccept = function () if ( editing ) then sendRecipe("U", editing); end end, timeout = 0, whileDead = true, hideOnEscape = true,
};
StaticPopupDialogs["OURSFORGE_FORGET"] = {
	text = "Forget %s? It is gone for good.", button1 = ACCEPT, button2 = CANCEL,
	OnAccept = function () if ( selected ) then send("X" .. selected); end end, timeout = 0, whileDead = true, hideOnEscape = true,
};

------------------------------------------------------------------------------------------------------------------
-- The icon picker

picker = CreateFrame("Frame", "OursForgeIconPicker", frame);
picker:Hide();
picker:SetWidth(392);
picker:SetHeight(340);
picker:SetPoint("TOPLEFT", iconButton, "TOPRIGHT", 8, 0);
picker:SetFrameLevel(frame:GetFrameLevel() + 10);
picker:SetScript("OnShow", function () tip:Hide(); end);
picker:SetScript("OnHide", function () if ( previewShown ) then showPreview(); end end);
picker:EnableMouse(true);
picker:SetBackdrop(frame:GetBackdrop());
local icons = nil;           -- { { id, texture }, ... } the game's
local shownIcons = {};
local iconPage = 1;
local ICONS = 48;
local iconButtons = {};
local searchBox = editBox("OursForgeIconSearch", picker, 180, 20, -18, function () iconPage = 1; picker:Fill(); end);
local pageText = label(picker, "", 220, -22, "GameFontHighlightSmall");
for i = 1, ICONS do
	local b = CreateFrame("Button", "OursForgeIconChoice" .. i, picker);
	b:SetWidth(40);
	b:SetHeight(40);
	b:SetPoint("TOPLEFT", 18 + ((i - 1) % 8) * 44, -44 - math.floor((i - 1) / 8) * 44);
	b.texture = b:CreateTexture(nil, "ARTWORK");
	b.texture:SetAllPoints();
	b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD");
	b:SetScript("OnClick", function (self)
		recipe.icon = self.iconId;
		iconButton.texture:SetTexture(self.texture:GetTexture());
		picker:Hide();
		changed();
	end);
	iconButtons[i] = b;
end
function picker:Fill ()
	if ( not icons ) then
		icons = {};
		for i = 1, (SpellforgeIconCount and SpellforgeIconCount() or 0) do
			local id, texture = SpellforgeIcon(i);
			if ( id and texture and texture ~= "" ) then table.insert(icons, { id = id, texture = texture }); end
		end
	end
	local words = string.lower(searchBox:GetText() or "");
	shownIcons = {};
	for _, icon in ipairs(icons) do
		if ( words == "" or string.find(string.lower(icon.texture), words, 1, true) ) then table.insert(shownIcons, icon); end
	end
	local pages = math.max(1, math.ceil(#shownIcons / ICONS));
	iconPage = math.min(math.max(iconPage, 1), pages);
	for i, b in ipairs(iconButtons) do
		local icon = shownIcons[(iconPage - 1) * ICONS + i];
		if ( icon ) then
			b.iconId = icon.id;
			b.texture:SetTexture(icon.texture);
			b:Show();
		else
			b:Hide();
		end
	end
	pageText:SetText(iconPage .. " / " .. pages);
end
button("OursForgeIconPrev", picker, "<", 30, 300, -16, function () iconPage = iconPage - 1; picker:Fill(); end);
button("OursForgeIconNext", picker, ">", 30, 334, -16, function () iconPage = iconPage + 1; picker:Fill(); end);
iconButton:SetScript("OnClick", function ()
	if ( picker:IsShown() ) then picker:Hide(); else picker:Show(); picker:Fill(); end
end);

------------------------------------------------------------------------------------------------------------------
-- The look chooser: the game's spells by words of their name (our client searches its own table)

local LOOK_ROWS = 12;
local lookPicker = CreateFrame("Frame", "OursForgeLookPicker", frame);
lookPicker:Hide();
lookPicker:SetWidth(360);
lookPicker:SetHeight(330);
lookPicker:SetPoint("TOPLEFT", frame, "TOPLEFT", M - 12, -86);
lookPicker:SetFrameLevel(frame:GetFrameLevel() + 10);
lookPicker:EnableMouse(true);
lookPicker:SetBackdrop(frame:GetBackdrop());
label(lookPicker, "Looks like a spell of the game's: words of its name", 20, -16, "GameFontNormalSmall");
local lookChangedAt;
local lookSearch = editBox("OursForgeLookSearch", lookPicker, 220, 24, -32, function () lookChangedAt = GetTime(); end);
local lookButtons = {};
for i = 1, LOOK_ROWS do
	local b = CreateFrame("Button", "OursForgeLookChoice" .. i, lookPicker);
	b:SetWidth(320);
	b:SetHeight(20);
	b:SetPoint("TOPLEFT", 20, -60 - (i - 1) * 21);
	b.icon = b:CreateTexture(nil, "ARTWORK");
	b.icon:SetWidth(18);
	b.icon:SetHeight(18);
	b.icon:SetPoint("LEFT");
	b.text = b:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall");
	b.text:SetPoint("LEFT", b.icon, "RIGHT", 4, 0);
	b.text:SetWidth(296);
	b.text:SetJustifyH("LEFT");
	b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD");
	b:SetScript("OnClick", function (self)
		recipe.look = self.spell;
		lookPicker:Hide();
		showLook();
		changed();
	end);
	b:Hide();
	lookButtons[i] = b;
end
button("OursForgeLookAuto", lookPicker, "As it does", 100, 20, -298, function ()
	recipe.look = nil;
	lookPicker:Hide();
	showLook();
	changed();
end);
button("OursForgeLookCancel", lookPicker, "Cancel", 80, 260, -298, function () lookPicker:Hide(); end);
local function fillLooks ()
	local found = {};
	if ( SpellforgeFindSpells ) then found = { SpellforgeFindSpells(lookSearch:GetText() or "", LOOK_ROWS) }; end     -- (all it returns)
	for i, b in ipairs(lookButtons) do
		local at = (i - 1) * 4;
		if ( found[at + 1] ) then
			b.spell = found[at + 1];
			b.icon:SetTexture(found[at + 4]);
			b.text:SetText(found[at + 2] .. (found[at + 3] ~= "" and ("  |cff808080" .. found[at + 3] .. "|r") or ""));
			b:Show();
		else
			b:Hide();
		end
	end
end
lookPicker:SetScript("OnUpdate", function ()
	if ( lookChangedAt and GetTime() - lookChangedAt > 0.3 ) then
		lookChangedAt = nil;
		fillLooks();
	end
end);
lookButton:SetScript("OnClick", function ()
	if ( lookPicker:IsShown() ) then lookPicker:Hide(); return; end
	lookSearch:SetText("");
	fillLooks();
	lookPicker:Show();
end);

------------------------------------------------------------------------------------------------------------------
-- The creature chooser: the server's creatures by words of their name

local TYPE_WORDS = { "Beast", "Dragonkin", "Demon", "Elemental", "Giant", "Undead", "Humanoid", "Critter", "Mechanical",
	"Not specified", "Totem", "Pet", "Gas cloud" };
local CREATURE_ROWS = 12;
local creaturePicker = CreateFrame("Frame", "OursForgeCreaturePicker", frame);
creaturePicker:Hide();
creaturePicker:SetWidth(360);
creaturePicker:SetHeight(330);
creaturePicker:SetPoint("TOPLEFT", frame, "TOPLEFT", M - 12, -262);
creaturePicker:SetFrameLevel(frame:GetFrameLevel() + 10);
creaturePicker:EnableMouse(true);
creaturePicker:SetBackdrop(frame:GetBackdrop());
local creatureFor;                 -- the effect it chooses for
local creatureReq = 0;
local creatureFound = {};
local creatureChangedAt;
label(creaturePicker, "Words of its name, or # and its number", 20, -16, "GameFontNormalSmall");
local creatureSearch = editBox("OursForgeCreatureSearch", creaturePicker, 220, 24, -32, function () creatureChangedAt = GetTime(); end);
local creatureStatus = label(creaturePicker, "", 256, -36, "GameFontHighlightSmall");
local creatureButtons = {};
for i = 1, CREATURE_ROWS do
	local b = CreateFrame("Button", "OursForgeCreatureChoice" .. i, creaturePicker);
	b:SetWidth(320);
	b:SetHeight(20);
	b:SetPoint("TOPLEFT", 20, -60 - (i - 1) * 21);
	b.text = b:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall");
	b.text:SetPoint("LEFT", 4, 0);
	b.text:SetWidth(312);
	b.text:SetJustifyH("LEFT");
	b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD");
	b:SetScript("OnClick", function (self)
		if ( creatureFor and self.entry ) then
			creatureFor.creature = self.entry;
			creatureNames[self.entry] = self.name;
		end
		creaturePicker:Hide();
		showEffects();
		changed();
	end);
	b:Hide();
	creatureButtons[i] = b;
end
button("OursForgeCreatureCancel", creaturePicker, "Cancel", 80, 260, -298, function () creaturePicker:Hide(); end);
local function showCreatures ()
	for i, b in ipairs(creatureButtons) do
		local c = creatureFound[i];
		if ( c ) then
			b.entry, b.name = c.entry, c.name;
			b.text:SetText(c.name .. "  |cff808080level " .. c.level .. ", " .. (TYPE_WORDS[c.type] or "?") .. ", #" .. c.entry .. "|r");
			b:Show();
		else
			b:Hide();
		end
	end
end
openCreaturePicker = function (effect)
	creatureFor = effect;
	creatureFound = {};
	showCreatures();
	creatureStatus:SetText("");
	creatureSearch:SetText("");
	creaturePicker:Show();
end
creaturePicker:SetScript("OnUpdate", function ()
	if ( creatureChangedAt and GetTime() - creatureChangedAt > 0.4 ) then
		creatureChangedAt = nil;
		creatureReq = creatureReq + 1;
		creatureFound = {};
		creatureStatus:SetText("...");
		send("C" .. creatureReq .. ":" .. (creatureSearch:GetText() or ""));
	end
end);

------------------------------------------------------------------------------------------------------------------
-- What the server says

frame:RegisterEvent("CHAT_MSG_ADDON");
frame:SetScript("OnEvent", function (self, event, prefix, message)
	if ( event ~= "CHAT_MSG_ADDON" or prefix ~= PREFIX or not message ) then
		return;
	end
	local kind, rest = string.sub(message, 1, 1), string.sub(message, 2);
	if ( kind == "n" or kind == "p" or kind == "e" or kind == "f" or kind == "u" ) then
		local req, body = string.match(rest, "^(%d+):(.*)$");
		req = tonumber(req) or 0;
		if ( kind == "n" ) then
			if ( req == request ) then table.insert(notes, body); end
		elseif ( kind == "p" ) then
			if ( req ~= request ) then return; end
			local cost, power, records = string.match(body, "^(%d+):(%a+):(%d+)$");
			if ( power == "points" ) then
				-- a passive: what it takes of the pool, and what is left for it (one being changed gives its own back)
				local left = pointsPool - pointsSpent;
				for _, spell in ipairs(spells) do
					if ( spell.id == editing and spell.passive ) then left = left + (tonumber(spell.cost) or 0); end
				end
				local over = (tonumber(cost) or 0) > left;
				costText:SetText((over and "|cffa00000" or "") .. "Takes " .. (cost or "?") .. " points of " .. math.max(0, left) .. " left"
					.. (over and "|r" or "") .. "  (" .. (records or "?") .. " record(s))");
			else
				costText:SetText("Costs " .. (cost or "?") .. " " .. (power or "") .. "  (" .. (records or "?") .. " record(s))");
			end
			notesText:SetText(#notes > 0 and ("|cff7a1a00Note:|r " .. table.concat(notes, "\n|cff7a1a00Note:|r ")) or "");
			notes = {};
			showPreview();
			forgeButton:Enable();
			saveNewButton:Enable();
		elseif ( kind == "e" ) then
			if ( req ~= 0 and req ~= request ) then return; end
			previewShown = false;
			tip:Hide();
			costText:SetText("");
			notesText:SetText("|cffa00000" .. (body or "") .. "|r");
			notes = {};
			forgeButton:Disable();
			saveNewButton:Disable();
		elseif ( kind == "f" or kind == "u" ) then
			-- the form now holds that spell: a later Save changes it
			local id = tonumber(body);
			UIErrorsFrame:AddMessage((kind == "f" and "Forged: " or "Saved: ") .. (recipe.name or ""), 1, 0.82, 0);
			if ( id ) then editing, selected = id, id; end
			showEditing();
			askList();
		end
	elseif ( kind == "c" ) then
		-- a creature: one of a search's ("c<req>:...") or a name asked for ("cn<entry>:...")
		local req, entry, level, ctype, name = string.match(rest, "^(%w+):(%d+):(%d+):(%d+):(.*)$");
		entry = tonumber(entry);
		if ( not entry ) then return; end
		creatureNames[entry] = name;
		if ( tonumber(req) == creatureReq ) then
			table.insert(creatureFound, { entry = entry, level = tonumber(level), type = tonumber(ctype), name = name });
		end
	elseif ( kind == "k" ) then
		local req, count = string.match(rest, "^(%w+):(%d+)$");
		if ( tonumber(req) == creatureReq ) then
			showCreatures();
			creatureStatus:SetText((count or "0") .. " found" .. ((tonumber(count) or 0) > CREATURE_ROWS and ": say more" or ""));
		elseif ( req and string.sub(req, 1, 1) == "n" ) then
			showEffects();
		end
	elseif ( kind == "l" or kind == "a" ) then
		-- a spell ("l") or a passive ("a": what it costs is points)
		local id, cost, name = string.match(rest, "^(%d+):(%d+):(.*)$");
		if ( id ) then table.insert(spells, { id = tonumber(id), cost = cost, name = name, passive = kind == "a" }); end
	elseif ( kind == "s" ) then
		-- the character's points for passives: taken, and the pool
		local spent, pool = string.match(rest, "^(%d+):(%d+)$");
		pointsSpent, pointsPool = tonumber(spent) or 0, tonumber(pool) or 0;
		showPoints();
	elseif ( kind == "o" ) then
		-- the character's slots: spells taken, spell slots, passives taken, passive slots
		local a, b, c, d = string.match(rest, "^(%d+):(%d+):(%d+):(%d+)$");
		if ( a ) then
			slots = { spells = tonumber(a), spellSlots = tonumber(b), passives = tonumber(c), passiveSlots = tonumber(d) };
			showSlots();
		end
	elseif ( kind == "w" ) then
		-- the resources the character may craft with, their own first
		allowedPowers = {};
		for power in string.gmatch(rest, "[^,]+") do table.insert(allowedPowers, power); end
		if ( #allowedPowers == 0 ) then allowedPowers = { "mana" }; end
		costMenu.items = costItems();
		costMenu:SetValue(recipe.power or allowedPowers[1]);
	elseif ( kind == "L" ) then
		showList();
	elseif ( kind == "x" ) then
		-- forgotten: what is in the form is a new spell from now on
		if ( tonumber(rest) == editing ) then editing = nil; end
		selected = nil;
		showEditing();
		askList();
	elseif ( kind == "r" ) then
		local id, part, parts, text = string.match(rest, "^(%d+):(%d+):(%d+):(.*)$");
		id, part, parts = tonumber(id), tonumber(part), tonumber(parts);
		if ( not id ) then return; end
		if ( pendingRecipe.id ~= id or pendingRecipe.parts ~= parts ) then
			pendingRecipe = { id = id, parts = parts, received = {} };
		end
		pendingRecipe.received[part] = text;
		for i = 1, parts do
			if ( not pendingRecipe.received[i] ) then return; end
		end
		local loaded, dropped = R.FromText(table.concat(pendingRecipe.received));
		pendingRecipe = {};
		if ( loaded ) then
			recipe = loaded;
			editing, selected = id, id;
			showEditing();
			showRecipe();
			if ( dropped and #dropped > 0 ) then
				UIErrorsFrame:AddMessage("Left out (the window has no place for it): " .. table.concat(dropped, ", "), 1, 0.4, 0.4);
			end
		end
	end
end);

-- A preview a moment after the last change
frame:SetScript("OnUpdate", function ()
	if ( changedAt and GetTime() - changedAt > 0.4 and GetTime() - lastPreview > 0.3 ) then
		changedAt = nil;
		lastPreview = GetTime();
		sendRecipe("P");
	end
end);

frame:SetScript("OnShow", function ()
	askList();
	showEditing();
	showRecipe();
end);

SLASH_OURSFORGE1 = "/forge";
SlashCmdList["OURSFORGE"] = function ()
	if ( frame:IsShown() ) then frame:Hide(); else frame:Show(); end
end;

------------------------------------------------------------------------------------------------------------------
-- A forged character has no talents (its passives are), so the Talents button of the bar below is the Spellforge's
-- for it, there from level 1 on, and N opens the forge. Its class underneath is only its stats; bots and characters
-- of the old make keep their talents.

local function forged ()
	return SpellforgeIsForged and SpellforgeIsForged();
end

local function toggleForge ()
	if ( frame:IsShown() ) then frame:Hide(); else frame:Show(); end
end

local FORGE_TIP = "Spellforge";
local FORGE_NEWBIE = "Craft your own spells and passives.";

-- the button as the game's own Character button is made: its empty frame, and a picture where the portrait goes
local forgeTurned, forgeIcon = false, nil;
local function forgeButton ()
	local b = TalentMicroButton;
	if ( not forged() or not b ) then return; end
	if ( not forgeTurned ) then
		forgeTurned = true;
		b:SetNormalTexture("Interface\\Buttons\\UI-MicroButtonCharacter-Up");
		b:SetPushedTexture("Interface\\Buttons\\UI-MicroButtonCharacter-Down");
		b:SetHighlightTexture("Interface\\Buttons\\UI-MicroButton-Hilight");
		forgeIcon = b:CreateTexture("OursForgeMicroIcon", "OVERLAY");
		forgeIcon:SetWidth(18);
		forgeIcon:SetHeight(25);
		forgeIcon:SetPoint("TOP", b, "TOP", 0, -28);
		forgeIcon:SetTexture("Interface\\Icons\\Trade_BlackSmithing");
		forgeIcon:SetTexCoord(0.14, 0.86, 0, 1);
		b.minLevel = 1;          -- (the game's UpdateMicroButtons holds the level against it)
		b.newbieText = FORGE_NEWBIE;
		b:SetScript("OnClick", toggleForge);
		b:SetScript("OnEvent", function (self, event)
			if ( event == "UPDATE_BINDINGS" ) then
				self.tooltipText = MicroButtonTooltipText(FORGE_TIP, "TOGGLETALENTS");
			end
		end);
	end
	b.tooltipText = MicroButtonTooltipText and MicroButtonTooltipText(FORGE_TIP, "TOGGLETALENTS") or FORGE_TIP;
	b:Show();
	b:Enable();
	if ( frame:IsShown() ) then
		b:SetButtonState("PUSHED", 1);
		forgeIcon:SetAlpha(0.5);
	else
		b:SetButtonState("NORMAL");
		forgeIcon:SetAlpha(1);
	end
end
frame.forgeButton = forgeButton;
frame.forgeTurned = function () return forgeTurned; end

if ( UpdateMicroButtons ) then hooksecurefunc("UpdateMicroButtons", forgeButton); end
frame:HookScript("OnShow", forgeButton);
frame:HookScript("OnHide", forgeButton);
local toggleTalents = ToggleTalentFrame;
function ToggleTalentFrame (...)
	if ( forged() ) then return toggleForge(); end
	if ( toggleTalents ) then return toggleTalents(...); end
end
local talentWatch = CreateFrame("Frame");
talentWatch:RegisterEvent("PLAYER_ENTERING_WORLD");
talentWatch:SetScript("OnEvent", forgeButton);
