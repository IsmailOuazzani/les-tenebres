# Map / Environment Asset Research — "Les Tenebres"

Research for free, Godot 4.7-compatible map/environment assets (streets, buildings, plazas,
modular city kits) to build the Paris-inspired low-poly test map for the protest simulator.
Character, NPC, and prop assets (barricades, people, buses-as-props, etc.) are **out of scope**
here — covered by a separate agent.

All packs below are free. Where a pack is "pay what you want," the $0 tier is confirmed to
unlock the full download.

---

## 1. Kenney — City Kit (Roads)

- **URL:** https://kenney.nl/assets/city-kit-roads (mirror: https://opengameart.org/content/city-kit-roads)
- **License:** CC0 (public domain). No attribution required, unlimited commercial use.
- **Format:** FBX, OBJ, and GLTF provided separately, with import instructions for popular engines. GLTF import into Godot 4.7 is near-plug-and-play (Godot has native glTF2 import).
- **Scope:** ~90 pieces — straight/curved/intersection road tiles, sidewalks, crosswalks, barriers, traffic lights, road signs, a Dutch-style color variant with cycle paths.
- **Fit:** Excellent base layer for Paris streets. Low-poly, flat-shaded style matches Fall Guys/Schedule 1 aesthetic closely. Doesn't include buildings — needs a companion kit (see below).

## 2. Kenney — City Kit (Commercial)

