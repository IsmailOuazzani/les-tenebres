# Game Concept: Protest Simulator

## Overview

A chaotic, funny, first-person protest simulator set in Paris, France.

The player starts alone and recruits NPCs to form an increasingly massive protest. Using a megaphone, they direct their mob toward locations and objects, causing ridiculous disruptions across the city.

**Genre:** First-person sandbox, crowd simulator, arcade

**Inspiration:** Goat Simulator, Katamari Damacy, Pikmin

**Goal:** Build the biggest protest possible before the crowd disperses. No story mode, just replayable sandbox gameplay and high scores.

## Core Gameplay Loop

1. **Recruit:** Use your megaphone to convince nearby civilians to join your protest.
2. **Direct:** Aim at a location or object and shout "À L'ATTAQUE!" to send your mob there.
3. **Cause chaos:** Protesters interact with the target, creating funny, physics-driven disruptions.
4. **Gain publicity:** Successful disruptions attract more civilians and increase crowd enthusiasm.
5. **Grow:** Use your larger mob to cause increasingly spectacular disruptions.
6. **Survive:** Keep protesters engaged and together before they lose patience and leave.

Repeat until the protest collapses.

## Core Controls

| Input | Action | Behavior |
|---|---|---|
| WASD | Movement | First-person movement |
| Mouse | Aim | Look around and select targets |
| Left Click | Recruit | Shout through megaphone to recruit nearby NPCs |
| Right Click | À L'ATTAQUE! | Send the crowd toward the targeted object or location |
| Hold Right Click | Rally | Gather protesters at the targeted location |
| E | Protest Action | Perform contextual actions such as chanting, sitting, or occupying an area |

## Main Mechanic: Context-Sensitive Mob Direction

**The player decides WHERE the mob goes. The NPCs decide HOW to interact with the destination.**

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

## Publicity and Recruitment

Publicity rewards the player for causing disruptions.

- Recruiting people increases enthusiasm.
- Disruptions generate publicity.
- Bigger, more ridiculous disruptions generate more publicity.
- Higher publicity attracts more NPCs and accelerates recruitment.
- Successful chains of actions can create rapid, exponential crowd growth.

The player is encouraged to keep moving and find increasingly interesting targets.

## Losing Condition: Protester Patience

The protest has a shared **Patience Meter**.

Patience decreases when:
- Nothing interesting happens for too long.
- Protesters become separated from the main crowd.
- Commands fail or cause the mob to scatter.
- The player repeatedly attempts unsuccessful disruptions.

Patience increases through successful actions, recruiting, and exciting events.

When patience gets low, NPCs gradually begin leaving. At zero, the crowd disperses rapidly.

**Game Over:** The last protester leaves.

The final screen displays:
- Peak number of protesters
- Total disruptions
- Protest duration
- Total publicity generated
- A humorous reason for the protest ending

## Secondary Mechanics for Later

**Occupy Locations:** Leave portions of your mob at intersections or landmarks to generate passive publicity, at the expense of reducing your mobile crowd.

**Recruitment Combos:** Consecutive recruitments and successful stunts build an enthusiasm multiplier.

**Mob Imitation:** NPCs copy funny player actions, such as sitting in the road or climbing on objects.

**Escalating City Response:** As publicity increases, the city responds with more obstacles, traffic disruptions, and police barricades.

## MVP Scope

Build the smallest prototype that proves the central mechanic is fun.

**First playable version:**
1. A small Paris-inspired street environment.
2. First-person character with a megaphone.
3. Civilian NPCs who can be recruited using left click.
4. Recruited NPCs follow the player as a crowd.
5. Right click sends the mob toward a selected target.
6. Two or three contextual targets, such as a bus, road, and plaza.
7. Simple NPC reactions and crowd physics.
8. Publicity and patience systems.
9. Crowd counter and game-over screen.

**Avoid initially:** Story mode, complex combat, sophisticated police AI, skill trees, detailed progression systems, and large maps.

## Design Pillars

1. **Simple controls, chaotic results.** The player should understand the controls immediately.
2. **The mob is the main character.** Watching and directing the crowd is the primary entertainment.
3. **Size changes gameplay.** A crowd of 500 must feel substantially different from a crowd of 10.
4. **Comedy through simulation.** Funny moments emerge from NPC physics and interactions, not scripted cutscenes.
5. **Constant risk and reward.** Bigger disruptions create more publicity but risk scattering the crowd.
6. **Replayability over narrative.** Short sandbox runs centered on beating your previous high score.

## The Core Design Test

**Is pointing at an object, shouting "À L'ATTAQUE!", and watching 100 NPCs attempt to interact with it inherently fun?**

If yes, build the rest of the game around that.

The first prototype should focus on making this single interaction satisfying before adding more systems.
