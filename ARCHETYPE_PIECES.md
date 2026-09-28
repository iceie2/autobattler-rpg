# Archetype Pieces for Roles and Elements - design worksheet

Status: DRAFT for owner review, written 2026-09-27. Decision record:
`VERTICAL_DEPTH_BACKLOG.md` **VD-22**. This worksheet proposes; it does not
decide. Piece effects are moves, so the owner keeps, changes or cuts each row
before any code (numbers are free to tune in the arena).

Owner, 2026-09-27: *"i think the next focus should be making more syergentic
relics like we did for burn. we need ones for the different elements for the
different roles. etc"*

## How Burn works (the pattern to copy)

Burn (VD-16, `BUILD_ARCHETYPES.md`) has a **seed** and four **pieces**:
- The seed is offered on the run's first relic screen. It also makes the
  shop show that archetype's heroes more often, so the player can act on it.
- Each later relic screen reserves one of its three cards for a piece whose
  archetype the team already fields.
- Each piece is one effect with a magnitude by grade (D-S), like every other
  relic.

## Rules carried over (already decided)

1. **The direction test** (VD-16): a piece must change which heroes you want
   next. "+10% attack" is an upgrade; "+X per Tank you field" is a direction.
2. **A piece amplifies something that is a real share of the team's power.**
   Burn pieces measured weak because burn is ~14% of a Burn team's damage
   (VD-16). Every draft below names the share it leans on.
3. **Never hand a move to a whole element** (VD-16 rule 1, after the 2026-08-02
   element-status scrap). An element piece may only amplify a move that
   element's heroes already have. This is why elements are harder than roles -
   see "Elements" below.
4. **Say which damage.** Damage relics currently reach basic attacks only
   (VD-21). A draft that says "damage" names the source.
