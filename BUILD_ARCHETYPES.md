# Build Archetypes - design worksheet

Status: DRAFT for owner review, written 2026-09-25. Decisions live in
`VERTICAL_DEPTH_BACKLOG.md` under **VD-16**. This worksheet proposes; it does not
decide. Burn piece effects are moves, so the owner designs or approves them before
any code (numbers are free to tune in the arena).

## Rules (owner, 2026-09-25 - see VD-16)

1. **Archetypes are built on verbs heroes already have.** A build piece amplifies
   an existing hero move. It never hands a verb to a whole element - the
   2026-08-02 element-status scrap stands (`ELEMENT_IDENTITY_SPEC.md`).
2. **Elements are the coverage axis:** affinity, stat synergy, and the enemy
   counter passives in `ELEMENT_COUNTERS.md`.
3. **No new reward screens.** The wave-1 seed replaces what that relic screen
   offers today; later build pieces take one of the existing three cards.
4. **The direction test** (answers the owner's worry that this is "just more
   upgrades"): a build piece must change which heroes or items you want next.
   "+10% ATK" makes everything a bit stronger and changes nothing - that is an
   upgrade and stays in the generic pool. "Your burns get stronger per Burn hero"
   sends you looking for Coal, Sear and Ember - that is a direction.
5. **Every piece has a visible cue** in combat (same standing rule as the
   equipment passives).

## Verb tags - proposal

Read from the kit text in `scripts/units/ability_formulas.gd`. Only the **Burn**
tags are up for review now; the rest show which archetypes the roster already
supports. `*` = starter hero.

| Hero | Element | Verbs | Kit evidence |
|---|---|---|---|
| Coal | Fire | **Burn** | every hit burns; Stoke charges multiply a burn; Meltdown hits explode |
| Sear | Fire | **Burn** | burning trail; Ignite; ult copies the worst burn onto every enemy |
| Ember | Fire | **Burn**, Area | every arrow burns; Cinder hits 2 tiles; Wildfire detonates burns |
| Pastor | Fire | Aura | damage aura; attack-speed buff; weakens every enemy |
| Shauna* | Fire | Rhythm | every 3rd hit ignores armor; double attack |
| Bouncer* | Normal | Pull, Area | fist reels a target in; ult drags enemies in; +damage per unit within 2 tiles |
| Lordee | Normal | Area, Ramp | hits adjacent; 2-tile slam; ult steals ATK |
| Stitch | Normal | Guard | links share damage; shields from transferred damage |
| Cross | Normal | Retaliate | banks healing from hits taken, spends it as damage |
| Necro | Normal | Summon | zombies and bats; regen per living summon |
| Static* | Lightning | Lockdown, Retaliate | stun; stun-lock ult; reflects damage |
| Riot | Lightning | Lockdown, Retaliate | stun + taunt; taunts everyone; slows attackers |
| Rush | Lightning | Lockdown | ult freezes everyone else |
| Zolt | Lightning | Area, Lockdown | every Nth attack arcs; storm stuns; ult stuns |
| Lumen | Lightning | Area | second target every attack; bouncing beam; hits all |
| Rift | Lightning | Pull, Retaliate | ult drags every enemy to the centre; redirects damage taken |
| Sheildor | Earth | Guard | shields the weakest adjacent ally; ally shield; leap shield |
| June | Earth | Aura, Lockdown | regen aura; root; rooting thorn field |
| Spore | Earth | Area, Ramp | spores gather in a radius, burst by stacks |
| Bloodhound* | Earth | Brink? | stronger below 45% HP; bite drains; leap stun |
| Nemi* | Water | Aura, Heal | allies move +1; chain heals and damages; shove |
| Reed | Water | Aura, Heal | regen/cleanse aura; team heal + per Water ally |
| Doc | Water | Heal | heals the weakest; revive |
| Headhunter* | Air | Rhythm | every Nth shot hits harder; extra shot |
| Sable | Air | Ramp | each hit banks ultimate damage |
| Vail | Air | Aura, Guard | attack-speed aura; lifts an ally untargetable |

Heroes per verb: Area 6 · Lockdown 5 · Aura 5 · Retaliate 4 · **Burn 3** ·
Guard 3 · Heal 3 · Ramp 3 · Pull 2 · Rhythm 2 · Summon 1 · Brink 1.
Pull is small alone but feeds Area ("Vortex": drag them together, hit them all).

**Fresh accounts can't build Burn** - Coal, Sear and Ember are all crystal-tree
unlocks. Starters reach Rhythm (Headhunter + Shauna) and a thin Lockdown
(Static, Bouncer's stun). So hero unlocks in the tree become *build* unlocks.

## Burn - how it works today (read from code)

- `apply_burn` keeps the **stronger** burn and the **longer** duration. A second
  burn on the same enemy adds nothing. Two burners on one target = one burn.
  This is why a Burn team doesn't feel like a team today.
- Burn ticks as true Fire damage, credited to whoever applied a burn **last** -
  even when the stronger burn was someone else's. Matters for the run recap.
- **The combo already exists, unannounced.** Coal's charged hits make the
  biggest burn; Sear's ult copies the worst burn onto every enemy; Ember's
  Wildfire makes every burning enemy explode for its burn x mult + blast
  (1.5-tile radius, so a clumped board eats several blasts - Burn and Vortex
  feed each other). It only lines up when the ults happen to, and nothing tells
  the player it happened.
- Shauna and Pastor are Fire but never burn. Element is not the verb.

## Burn pieces - drafts for review

Numbers are first-pass. Each piece uses the existing relic **ladder pattern**
(one effect, magnitude by grade), so it drops into the graded screens without a
new rule. State column is for the owner: keep / change / cut.

| # | Piece | Draft effect | Makes you want | Cue | State |
|---|---|---|---|---|---|
| B1 | **Kindling** (wave-1 seed) | Your burns deal +15% damage per Burn hero you field (max 3). | Coal, Sear, Ember | flames on burning enemies get a gold core | draft |
| B2 | **Kindred Flames** (enabler) | Burns from different heroes add up: the strongest counts in full, each other hero's burn adds half. | a 2nd and 3rd burner | a pip per distinct burner under the burn icon; "+" flare when one joins | draft |
| B3 | **Ashfall** (payoff) | When a burning enemy dies, its burn leaps to the nearest enemy with its remaining time. | wide burns; swarm fights | flame arc from the corpse to the next enemy | draft |
| B4 | **Tinder Heart** (payoff) | While any enemy is burning, Burn heroes' ultimates charge 25% faster. | Sear + Ember together, so the spread-then-detonate combo fires | Burn heroes' ult bars flicker orange | draft |
| B5 | **Inferno Crown** (capstone) | Every 8 s, every burning enemy takes 2 s of its burn at once. | big burns (Coal's charges, B2) | board-wide flare, numbers pop together | draft |

Implementation notes (no design decisions): B2 needs per-hero burn tracking on
the target (today a unit holds one burn). B4 needs the verb tags as data.

### Seed rules (wave 1)

- The wave-1 relic screen offers seeds for archetypes you can actually build
  (2+ unlocked heroes with that verb), topped up with today's wave-1 relics.
  With only Burn authored, an account without Burn unlocks sees today's screen.
- Seeds on one screen share a grade, so the pick is about direction.
- **Every seed also raises its archetype's heroes in your hero shop.** This is the
  seeking tool - without it, a Burn seed is a lottery ticket.

### Reserved slot (later relic screens)

Once you field a hero whose verb has pieces, one of the three cards on each
relic screen is a piece for that verb. Not a fourth card.

## Element synergy vs the crystal tree (VD-16 item 2 - open)

Each element has three tree nodes (`synergy_<element>_1..3`, +1 count each). They
apply whenever you field at least one hero of that element. Thresholds are 2/3.

| Rule | Heroes to light all six elements at tier 2 | One hero per element gets |
|---|---:|---|
| Today: +3 if you field 1+ | **6** | tier 2 everywhere |
| +1 per element instead of +3 | 12 | tier 1 everywhere |
| **+3 only if you field 2+ (recommended)** | 12 | nothing from the tree |
| No tree nodes | 18 | nothing |

Recommendation: the tree's count applies once you field 2+ heroes of that
element. A committed element keeps the full value; a one-of-each team gets
nothing from the tree. At 18+ heroes every element lights with no nodes at all,
so big boards eventually need deeper thresholds - a synergy numbers pass in the
arena, not part of the Burn slice. Duplicates also count toward synergy today
(TFT counts each champion once); same pass.

## Gates

- **Rewards going deep:** each Burn piece is worth at least 2x more on a
  3-burner team than on a 1-burner team, and about nothing on a team with no
  burner. A piece that pays the same everywhere fails rule 4.
- **Worth picking:** on a Burn team, a Burn piece beats a generic relic one
  grade higher.
- **Not dominant:** a Burn team with its pieces lands in the band of the best
  generic setup at waves 10 / 20 / 30.
- **Runs diverge:** telemetry (VD-01) shows relic picks spreading out between
  runs, and Burn runs name themselves in the recap.
- Tooling (no design decisions): an arena mode that A/Bs one relic across two
  teams.

## Open questions

1. VD-16 item 2 - which tree synergy rule.
2. Do verb tags show in the UI (a chip on the hero card), or only on the relic
   card ("Affects: Coal, Sear, Ember")?
3. Does the merchant's relic slot follow the reserved-slot rule too?
4. Next archetype after Burn - one that starters can build (Rhythm or Lockdown),
   so a fresh account gets a seed too.
5. The six element relics ("+8% for all, Fire +25%") fail the direction test.
   Keep them as generic, or make them pure element pieces?
