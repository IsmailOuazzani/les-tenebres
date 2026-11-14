# LAN Co-op Multiplayer — Implementation Notes

Implementation notes for the 1-4 player LAN co-op mode. Terminology follows
the spec: listen server, state replication, network ownership/authority,
spawn/despawn, snapshot interpolation, aggro, crowd AI.

---

## 1. Architecture

**Listen server. Server-authoritative game simulation, client-authoritative
player movement.**

The hosting player's process runs both the authoritative server and a local
client. Transport is `ENetMultiplayerPeer` over UDP on port **7000**.

Everything is built on Godot 4's own high-level multiplayer API — there is no
custom networking framework:

| Need | Godot mechanism |
|---|---|
| Transport / session | `ENetMultiplayerPeer` |
| Entity spawn/despawn replication | `MultiplayerSpawner` (3 of them) |
| State replication | `MultiplayerSynchronizer` + `SceneReplicationConfig` |
| Network ownership | `Node.set_multiplayer_authority()` |
| Gameplay commands and events | `@rpc` methods on the owning node |

### Network ownership

| Entity / system | Authority | Where |
|---|---|---|
| Player movement and look | Owning client | `scripts/player.gd` + `InputSync` |
| Player health, death, respawn | Server | `ServerSync`, `scenes/test_map.gd` |
| Crowd simulation (recruitment, steering) | Server | `scripts/crowd_controller.gd`, `scripts/npc.gd` |
| Crowd commands ("À L'ATTAQUE!") | Server | `CrowdController.request_send_mob()` |
| Police AI and combat | Server | `scripts/police.gd` |
| Civilian / police spawning | Server | `npc_spawner.gd`, `police_spawner.gd` |
| Gameplay physics and destruction | Server | `destructible_prop.gd` |
| Grabuge and gameplay events | Server | `scripts/game_state.gd` |

### The one predicate everything branches on

`NetworkManager.is_authoritative()` — true on the listen server and in
single-player, false on a client. Every server-authoritative system starts
with it. `NetworkManager.is_multiplayer_session()` is the separate "is there
a peer to send RPCs to" guard, false in single-player.

### Single-player uses the same code path

Single-player installs an **`OfflineMultiplayerPeer`** rather than leaving
`multiplayer.multiplayer_peer` unset. With no peer at all, every
`is_multiplayer_authority()` call pushes *"No multiplayer peer is assigned"*
(confirmed headlessly — it spammed the log every frame from
`MovementController`, `Head`, `Megaphone` and `PlayerRegistry`). The offline
peer reports unique id 1 and `is_server()`, so all authority guards are
trivially true and single-player and multiplayer share one code path.

---

## 2. Session flow

`scenes/main_menu.tscn` → `scenes/lobby.tscn` → `scenes/test_map.tscn`.
`run/main_scene` is now the main menu; **Single Player** jumps straight to the
match scene with `Mode.SINGLE_PLAYER`.

### Synchronized scene loading

No player is spawned until every peer confirms the map is loaded (spec 3):

1. Host presses Start Match → `NetworkManager.start_match()` → `rpc("_begin_match")`.
2. Every peer `change_scene_to_file(MATCH_SCENE)` (deferred — changing scenes
   inside an RPC callback frees the tree the multiplayer layer is iterating).
3. Each peer's `test_map.gd::_ready()` calls `NetworkManager.notify_map_loaded()`.
4. The server flips that peer's `loaded` flag; once all are true it emits
   `all_peers_loaded`.
5. **Only then** does the server spawn player characters and call
   `begin_spawning()` on the civilian and police spawners.

Step 5 matters: spawning during `_ready()` pushes `MultiplayerSpawner` packets
at peers whose spawner nodes do not exist yet, and those spawns are lost.

### Disconnects

* **Client leaves** → `NetworkManager._on_peer_disconnected()` prunes the peer
  registry and calls `test_map.despawn_player(id)`, which frees that
  character; the spawner mirrors the despawn. Their recruited protesters stay
  in the shared crowd — there are no player-owned squads, so there is nothing
  to clean up.
* **Host leaves** → clients get `server_disconnected` → `return_to_menu()`
  with an error message.
* **No late joining**: a peer that connects while `match_in_progress` is
  disconnected immediately.
* Sessions can be restarted without relaunching: `leave_session()` closes the
  peer and resets state, and game over offers the host "Back to Lobby"
  (`return_to_lobby()`), which rpc's everyone back to the lobby scene.

