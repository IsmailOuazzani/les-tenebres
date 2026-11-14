#!/usr/bin/env python3
"""Generate scenes/map_geometry.tscn -- the whole street grid, buildings and
destructible street furniture for the test map.

Why this is a text generator and not a Godot script:
an earlier attempt did `load("test_map.tscn").instantiate()` -> mutate ->
`PackedScene.pack(root)` -> save, run under `godot --headless --script`.
Bare `--script` mode does not initialise autoloads, so every script that
touches the `GameState` autoload (npc_spawner, police_spawner,
crowd_controller, hud, game_over) failed to compile, Godot nulled those
`script` properties, and repacking the *whole* scene then serialised that
broken state -- wiping all the gameplay wiring along with the map.

So: the map lives in its own scene containing nothing but geometry, it is
emitted as text (no engine involved, nothing to round-trip), and
`test_map.tscn` references it with a single `instance=ExtResource(...)` line.
Regenerating the map now structurally cannot reach the gameplay nodes.

Run:  python3 tools/generate_map_geometry.py
Then: godot --path . --headless --quit-after 5   (to verify it loads)
"""

import random
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "scenes" / "map_geometry.tscn"

# --- Grid -------------------------------------------------------------------
# Kenney tiles are 1 unit square, instanced at the project-wide 4x scale, so
# the grid pitch is 4 and a tile centred at c spans [c-2, c+2].
PITCH = 4.0
LANES = (-4.0, 0.0, 4.0)   # 3-lane carriageway, 12 units of road
SIDEWALK = 8.0             # sidewalk strip centre offset
HALF_CORR = 10.0           # outer edge of the street corridor (incl. sidewalk)

# Street spacing is 64, a multiple of the 4-unit pitch so intersection tiles
# land on the same grid as street tiles. 64 is the smallest spacing that works
# with this building set: it leaves a 44-unit block run, enough to take a
# facade on all four block edges (widest building is 20.4) *and* still fit
# ~3 buildings per edge. Tighter spacing (tried 48) makes every block corner a
# collision between two perpendicular facades and the map ends up sparser, not
# denser -- which is the "empty gaps" failure mode all over again.
NS_STREETS = (-96.0, -32.0, 32.0, 96.0)          # run along Z
EW_STREETS = (-96.0, -32.0, 32.0, 96.0)          # run along X

X_MIN, X_MAX = -106.0, 106.0
Z_MIN, Z_MAX = -106.0, 106.0

# Keep props off the player spawn.
SPAWN = (0.0, 10.0)
SPAWN_CLEAR = 7.0

# --- Tile orientations ------------------------------------------------------
# Extracted from the hand-built map: the four cardinal Y-rotations at scale 4,
# verbatim (float noise included) so new tiles match existing ones exactly.
# `road-side` is asymmetric -- its curb sits on local -Z, so the rotation
# chosen for a sidewalk is the one that points local -Z at the road.
R0 = "4, 0, 0, 0, 4, 0, 0, 0, 4"                                      # -Z
R90 = "-1.7484555e-07, 0, -4, 0, 4, 0, 4, 0, -1.7484555e-07"          # -X
R180 = "-4, 0, -3.496911e-07, 0, 4, 0, 3.496911e-07, 0, -4"           # +Z
R270 = "-1.7484555e-07, 0, 4, 0, 4, 0, -4, 0, -1.7484555e-07"         # +X

