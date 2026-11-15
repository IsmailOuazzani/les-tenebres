# Game Concept: Protest Simulator

## Overview

A chaotic, funny, first-person protest simulator set in Paris, France.

The player starts alone and recruits NPCs to form an increasingly massive protest. Using a megaphone, they direct their mob toward locations, objects, and police, causing ridiculous disruptions across the city while surviving escalating waves of police attacks.

**Genre:** First-person wave-survival crowd simulator, arcade

**Inspiration:** Goat Simulator, Katamari Damacy, Pikmin, Call of Duty Zombies, Team Fortress 2: Mann vs. Machine

**Goal:** Survive as many waves of police as possible, growing an increasingly ridiculous mob and upgrading yourself between waves. No story mode — replayable runs centered on beating your previous best wave/Act.

## Core Gameplay Loop

The game launches directly into **Survival Mode** by default.

1. **Prepare:** Recruit civilians, position your mob, and prepare for the next attack.
2. **Survive:** Police arrive in increasingly large waves. Use your mob to defend yourself and fight back.
3. **Cause chaos:** Continue recruiting and directing protesters toward objects, locations, and police to generate Grabuge.
4. **Earn Grabuge:** Accumulate currency through recruitment and successful disruptions.
5. **Upgrade:** Between waves, spend Grabuge on upgrades that improve your chances of surviving.
6. **Escalate:** Face larger, more dangerous waves as the run progresses.

Repeat until the player dies or completes the Act.

The player should feel increasingly powerful, but the police should escalate enough to remain threatening.

## Core Controls

| Input | Action | Behavior |
|---|---|---|
| WASD | Movement | First-person movement |
| Mouse | Aim | Look around; the reticle outlines an interactable in view, or shows a plain marker when aiming at nothing interactable |
| Hold Right Click | Megaphone | Project a recruitment cone that recruits nearby civilians; size scales with Grabuge |
| Hold Left Click | Send Mob | Hold to ramp up what % of the mob gets committed, release to send that share at the reticle's target |
| E | Protest Action | Perform contextual actions such as chanting, sitting, or occupying an area |

## Main Mechanic: Context-Sensitive Mob Direction

**The player decides WHERE the mob goes. The NPCs decide HOW to interact with the destination.**

