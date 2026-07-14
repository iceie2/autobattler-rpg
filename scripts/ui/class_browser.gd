extends CanvasLayer
class_name ClassBrowser

# ── Class data ────────────────────────────────────────────────────────────────
# Stats are pulled live from UnitFactory.CLASS_BASE_STATS via each entry's
# "unit_class", so the compendium can never drift from the real values. Only the
# flavour (role / skill text / lore / colour) lives here.
const IDLE_SOUTH_FRAME := Rect2(0, 640, 64, 64)

# Portrait sprite folder per class (omitted = no generated sheet yet → colour card).
const SPRITE_FOLDER := {
	UnitBase.UnitClass.BLOODHOUND: "warrior",
	UnitBase.UnitClass.BOUNCER:    "bouncer",
	UnitBase.UnitClass.HEADHUNTER: "archer",
	UnitBase.UnitClass.SHAUNA:     "shauna",
	UnitBase.UnitClass.NEMI:       "nemi",
	UnitBase.UnitClass.SHEILDOR:   "bouncer",
	UnitBase.UnitClass.LORDEE:     "warrior",
	UnitBase.UnitClass.NECRO:      "black_mage",
}

const CLASSES := [
	{
		"name": "Bloodhound", "unit_class": UnitBase.UnitClass.BLOODHOUND,
		"color": Color(0.8, 0.3, 0.25),
		"role": "Relentless bruiser that hunts its attacker",
		"skill": "Blood Frenzy  /  Bite  /  Pounce",
		"skill_color": Color(0.95, 0.4, 0.35),
		"skill_desc": (
			"[PASSIVE] Blood Frenzy — below 45% HP, Bloodhound enters a frenzy and locks " +
			"onto whichever enemy has dealt it the most damage, chasing them down.\n\n" +
			"[ACTIVE – 50 MP] Bite — savages the nearest enemy for 130% ATK and heals " +
			"Bloodhound for 30% of the damage dealt.\n\n" +
			"[ULTIMATE – 300 charge] Pounce — leaps onto its top damage-dealer for 250% " +
			"ATK and stuns them for 1.5s."
		),
		"lore": "A wounded Bloodhound is the most dangerous one. Let it dip low and it " +
			"becomes a heat-seeking missile aimed at whoever hurt it most."
	},
	{
		"name": "Bouncer", "unit_class": UnitBase.UnitClass.BOUNCER,
		"color": Color(0.3, 0.5, 0.9),
		"role": "Magic-damage tank that pulls enemies in",
		"hp": 1300, "mana": 600,
		"str": 8, "dex": 6, "int": 16, "res": 16,
		"atk": 11, "mag": 18, "def": 17,
		"move": 2, "range": 2,
		"skill": "Presence  /  Slam  /  Gravity Drop",
		"skill_color": Color(0.4, 0.65, 1.0),
		"skill_desc": (
			"[PASSIVE] Presence — each unit within 2 tiles grants +5% magic damage " +
			"(max +30%). The more crowded the battlefield, the harder Bouncer hits.\n\n" +
			"[ACTIVE – 80 MP] Slam — leaps to the nearest enemy, stunning them for " +
			"1.5s and dealing 100% MAG damage.\n\n" +
			"[ULTIMATE – 350 charge] Gravity Drop — creates a shockwave that pulls all " +
			"enemies in a 4-tile radius to the nearest open cell beside Bouncer, " +
			"dealing 150% MAG to every enemy caught."
		),
		"lore": "A wall of muscle and magic that drags the entire battlefield to itself. " +
			"Use Bouncer to disrupt enemy formations and protect your back line."
	},
	{
		"name": "Headhunter", "unit_class": UnitBase.UnitClass.HEADHUNTER,
		"color": Color(0.4, 0.85, 0.6),
		"role": "Long-range glass cannon sniper",
		"hp": 600, "mana": 350,
		"str": 14, "dex": 20, "int": 12, "res": 5,
		"atk": 24, "mag": 16, "def": 7,
		"move": 3, "range": 6,
		"skill": "Seventh Shot  /  Rapid Fire  /  Snipe",
		"skill_color": Color(0.5, 1.0, 0.65),
		"skill_desc": (
			"[PASSIVE] Seventh Shot — every 7th auto-attack is a guaranteed critical " +
			"hit dealing 3× damage. Keep the Headhunter alive and the crits roll in.\n\n" +
			"[ACTIVE – 60 MP] Rapid Fire — for 4 seconds attacks hit 1 extra " +
			"target and gain +2 attack range. Perfect for hitting the back line.\n\n" +
			"[ULTIMATE – 400 charge] Snipe — locks onto the farthest enemy and fires " +
			"a high-velocity shot for 400% ATK. The bullet can be intercepted by any " +
			"enemy standing in the line of fire."
		),
		"lore": "Devastating from afar but paper-thin up close. Keep the Headhunter " +
			"in the back row and pair with tanks who can soak incoming fire."
	},
	{
		"name": "Shauna", "unit_class": UnitBase.UnitClass.SHAUNA,
		"color": Color(0.1, 0.85, 0.85),
		"role": "Ranged attack carry with burst damage",
		"hp": 700, "mana": 400,
		"str": 12, "dex": 20, "int": 8, "res": 6,
		"atk": 22, "mag": 11, "def": 8,
		"move": 3, "range": 5,
		"skill": "Glass Cannon  /  Kite  /  Overdrive",
		"skill_color": Color(0.1, 0.9, 0.85),
		"skill_desc": (
			"[PASSIVE] Glass Cannon — every 3rd auto-attack deals true damage, " +
			"bypassing all defence and damage reduction.\n\n" +
			"[ACTIVE – 60 MP] Kite — when an enemy is focusing Shauna, she steps " +
			"1 cell away from the nearest enemy and marks her next auto for +50% " +
			"bonus damage.\n\n" +
			"[ULTIMATE – 400 charge] Overdrive — for 4 seconds Shauna attacks with " +
			"an extra swing every action, doubling her damage output."
		),
		"lore": "A nimble sharpshooter who builds momentum across every third shot " +
			"and accelerates into a damage frenzy. Pair with a frontline tank so " +
			"Shauna can kite freely without getting hit."
	},
	{
		"name": "Nemi", "unit_class": UnitBase.UnitClass.NEMI,
		"color": Color(0.95, 0.55, 0.05),
		"role": "Ranged disruptor support with bouncing waves",
		"hp": 750, "mana": 600,
		"str": 6, "dex": 10, "int": 18, "res": 10,
		"atk": 11, "mag": 20, "def": 11,
		"move": 2, "range": 4,
		"skill": "Resonance  /  Tide  /  Tidal Wave",
		"skill_color": Color(0.3, 0.75, 1.0),
		"skill_desc": (
			"[PASSIVE] Resonance — allies within 3 tiles of Nemi gain +1 move speed; " +
			"the nearest enemy is slowed by 1.\n\n" +
			"[ACTIVE – 80 MP] Tide — sends a bouncing chain that deals 80% MAG " +
			"to each enemy it hits and heals each ally it bounces to for the same amount. " +
			"Alternates between teams, up to 8 bounces.\n\n" +
			"[ULTIMATE – 450 charge] Tidal Wave — launches a 3-column-wide " +
			"surge forward. Enemies take 150% MAG damage and are pushed back 2 cells."
		),
		"lore": "A fluid mystic who controls the flow of battle through disruption " +
			"and sustain. Tidal Wave can completely reset the enemy formation if " +
			"timed at the right moment."
	},
	{
		"name": "Sheildor", "unit_class": UnitBase.UnitClass.SHEILDOR,
		"color": Color(0.4, 0.7, 1.0),
		"role": "Shield-based tank and protector",
		"hp": 1400, "mana": 700,
		"str": 10, "dex": 8, "int": 14, "res": 18,
		"atk": 14, "mag": 17, "def": 20,
		"move": 2, "range": 1,
		"skill": "Guardian Aura  /  Iron Bulwark  /  Guardian Leap",
		"skill_color": Color(0.5, 0.85, 1.0),
		"skill_desc": (
			"[PASSIVE] Guardian Aura — passively projects a protective presence that " +
			"reduces incoming damage to nearby allies.\n\n" +
			"[ACTIVE – 80 MP] Iron Bulwark — grants a shield (absorbs damage before HP) " +
			"to the most-wounded ally within 2 tiles, scaled by INT and their max HP. " +
			"Also heals them for 5% max HP. Shields last the duration of a round.\n\n" +
			"[ULTIMATE – 350 charge] Guardian Leap — blinks to the lowest-HP ally on " +
			"the field and wraps both of them in a massive shield (20% of ally max HP). " +
			"Sheildor also gains half that shield."
		),
		"lore": "A devoted protector who throws himself between allies and danger. " +
			"Sheildor's shields absorb damage before HP and stack with repeated casts — " +
			"place him near fragile carries to keep them alive."
	},
	{
		"name": "Lordee", "unit_class": UnitBase.UnitClass.LORDEE,
		"color": Color(0.85, 0.3, 0.9),
		"role": "Melee fighter with AoE aura and life-steal",
		"hp": 950, "mana": 500,
		"str": 16, "dex": 14, "int": 10, "res": 10,
		"atk": 23, "mag": 14, "def": 13,
		"move": 3, "range": 1,
		"skill": "Feeding Frenzy  /  Ground Slam  /  Parasite Lunge",
		"skill_color": Color(0.9, 0.4, 1.0),
		"skill_desc": (
			"[PASSIVE] Feeding Frenzy — every 0.8s, Lordee pulses dark energy dealing " +
			"12% ATK to all adjacent enemies. Completely automatic, always on.\n\n" +
			"[ACTIVE – 70 MP] Ground Slam — slams the ground in a 2-tile AoE around " +
			"the nearest enemy, dealing 120% ATK to all caught in the blast.\n\n" +
			"[ULTIMATE – 400 charge] Parasite Lunge — teleports to the nearest untapped " +
			"enemy, deals 150% ATK damage, and steals 7% of their attack power. " +
			"Marks that target for 20 seconds — Lordee hunts them until they die. " +
			"Each unique target can only be stolen from once per round."
		),
		"lore": "A ravenous predator who drains strength from its prey. Lordee grows " +
			"stronger with every kill and chews through clustered enemies with its aura. " +
			"Best positioned mid-board where the aura can reach multiple targets."
	},
	{
		"name": "Necro", "unit_class": UnitBase.UnitClass.NECRO,
		"color": Color(0.55, 0.9, 0.45),
		"role": "Summoner who raises undead to overwhelm enemies",
		"hp": 800, "mana": 900,
		"str": 5, "dex": 7, "int": 20, "res": 8,
		"atk": 8, "mag": 21, "def": 9,
		"move": 2, "range": 4,
		"skill": "Soul Harvest  /  Raise Zombie  /  Bat Swarm",
		"skill_color": Color(0.6, 1.0, 0.5),
		"skill_desc": (
			"[PASSIVE] Soul Harvest — while Necro has active summons, passively " +
			"regenerates HP by drawing life energy from them.\n\n" +
			"[ACTIVE – 120 MP] Raise Zombie — summons a Zombie in the cell directly " +
			"in front of Necro. Zombies are independent melee fighters that protect " +
			"Necro and despawn at round end. Multiple can be active at once.\n\n" +
			"[ULTIMATE – 500 charge] Bat Swarm — deals 60% MAG as AoE damage to all " +
			"enemies within 5 tiles, then summons 3 Bats around Necro. Bats are fast " +
			"flankers that also despawn at round end."
		),
		"lore": "A dark mage who never fights alone. Necro stays safely in the back " +
			"while a growing horde of undead absorbs hits and piles on pressure. " +
			"Every mana spent is another body on the field."
	},
	# ── Roster expansion ──────────────────────────────────────────────────────
	{
		"name": "Doc", "unit_class": UnitBase.UnitClass.DOC,
		"color": Color(0.3, 0.8, 0.8),
		"role": "Triage support — heals scale with the wound",
		"skill": "Triage  /  Inject  /  Field Surgery",
		"skill_color": Color(0.4, 0.9, 0.85),
		"skill_desc": (
			"[PASSIVE] Triage — every ~1.4s Doc patches up the lowest-HP ally nearby; the " +
			"more HP they're missing, the bigger the mend.\n\n" +
			"[ACTIVE – 70 MP] Inject — a burst heal on the most-wounded ally in range, " +
			"scaling hard with their missing HP.\n\n" +
			"[ULTIMATE – 450 charge] Field Surgery — once per battle, revives a fallen " +
			"ally at 30% HP. With no one to revive, it emergency-heals the whole team."
		),
		"lore": "A back-alley surgeon who works best when things are already going wrong. " +
			"Let allies dip low and Doc's heals hit hardest."
	},
	{
		"name": "Riot", "unit_class": UnitBase.UnitClass.RIOT,
		"color": Color(0.55, 0.6, 0.75),
		"role": "Frontline tank that controls aggro",
		"skill": "Crowd Control  /  Shield Bash  /  Kettle",
		"skill_color": Color(0.65, 0.7, 0.9),
		"skill_desc": (
			"[PASSIVE] Crowd Control — any enemy that damages Riot is briefly slowed.\n\n" +
			"[ACTIVE – 60 MP] Shield Bash — stuns the nearest enemy for 1.2s and taunts " +
			"them onto Riot for 3s.\n\n" +
			"[ULTIMATE – 350 charge] Kettle — forces every enemy to target Riot for 4s, " +
			"freeing the rest of the team to act untouched."
		),
		"lore": "An ex-riot cop who turns the enemy's attention into your advantage. " +
			"Pop Kettle and your carries get four free seconds."
	},
	{
		"name": "Pastor", "unit_class": UnitBase.UnitClass.PASTOR,
		"color": Color(1.0, 0.55, 0.2),
		"role": "Buff/debuff support-disruptor",
		"skill": "Righteous Fury  /  Sermon  /  Damnation",
		"skill_color": Color(1.0, 0.65, 0.3),
		"skill_desc": (
			"[PASSIVE] Righteous Fury — allies within 3 tiles deal +12% damage.\n\n" +
			"[ACTIVE – 70 MP] Sermon — grants the strongest nearby ally +40% attack speed " +
			"for 5s.\n\n" +
			"[ULTIMATE – 400 charge] Damnation — curses every enemy, cutting their damage " +
			"output to 60% for the rest of the round."
		),
		"lore": "A street preacher who lifts up the faithful and damns everyone else. " +
			"Equal parts cheerleader and curse."
	},
	{
		"name": "Sable", "unit_class": UnitBase.UnitClass.SABLE,
		"color": Color(0.75, 0.95, 1.0),
		"role": "Ranged carry that snowballs on momentum",
		"skill": "Momentum  /  Bolt  /  Headshot",
		"skill_color": Color(0.8, 1.0, 1.0),
		"skill_desc": (
			"[PASSIVE] Momentum — every shot stacks +6% damage on the next (up to 12 " +
			"stacks). Keep firing to ramp up.\n\n" +
			"[ACTIVE – 50 MP] Bolt — a piercing shot down Sable's column, hitting every " +
			"enemy in the line.\n\n" +
			"[ULTIMATE – 400 charge] Headshot — one massive hit (400% ATK, +12% per " +
			"momentum stack) that resets all stacks."
		),
		"lore": "A patient crossbow sniper who gets deadlier the longer a fight drags on. " +
			"Protect Sable and the momentum becomes lethal."
	},
	{
		"name": "Rush", "unit_class": UnitBase.UnitClass.RUSH,
		"color": Color(1.0, 0.95, 0.3),
		"role": "Hyper-mobile fighter that hits the backline",
		"skill": "Fleetfoot  /  Blitz  /  Afterimage",
		"skill_color": Color(1.0, 1.0, 0.45),
		"skill_desc": (
			"[PASSIVE] Fleetfoot — the fastest mover on the board, reaching the back row " +
			"in a heartbeat.\n\n" +
			"[ACTIVE – 60 MP] Blitz — dashes through an entire enemy row, striking each " +
			"unit in it, then re-positions beside the target.\n\n" +
			"[ULTIMATE – 400 charge] Afterimage — freezes every other unit (allies " +
			"included) for 3s while Rush acts freely, opening with a hit on every enemy."
		),
		"lore": "A parkour street-runner who's gone before anyone can react. Afterimage is " +
			"a literal three seconds where only Rush exists."
	},
	{
		"name": "Stitch", "unit_class": UnitBase.UnitClass.STITCH,
		"color": Color(0.6, 0.35, 0.75),
		"role": "Disruptor that ties enemies together",
		"skill": "Loose Threads  /  Link  /  Puppet",
		"skill_color": Color(0.72, 0.45, 0.9),
		"skill_desc": (
			"[PASSIVE] Loose Threads — while Stitch lives, 8% of all damage dealt to any " +
			"enemy bleeds to every other enemy. Always on.\n\n" +
			"[ACTIVE – 70 MP] Link — binds the two nearest enemies so they share half of " +
			"all damage either takes.\n\n" +
			"[ULTIMATE – 450 charge] Puppet — seizes control of an enemy for 4s, turning " +
			"its auto-attacks against its own team."
		),
		"lore": "A voodoo practitioner who's always pulling strings. Even idle, the whole " +
			"enemy team bleeds together."
	},
	{
		"name": "Coal", "unit_class": UnitBase.UnitClass.COAL,
		"color": Color(0.95, 0.4, 0.2),
		"role": "Burn brawler with escalating fire",
		"skill": "Smolder  /  Stoke  /  Meltdown",
		"skill_color": Color(1.0, 0.5, 0.25),
		"skill_desc": (
			"[PASSIVE] Smolder — every punch sets the target on fire (burn damage over " +
			"time).\n\n" +
			"[ACTIVE – 50 MP] Stoke — Coal's next 3 attacks apply double burn stacks.\n\n" +
			"[ULTIMATE – 400 charge] Meltdown — for 5s every punch explodes on impact; " +
			"afterward Coal briefly cools down and is weakened."
		),
		"lore": "A bare-knuckle furnace worker whose fists never stop burning. High risk on " +
			"the cooldown, high reward during the blaze."
	},
	{
		"name": "June", "unit_class": UnitBase.UnitClass.JUNE,
		"color": Color(0.45, 0.8, 0.4),
		"role": "Support with regen and area control",
		"skill": "Verdant Aura  /  Root  /  Bloom",
		"skill_color": Color(0.55, 0.9, 0.5),
		"skill_desc": (
			"[PASSIVE] Verdant Aura — allies within 3 tiles slowly regenerate HP.\n\n" +
			"[ACTIVE – 60 MP] Root — vines pin the nearest enemy in place for 3s.\n\n" +
			"[ULTIMATE – 400 charge] Bloom — thorns cover the whole field for 8s; enemies " +
			"take damage every step they move."
		),
		"lore": "An urban herbalist whose garden is a battlefield. Bloom punishes any enemy " +
			"that dares to advance."
	},
	{
		"name": "Cross", "unit_class": UnitBase.UnitClass.CROSS,
		"color": Color(0.95, 0.92, 0.7),
		"role": "Self-sustaining tank that converts healing to damage",
		"skill": "Penance  /  Absolution  /  Judgment",
		"skill_color": Color(1.0, 0.95, 0.6),
		"skill_desc": (
			"[PASSIVE] Penance — Cross heals himself for 35% of every hit he takes.\n\n" +
			"[ACTIVE – 60 MP] Absolution — cleanses all debuffs from the most-wounded " +
			"ally and heals them.\n\n" +
			"[ULTIMATE – 400 charge] Judgment — strikes every enemy for damage equal to " +
			"60% of all the healing Cross has done this battle."
		),
		"lore": "A vigilante holy knight who turns punishment into power. The longer he " +
			"endures, the harder Judgment lands."
	},
	{
		"name": "Sear", "unit_class": UnitBase.UnitClass.SEAR,
		"color": Color(1.0, 0.45, 0.15),
		"role": "Magic fighter that spreads fire",
		"skill": "Scorched Path  /  Ignite  /  Conflagration",
		"skill_color": Color(1.0, 0.55, 0.2),
		"skill_desc": (
			"[PASSIVE] Scorched Path — Sear leaves a burning trail on every tile he " +
			"walks; enemies crossing it catch fire.\n\n" +
			"[ACTIVE – 60 MP] Ignite — sets a target ablaze with a long, heavy burn.\n\n" +
			"[ULTIMATE – 420 charge] Conflagration — copies the strongest active burn onto " +
			"every enemy and detonates a chunk of it instantly."
		),
		"lore": "A robe-burning zealot who turns the whole arena into kindling. Pairs " +
			"viciously with other fire heroes."
	},
	{
		"name": "Ember", "unit_class": UnitBase.UnitClass.EMBER,
		"color": Color(1.0, 0.55, 0.25),
		"role": "Ranged carry that ignites clusters",
		"skill": "Burning Arrows  /  Cinder Shot  /  Wildfire",
		"skill_color": Color(1.0, 0.6, 0.3),
		"skill_desc": (
			"[PASSIVE] Burning Arrows — every arrow applies a burn on hit.\n\n" +
			"[ACTIVE – 50 MP] Cinder Shot — ignites all enemies in a 2-tile area around " +
			"the nearest target.\n\n" +
			"[ULTIMATE – 420 charge] Wildfire — every burning enemy violently explodes, " +
			"dealing area damage around itself."
		),
		"lore": "A fire dancer turned archer. On her own she chips; alongside Coal and " +
			"Sear the whole board goes up at once."
	},
	{
		"name": "Rift", "unit_class": UnitBase.UnitClass.RIFT,
		"color": Color(0.55, 0.4, 0.8),
		"role": "Magic fighter that bends space",
		"skill": "Backlash  /  Tear  /  Collapse",
		"skill_color": Color(0.68, 0.5, 0.95),
		"skill_desc": (
			"[PASSIVE] Backlash — 30% of any damage Rift takes is redirected to a random " +
			"enemy.\n\n" +
			"[ACTIVE – 60 MP] Tear — banishes the nearest enemy to the far edge of the " +
			"field, out of the fight for a moment.\n\n" +
			"[ULTIMATE – 450 charge] Collapse — yanks every enemy into the centre of the " +
			"board and detonates a concentrated burst before they scatter."
		),
		"lore": "A reality-warper trailed by tears in space. Collapse turns a spread-out " +
			"enemy team into one tidy target."
	},
	{
		"name": "Zolt", "unit_class": UnitBase.UnitClass.ZOLT,
		"color": Color(1.0, 0.95, 0.35),
		"role": "Magic carry with roaming storms",
		"skill": "Chain Lightning  /  Thunderstorm  /  Thunderhammer",
		"skill_color": Color(1.0, 1.0, 0.45),
		"skill_desc": (
			"[PASSIVE] Chain Lightning — every 6th auto arcs lightning to all enemies " +
			"within 3 tiles.\n\n" +
			"[ACTIVE – 90 MP] Thunderstorm — conjures a roaming storm hazard that drifts " +
			"the board in one direction. Its own tile takes full lightning damage plus a " +
			"0.5s stun; the 8 tiles around it take half damage. Persists until the round " +
			"ends — stack several and the field becomes a deathtrap.\n\n" +
			"[ULTIMATE – 480 charge] Thunderhammer — slams the toughest enemy for huge " +
			"lightning damage and a 5s stun."
		),
		"lore": "A storm-caller who litters the arena with hazards. Give Zolt time and the " +
			"board itself fights for you."
	},
	{
		"name": "Lumen", "unit_class": UnitBase.UnitClass.LUMEN,
		"color": Color(0.8, 1.0, 1.0),
		"role": "Magic carry whose attacks ricochet",
		"skill": "Refraction  /  Refract  /  Prism",
		"skill_color": Color(0.85, 1.0, 1.0),
		"skill_desc": (
			"[PASSIVE] Refraction — every attack bounces to one extra enemy automatically.\n\n" +
			"[ACTIVE – 60 MP] Refract — fires a beam that ricochets between up to 5 enemies, " +
			"weakening with each bounce.\n\n" +
			"[ULTIMATE – 460 charge] Prism — splits into beams that strike every enemy on " +
			"the field at once."
		),
		"lore": "A light-bending mage who never hits just one target. The more enemies " +
			"clustered, the more her beams find."
	},
	{
		"name": "Static", "unit_class": UnitBase.UnitClass.STATIC,
		"color": Color(1.0, 0.95, 0.4),
		"role": "Disruptor that punishes movement",
		"skill": "Live Wire  /  Tripwire  /  Grid",
		"skill_color": Color(1.0, 1.0, 0.5),
		"skill_desc": (
			"[PASSIVE] Live Wire — any enemy that ends a move next to Static is shocked " +
			"and briefly slowed.\n\n" +
			"[ACTIVE – 60 MP] Tripwire — stuns the nearest enemy for 3s as if it crossed a " +
			"live wire.\n\n" +
			"[ULTIMATE – 420 charge] Grid — electrifies the entire floor for 4s; enemies " +
			"take damage with every step."
		),
		"lore": "A saboteur who weaponised the power grid. Standing still near Static is " +
			"bad; moving across the Grid is worse."
	},
	{
		"name": "Reed", "unit_class": UnitBase.UnitClass.REED,
		"color": Color(0.35, 0.7, 1.0),
		"role": "Water support and cleanser",
		"skill": "Wellspring  /  Cleanse  /  Confluence",
		"skill_color": Color(0.45, 0.78, 1.0),
		"skill_desc": (
			"[PASSIVE] Wellspring — nearby allies regenerate HP and shed debuffs 30% " +
			"faster.\n\n" +
			"[ACTIVE – 60 MP] Cleanse — strips all debuffs from the most-wounded ally and " +
			"heals them.\n\n" +
			"[ULTIMATE – 430 charge] Confluence — heals the whole team, scaling up for " +
			"every Water-aspect unit on your side (the payoff for a water comp)."
		),
		"lore": "A river hermit who rewards committing to water. The more of the team flows " +
			"with her, the bigger Confluence heals."
	},
	{
		"name": "Vail", "unit_class": UnitBase.UnitClass.VAIL,
		"color": Color(0.8, 0.95, 1.0),
		"role": "Air support with global reach",
		"skill": "Far Winds  /  Updraft  /  Tailwind",
		"skill_color": Color(0.85, 1.0, 1.0),
		"skill_desc": (
			"[PASSIVE] Far Winds — Vail's heals reach any ally anywhere on the field.\n\n" +
			"[ACTIVE – 60 MP] Updraft — lifts the most-wounded ally on a gust, making them " +
			"untargetable for 2s.\n\n" +
			"[ULTIMATE – 420 charge] Tailwind — grants the entire team increased move and " +
			"attack speed for 6s."
		),
		"lore": "A wind-healer who carries aid on the breeze. Updraft can yank a focused " +
			"carry out of danger at the perfect moment."
	},
	{
		"name": "Spore", "unit_class": UnitBase.UnitClass.SPORE,
		"color": Color(0.55, 0.75, 0.35),
		"role": "Magic carry that wins by attrition",
		"skill": "Spore Cloud  /  Bloom  /  Release",
		"skill_color": Color(0.65, 0.85, 0.4),
		"skill_desc": (
			"[PASSIVE] Spore Cloud — enemies within 2 tiles gather spore stacks each " +
			"second; at 10 stacks they take a burst of damage.\n\n" +
			"[ACTIVE – 50 MP] Bloom — instantly max-stacks one target, triggering its " +
			"burst right away.\n\n" +
			"[ULTIMATE – 440 charge] Release — detonates the accumulated spores on every " +
			"enemy at once, scaled by how many stacks each had built."
		),
		"lore": "A fungal mage who plays the long game. Let the cloud sit and Release turns " +
			"patience into a board-wide payoff."
	},
]

