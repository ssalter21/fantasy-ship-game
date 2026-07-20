# ADR-0026: Durability and bulwark are deleted — damage lands

## Status

Accepted — **supersedes ADR-0006's composition arithmetic** (`final_damage = max(0, raw_damage − Durability)`) and retires the Durability stat ADR-0004 gave every ship. The rest of ADR-0006 stands unchanged: phased rounds, simultaneous resolution, the one captain decision per round, Speed-gated escape, the hard round cap, permadeath, and determinism are all untouched. It also closes the Brace question ADR-0025 carried forward, though not by the route that ADR imagined.

(ADR-0004/0006 predate the ADR-0021 rename and say *Defensive*/*Offensive*/*Boost*; read those as **Brace**/**Fire**/**Press**. ADR-0021 renamed *soak* to **bulwark**; both names mean the subtracted term this ADR deletes.)

## Context

Issue [#396](https://github.com/ssalter21/fantasy-ship-game/issues/396), under the item-authoring effort ([#363](https://github.com/ssalter21/fantasy-ship-game/issues/363)), forced the question ADR-0025 left open: does Brace earn its phase?

The defensive half of combat did not work, and the reason was structural rather than tuned. Three facts, all confirmed in live code:

1. **Bulwark is mandated small while raw damage is site-multiplied.** ADR-0019 scales a hostile's Fire output by the site's power reading and deliberately never scales its bulwark — a subtrahend that grew with the site would eventually make a hostile impossible to hurt at any magnitude. CONTEXT.md states the same rule from the player's side: bulwark's vocabulary is *deliberately* the smaller of the two, because anything that can reach raw's own size on the bulwark side is a zero-damage floor rather than a hard fight. So one side of the subtraction is free to grow across a voyage and the other is barred from it, by design.
2. **Absorption therefore decays with depth** — roughly 47% of a hit at Coastal down to roughly 15% in The Deep. The defensive stat is worth most exactly where the fights are easiest.
3. **The roster cannot feed it.** Two of fifty items carried an active Brace effect; five carried `Modify_Durability`. A slot spent on defence bought roughly a quarter of what the same slot bought in offence. Press Brace was the wasted order ADR-0025 already recorded: *"Press Fire, or waste it."*

Propping this up means either letting bulwark scale with the site — which ADR-0019 rules out for a reason that has not changed — or re-authoring the roster around a stat that is structurally capped. Both spend the effort's budget defending arithmetic nobody wanted.

## Decision

**`final_damage` is `raw_damage`.** A side's pressed Fire output reaches the target's hull whole. Nothing is subtracted, so there is no floor to clamp at and no `max(0, …)`.

**Durability is deleted, root and branch.** `Ship.durability` goes; so do `STARTING_DURABILITY`, the `Modify_Durability` effect kind, and `ship_effective_durability`. `Effect_Kind` is `{Phase_Contribution, Modify_Speed, Modify_Max_Hull}`. The shared `ship_effective_stat` shape survives for its two remaining readers.

**Stakes stops supplying an opponent durability.** `voyage_fight_opponent_durability` and its two constants go; a hostile's staying power is its Hull pool alone.

**Trade closes at three stats — `{Hull, Max_Hull, Cargo}`.** The Scrapped Armour axis (gain Cargo, cost Durability) is deleted with the stat it sold, and the `TRADE_SWING_DURABILITY_PER_TIER` row with it. The two surviving axes — Cannibalized Timbers and Shipwright's Bargain — are **untouched at every site**: no magnitude moves. The swing table's "no PER_DEPTH row" argument is re-anchored, since it used to rest on Durability being the table's smallest row; every row now quotes in reference-fight Hull swing, and Max Hull is the binding row.

**Brace survives as a phase with no consumer — deliberately, and briefly.** `ship.Category` stays `{Brace, Fire}`; `combat_phase_output` still answers for Brace; `Command_Press{phase}` still accepts it. But nothing reads a Brace total, so Press Brace is inert and every Brace fitting is inert with it. This is the one-ticket gap between deleting the defensive verb and authoring its replacement: [#397](https://github.com/ssalter21/fantasy-ship-game/issues/397) makes Brace **repair**, which is a defensive verb the site *can* scale, because it adds on the player's side rather than subtracting on the hostile's.

**The five `Modify_Durability` items are left effect-less, not re-authored.** Iron Plating, Ballast Stones, Reinforced Hull, Dragon Turtle and Adamant Bulwark keep their names, sizes, weights and tags and carry no effect at all until #397 re-authors them as repair. Pinned by name in a test, so the hole is known rather than silent.

**Magnitudes remain placeholders** (ADR-0006, ADR-0012). This deletes a term; it is not a rebalance.

## Consequences

- **`Round_State` loses `defense_bonus`**, and `combat_resolve_round` computes only the Fire phase into a number. The damage site at `core/combat/combat.odin` reads no ship stat at all beyond the hull it writes.
- **Every fight is shorter, on both sides.** Hits that were absorbed now land, for the player and the hostile alike. The hostile band tests (`a_starting_player_can_fight_every_archetype_at_coastal` and its floor counterpart) still hold at Coastal, so the eight archetypes stay inside the band without re-authoring — but they are the tripwire if a later magnitude edit pushes a fight below the escape gate.
- **Hull is the whole of a ship's staying power.** `STARTING_HULL` was already the scale everything Hull-denominated hangs off; it now also carries the entire exchange, with nothing between raw damage and the pool.
- **Press is still degenerate, and now visibly so.** ADR-0025 recorded the decay; with Brace's consumer gone, Press Fire is not merely the better order but the only one that reads. #397 is what makes it a choice again.
- **A ghost snapshot gets marginally smaller** and stays plain data (ADR-0008): one fewer scalar on `Ship`, no new state anywhere.
- **Pierce stays dead.** #364's shelved per-weapon pierce bypassed bulwark; with no bulwark there is nothing to bypass.
- **ADR-0019's "stakes never scales bulwark" rule loses its subject.** `voyage_stakes_scales_category` still exempts Brace, on the plainer ground that Brace feeds nothing; when #397 lands, whether repair is site-scaled is that ticket's decision, not a survival of this rule.
- **The retired vocabulary is recorded, never un-said.** ADR-0004/0006 still describe a Durability stat and a subtracting damage formula; read those as arithmetic that existed and was deleted here. CONTEXT.md drops the Durability and bulwark entries and files both under the `_Avoid_` convention (ADR-0021). Earlier ADR prose is not edited.

See GitHub issue [#396](https://github.com/ssalter21/fantasy-ship-game/issues/396) for the ticket, and ADR-0025 for the Brace question this closes.