---

## 3. Player characters

`scenes/player.tscn` instances the vendored `addons/fps_controller/Player.tscn`
and overrides the root script with `scripts/player.gd` (`extends
MovementController`), adding:

* `Body/Character` — a Quaternius character, **visible only on remote peers**
  (hidden for the local player, who is in first person).
* `InputSync` — authority = owning peer. 30 Hz transform snapshot
  (`net_position`, `net_body_yaw`, `net_head_pitch` as *always*/unreliable) +
  `net_anim` and `net_recruiting` (*on change*/reliable).
* `ServerSync` — authority = 1. `net_health` and `net_alive`, both on change.

Two synchronizers, because one synchronizer has exactly one authority and the
movement/health split needs two.

**Authority is derived from the node name**: the server names each character
after its owning peer id, the spawner replicates the name, and
`player.gd::_enter_tree()` does `set_multiplayer_authority(name.to_int())`
(recursive, so Head/Sprint/Megaphone/Croissant/WeaponSwitcher inherit it).
`_ready()` then pins `ServerSync` and `HealthComponent` back to peer 1.

That recursive authority is what makes the input guards in the vendored addon
scripts a one-liner: `if not is_multiplayer_authority(): return` in
`MovementController` (via `player.gd`), `Head`, `Sprint`, `WeaponSwitcher`,
`Megaphone` and `Croissant`.

Remote players are **interpolated, not simulated**: `_interpolate_snapshot()`
exponentially smooths toward the latest snapshot with a snap guard for
teleports. They run no physics at all, so only the owning client's simulation
can disagree with itself.

### Respawn

Server-side, in `test_map.gd::_on_player_died()`:

* Single-player: unchanged — the death is a game-over condition.
* Multiplayer: `server_set_down()` (body hidden, collider disabled), a 5 s
  timer, then `server_respawn()` at the player's original spawn slot with full
  health. The protest is untouched.

`_apply_down_state()` / `_apply_respawn()` are `@rpc("any_peer")` with an
explicit "sender is peer 1" check rather than `@rpc("authority")`. The
character's authority is the *owning client*, so an `authority` RPC sent by
the server would be rejected on arrival. This was a real bug caught by
reading the authority model, and the respawn path is now covered by the
loopback test.

`net_health` mirrors into the local `HealthComponent` from its **property
setter**, not from `_process`. The game-over screen pauses the tree, which
stops node processing while synchronizers keep delivering — polling in
`_process` silently stopped mirroring. Caught by the loopback test.

---

## 4. Shared crowd

**One shared protest crowd.** No personal squads.

* Recruitment: every player's `net_recruiting` flag is replicated, and
  `CrowdController._process_recruitment()` (server-only) iterates *all*
  players and recruits unrecruited civilians inside each one's megaphone
  radius. `recruited` membership is the "a civilian can only be recruited
  once" guard. Remote players recruit exactly like the host.
  * The old `Megaphone.is_point_within_recruit_range()` was removed: it
    measured from `get_viewport().get_camera_3d()`, i.e. *this peer's* camera,
    which is meaningless for a remote player. The radius test now lives
    server-side and uses each player's body position.
* Crowd commands: the megaphone's `send_mob_triggered` signal is routed by
  `player.gd::_on_send_mob_triggered()` — applied directly on the server,
  forwarded by `rpc_id(1, "request_send_mob", ...)` on a client. **Last valid
  command wins**: `apply_send_mob()` just overwrites `_attack_target` and
  reassigns its ring slice. No queues, no ownership, no priority.
* Targets travel as **absolute scene paths**, not object ids (which are
  per-process). Props are part of the statically loaded map scene; NPCs and
  police get deterministic replicated names (`Civilian7`, `Cop3`).
* `GameState.live_crowd_count` is the replicated mirror of
  `CrowdController.recruited.size()`, because the megaphone's
  send-percentage readout needs the live headcount on clients where the
  recruited list is empty by design.

---

## 5. Entity replication and performance

**Server-side NPC simulation with client-side visual interpolation.**

Per NPC and per cop the wire carries:

| Property | Mode | Rate | Transport |
|---|---|---|---|
| `net_position`, `net_yaw` | always | 10 Hz (`replication_interval = 0.1`) | unreliable |
| `net_anim` (idle/walk/run/punch/shoot) | on change | — | reliable |
| `net_health` | on change | — | reliable |
| `variant_index` (outfit) | spawn only | once | reliable |