# --- Resources --------------------------------------------------------------
EXT = [
    ("2_road", "res://assets/kenney_city_kit_roads/road-straight.glb"),
    ("3_side", "res://assets/kenney_city_kit_roads/road-side.glb"),
    ("4_square", "res://assets/kenney_city_kit_roads/road-square.glb"),
    ("5_crossing", "res://assets/kenney_city_kit_roads/road-crossing.glb"),
    ("6_lamp", "res://assets/kenney_city_kit_roads/light-square.glb"),
    ("7_parisa", "res://assets/paris_building_pack/BuildingA/BuildingA.fbx"),
    ("8_parisb", "res://assets/paris_building_pack/BuildingB/BuildingB.fbx"),
    ("9_parisc", "res://assets/paris_building_pack/BuildingC/BuildingC.fbx"),
    ("10_parasola", "res://assets/kenney_city_kit_commercial/detail-parasol-a.glb"),
    ("11_parasolb", "res://assets/kenney_city_kit_commercial/detail-parasol-b.glb"),
    ("12_awning", "res://assets/kenney_city_kit_commercial/detail-awning.glb"),
    # Destructibles (each scene bakes its own 4x/model scale -> instance at 1)
    ("20_d_barricade", "res://scenes/destructible_barricade.tscn"),
    ("21_d_cone", "res://scenes/destructible_cone.tscn"),
    ("22_d_traffic", "res://scenes/destructible_traffic_light.tscn"),
    ("23_d_sign", "res://scenes/destructible_road_sign.tscn"),
    ("24_d_bus", "res://scenes/destructible_bus.tscn"),
    ("25_d_glass", "res://scenes/destructible_shop_window.tscn"),
    ("26_d_dumpster", "res://scenes/destructible_prop.tscn"),
    ("27_d_sedan", "res://scenes/destructible_sedan.tscn"),
    ("28_d_ambulance", "res://scenes/destructible_ambulance.tscn"),
    ("29_d_lamppost", "res://scenes/destructible_lamp_post.tscn"),
    ("30_d_pole", "res://scenes/destructible_electricity_pole.tscn"),
    ("31_d_fence", "res://scenes/destructible_fence.tscn"),
    ("32_d_parasol", "res://scenes/destructible_parasol.tscn"),
    ("33_d_awning", "res://scenes/destructible_awning.tscn"),
    ("34_d_highway", "res://scenes/destructible_highway_sign.tscn"),
    ("35_d_pillar", "res://scenes/destructible_bridge_pillar.tscn"),
]

# Paris Building Pack, already-baked dims at the project's 3x scale.
# w = street-perpendicular (the model's local X), d = along-street (local Z).
BUILDINGS = {
    "A": dict(res="7_parisa", w=6.87, h=14.28, d=13.41, yoff=0.0, box="Box_parisA"),
    "B": dict(res="8_parisb", w=20.4, h=22.05, d=20.43, yoff=0.0, box="Box_parisB"),
    "C": dict(res="9_parisc", w=9.09, h=17.76, d=13.11, yoff=2.16, box="Box_parisC"),
}
# Weighted toward the two shallow buildings: B is 20.4 deep and on its own
# consumes almost a whole 28-unit block run.
BUILDING_CYCLE = ("A", "C", "A", "B", "C", "A", "C", "B")
BUILDING_GAP = 1.0

rng = random.Random(7)

visuals: list[str] = []
collision: list[str] = []
props: list[str] = []
footprints: list[tuple[float, float, float, float]] = []  # x0,z0,x1,z1
counters: dict[str, int] = {}


def uid(prefix: str) -> str:
    counters[prefix] = counters.get(prefix, 0) + 1
    return f"{prefix}{counters[prefix]}"


def fmt(v: float) -> str:
    return f"{v:g}"


def node(out: list[str], name: str, parent: str, res: str, basis: str,
         x: float, y: float, z: float) -> None:
    out.append(f'[node name="{name}" parent="{parent}" instance=ExtResource("{res}")]')
    out.append(f"transform = Transform3D({basis}, {fmt(x)}, {fmt(y)}, {fmt(z)})\n")


def body(name: str, shape: str, basis: str, x: float, y: float, z: float) -> None:
    collision.append(f'[node name="{name}" type="StaticBody3D" parent="Collision"]')
    collision.append(f"transform = Transform3D({basis}, {fmt(x)}, {fmt(y)}, {fmt(z)})\n")
    collision.append(f'[node name="Shape" type="CollisionShape3D" parent="Collision/{name}"]')
    collision.append(f'shape = SubResource("{shape}")\n')


