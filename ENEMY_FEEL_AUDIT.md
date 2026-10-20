# Enemy Combat-Feel Audit

Started 2026-09-26. Goal: every enemy's combat reads at indie-dev quality — you can
*see* what each enemy is doing, what it did to you, and why. Combat already works;
this is about feel and legibility, not new balance.

Data source: `scripts/tools/enemy_kit_survey.gd` (dumps every enemy's real kit via
`create_by_type`), plus reading each ability's code path in `auto_battle_manager.gd`.
Art is out of scope (another agent owns it) but noted where it limits feel.

---

## 1. The rubric

Every enemy is scored on 7 steps. Each step is one moment in a fight a player can see.

| # | Step | The question it answers | Indie bar (what "3" looks like) |
|---|---|---|---|
| A | **Auto attack** | "It's hitting me" | Wind-up → contact → impact spark; ranged autos have their own projectile, not a generic orb |
| S | **Signature skill** | "It did its special thing" | Telegraph you can react to → the move → impact → result visible on the target |
| P | **Passive** | "It has a trait, and it's on right now" | Persistent readout while active + a one-shot beat when it turns on/off |
| St | **Status it applies** | "It did something to my hero, for how long" | Victim carries a distinct, readable mark for the whole duration + icon |
| F | **Fiction match** | "It looks like what the tooltip says" | The visual matches the ability's *name* (roots look like roots, not arrows) |
| E | **Element read** | "It's a Fire one / weak to X" | Its effects speak its element's stroke language; counter weaknesses are visible |
| B | **Big beats** | "Something important just happened" | Deaths, revives, splits, phase changes, shields breaking get a real moment |

**Scores are what the CODE shows, not a taste verdict.** I can't self-certify art.
- **✅** bespoke effect exists (built in the kit-polish pass) — *still needs your eye*
- **◐** generic / borrowed — works, but it's a shared placeholder or another unit's look
- **✗** missing, silent, or wrong fiction
- **—** not applicable (the kit has no such piece)

---

## 2. System-wide findings (affect every enemy)

These matter more than any single enemy — fixing one fixes dozens of fights.

### 2.1 Status effects are mostly invisible  ← biggest gap
The game already has **more statuses than stun and burn** — they just can't be seen:

| Status | Exists? | What the player sees today |
|---|---|---|
| Stun | yes | ✅ icon over head + flinch |
| Burn (fire) | yes | ◐ one orange puff when applied, **nothing while it ticks** |
| Disease / Venom | yes (burn flavours) | ✅ bespoke (Rat, Sky Wyvern) |
| Bleed | yes | ✅ (Bear's look, used for every bleed) |
| Corroded (weaken) | yes | ✅ (Slime only) |
| **Slow** | yes | ✗ nothing (Goblin Archer, Root Walker, Storm Crow apply it) |
| **Root** | yes | ✗ nothing |
| **Taunt** | yes | ✗ nothing |
| **Heal-cut** (Riptide) | yes | ✗ nothing |
| **Weaken** (non-slime) | yes | ✗ nothing |

**BUILT 2026-09-26 (step 1), awaiting owner review:** `StatusBadge`
(scripts/units/status_badge.gd — every status gets a code-drawn icon with a
draining duration ring; real art drops in via `STATUS_ICON_SHEETS`) and
`StatusFX` (scripts/combat/status_fx.gd — body marks for burn/slow/root/taunt/
heal-cut/weaken, skipped where a bespoke look exists). Gate:
`status_layer_probe`; review: `status_layer_capture`.

Original finding: only `stun` was in `STATUS_ICON_SHEETS`. **Proposal:** one shared status layer —
every status gets (1) an icon in the existing status row, (2) a body tint/overlay
for its duration, (3) an apply beat. Per-ability bespoke looks (Rat disease etc.)
stay on top of it.

### 2.2 No impact "juice"
No screen shake and no hit-stop anywhere in the game. Hits get a flash + recoil; the
full flinch only plays on stuns. **Proposal:** short hit-stop on crits and big skill
impacts, light camera shake reserved for elite/boss slams, stronger crit readout.

### 2.3 Shared-key leaks (borrowed or silent visuals)
Enemies reuse each other's code keys. Visuals are gated per unit, so a newer enemy
on an old key often inherits **nothing** or **the wrong look**:

| Enemy | Ability | Problem |
|---|---|---|
| Root Walker | Entangling Roots | ✗ fires the **Goblin Archer's arrow** |
| Storm Crow | Static Shriek | ✗ fires the **Goblin Archer's arrow** |
| Root Walker | Nature's Blessing | ◐ shows the **Goblin Shaman's aura** |
| Stone Golem | Granite Shell | ✗ plays a generic **holy-light** puff |
| Crystal Crab | Frenzied Clacking | ✗ silent (Fury readout gated to Bear/Minotaur/Wyvern) |
| Hellhound | Hunting Pack | ✗ silent (Pack readout gated to Goblin) |
| Storm Crow | Murder | ✗ silent (same gate) |
| Tidepool Horror | Pincer Slam | ✗ no wind-up (slam look gated to Orc/Ogre/Fire Giant) |
| Tidepool Horror | Deathgrip | ✗ silent (Focus stacks only drawn on the goblin arrow) |

### 2.4 Ranged autos are generic orbs
Only the Goblin Archer and Goblin Shaman have their own basic-attack projectile.
Troll, Lizard, Ember Phoenix, Root Walker, Storm Crow, Tidecaller, Tempest Conduit,
Stat Stealer, Aspect Devourer all throw the default orb.

### 2.5 Element counters aren't shown in combat
The Troll's regen readout shows *that* it's regenerating, not *what stops it*. The
two counter elements live only in the tooltip. See §4.

### 2.6 Art (out of scope, noted)
Most enemies are single still images animated procedurally. Only the Goblin
(3D) and Hill Giant, Gale Warden, Skyrender, Triarch (frame sheets) have real
animation. Tidepool Horror has **no art at all**. This caps how good auto attacks
can feel — VFX can carry a lot, but not everything.

---

## 3. Per-enemy scorecard

Elemental families (×6) share one kit, so one row covers all six.
Ordered roughly by when the player meets them.

### Normal enemies

| Enemy | A | S | P | St | F | E | B | Notes |
|---|---|---|---|---|---|---|---|---|
| Goblin | ✅ | ✅ Shank | ✅ Pack | — | ✅ | — | ◐ | 3D; reference quality |
| Goblin Archer | ✅ | ✅ Crippling Arrow | ✅ Focus Fire | ✗ slow | ✅ | — | ◐ | victim's slow is invisible |
| Goblin Shaman ×6 | ✅ | ✅ Mend | ✅ Spirit Link | — | ✅ | ◐ | ◐ | |
| Orc ×6 | ◐ | ✅ Crushing Blow | ✅ Bloodrage | ✅ stun | ✅ | ◐ | ◐ | |
| Slime ×6 | ◐ | ✅ Goo | ✅ Split | ✅ corroded | ✅ | ◐ | ✅ split | |
| Lizard ×6 | ◐ orb | ✅ Precision Shot | ✅ Cold Blood | — | ✅ | ◐ | ◐ | |
| Bear ×6 | ◐ | ✅ Rending Swipe | ✅ Fury | ✅ bleed | ✅ | ◐ | ◐ | |
| Troll ×6 | ◐ orb | ✅ Enrage | ✅ Regeneration | — | ✅ | ✗ counters hidden | ◐ | §2.5 |
| Wind-Up Bot ×6 | ✅ | ✅ Punch | ✅ Overclock | ✅ stun | ✅ | ◐ | ◐ | |
| Rat | ◐ | ✅ Infected Bite | ✅ Infestation | ✅ disease | ✅ | — | ◐ | |
| Skeleton | ◐ | ✅ Bone Shield | ✅ Undying | — | ✅ | — | ✅ reassemble | |
| Ogre | ◐ | ✅ (Orc's) | ✅ (Orc's) | ✅ stun | ✅ same name | — | ◐ | |
| Minotaur | ◐ | ✅ Gore Rush | ✅ Savage Charge | ✅ stun | ✅ | ◐ | ◐ | |
| Gargoyle | ◐ | ✅ Talon Rake | ◐ Stone Ward | — | ✅ | — | ◐ | ward reuses old seal look (new 09-24) |
| Stone Golem | ◐ | ✗ holy-light puff | — | — | ✗ | — | ◐ | §2.3 |
| Crystal Crab | ◐ | ✅ Shell | ✗ silent | — | ◐ | — | ✅ shell break | |
| Root Walker | ◐ orb | ✗ arrow | ◐ shaman aura | ✗ slow | ✗ | ◐ | ◐ | worst normal enemy |
| Fire Giant | ◐ | ✅ Molten Smash | ✅ Forge Fury | ✅ stun | ✅ | ✅ | ◐ | |
| Hellhound | ◐ | ◐ generic burn puff | ✗ silent | ◐ burn | ◐ | ◐ | ◐ | |
| Ember Phoenix | ◐ orb | ✅ Cinder Lance | ◐ Rebirth | — | ✅ | ✅ | ◐ | rebirth reuses old ember look (new 09-24) |
| Storm Giant | ◐ | ✅ Thunderclap | ✅ Gathering Storm | ✅ stun | ✅ | ✅ | ◐ | |
| Storm Crow | ◐ orb | ✗ arrow | ✗ silent | ✗ slow | ✗ | ◐ | ◐ | worst normal enemy |
| Sky Wyvern | ◐ | ✅ Venom Stinger | ✅ Wounded Dive | ✅ venom | ✅ | ◐ | ◐ | |
| Tidepool Horror | ✗ no art | ✗ no wind-up | ✗ silent | ? | ✗ | ◐ | ◐ | needs art first |
| Harpy | ◐ | ✅ Talon Rake | ✅ Windborne (evade) | ◐ bleed | ✅ | ◐ | ◐ | |
| Coral Husk | ◐ | ✅ Calcify | ✅ Slow Tide | — | ✅ | ✅ | ◐ | |

### Elites (one per decade) — NOT covered by the kit-polish pass

| Elite | A | S | P | Notes |
|---|---|---|---|---|
| Hill Giant | ✅ | ✅ Boulder Smash | — | done |
| Gale Warden | ◐ | ◐ generic Cyclone Shove | ✅ evade | |
| Tidecaller | ◐ orb | ◐ generic Tidal Ward | ? Tide Font | |
| Terracotta Colossus | ◐ | — | ? Set in Stone | |
| Magma Heart | — | — | ? Eruption | |
| Tempest Conduit | ◐ orb | ◐ generic Chain Discharge | — | chain should read as a chain |
| Mirrorplate Warden | ◐ | — | ? reflect | reflect is a perfect "you did this to yourself" moment |
| Aspect Devourer | ◐ orb | — | ? Devour Aspect | |
| Stat Stealer / Ant Hill | ◐ | ? | ? | |

### Decade bosses — deferred in the earlier pass
Hydra, Triarch, Khagan, Skyrender, Drowned Maw, Cloven Titan, Emberhollow,
Arcfang, Gravekeeper, The Architect. Mechanically distinct (see Decade Bosses notes)
but mostly generic `SkillEffect` visuals, no dedicated VFX files except Khagan. Each
deserves its own pass; they are the moments players remember.

### Boss pass, part 1 (2026-09-28) — mechanics + art fixes

**Root-cause finding:** bosses were near-inert for the whole game. None declared
an ultimate, so each inherited the default 300 charge pool; the generic ult
falls back to `_use_skill`, so every boss re-cast its signature ~1/s with no
cooldown, and that signature was the Warrior hero's Whirlwind, measured from the
2×2 corner, so it mostly hit nothing. Ults outrank attacks, so bosses rarely
auto-attacked (Gravekeeper: 111 ults, 0 attacks, 0 damage in a 97s fight).

**Owner rulings applied:** signatures do what their tooltips say
(`AutoBattleManager.BOSS_SIGNATURES`, one target unless it's a sweep/slam),
range measured from the body; all 10 bosses + Ember Heart now
`ultimate_charge_max = 0`. Gate: `boss_signature_probe`.

**Measured (6 fights each, 8-hero team at curve level, seed 100):** bosses now
fight (attack + signature on cooldown, 0 ults). Win rate unchanged where both
were measurable; fights cost more heroes (e.g. rd 90 survivors 8.0 → 5.2,
rd 50 8.0 → 6.3). With a realistic time cap, rd 40/60/100 all 6/6 wins
(survivors 4.3 / 1.8 / 3.0 of 8).

**Art:** 7 boss sprites were installed WITHOUT their green screen keyed
(arcfang, cloven_titan, drowned_maw, ember_heart, emberhollow, gravekeeper,
the_architect) — green rectangles in game since 07-28. Re-keyed via
tools/sprite_pipeline/key_boss_backgrounds.py (colour-distance key, catches
enclosed pockets + drops the ✦ watermark); originals backed up as
gemini_raw/<boss>/installed_green_backup_0928.png. Triarch has NO sprite
(renders the Warrior fallback) — owner art task. Khagan phase-1 art and the new
Tidepool Horror share one concept (octopus-riding crab) — owner call.

**Signature strike VFX:** BossStrikeVFX, one shape per boss (capture:
boss_vfx_capture). Still TODO: the passive/big-moment visuals below.

### Elite & boss work list (2026-09-26)

Boss signatures with no mob key fall through to the generic class effect, and
most boss passives have no visual at all (only Khagan has its own VFX). Almost
all of this is **VFX work (Claude, in code)**; art needs are marked 🎨 (owner).

| Enemy | Needs (VFX unless 🎨) |
|---|---|
| Gale Warden | ✅ BUILT 09-27: GaleVFX crescent gust + slide trail; victim body slides (VisualUnit.play_shove_slide) |
| Tidecaller | ✅ BUILT 09-27: TideVFX sapphire stream+dome (no more Nemi TIDE_WAVE); Tide Font ripple to true reach + droplets |
| Terracotta Colossus | ✅ BUILT 09-27: TerracottaVFX — riveted slabs rise around its base, 1 per 16 armor; 09-30: + skill Weight of Stone (slam grows with armor), Water/Air erosion weakness, windup/impact/hit/clang/rubble effects (TerracottaStrikeVFX) |
| Magma Heart | ✅ BUILT 09-26: MagmaVFX additive heartbeat telegraph, erupt globs, pulse pips |
| Tempest Conduit | ✅ BUILT 09-26: TempestVFX serpent chain from the Conduit through every link |
| Mirrorplate Warden | ✅ BUILT 09-26: MirrorVFX always-on sheen, glint + shard (rate-limited) |
| Aspect Devourer | ✅ BUILT 09-27: AspectVFX held sigil + swap countdown ring + ground glow; gulp/burst on swap |
| Stat Stealer | ✅ BUILT 09-27: StealVFX sand siphon w/ stat label, held-stat runes, own ward (no more Monk CHI_BURST / CHAOS_BOLT) |
| Ant Hill | ✅ BUILT 09-27: AnthillVFX RAGE counter + quickening ring; burrow burst on spawn |
| Hydra | Serpent Strike: per-head bite lines; Regrowth: head-grow moment |
| Triarch | form-change moment (it has frame art already) |
| Khagan | has VFX — review only |
| Skyrender | aloft/landing moments, <50% enrage read |
| Drowned Maw | Undertow bite; Riptide: persistent healing-cut aura on the whole field |
| Cloven Titan | Fault Line crack; split moment |
| Emberhollow + Ember Hearts | Backdraft; heart link to the boss; Hollow Return revive moment |
| Arcfang | Thunder Run: blink-flash with a trail showing where it went |
| Gravekeeper | Grave Toll sweep; Grave Call: hero-rises-as-shade moment |
| The Architect | trial-change moments (aloft / heal-cut / blink) |
| Tidepool Horror (normal) | 🎨 art DONE 2026-09-27 (owner's Gemini gen, keyed + installed); still needs Pincer Slam wind-up + Deathgrip readout |

---

## 4. Element counters — where they fit (see ELEMENT_COUNTERS.md)

Candidates among existing kits, for your decision (not built):

- **Shield family** — Skeleton Bone Shield, Stone Golem Granite Shell, Crystal Crab
  Crystalline Shell, Coral Husk Calcify all ride one shield key. A counter-element
  hit could **shatter the shield outright**. Four enemies, four natural fictions
  (bone / granite / crystal / coral), each with its own pair.
- **Troll** — keep the mechanic, but *show* the two counter elements on its regen
  readout (small element pips), and flash them when a counter hit lands.
- **Tutorial hook** — first Troll fight explains it (already noted, later).

## 5. Status-effect expansion (for your decision)

Existing statuses first need to be *visible* (§2.1). New ones should belong to
**specific abilities**, not to a whole element — element-wide statuses were built
and scrapped on 2026-08-02 because they stole identity from individual heroes.
Candidate statuses, each with an obvious owner:

| Status | Effect | Natural owner |
|---|---|---|
| Chill → Freeze | stacking slow; at N stacks, a short freeze | Tidecaller / water enemies |
| Shock | next hit taken arcs to a neighbour | Tempest Conduit / Storm Crow |
| Brittle | armor down; next big hit shatters it | Terracotta Colossus / Earth |
| Blind | misses some attacks | Gale Warden / Air |
| Silence | can't cast its skill | Stat Stealer / Aspect Devourer |
| Mark | takes bonus damage from all sources | Goblin Archer Focus Fire already *is* this — make it visible |

---

## 6. Proposed order of work

1. **Status layer** (§2.1) — icons + body marks for every existing status. Biggest
   feel win per hour; every enemy and hero benefits.
2. **Fix the broken fictions** (§2.3) — Root Walker, Storm Crow, Stone Golem, Crab,
   Hellhound, Tidepool Horror. Mostly VFX, no balance change.
3. **Impact juice** (§2.2) — hit-stop + crit + elite/boss shake.
4. **Element-counter readout** on the Troll, then the shield family if approved.
5. **Ranged auto projectiles** (§2.4).
6. **Elites**, then **bosses**, one at a time.

Each step: build → probe/arena gate → capture on the real grass board → your review.
