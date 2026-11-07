# Free Asset Research — Characters & Props for "Les Tenebres"

Research pass for free (commercially-usable where noted) Godot-4.7-compatible assets
for crowd NPCs and street props, matching the low-poly Fall Guys / Schedule 1 vibe
described in `vision.md`. Scope: mob NPC character (walk/idle/run), barricades/barriers,
street furniture, a bus/vehicle, a statue, and a megaphone prop.

All links below were actually retrieved during research (via search + page fetch), not guessed.

---

## 1. Crowd NPC Characters (rigged, walk/idle/run)

### Quaternius — Ultimate Modular Men Pack (top pick for crowd character)
- **URL:** https://quaternius.com/packs/ultimatemodularcharacters.html (mirrored on https://poly.pizza/bundle/Ultimate-Modular-Men-Pack-ZiH8muWqwQ)
- **License:** CC0 — free for personal and commercial use, no attribution required.
- **Format / rig:** FBX, OBJ, glTF, and Blend. 11 different base characters, each split into 4 swappable modular parts (head/torso/legs/accessories) so you can mix-and-match to get crowd variety cheaply. **24 animations** included, fully rigged and skinned — glTF import into Godot 4.7 brings in the `Skeleton3D` + `AnimationPlayer`/`AnimationLibrary` directly, which is exactly what's needed for AnimationTree-driven crowd NPCs.
- **Caveat:** models are untextured (flat/vertex-color low-poly look) — this is actually a *feature* for the Fall-Guys-esque, simple-shaded aesthetic; you can tint per-NPC via material override for crowd variety instead of needing texture work.
- **Fit:** Purpose-built for exactly this use case (Quaternius explicitly markets it for crowds), optimized for Unity/Unreal/Godot/AR-VR, low-poly, CC0, and the modular-swap system is ideal for cheaply generating dozens of visually distinct "civilian" NPCs for recruitment.

### Quaternius — Ultimate Animated Character Pack (alternative, more "finished" look)
- **URL:** https://quaternius.com/packs/ultimatedanimatedcharacter.html
- **License:** CC0.
- **Format / rig:** FBX, OBJ, Blend. 50+ already-textured animated characters (casual male/female, business, etc.) sharing a common rig, each with a broad animation set including idle/walk/run.
- **Fit:** Good if textured, more "character-y" civilians are wanted instead of flat-shaded modular men; slightly heavier to import (50+ separate characters vs. one modular rig).

### Quaternius — Animated Men / Animated Women packs
- **URL:** https://quaternius.com/packs/animatedmen.html (and the equivalent Animated Women pack)
- **License:** CC0, FBX/OBJ/Blend.
- **Fit:** 4 male / 4 female pre-textured characters on the same shared rig family as the Modular Men pack — a lightweight way to add a couple of distinct "named" civilians (or the player model) without touching the full modular kit.

