# Game Concept: Protest Simulator

## Overview

A chaotic, funny, first-person protest simulator set in Paris, France.

The player starts alone and recruits NPCs to form an increasingly massive protest. Using a megaphone, they direct their mob toward locations and objects, causing ridiculous disruptions across the city.

**Genre:** First-person sandbox, crowd simulator, arcade

**Inspiration:** Goat Simulator, Katamari Damacy, Pikmin

**Goal:** Build the biggest protest possible before the crowd disperses. No story mode, just replayable sandbox gameplay and high scores.

## Core Gameplay Loop

1. **Recruit:** Hold your megaphone to project a recruitment cone and convince nearby civilians to join your protest.
2. **Direct:** Aim at a location or object and shout "À L'ATTAQUE!" to send your mob there.
3. **Cause chaos:** Protesters interact with the target, creating funny, physics-driven disruptions.
4. **Build Grabuge:** Recruiting and successful disruptions raise the crowd's shared chaos/excitement meter.
5. **Grow:** Use your larger mob — and a bigger megaphone cone — to cause increasingly spectacular disruptions.
6. **Survive:** Keep Grabuge up before it decays away and the crowd disperses.

Repeat until the protest collapses.

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

## Grabuge: the One Shared Resource

**Grabuge** is the protest's single shared meter of chaos and excitement (0-100%). It replaces any separate publicity, enthusiasm, or patience-style meters — there is only one number to manage.

- Recruiting civilians and pulling off disruptions raise Grabuge.
- Bigger, more ridiculous disruptions raise it more.
- Grabuge decays continuously on its own.
- Higher Grabuge grows the megaphone's recruitment cone (range and width), making recruiting easier and the mob grow faster.

The player is encouraged to keep moving and find increasingly interesting targets to keep Grabuge from running out.

## Losing Condition: Grabuge Collapse

When Grabuge runs out, the protest loses steam: NPCs gradually begin leaving, and at zero the crowd disperses rapidly.

**Game Over:** The last protester leaves.

The final screen displays:
- Peak number of protesters
- Total disruptions
- Protest duration
- Peak Grabuge reached
- A humorous reason for the protest ending

## Secondary Mechanics for Later

**Occupy Locations:** Leave portions of your mob at intersections or landmarks to generate passive Grabuge, at the expense of reducing your mobile crowd.

**Recruitment Combos:** Consecutive recruitments and successful stunts build a temporary Grabuge multiplier.

**Mob Imitation:** NPCs copy funny player actions, such as sitting in the road or climbing on objects.

**Escalating City Response:** As Grabuge rises, the city responds with more obstacles, traffic disruptions, and police barricades. Police spawn rate already scales with Grabuge this way (same trickle-rate formula as Civilian Spawning, capped at a max concurrent count); obstacles/traffic/barricades are still unimplemented.

**Civilian Spawning:** Bystanders trickle in near the player over time, at a rate that scales up with Grabuge (a bigger, louder protest draws more onlookers) up to a cap, and despawn once too far from the player. Keeps recruits available for the whole run instead of a one-time pool that runs dry.

**Police:** Cops beeline for the player by default and only engage the crowd once the player actively directs part of it at them — standing nearby isn't enough to draw them into a fight. Police are a Send Mob target like any destructible object — the player can aim and "À L'ATTAQUE!" a cop directly, not just march the crowd near one and hope for an intercept.

## MVP Scope

Build the smallest prototype that proves the central mechanic is fun.

**First playable version:**
1. A small Paris-inspired street environment.
2. First-person character with a megaphone.
3. Civilian NPCs who can be recruited by holding left click (recruitment cone).
4. Recruited NPCs follow the player as a loose crowd (seek/separation/cohesion steering).
5. Right click sends the mob charging toward a selected target; hold right click regroups it.
6. Two or three contextual targets, such as a bus, road, and plaza.
7. Simple NPC reactions and crowd physics.
8. The Grabuge system (single shared meter, decay, and debug controls).
9. Crowd counter and game-over screen.

**Avoid initially:** Story mode, complex combat, sophisticated police AI, skill trees, detailed progression systems, and large maps.

## Design Pillars

1. **Simple controls, chaotic results.** The player should understand the controls immediately.
2. **The mob is the main character.** Watching and directing the crowd is the primary entertainment.
3. **Size changes gameplay.** A crowd of 500 must feel substantially different from a crowd of 10.
4. **Comedy through simulation.** Funny moments emerge from NPC physics and interactions, not scripted cutscenes.
5. **Constant risk and reward.** Bigger disruptions raise Grabuge faster but risk scattering the crowd.
6. **Replayability over narrative.** Short sandbox runs centered on beating your previous high score.

## Tweakable Parameters

Gameplay-relevant ratios/knobs worth knowing exist, without duplicating every number here (see each script for current defaults and `agents/crowd-swarm-notes.md` for rationale):

- **Collider-to-damage ratio** (`NPC.collider_to_damage_ratio`, `Police.collider_to_damage_ratio`): physical collision size as a fraction of attack range. Lower = bodies can overlap/pack tighter for a denser mob visual, without changing when they can actually hit or be hit.

## The Core Design Test

**Is pointing at an object, shouting "À L'ATTAQUE!", and watching 100 NPCs attempt to interact with it inherently fun?**

If yes, build the rest of the game around that.

The first prototype should focus on making this single interaction satisfying before adding more systems.