def free(x0: float, z0: float, x1: float, z1: float, pad: float = 0.0) -> bool:
    """True if the rect is clear of every footprint placed so far."""
    for a0, b0, a1, b1 in footprints:
        if x0 - pad < a1 and a0 < x1 + pad and z0 - pad < b1 and b0 < z1 + pad:
            return False
    return True


def claim(x0: float, z0: float, x1: float, z1: float) -> None:
    footprints.append((x0, z0, x1, z1))


def on_street(x: float, z: float) -> bool:
    """Inside a street corridor (incl. sidewalks and intersections)?"""
    if any(abs(x - sx) <= HALF_CORR for sx in NS_STREETS):
        return True
    return any(abs(z - ez) <= HALF_CORR for ez in EW_STREETS)


def in_intersection(x: float, z: float) -> bool:
    return (any(abs(x - sx) <= HALF_CORR for sx in NS_STREETS)
            and any(abs(z - ez) <= HALF_CORR for ez in EW_STREETS))


def near_spawn(x: float, z: float, r: float = SPAWN_CLEAR) -> bool:
    return (x - SPAWN[0]) ** 2 + (z - SPAWN[1]) ** 2 < r * r


def frange(lo: float, hi: float, step: float):
    v = lo
    while v <= hi + 1e-6:
        yield v
        v += step


# --- Roadway ----------------------------------------------------------------

def tile_centres(lo: float, hi: float):
    """Tile centres on the 4-unit grid fully inside [lo, hi]."""
    first = PITCH * round((lo + PITCH / 2) / PITCH)
    return list(frange(first, hi - PITCH / 2, PITCH))


def build_intersections() -> int:
    n = 0
    for sx in NS_STREETS:
        for ez in EW_STREETS:
            for dx in (-8.0, -4.0, 0.0, 4.0, 8.0):
                for dz in (-8.0, -4.0, 0.0, 4.0, 8.0):
                    node(visuals, uid("Xsq"), "Visuals", "4_square", R0,
                         sx + dx, 0.0, ez + dz)
            n += 1
    return n


def build_ns_streets() -> None:
    for sx in NS_STREETS:
        for z in tile_centres(Z_MIN, Z_MAX):
            if in_intersection(sx, z):
                continue
            # Zebra crossings on the approach to every intersection.
            approach = any(HALF_CORR < abs(z - ez) <= HALF_CORR + PITCH
                           for ez in EW_STREETS)
            res = "5_crossing" if approach else "2_road"
            for dx in LANES:
                node(visuals, uid("NSr"), "Visuals", res, R270, sx + dx, 0.0, z)
            node(visuals, uid("NSw"), "Visuals", "3_side", R270, sx - SIDEWALK, 0.0, z)
            node(visuals, uid("NSe"), "Visuals", "3_side", R90, sx + SIDEWALK, 0.0, z)


def build_ew_streets() -> None:
    for ez in EW_STREETS:
        for x in tile_centres(X_MIN, X_MAX):
            if in_intersection(x, ez):
                continue
            approach = any(HALF_CORR < abs(x - sx) <= HALF_CORR + PITCH
                           for sx in NS_STREETS)
            res = "5_crossing" if approach else "2_road"
            for dz in LANES:
                node(visuals, uid("EWr"), "Visuals", res, R0, x, 0.0, ez + dz)
            node(visuals, uid("EWn"), "Visuals", "3_side", R0, x, 0.0, ez + SIDEWALK)
            node(visuals, uid("EWs"), "Visuals", "3_side", R180, x, 0.0, ez - SIDEWALK)


# --- Buildings --------------------------------------------------------------
# A building's front face sits flush on the sidewalk's outer edge, so its
# centre is HALF_CORR + w/2 out from the street centreline.