Nothing replicates the whole state every physics frame. Godot sends *always*
properties unreliably and *on change* deltas reliably, which lines up exactly
with the spec's "unreliable for frequent transforms, reliable for discrete
events".

Clients run no AI: `npc.gd` and `police.gd` short-circuit
`_physics_process()` into `_interpolate_snapshot()` + `_update_visuals()`.
Animation is driven entirely off the replicated `net_anim`, so the clip
selection logic exists in one place and clients never reproduce it.

Measured in the headless loopback test: ~48 civilians and ~8 police
replicated to the client with no errors and no visible drift
(`global_position` within 1 m of `net_position`). Starting point for the
"~50 active NPCs" performance target; interest management and batched
snapshots are deliberately *not* implemented yet.

### Destruction

Props are static map-scene nodes at identical paths on every peer, so they
need no spawner. They replicate themselves with two RPCs:

* `_net_health(value)` — unreliable-ordered, throttled to 10 Hz, drives the
  floating health bar.
* `_net_destroy()` — reliable, `call_local`. Each peer then runs its own
  `_die()`, so vehicle debris and glass shards are simulated locally from one
  replicated trigger instead of streaming every piece.

Scoring moved out of `_die()` into `_trigger_destruction()` (server-only), so
one destroyed prop is one disruption no matter how many players saw it.

### Melee (croissant)

The overlap test runs on the attacker — the `HitArea` only exists
meaningfully where the swing is simulated — and the hit list is sent to the
server, which re-checks that each target is within `SERVER_HIT_RANGE` before
applying damage. "Trusted client melee with a server-side range check":
proportionate for LAN co-op, and documented rather than accidental.

---

## 6. Grabuge, feed and HUD

* Grabuge, `crowd_count` and `live_crowd_count` are server-authoritative.
  Every mutator in `game_state.gd` is a no-op on clients; the server pushes
  the three numbers at 10 Hz over an **unreliable-ordered** RPC (lossy-safe,
  but out-of-order delivery would make the bar jitter backwards).
* Discrete events — disruption recorded, police defeated, game over — go out
  **reliably**, so the protest feed is consistent for everyone. Game over
  also ships the server's end-of-run stats so every player's summary screen
  shows the same numbers.
* The HUD is purely local (own health, own hotbar, own compass). Because
  player characters are spawned at runtime, `hud.gd` lost its `player_path`
  exports in favour of `bind_player()`, called by the match scene once the
  local character exists.
* Ambient Snapchat-style feed messages are still generated locally
  (cosmetic); gameplay-driven ones ride the replicated GameState signals.

---

## 7. Known gaps / accepted compromises

* **Police spawn-out-of-view check is host-only.** `police_spawner.gd` can
  only consult `get_viewport().get_camera_3d()`, i.e. the listen server's own
  camera, so a cop can pop into a remote player's view. Fixing it exactly
  would mean replicating four view frustums to the server purely to pick a
  spawn point.
* **No lag compensation**, no interest management, no batched snapshots. Out
  of scope per spec 9; the hooks (replication intervals, the one
  `_publish_snapshot()` per entity) are where to start if testing demands it.
* **Host migration, dedicated servers, NAT traversal, late joining, PvP** —
  explicitly out of scope.
* **Client-side prediction** is not implemented; the owning client simply *is*
  the authority for its own movement, which is why none is needed.

---

## 8. Verification

### Automated, headless

* `task verify:singleplayer` — boots single-player, dumps the live scene
  tree, and asserts the player spawned at `Players/1` with authority 1, the
  three spawners resolved, and **every `SceneReplicationConfig` parsed
  non-empty**. That last one matters: a hand-written `SceneReplicationConfig`
  in a `.tscn` that Godot fails to parse comes out empty and replicates
  nothing *with no error*, so it is asserted explicitly rather than inferred
  from a clean log. Finally it exercises the single-player game-over restart
  (`GameState.reset()` + `reload_current_scene()`) and re-checks the spawn
  handshake, since the player is now spawned by a script rather than baked
  into the scene.