5. **Loop safety** (Burn's owner concern). Nothing that refunds ult charge may
   refund it from an ult. Payoffs may read totals but never create more of
   what they read.
6. **Every piece has a visible cue** in combat.

## Who can build what

`*` = starter hero. Counts are heroes on the 26-hero roster.

| Role | Heroes | Starters |
|---|---|---|
| Mage (9) | Lumen, Nemi*, Pastor, Rift, Sear, Spore, Static*, Stitch, Zolt | 2 |
| Fighter (5) | Bloodhound*, Coal, Lordee, Rush, Shauna* | 2 |
| Tank (4) | Bouncer*, Cross, Riot, Sheildor | 1 |
| Healer (4) | Doc, June, Reed, Vail | 0 |
| Ranged (3) | Ember, Headhunter*, Sable | 1 |
| Summoner (1) | Necro | 0 |

| Element | Heroes | Move they share |
|---|---|---|
| Lightning (6) | Lumen, Rift, Riot, Rush, Static*, Zolt | **Stuns** (Static, Riot, Rush, Zolt); chain hits (Lumen, Zolt) |
| Fire (5) | Coal, Ember, Pastor, Sear, Shauna* | **Burn** (Coal, Sear, Ember) - built |
| Normal (5) | Bouncer*, Cross, Lordee, Necro, Stitch | none - pull, area, guard, retaliate, summon |
| Earth (4) | Bloodhound*, June, Sheildor, Spore | thin - one shielder, one rooter |
| Water (3) | Doc, Nemi*, Reed | **Healing** (all three) - but Doc and Reed are also Healers |
| Air (3) | Headhunter*, Sable, Vail | thin - every-Nth shot, ramp, attack-speed aura |

A fresh account can build Mage and Fighter from starters alone. Burn still needs
three tree unlocks.

## Roles - drafts

Every role follows the Burn shape: seed, enabler, two payoffs, capstone. "Per X
hero" always means distinct heroes fielded, max 3 (like Kindling).

### Tank - leans on: damage taken (tanks absorb most of the enemy's damage)

| # | Piece | Draft effect | Makes you want | Cue | State |
|---|---|---|---|---|---|
| T1 | **Bulwark Oath** (seed) | Tanks take 6% less damage per Tank you field. | a 2nd and 3rd Tank | steel rim on Tank HP bars | |
| T2 | **Shared Burden** (enabler) | 20% of the damage your other heroes take is moved to the nearest Tank. | Tanks next to your carries | thin chain from the ally to the Tank on each moved hit | |
| T3 | **Retribution** (payoff) | Each Tank deals 15% of the damage it takes back to its attacker. | Tanks that get hit a lot (Riot's taunt) | spark back along the attack | |
| T4 | **Iron Will** (payoff) | Tanks' ultimates charge 30% faster from damage taken. | several Tanks, so ults stagger | Tank ult bars glow steel | |
| T5 | **Last Wall** (capstone) | While a Tank is alive, heroes in the rows behind it take 15% less damage. | a full front row of Tanks | faint wall line behind the front row | |

### Mage - leans on: skill and ult damage (magic power drives it)

| # | Piece | Draft effect | Makes you want | Cue | State |
|---|---|---|---|---|---|
| M1 | **Arcane Circle** (seed) | Mages get +10% magic power per Mage you field. | more Mages | violet glyph under each Mage | |
| M2 | **Resonance** (enabler) | When a Mage casts its ultimate, every other Mage gains 10% ult charge. | 3+ Mages so ults chain | violet pulse jumping between Mages | |
| M3 | **Mana Tide** (payoff) | Mages' skills cost 25% less mana. | Mages whose skills cost the most mana | blue shimmer on the mana bar | |
| M4 | **Spell Echo** (payoff) | Mage skills have a 20% chance to fire a second time at half power. | Mages with strong skills | ghost copy of the skill effect | |
| M5 | **Overload** (capstone) | Every 4th ultimate your team casts also hits every enemy for 50% of your Mages' combined magic power. | many ults from any source | board-wide violet crack | |

Loop check M2: a cast gives others 10% each, never the caster, and ult casts
never give the caster charge. With 9 Mages that is 0.8 of an ult per cast
spread over 8 bars - it speeds casting but converges. Arena gate like Burn's.

### Fighter - leans on: basic attacks (fighters' main damage)

| # | Piece | Draft effect | Makes you want | Cue | State |
|---|---|---|---|---|---|
| F1 | **Warband** (seed) | Fighters get +8% attack damage per Fighter you field. | more Fighters | red war-paint stripe on Fighters | |
| F2 | **Pack Hunt** (enabler) | Fighters deal +15% basic-attack damage to an enemy another Fighter hit in the last 2 s. | Fighters on the same target | red target mark on the shared enemy | |
| F3 | **Bloodrush** (payoff) | A Fighter's kill gives it +30% attack speed for 3 s. | Fighters that finish kills | red speed trails | |
| F4 | **Relentless** (payoff) | Each hit on the same target gives +3% damage against it, up to +30%; resets on a new target. | Fighters that stick to a target | stacking pips over the target | |
| F5 | **Onslaught** (capstone) | When a Fighter kills, its attack timer resets. | Fighters in fights with many enemies | flash on the Fighter | |

### Ranged - leans on: basic attacks from the back row

| # | Piece | Draft effect | Makes you want | Cue | State |
|---|---|---|---|---|---|
| R1 | **Deadeye** (seed) | Ranged heroes get +8% attack speed per Ranged hero you field. | all three Ranged | green sight line to the target | |
| R2 | **Longshot** (enabler) | Ranged basic attacks deal +4% damage per tile to the target. | Ranged in the back row, a front line | longer arrow trail | |
| R3 | **Volley** (payoff) | Every 5th Ranged attack also fires at a second enemy. | fast Ranged heroes | split arrow | |
| R4 | **Covered** (payoff) | Ranged heroes take 25% less damage while an ally stands in front of them. | a front line | small shield icon when covered | |
| R5 | **Killing Field** (capstone) | Enemies hit by 3 different Ranged heroes within 3 s take 25% more damage from all sources for 4 s. | all three Ranged | crosshair on the marked enemy | |

Only 3 Ranged heroes exist (Ember, Headhunter, Sable), so this is the smallest
role archetype. Summoner (1 hero) gets none.

### Healer - leans on: healing done

| # | Piece | Draft effect | Makes you want | Cue | State |
|---|---|---|---|---|---|
| H1 | **Mending Circle** (seed) | Healing from Healers is +12% per Healer you field. | more Healers | soft green ring on Healers | |
| H2 | **Overflow** (enabler) | Healing past full HP becomes a shield, up to 20% of max HP. | strong healers; no heal is wasted | shield bar fills after a green number | |
| H3 | **Radiance** (payoff) | 15% of each heal from a Healer also hits the nearest enemy. | Healers that heal often | green bolt to an enemy | |
| H4 | **Vigil** (payoff) | Healers' ultimates charge from healing done (1 charge per 20 HP healed). Ult heals give no charge. | Healers with big heals | Healer ult bars glow green | |
| H5 | **Miracle** (capstone) | Once per fight, the first ally who would die is healed to 30% HP instead. | any Healer | golden flash | |

## Elements - a decision first

Rule 3 means an element's pieces can only amplify a move its heroes already
share. Only two elements have one:

- **Fire -> Burn:** done (Kindling and four pieces, VD-16).
- **Lightning -> Stuns:** strong. Four of six heroes stun. A draft:
  **Static Charge** (seed: stuns last +10% longer per stunner you field);
  **Conductive** (stunned enemies take +20% damage);
  **Arc** (when a stunned enemy dies, a 1 s stun jumps to the nearest enemy);
  **Overcharge** (stunners' ults charge faster while an enemy is stunned);
  **Thunderhead** (capstone: every 5th stun you apply hits all stunned enemies
  for a lightning burst).
- **Water -> Healing:** all three Water heroes heal, but it overlaps the Healer
  role (Doc and Reed are both).
- **Earth, Air, Normal:** no shared move. Earth has one shielder and one
  rooter; Air has an every-Nth shooter, a ramper and an aura; Normal is
  pull, area, guard, retaliate and summon.

**Options for the owner:**
- **A. Verb elements only** (recommended). Build Lightning (stuns) next. Water
  is covered by the Healer role. Earth, Air and Normal get no pieces until a
  hero rework gives them a shared move.
- **B. Every element gets pieces**, with Earth/Air/Normal pieces built on their
  stat identity instead of a move (e.g. Earth = shields and max HP, Air = attack
  speed). This bends rule 3 - those pieces risk being "+X% stat" upgrades that
  fail the direction test.
- **C. Element pieces amplify the counter system** (`ELEMENT_COUNTERS.md`):
  e.g. "your Water heroes' hits shut off regen for longer". This rewards
  bringing the right element for the enemy, not stacking one.

## Screen rules to settle

- **Wave-1 seeds.** Burn offers one seed per buildable archetype. With five
  roles plus elements, that exceeds three cards. Proposal: offer up to three
  seeds, chosen at random among archetypes you can build (2+ unlocked heroes),
  topped up with regular relics.
- **Reserved card.** One card per later screen stays reserved for a piece of an
  archetype you field; with several, pick one at random (as today).
- **Heroes in two archetypes.** Coal is a Fighter and a Burn hero; Static is a
  Mage and a Lightning stunner. Proposal: both count - that is the point of
  mixing a role archetype with an element one.

## Suggested order

1. **Roles first:** every hero has one, and a fresh account can build two of
   them. Tank and Mage have the clearest share of power; Mage has the most heroes.
2. **Lightning (stuns)** next: the only element besides Fire with a shared move.
3. Settle options A/B/C for the remaining elements.

## Gates (from VD-16, per archetype)

- Each piece is worth 2x more with 3 of its heroes than with 1, and about
  nothing with 0.
- On its own team, a piece beats a generic relic one grade higher.
- A full archetype lands in the band of the best generic setup at waves
  10 / 20 / 30.