**Send Mob is one command, not two.** It's always "send this share of the
mob to a position" — the only difference is what that position resolves
to: an aimed-at interactable object (outlined in the reticle, À
L'ATTAQUE!), or wherever the aim is pointing at ground/world geometry when
nothing interactable is in view (shown as a plain marker instead). See
`agents/mob-selector-notes.md` for the targeting/outline and send-percentage
spec.

Examples:

- **Bus:** Protesters surround and block it, with some attempting to climb onto it.
- **Road:** Protesters occupy the street and block traffic.
- **Plaza:** Protesters gather and begin chanting.
- **Barricade:** Protesters push against it.
- **Statue:** Protesters climb all over it.
- **Police:** Protesters swarm and fight them, when explicitly targeted with Send Mob.

The outcome depends on crowd size, positioning, physics, and the environment.

Actions should be visually funny, exaggerated, and somewhat unpredictable.

## Crowd Behavior

The mob should feel like a living, slightly uncontrollable entity.

**Small crowds:**
- Respond quickly to commands.
- Move precisely.
- Are easy to control but have little physical influence.

**Large crowds:**
- Can create much bigger disruptions.
- Take longer to respond to commands.
- Have momentum and struggle with sharp turns.
- Can become separated in narrow streets.
- Create chaotic chain reactions through NPC interactions.

**Key design principle:** A larger crowd is more powerful but harder to control.

NPCs should also imitate certain player actions where appropriate, creating emergent comedy.

**Physical size vs. damage range are separate knobs.** How tightly bodies can pack together (for a dense mob look) and how close something needs to be to deal/take damage are deliberately independent — shrinking one doesn't shrink the other. See "Tweakable Parameters" below.

## Grabuge: Currency and Progression

**Grabuge is no longer a survival meter — it's the run's currency.**

Grabuge is earned during the run and spent on upgrades between waves. It no longer decays, and it no longer determines anything about losing the run.

**Important design distinction:** the game tracks two separate numbers:
- **Total Grabuge earned** this run — never decreases, used to scale civilian spawn rate (a bigger, louder protest draws more onlookers).
- **Available (unspent) Grabuge** — rises and falls as the player earns and spends it, used only for upgrade purchases.

Keeping these separate means buying an upgrade can never accidentally shrink the recruitment pool.

- Recruiting civilians generates Grabuge.
- Successful disruptions generate Grabuge.
- Grabuge no longer decays.
- Unspent Grabuge carries over between waves.
- Police spawning is completely independent of Grabuge — it's controlled entirely by the wave system (see below).
- Higher Grabuge (total earned) still grows the megaphone's recruitment cone, making recruiting easier as the mob grows.

Do not introduce additional currencies or resource meters.

## Losing Condition: Player Health

The only game-over condition is **the player's health reaching zero**.

- The player has health.
- Police attempt to reach and attack the player directly.
- The player must direct protesters to intercept and fight the police before they close in.
- Protesters can take damage and die.
- Losing protesters makes survival harder (a smaller mob to throw at incoming waves), but does not directly end the run.
- Grabuge reaching zero does **not** end the run.

**Game Over:** Player health reaches zero.

## Wave System

A straightforward survival-wave structure, inspired by zombie survival games.

**During waves:**
- A visible survival timer and wave number.
- Police spawn at randomized locations around the play area, and continue spawning throughout the wave.
- Wave sizes increase as the player progresses.
- Clear audiovisual warning signals precede dangerous incoming attacks.
- Spawn locations vary, but enemies should never unfairly appear directly on top of the player.

**Between waves:**
- Clear wave completion feedback.
- A brief quiet period with no new police spawning.
- An opportunity to recruit additional civilians.
- An upgrade purchasing opportunity (see below).
- A preview of the next wave's difficulty/approximate threat level.
- A countdown before the next wave begins.

Waves are primarily **time-based survival challenges**, not kill-everything challenges: surviving the timer completes the wave, and any remaining police can retreat or despawn during the transition.

**Escalation:**
- Wave size increases over time.
- Escalation milestones should be predictable and understandable (e.g. every third wave introduces a more substantial assault).
- Later Acts raise the overall difficulty further.

For the MVP, escalating enemy counts are sufficient — no multiple enemy types, bosses, or sophisticated police tactics yet.

## Acts and Progression

The game is organized into **Acts**, each a discrete survival challenge made of multiple waves with increasing difficulty.

At the end of an Act, display a scoreboard with:
- Waves survived
- Peak crowd size
- Total Grabuge earned
- Police defeated
- Total disruptions
- Time survived

Completing an Act should feel rewarding, with clear feedback before proceeding to a harder Act. For now, Acts don't need different environments, scripted story sequences, or elaborate objectives — their job is to structure progression and create meaningful milestones.

## Upgrade System

Between waves, players spend available Grabuge on upgrades. Upgrades persist for the current run only (no permanent meta-progression).

Three starting player upgrades:

| Upgrade | Effect |
|---|---|
| **Speed** | Increase player movement speed by 10%. |
| **Jump** | Increase player jump height by 15%. |
| **Health** | Increase maximum player health by 20 HP and restore 20 HP. |

Upgrades aren't limited to the player — the same purchasing flow can apply to the mob, since the crowd is as central to survival as the player is:

| Upgrade | Effect |
|---|---|
| **Crowd Velocity** | Increase protester movement speed by 10%, so the mob responds and closes distance faster. |
| **Crowd Health** | Increase protester max health by 20%, so NPCs survive longer against police. |
| **Crowd Strength** | Increase protester attack damage by 15%, so the mob clears police faster. |

These numbers are all configurable.

Design principles:
- Upgrades are purchased with available Grabuge; players can save up across waves instead of spending immediately.
- Upgrades should be immediately noticeable in how the player feels to control.
- The UI stays simple: show each upgrade, its effect, its price, and whether the player can currently afford it.
- No skill trees, inventory management, complex item systems, or permanent meta-progression for now.

This starting set is intentionally simple — the selection can expand once the survival loop itself is fun.

## Secondary Mechanics for Later

**Occupy Locations:** Leave portions of your mob at intersections or landmarks to generate passive Grabuge, at the expense of reducing your mobile crowd.

**Recruitment Combos:** Consecutive recruitments and successful stunts build a temporary Grabuge multiplier.

**Mob Imitation:** NPCs copy funny player actions, such as sitting in the road or climbing on objects.

**Civilian Spawning:** Bystanders trickle in near the player over time, at a rate that scales up with total Grabuge earned (a bigger, louder protest draws more onlookers) up to a cap, and despawn once too far from the player. Keeps recruits available for the whole run instead of a one-time pool that runs dry.

**Escalating Obstacles:** Beyond wave size, later Acts could add traffic disruptions, barricades, or other environmental obstacles tied to wave/Act progression (not to Grabuge, which no longer drives police presence). Unimplemented for now.

**Police:** Cops beeline for the player by default and only engage the crowd once the player actively directs part of it at them — standing nearby isn't enough to draw them into a fight. Police are a Send Mob target like any destructible object — the player can aim and "À L'ATTAQUE!" a cop directly, not just march the crowd near one and hope for an intercept. Police spawning itself (timing, count, location) is driven entirely by the Wave System, not by Grabuge.

## MVP Scope

Build the smallest prototype that proves the central mechanic is fun.

**First playable version:**
1. A small Paris-inspired street environment.
2. First-person character with a megaphone and health.
3. Civilian NPCs who can be recruited by holding right click (recruitment cone).
4. Recruited NPCs follow the player as a loose crowd (seek/separation/cohesion steering).
5. Hold left click to ramp up a % of the mob, release to send it charging at the reticle's target; holding right click regroups the crowd around the player.
6. Two or three contextual targets, such as a bus, road, and plaza, plus police as a Send Mob target.
7. Simple NPC reactions and crowd physics.
8. The Grabuge system (total earned vs. available, no decay) and civilian spawn scaling.
9. A basic wave system: timer, wave number, escalating police spawns, and a between-wave upgrade screen with the three starting upgrades.
10. Crowd counter, player health bar, and a game-over screen on player death.

**Avoid initially:** Story mode, complex combat, sophisticated police AI/multiple enemy types, skill trees, detailed meta-progression systems, and large maps.

## Design Pillars

1. **Simple controls, chaotic results.** The player should understand the controls immediately.
2. **The mob is the main character.** Watching and directing the crowd is the primary entertainment.
3. **Size changes gameplay.** A crowd of 500 must feel substantially different from a crowd of 10.
4. **Comedy through simulation.** Funny moments emerge from NPC physics and interactions, not scripted cutscenes.
5. **Escalating tension, not a ticking clock.** Waves of police — not a decaying meter — create pressure; the player's own choices (recruiting, upgrading, picking fights) determine whether they keep pace.
6. **Replayability over narrative.** Short survival runs centered on beating your previous wave count or Act.

## Tweakable Parameters

Gameplay-relevant ratios/knobs worth knowing exist, without duplicating every number here (see each script for current defaults and `agents/crowd-swarm-notes.md` for rationale):

- **Collider-to-damage ratio** (`NPC.collider_to_damage_ratio`, `Police.collider_to_damage_ratio`): physical collision size as a fraction of attack range. Lower = bodies can overlap/pack tighter for a denser mob visual, without changing when they can actually hit or be hit.

## The Core Design Test

**Is recruiting and commanding an increasingly ridiculous mob to survive escalating waves of police, while earning Grabuge and upgrading yourself between waves, fun enough to sustain repeated runs?**

The game must retain the comedy and emergent crowd chaos of the original concept, but now have the pacing, tension, progression, and replayability of a wave-survival game.

If yes, build the rest of the game around that. The first prototype should focus on making the recruit → direct → survive → upgrade loop satisfying before adding more systems.