### Kenney + Kay Lousberg — Kenney Character Assets ("Mini Characters" collab)
- **URL:** https://kenney.itch.io/kenney-character-assets (also listed via https://kaylousberg.com/work/kenney-character-assets and https://kenney-assets.itch.io/)
- **License:** CC0.
- **Format / rig:** 75+ skins, 40+ accessories, and **17 shared animations** (idle, walk, run, jump, punch, kick, death, crouch variants, interact, etc.) on one rig — glTF/FBX. This is a Kenney-style blocky-chunky low-poly look (closer to the Kenney "Blocky" aesthetic than Quaternius' more humanoid-proportioned look).
- **Fit:** Very strong Fall-Guys-adjacent "toy figure" silhouette, huge animation set already covers walk/idle/run plus comedic extras (punch/kick/death) that could map nicely onto protester reactions (getting knocked over, climbing, etc.).

### Kenney — Animated Characters 2 (lighter option)
- Referenced via https://kenney.itch.io/kenney-character-assets and OpenGameArt mirror https://opengameart.org/content/animated-characters-2
- **License:** CC0.
- **Format / rig:** One rigged model, 4 skins, 3 animations only (idle, jump, running) — no dedicated walk cycle, which is a gap for crowd locomotion. Lighter-weight than the full Character Assets pack; useful only as a placeholder/prototype character, not final crowd asset.

---

## 2. Barricades, Barriers, Traffic Cones, Road Signs

### Kenney — City Kit (Roads) (top pick for barricades/street furniture)
- **URL:** https://kenney.nl/assets/city-kit-roads (also mirrored at https://kenney-assets.itch.io/city-kit-roads)
- **License:** CC0 — "completely free to use by anyone for anything" per Kenney's own announcement.
- **Format:** OBJ, FBX, DAE, STL, and glTF — glTF import works cleanly in Godot 4.7. 65+ models, single shared material across the kit (cheap to batch/instance for crowds of barricades).
- **Contents relevant to this project:** road pieces, **barriers/barricades**, **traffic cones**, **street lamps**, **road signs**, traffic lights, construction fences, and (per a 2.2 update) a dumpster/trash bin. A separate Dutch-color variant with cycle paths also exists if a more "European street" look is wanted.
- **Fit:** This is Kenney's flagship street-infrastructure kit — single consistent low-poly style, free-for-anything license, and it already contains almost every item on the prop checklist (barricades, cones, signs, lamps, bins) in one coherent pack.

### Kenney — standalone "Barricade" model
- **URL:** https://poly.pizza/m/cNGRlrEJEe
- **License:** CC0 (public domain), author confirmed as Kenney.
- **Format:** FBX and glTF.
- **Fit:** A single standalone barricade model (useful if only City Kit: Roads' bundled barricade variant isn't quite right, or as a lightweight single-prop import without pulling the whole kit).

### Other barricade options found (secondary, not verified for license depth)
- "Wood Barricade" by Dakota_Du — https://poly.pizza/m/HS49Rmidqs (poly.pizza models are either CC0 or CC-BY; check the individual page before use since license varies per-model on poly.pizza, unlike Kenney's own CC0-everything policy).
- Sketchfab has several "Police Crowd Barrier" / barricade models surfaced in search, but Sketchfab licenses vary per-uploader (many are "Standard" non-commercial) — would need individual verification and are not recommended as a primary source given Kenney's City Kit already covers this need under a clean CC0 license.

---

## 3. Street Props: Benches, Lamp Posts, Trash Cans, Statue

### Kenney — City Kit (Roads) / City Kit (Commercial) family
- Benches, lamp posts (street lamps), and trash cans/dumpsters are confirmed present in **City Kit (Roads)** (see above) and Kenney's related City Kit series (Commercial / Suburban variants, same CC0 license, cross-compatible models) — see the full Kenney "Transport"/"City" series index at https://kenney.nl/assets/series:Transport for sibling kits.
- Same license/format/fit notes as section 2.

### Statue — "Statue" by Zsky (poly.pizza)
- **URL:** https://poly.pizza/m/VerAznL5lK
- **License:** Creative Commons Attribution (CC-BY) — commercial use allowed, but **requires crediting Zsky** in the game's credits.
- **Format:** Available via poly.pizza (FBX/glTF, optimized for Unity/Unreal/Godot per poly.pizza's standard listing format).
- **Fit:** A generic plinth-style statue is exactly the "climb all over it" target object described in the vision doc; low-poly style matches.

### Statue — alternative CC0 option: "Fox Statue" by Quaternius
- **URL:** https://www.poly.pizza/m/abxyXID5EA
- **License:** CC0 / Public Domain — no attribution needed.
- **Format:** FBX/glTF.
- **Fit:** Thematically a statue of an animal rather than a person/general monument — less of a fit for a "Paris landmark statue" look, but useful if a zero-attribution option is preferred over the Zsky statue. For an actual human/Parisian-monument-style statue, the Zsky CC-BY model (or a "Mannequin" — https://poly.pizza/m/tYwjQJvcFX, CC0, by reyshapes — posed as a faux-statue) are closer fits.

---

## 4. Bus / Vehicle

### Kenney — Car Kit (top pick for the bus target)
- **URL:** https://kenney.nl/assets/car-kit (also https://kenney-assets.itch.io/car-kit)
- **License:** CC0 — no attribution required (crediting Kenney appreciated but optional).
- **Format:** OBJ, FBX, and glTF (glTF imports cleanly into Godot 4.7). 45+ models total, including a confirmed **bus model** alongside sedans, vans, an ambulance, trucks, and 8 separate wheel models plus debris pieces for "exploding"/damaged vehicle variants.
- **Fit:** Directly matches the vision doc's "Bus: protesters surround and block it, some climb onto it" target — low-poly, single consistent style matching the City Kit series (shares Kenney's visual language), and the included wheel/debris parts are a bonus for physics-chaos moments (parts falling off under mob pressure).

---

## 5. Megaphone Prop

### "Megaphone" by 4444ESOUSA (poly.pizza)
- **URL:** found via https://poly.pizza/search/megaphone (listing page); direct model page not individually re-verified beyond the search listing.
- **License:** Not confirmed on the search listing — poly.pizza hosts a mix of CC0 and CC-BY models, so **check the individual model page before use** to confirm license and attribution requirement.
- **Fit:** Only clearly-named free low-poly megaphone found. Given Kenney's catalog doesn't appear to include a megaphone, this is the most promising lead but needs a direct visit to the model page to confirm license/format before committing.
- **Fallback plan:** If this doesn't pan out, the megaphone is a very simple prop (cone + handle + cylinder) — worth considering a quick custom low-poly model in Blender matching Kenney's flat-shaded style rather than depending on an unverified third-party asset, since it's the player's signature "weapon" and should match the rest of the kit's visual language exactly.

---

## Top Recommendations

**Crowd NPC character:** **Quaternius — Ultimate Modular Men Pack**
(https://quaternius.com/packs/ultimatemodularcharacters.html) — CC0, glTF with full
skeleton + 24 animations (walk/idle/run included), and the 4-part modular swap system
is the cheapest way to get visually varied crowds of dozens/hundreds of NPCs without
needing new rigs or animations per variant. Its flat-shaded, untextured look also suits
a Fall-Guys-style simple aesthetic out of the box.

**Prop pack (barricades/street furniture):** **Kenney — City Kit (Roads)**
(https://kenney.nl/assets/city-kit-roads) — CC0, glTF, 65+ models under one shared
material, and it already covers barricades, traffic cones, lamp posts, road signs,
and trash bins in one consistent, free-for-anything-licensed kit. Pair it with
**Kenney — Car Kit** (https://kenney.nl/assets/car-kit, same license/visual style) for
the bus, since both kits share Kenney's house style and will look cohesive side by side.

## Open Items / Needs Follow-Up
- Megaphone: license on the poly.pizza "Megaphone" model (by 4444ESOUSA) needs direct
  confirmation before use; otherwise a quick custom model is the safer bet for the
  player's signature prop.
- Statue: decide between CC-BY "Statue" by Zsky (needs credit) vs. a CC0 substitute
  (Quaternius Fox Statue, or a posed Mannequin) depending on whether crediting is
  acceptable for the project.
- Benches/lamp posts/trash cans are referenced as part of Kenney's City Kit (Roads)
  pack but weren't individually broken out by model name in this pass — confirm exact
  model names once the pack is downloaded.