def _place(kind: str, cx: float, cz: float, along_z: bool) -> bool:
    b = BUILDINGS[kind]
    if along_z:                      # faces +/-X, depth runs along Z
        hx, hz = b["w"] / 2, b["d"] / 2
        vbasis, cbasis = "3, 0, 0, 0, 3, 0, 0, 0, 3", "1, 0, 0, 0, 1, 0, 0, 0, 1"
    else:                            # rotated 90 deg: depth runs along X
        hx, hz = b["d"] / 2, b["w"] / 2
        vbasis, cbasis = "0, 0, -3, 0, 3, 0, 3, 0, 0", "0, 0, -1, 0, 1, 0, 1, 0, 0"
    x0, z0, x1, z1 = cx - hx, cz - hz, cx + hx, cz + hz
    if not free(x0, z0, x1, z1, pad=0.5):
        return False
    name = uid(f"Bld{kind}")
    node(visuals, name, "Visuals", b["res"], vbasis, cx, b["yoff"], cz)
    body(f"Col_{name}", b["box"], cbasis, cx, b["h"] / 2, cz)
    claim(x0, z0, x1, z1)
    return True


def block_runs(crossings, lo: float, hi: float) -> list[tuple[float, float]]:
    """The buildable stretches along a street: [lo, hi] minus every crossing
    street's corridor. Buildings are packed inside one run at a time -- packing
    from the map edge instead makes nearly every candidate straddle a run
    boundary and get rejected."""
    out = []
    cursor = lo
    for c in sorted(crossings):
        a, b = c - HALF_CORR, c + HALF_CORR
        if a > cursor:
            out.append((cursor, min(a, hi)))
        cursor = max(cursor, b)
    if cursor < hi:
        out.append((cursor, hi))
    return [(a, b) for a, b in out if b - a > 8.0]


SLIDE = 2.0  # how far to nudge along when a slot is already occupied


def fill_run(street: float, side: float, run: tuple[float, float],
             along_z: bool, cyc: int):
    """Pack one block edge. Walks the type cycle; when a candidate overlaps
    something already placed (the usual case at block corners, where the
    perpendicular facade got there first) it slides along by SLIDE and retries
    rather than abandoning the slot -- that single behaviour roughly doubled
    the building count."""
    lo, hi = run
    cursor, placed, stalls = lo, 0, 0
    while cursor < hi and stalls < 64:
        kind = BUILDING_CYCLE[cyc % len(BUILDING_CYCLE)]
        b = BUILDINGS[kind]
        if cursor + b["d"] > hi:
            cyc += 1
            stalls += 1
            continue
        centre = cursor + b["d"] / 2
        off = street + side * (HALF_CORR + b["w"] / 2)
        cx, cz = (off, centre) if along_z else (centre, off)
        lim = (X_MIN, X_MAX) if along_z else (Z_MIN, Z_MAX)
        if lim[0] <= off <= lim[1] and _place(kind, cx, cz, along_z):
            cursor = centre + b["d"] / 2 + BUILDING_GAP
            placed += 1
            stalls = 0
        else:
            cursor += SLIDE
            stalls += 1
        cyc += 1
    return placed, cyc


def build_buildings() -> int:
    placed, cyc = 0, 0
    # N-S facades go down first and get the full run; E-W facades then slide
    # around whatever already holds the corners.
    for sx in NS_STREETS:
        for side in (-1.0, 1.0):
            for run in block_runs(EW_STREETS, Z_MIN, Z_MAX):
                n, cyc = fill_run(sx, side, run, True, cyc)
                placed += n
    for ez in EW_STREETS:
        for side in (-1.0, 1.0):
            for run in block_runs(NS_STREETS, X_MIN, X_MAX):
                n, cyc = fill_run(ez, side, run, False, cyc)
                placed += n
    return placed


# --- Street furniture -------------------------------------------------------

def prop(res: str, x: float, z: float, yaw_basis: str = "1, 0, 0, 0, 1, 0, 0, 0, 1",
         y: float = 0.0) -> None:
    node(props, uid("P"), "Props", res, yaw_basis, x, y, z)


YAW = {
    0: "1, 0, 0, 0, 1, 0, 0, 0, 1",
    90: "0, 0, -1, 0, 1, 0, 1, 0, 0",
    180: "-1, 0, 0, 0, 1, 0, 0, 0, -1",
    270: "0, 0, 1, 0, 1, 0, -1, 0, 0",
}