var _idx := 0
signal closed()

# UI refs
var _panel: Panel
var _portrait: TextureRect
var _class_idx_lbl: Label
var _class_name_lbl: Label
var _role_lbl: Label
var _lore_lbl: Label
var _stat_lbl: Label
var _skill_name_lbl: Label
var _skill_desc_lbl: Label

func _ready() -> void:
	_build_ui()

func open(start_idx: int = 0) -> void:
	_idx = clamp(start_idx, 0, CLASSES.size() - 1)
	visible = true
	_refresh()

func _build_ui() -> void:
	# Dark overlay
	var overlay := ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.72)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.gui_input.connect(_on_overlay_input)
	add_child(overlay)

	# Main panel — wider to give room for lore + skill desc
	_panel = Panel.new()
	_panel.size = Vector2(720, 600)
	_panel.add_theme_stylebox_override("panel",
		_flat(Color(0.09, 0.09, 0.15, 0.98), Color(0.4, 0.4, 0.65), 2, 10))
	overlay.add_child(_panel)

	# Title
	_lbl(_panel, "CLASS COMPENDIUM", 20, Color(0.8, 0.8, 1.0),
		Vector2(0, 14), Vector2(720, 36), true)

	# Close button
	var close_btn := _btn("✕", Rect2(678, 8, 34, 34))
	close_btn.pressed.connect(_close)
	_panel.add_child(close_btn)

	var _sep_top := _hsep(_panel, 58, 720)

	# ── Portrait area (left column) ───────────────────────────────────────────
	# Sprite sits directly on the panel — no intermediate background box
	# (2026-07-04 user report: panel > box > sprite should just be panel >
	# sprite). The element's color is already conveyed via _class_name_lbl's
	# font color below, so nothing is lost by dropping the tinted backdrop.
	_portrait = TextureRect.new()
	_portrait.position = Vector2(24, 72)
	_portrait.size = Vector2(140, 140)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_panel.add_child(_portrait)

	# Class number badge on portrait
	_class_idx_lbl = _lbl(_panel, "", 13, Color(0, 0, 0, 0.85),
		Vector2(24, 202), Vector2(140, 22), true)

	# ── Name, role, lore (right of portrait) ─────────────────────────────────
	_class_name_lbl = _lbl(_panel, "", 30, Color(1.0, 0.9, 0.6),
		Vector2(180, 68), Vector2(480, 44))
	_role_lbl = _lbl(_panel, "", 14, Color(0.65, 0.75, 0.95),
		Vector2(180, 112), Vector2(480, 24))
	_lore_lbl = _lbl(_panel, "", 12, Color(0.65, 0.65, 0.75),
		Vector2(180, 140), Vector2(480, 68))
	_lore_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	# ── Stats row ─────────────────────────────────────────────────────────────
	var _sep_stat := _hsep(_panel, 228, 720)
	_lbl(_panel, "BASE STATS", 12, Color(0.55, 0.6, 0.85),
		Vector2(24, 238), Vector2(200, 20))
	_stat_lbl = _lbl(_panel, "", 13, Color(0.82, 0.82, 0.95),
		Vector2(24, 260), Vector2(672, 80))

	# ── Skill section ─────────────────────────────────────────────────────────
	var _sep_skill := _hsep(_panel, 352, 720)
	_lbl(_panel, "CLASS SKILL", 12, Color(0.55, 0.6, 0.85),
		Vector2(24, 362), Vector2(200, 20))
	_skill_name_lbl = _lbl(_panel, "", 20, Color(1.0, 0.85, 0.3),
		Vector2(24, 384), Vector2(672, 30))
	_skill_desc_lbl = _lbl(_panel, "", 12, Color(0.72, 0.72, 0.82),
		Vector2(24, 418), Vector2(672, 130))
	_skill_desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	# ── Navigation ────────────────────────────────────────────────────────────
	var _sep_nav := _hsep(_panel, 560, 720)
	var prev_btn := _btn("◀  Previous", Rect2(24, 570, 160, 22))
	prev_btn.pressed.connect(_prev)
	_panel.add_child(prev_btn)
	var next_btn := _btn("Next  ▶", Rect2(536, 570, 160, 22))
	next_btn.pressed.connect(_next)
	_panel.add_child(next_btn)

	visible = false
	_center_panel()