* `task test:lan` — two real Godot processes over `127.0.0.1:7000`
  (`tools/lan_loopback_test.sh`, driving `scripts/_debug_net_host.gd` and
  `scripts/_debug_net_client.gd`). Covers peer connection, the
  synchronized-load handshake, both characters spawning with the correct
  authority split, remote-player interpolation, civilian/police spawn
  replication, a **client** recruiting ~27 civilians into the shared crowd
  and issuing a Send Mob command that lands server-side (14 protesters
  entered CHARGE), replicated Grabuge/crowd counters, server-side death →
  5 s → respawn seen as replicated state by the owner, and
  client-disconnect despawn with recruited protesters preserved.

  Two lessons about *writing* that test: the harness has to keep Grabuge
  topped up (otherwise the shared meter collapses within seconds of one
  recruit, fires game over, pauses the tree, and the rest of the run
  measures a paused game), and it has to cap concurrent police (a
  Grabuge-pinned spawn rate wipes a small test crowd, making every later
  assertion hostage to combat outcomes). Assertions are written against
  invariants — "the local HealthComponent tracks the replicated value", "the
  crowd was not wiped" — not against exact survival numbers.

### Still needs a human with windows

* Two to four windowed instances actually seeing and shooting at each other.
* Input feel: mouse look, megaphone cone, hold-to-charge Send Mob percentage.
* Remote player animation quality and interpolation smoothness by eye.
* Real two-Mac LAN (as opposed to loopback), including the firewall prompt.
* The exported `.app` hosting and joining.

---

## 9. macOS export

`task export:macos` → `dist/ProtestSimulator-macOS.zip` (Universal 2,
release, ad-hoc signed, notarization off, networking entitlements on). The
preset lives in `export_presets.cfg` as `[preset.0] name="macOS"`.

Three non-obvious things were needed to make this work:

1. **`config/name.macos="ProtestSimulator"` in `project.godot`.** The macOS
   exporter names the bundle, its executable and its `.pck` after
   `application/config/name`, and there is no per-preset override — but
   `get_project_setting()` resolves platform feature tags, so a `.macos`
   override renames the artifact. Required to produce `ProtestSimulator.app`
   rather than `les tenebres.app`. Side effect: the window title reads
   "ProtestSimulator" on macOS, including from the editor.
2. **`textures/vram_compression/import_etc2_astc=true`.** Godot refuses to
   export for `universal`/`arm64` otherwise: *"Cannot export for universal or
   arm64 if ETC2 ASTC texture format is disabled."* Costs a full texture
   reimport and a larger `.godot` cache.
3. **`export/distribution_type=0` (Testing), not Distribution.**
   Distribution expects a Developer ID; Testing is the mode that permits the
   built-in ad-hoc signature (`codesign/codesign=1`,
   `codesign/identity="-"`) with notarization disabled.

**Not verified end to end**: this sandbox has no export templates installed
(`~/Library/Application Support/Godot/export_templates/4.7.2.stable/` does
not exist), so the exporter cannot run. The preset itself *is* validated —
after fixing (2), a direct `--export-release` invocation reports the missing
template as its only remaining configuration error, which means every other
preset option passed Godot's validation. The Taskfile's template check and
archive verification have both been exercised (the check fails loudly with
the exact expected path).

Unrelated pre-existing issue surfaced by the export pass: the megaphone
textures are referenced as `assets/megaphone/textures/...` but stored as
`assets/megaphone/Textures/...`. Harmless on case-insensitive macOS, but
Godot warns it "will not open when exported to other case-sensitive
platforms".

---

## 10. Gotchas worth remembering

1. `Node.multiplayer` is **null** very early in startup (before the SceneTree
   builds its MultiplayerAPI). A `--script` harness that hosts from
   `_initialize()` silently fails to assign the peer, and the symptom is a
   client stuck in `CONNECTION_CONNECTING` forever. Host from the first
   `_process` frame instead.
2. Autoload globals (`GameState`, `NetworkManager`) are **not** compile-time
   identifiers inside a `--script` SceneTree. Fetch them with
   `get_root().get_node("GameState")`.
3. `@rpc("authority")` is validated on *receive* against the node's
   authority. For a node owned by a client, the server must use
   `@rpc("any_peer")` plus a sender check.
4. Set node name, position and spawn-state properties **before**
   `add_child()` — that is when `MultiplayerSpawner` serializes spawn state.
   Setting them afterwards leaves every replicated entity at the origin.
5. A paused tree stops node processing but synchronizers keep delivering. Do
   not poll replicated state in `_process` if it has to work during pause;
   use a property setter.