def build_furniture() -> dict[str, int]:
    tally: dict[str, int] = {}

    def add(res: str, x: float, z: float, yaw: int = 0) -> None:
        prop(res, x, z, YAW[yaw])
        tally[res] = tally.get(res, 0) + 1

    # Intersection corners: traffic lights, stop signs, lamps.
    for sx in NS_STREETS:
        for ez in EW_STREETS:
            for i, (dx, dz) in enumerate(((-9, -9), (9, -9), (-9, 9), (9, 9))):
                x, z = sx + dx, ez + dz
                if near_spawn(x, z, 4.0):
                    continue
                add("22_d_traffic" if i % 2 == 0 else "23_d_sign", x, z,
                    (i * 90) % 360)
            node(visuals, uid("Lmp"), "Visuals", "6_lamp", R0, sx - 9.0, 0.0, ez)
            node(visuals, uid("Lmp"), "Visuals", "6_lamp", R0, sx + 9.0, 0.0, ez)

    # Sidewalk furniture down every street, alternating along the strip.
    sidewalk_kit = ("29_d_lamppost", "26_d_dumpster", "30_d_pole", "31_d_fence",
                    "32_d_parasol", "21_d_cone")
    k = 0
    for sx in NS_STREETS:
        for side in (-1.0, 1.0):
            x = sx + side * 9.0
            for z in frange(Z_MIN + 6, Z_MAX - 6, 14.0):
                if in_intersection(x, z) or near_spawn(x, z):
                    continue
                add(sidewalk_kit[k % len(sidewalk_kit)], x, z, 0 if side < 0 else 180)
                k += 1
    for ez in EW_STREETS:
        for side in (-1.0, 1.0):
            z = ez + side * 9.0
            for x in frange(X_MIN + 6, X_MAX - 6, 14.0):
                if in_intersection(x, ez) or near_spawn(x, z):
                    continue
                add(sidewalk_kit[k % len(sidewalk_kit)], x, z, 90 if side < 0 else 270)
                k += 1

    # Shopfronts against building faces. Deliberately sparse: each glass pane is
    # a CSGPolygon3D (it rebuilds its mesh to fracture), so these are the most
    # expensive prop in the set -- one per block face, not a continuous parade.
    for sx in NS_STREETS:
        for side in (-1.0, 1.0):
            x = sx + side * 10.5
            for z in frange(Z_MIN + 24, Z_MAX - 24, 48.0):
                if in_intersection(x, z) or near_spawn(x, z):
                    continue
                add("25_d_glass", x, z, 0 if side < 0 else 180)
                add("33_d_awning", x, z + 7.0, 0 if side < 0 else 180)
                add("32_d_parasol", x - side * 1.5, z - 7.0)

    # Parked / abandoned vehicles in the gutter lanes.
    vehicles = ("24_d_bus", "27_d_sedan", "28_d_ambulance", "27_d_sedan")
    v = 0
    for sx in NS_STREETS:
        for z in frange(Z_MIN + 24, Z_MAX - 24, 31.0):
            if in_intersection(sx, z) or near_spawn(sx, z, 12.0):
                continue
            add(vehicles[v % len(vehicles)], sx + rng.choice((-4.0, 4.0)), z, 0)
            v += 1
    for ez in EW_STREETS:
        for x in frange(X_MIN + 24, X_MAX - 24, 37.0):
            if in_intersection(x, ez) or near_spawn(x, ez, 12.0):
                continue
            add(vehicles[v % len(vehicles)], x, ez + rng.choice((-4.0, 4.0)), 90)
            v += 1

    # Barricade lines across a few approaches -- riot-police chokepoints.
    for sx in NS_STREETS:
        for ez in EW_STREETS:
            if rng.random() > 0.45:
                continue
            side = rng.choice((-1.0, 1.0))
            z = ez + side * 14.0
            if near_spawn(sx, z, 10.0):
                continue
            for dx in (-5.0, -1.5, 1.5, 5.0):
                add("20_d_barricade", sx + dx, z, 0)
            for dx in (-7.0, 7.0):
                add("21_d_cone", sx + dx, z, 0)

    # Highway signs and bridge pillars as long-sightline landmarks.
    for i, ez in enumerate(EW_STREETS):
        add("34_d_highway", NS_STREETS[i % len(NS_STREETS)] + 9.0, ez + 20.0, 90)
    for sx in (NS_STREETS[0], NS_STREETS[-1]):
        add("35_d_pillar", sx, Z_MIN + 30.0, 0)
        add("35_d_pillar", sx, Z_MAX - 30.0, 0)

    return tally