func _center_panel() -> void:
	var vp := get_viewport().get_visible_rect().size if get_viewport() else Vector2(1800, 1080)
	_panel.position = (vp - _panel.size) / 2.0

func _refresh() -> void:
	var c: Dictionary = CLASSES[_idx]
	var uc: int = c["unit_class"]

	# Try AI-generated portrait first (file name = hero name lowercased).
	var ai_path: String = "res://assets/using/%s.png" % c["name"].to_lower()
	var ai_tex: Texture2D = null
	if ResourceLoader.exists(ai_path):
		ai_tex = load(ai_path) as Texture2D
	if ai_tex != null and ai_tex.get_width() > 0:
		_portrait.texture = ai_tex
		_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	else:
		# Fall back to idle-south frame from LPC sprite sheet.
		var folder: String = SPRITE_FOLDER.get(uc, "")
		var sheet: Texture2D = null
		if folder != "":
			sheet = load("res://assets/sprites/generated/%s/0/single.png" % folder) as Texture2D
		if sheet:
			var atlas := AtlasTexture.new()
			atlas.atlas = sheet
			atlas.region = IDLE_SOUTH_FRAME
			_portrait.texture = atlas
		else:
			_portrait.texture = null

	_class_idx_lbl.text  = "%s  (%d / %d)" % [c["name"], _idx + 1, CLASSES.size()]
	_class_name_lbl.text = c["name"]
	_class_name_lbl.add_theme_color_override("font_color", c["color"])
	_role_lbl.text  = c["role"]
	_lore_lbl.text  = c["lore"]

	# Stats pulled live from the factory so they always match the real units.
	var s: Dictionary = UnitFactory.CLASS_BASE_STATS.get(uc, {})
	_stat_lbl.text = (
		"HP: %-6d  Mana: %-6d  Move: %-3d  Range: %d\n" +
		"Attack: %-4d  Magic: %-4d  Defense: %-4d\n" +
		"Attack Speed: %-4.2f  HP/s: %-4.2f  MP/s: %.2f"
	) % [s.get("hp", 0), s.get("mana", 0), s.get("move", 0), s.get("range", 0),
		 s.get("atk", 0), s.get("magic", 0), s.get("res", 0),
		 s.get("aspd", 0.0), s.get("hpregen", 0.0), s.get("manaregen", 0.0)]

	_skill_name_lbl.text = c["skill"]
	_skill_name_lbl.add_theme_color_override("font_color", c["skill_color"])
	_skill_desc_lbl.text = c["skill_desc"]