- **URL:** https://kenney.nl/assets/city-kit-commercial (mirror: https://opengameart.org/content/city-kit-commercial)
- **License:** CC0. Same terms as above.
- **Format:** FBX, OBJ, GLTF.
- **Scope:** ~50 pieces (v2.0 remade) — commercial buildings/skyscrapers, awnings, building parts, signs (hospital signs, shop signage, etc.), designed to snap together with City Kit (Roads) on the same grid.
- **Fit:** Good generic low/mid-rise city buildings. Not Haussmannian/Parisian in style (more generic Western city), but the flat-color low-poly look blends fine with a "Paris-ish" stylized take rather than a photoreal Paris. Combine with Roads kit for a full modular street block.
- **Note:** Kenney also has City Kit (Suburban) and City Kit (Industrial) variants (https://kenney.nl/assets/series:City) if more building variety is wanted later — same CC0 terms.

## 3. Kay Lousberg (KayKit) — City Builder Bits

- **URL:** https://kaylousberg.itch.io/city-builder-bits
- **License:** CC0. Free for personal and commercial use, no attribution required (pay-what-you-want support tiers exist but $0 unlocks everything).
- **Format:** Standard KayKit delivery is FBX/OBJ/GLB with a single gradient atlas texture (1024×1024, can be downsampled). Needs the same straightforward glTF/FBX import into Godot 4.7.
- **Scope:** 32+ low-poly optimized models aimed at city-builder/RTS/simulation use — roads, small buildings, props, all using one shared gradient-ramp texture (Kay's signature super-efficient look).
- **Fit:** Very good — KayKit's aesthetic (chunky, rounded, flat-shaded) is one of the closest free matches to the Fall Guys/Schedule 1 vibe. Smaller scope than Kenney's kits, best used as a visual accent/prop layer alongside Kenney roads+buildings rather than the sole building source.

## 4. EH98 — Low Poly City Kit (Roads, Buildings with Interiors & Street Props)

- **URL:** https://eh98.itch.io/low-poly-city-kit
- **License:** Paid ($2.99+, "name a fair price" minimum may apply — confirm actual $0 availability before relying on it). License text: "Use in unlimited commercial and non-commercial projects, no attribution required." Resale of the raw model files themselves is prohibited.
- **Format:** GLB, FBX, OBJ, and .blend — **explicitly lists Godot 4 as a supported/tested engine**.
- **Scope:** 27 pieces — 7 road tiles (straight, crosswalk, crossroads, T-junction, corner, plaza, grass lot) snapping to a 12m grid, 7 buildings **with real interiors and removable roofs**, 13 street props (traffic lights, lamps, signs, bus stop, trees, benches), plus a pre-built demo city block.
- **Fit:** Very strong fit conceptually — explicit Godot 4 support, plaza tile already included, bus stop prop, and building interiors open up gameplay possibilities (crowd entering buildings later). **Caveat: this is the one pack here that is not confirmed free** — flag to the team before relying on it; verify current itch.io price before purchase/use.

## 5. Nozenx — Lowpoly Street Pack

- **URL:** https://nozenx.itch.io/lowpoly-street-pack
- **License:** Free, "name your own price" (0 is valid). "Personal and commercial use" permitted; creator states no generative AI was used in production.
- **Format:** Raw FBX with textures, plus a separate Unity-ready package; creator explicitly notes it works in "Unreal, Godot, Blender, etc." FBX import into Godot 4.7 works but typically needs material/texture reassignment (Unity package is not directly usable).
- **Scope:** 47 unique meshes — 27 modular wall pieces, 5 roof pieces, 6 road/sidewalk pieces, 5 street-furniture props, 4 nature/detail props. Single shared texture atlas, grid-based, snaps with no gaps.
- **Fit:** Good secondary/filler pack for building facade variety (more wall/roof modularity than Kenney's Commercial kit offers), at zero cost. Needs a bit more manual texture setup in Godot than the GLTF-first Kenney/KayKit options.

## 6. Quaternius — City Pack / LowPoly Modular Street Pack

- **URL (bundle incl. city pack):** https://poly.pizza/bundle/City-Pack-q11onRvPoJ
- **URL (modular street, mirrored on OpenGameArt):** https://opengameart.org/content/lowpoly-modular-street-pack
- **License:** CC0 / Public Domain (Quaternius's standard license across all packs).
- **Format:** FBX, OBJ, GLTF (Quaternius ships all three consistently) — direct Godot 4.7 import via glTF.
- **Scope:** City Pack bundle ≈ 36 models (cars, buildings, people, roads — note the cars/people are out of scope for this research but come bundled); Modular Street Pack is road/sidewalk-focused.
- **Fit:** Decent filler, very easy import, but thinner on dedicated building variety than Kenney's kits. Best used to pad out road/sidewalk tile variety if Kenney's road kit runs short, or to crowd-source extra generic low-poly clutter.

## Also considered, not recommended as primary sources

- **Sketchfab individual models** (e.g. "Paris" by TerraMesh, "A street in Paris" by Emm, "Plaza (LowPoly)" by 3dMuffin — found via sketchfab.com search) — these are one-off single scenes/models, mostly **CC-BY** (attribution required) rather than modular kits. Useful only as visual reference or a single hero landmark prop later, not as a buildable street-kit base. Licenses vary per model and must be re-checked individually before use.
- **Low-Poly Japanese City Assets for Godot** (potetiinu.itch.io, 528 assets) — large and Godot-packaged, but the style is explicitly Japanese/cyberpunk/SF themed, not Parisian — would fight the target art direction.

---

## Top Recommendation: What to Download First

**Start with the free Kenney CC0 combo — zero licensing risk, zero cost, native GLTF/FBX, and it's the single most widely used low-poly city base in the Godot/game-jam community:**

1. **Kenney City Kit (Roads)** — https://kenney.nl/assets/city-kit-roads
2. **Kenney City Kit (Commercial)** — https://kenney.nl/assets/city-kit-commercial

Together these give everything needed for the test map described in the brief:
- Street/road tiles and intersections to lay out a few blocks.
- A grass/plaza-style open tile (or combine with EH98's dedicated plaza tile later) for the "protesters gather and chant" plaza use case.
- A handful of commercial buildings to frame the streets.
- Traffic lights/signs for set dressing.

Import both via Godot's built-in glTF2 importer (drop the `.glb`/`.gltf` files into the project — Godot 4.7 handles this natively, no plugin needed). Snap pieces together on Kenney's shared grid to build a small test block: a couple of street segments meeting at an intersection, one open plaza tile, 3-4 buildings framing it, and whatever bus/vehicle prop the other agent sources dropped into the street.

**Optional immediate add-on:** grab **KayKit City Builder Bits** (also CC0, also free) for a few extra chunky low-poly building/prop variants — its rounded, gradient-shaded style blends well with Kenney's flat-color look and adds visual variety cheaply.

**Hold off on EH98's Low Poly City Kit** until its current itch.io price is confirmed — it's the best Godot-native fit on paper (explicit Godot 4 support, interiors, bus stop, plaza tile) but may not actually be free, so don't block the prototype on it.