# --- Emit -------------------------------------------------------------------

def main() -> None:
    n_int = build_intersections()
    build_ns_streets()
    build_ew_streets()
    n_bld = build_buildings()
    tally = build_furniture()

    size_x = X_MAX - X_MIN
    size_z = Z_MAX - Z_MIN

    head = ["[gd_scene format=4]", ""]
    for rid, path in EXT:
        kind = "PackedScene"
        head.append(f'[ext_resource type="{kind}" path="{path}" id="{rid}"]')
    head.append("")
    head += [
        '[sub_resource type="BoxShape3D" id="Box_parisA"]',
        "size = Vector3(6.87, 14.28, 13.41)", "",
        '[sub_resource type="BoxShape3D" id="Box_parisB"]',
        "size = Vector3(20.4, 22.05, 20.43)", "",
        '[sub_resource type="BoxShape3D" id="Box_parisC"]',
        "size = Vector3(9.09, 17.76, 13.11)", "",
        '[sub_resource type="BoxShape3D" id="Box_ground"]',
        f"size = Vector3({fmt(size_x)}, 1, {fmt(size_z)})", "",
        '[sub_resource type="StandardMaterial3D" id="Mat_ground"]',
        "albedo_color = Color(0.21, 0.2, 0.19, 1)",
        "roughness = 0.95", "",
        '[sub_resource type="PlaneMesh" id="Mesh_ground"]',
        'material = SubResource("Mat_ground")',
        f"size = Vector2({fmt(size_x)}, {fmt(size_z)})", "",
        '[node name="MapGeometry" type="Node3D"]', "",
        '[node name="Visuals" type="Node3D" parent="."]', "",
        # Base plate under everything: block interiors read as ground, not void,
        # and it matches GroundCollision exactly.
        '[node name="GroundPlane" type="MeshInstance3D" parent="Visuals"]',
        "transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, -0.05, 0)",
        'mesh = SubResource("Mesh_ground")', "",
    ]

    mid = ['[node name="Props" type="Node3D" parent="."]', ""]
    tail = ['[node name="Collision" type="Node3D" parent="."]', ""]

    ground = [
        '[node name="GroundCollision" type="StaticBody3D" parent="Collision"]',
        "transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, -0.5, 0)", "",
        '[node name="Shape" type="CollisionShape3D" parent="Collision/GroundCollision"]',
        'shape = SubResource("Box_ground")', "",
    ]

    OUT.write_text("\n".join(head + visuals + mid + props + tail + ground + collision))

    n_tiles = sum(counters.get(p, 0) for p in
                  ("Xsq", "NSr", "NSw", "NSe", "EWr", "EWn", "EWs"))
    print(f"wrote {OUT.relative_to(OUT.parents[1])}")
    print(f"  extent      {size_x:g} x {size_z:g}  = {size_x * size_z:,.0f} m2")
    print(f"  tiles       {n_tiles}")
    print(f"  intersect.  {n_int}")
    print(f"  buildings   {n_bld}")
    print(f"  props       {sum(tally.values())} ({len(tally)} kinds)")
    for res in sorted(tally, key=lambda r: -tally[r]):
        print(f"      {tally[res]:4d}  {res}")


if __name__ == "__main__":
    main()