func _prev() -> void:
	_idx = (_idx - 1 + CLASSES.size()) % CLASSES.size()
	_refresh()

func _next() -> void:
	_idx = (_idx + 1) % CLASSES.size()
	_refresh()

func _close() -> void:
	visible = false
	closed.emit()

func _on_overlay_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not _panel.get_rect().has_point(_panel.get_local_mouse_position()):
			_close()

func _input(event: InputEvent) -> void:
	if not visible: return
	if event.is_action_pressed("ui_cancel"): _close()
	if event.is_action_pressed("ui_left"):   _prev()
	if event.is_action_pressed("ui_right"):  _next()

# ── Helpers ───────────────────────────────────────────────────────────────────
func _lbl(parent: Node, text: String, sz: int, col: Color,
		pos: Vector2, size: Vector2, center: bool = false) -> Label:
	var l := Label.new()
	l.text = text; l.position = pos; l.size = size
	l.add_theme_font_size_override("font_size", UITheme.body_font(sz))
	l.add_theme_color_override("font_color", col)
	if center: l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(l)
	return l

func _btn(text: String, rect: Rect2) -> Button:
	var b := Button.new()
	b.text = text; b.position = rect.position; b.size = rect.size
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_color_override("font_color", Color(0.9, 0.9, 1.0))
	b.add_theme_stylebox_override("normal",  _flat(Color(0.18, 0.18, 0.28), Color(0.45, 0.45, 0.6), 1, 4))
	b.add_theme_stylebox_override("hover",   _flat(Color(0.26, 0.26, 0.38), Color(0.6, 0.6, 0.8),  1, 4))
	b.add_theme_stylebox_override("pressed", _flat(Color(0.12, 0.12, 0.22), Color(0.3, 0.3, 0.5),  1, 4))
	return b

func _hsep(parent: Node, y: float, width: float) -> HSeparator:
	var s := HSeparator.new()
	s.position = Vector2(0, y); s.size = Vector2(width, 4)
	parent.add_child(s)
	return s

func _flat(bg: Color, border: Color = Color.TRANSPARENT,
		bw: int = 0, radius: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg; s.border_color = border
	s.border_width_left = bw; s.border_width_right = bw
	s.border_width_top = bw;  s.border_width_bottom = bw
	s.corner_radius_top_left = radius; s.corner_radius_top_right = radius
	s.corner_radius_bottom_left = radius; s.corner_radius_bottom_right = radius
	return s
