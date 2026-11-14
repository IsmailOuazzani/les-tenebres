# Snapchat-Style Live Protest Feed

A chaotic, Snapchat-themed group-chat feed on the left side of the HUD,
simulating French protesters coordinating during the riot. Pure flavor/UI —
reads GameState to react to real events, but has zero gameplay effect.

## Addon-first check (per CLAUDE.md)

Searched conceptually for an existing "toast/notification list" Godot addon
before hand-rolling this. Didn't find (and didn't expect to find) anything
that would help here: the actual complexity of this feature is the content
(French-slang message pools, event-reactive copy, Snapchat-specific
styling) and the event wiring into `GameState`/`police.gd`, not the list
widget itself. The widget part is a `VBoxContainer` of styled
`PanelContainer` rows with insert-at-top + `Tween` fade/slide, which is the
same scale of custom work this HUD already does by hand for the hotbar
(`scripts/hud.gd`'s `_build_hotbar`) and compass markers
(`scripts/compass_markers.gd`) — both deliberately not addons, for the same
reason. Pulling in a generic toast-notification plugin would still need a
full custom rewrite of its item template for the Snapchat look, so it
wouldn't actually reduce the bespoke part.

## Architecture

- `scripts/snap_feed_data.gd` (`class_name SnapFeedData`, no instance state)
  — all copy as static `const` pools: usernames, avatar emoji/colors,
  chatter lines, nonsense lines, and per-event message templates. No AI
  generation at runtime, per the spec — just randomized combination of
  canned pools, matching this project's existing "no server, no
  generation" HUD patterns.
- `scripts/snap_feed.gd` (`class_name SnapFeed`, extends `Control`) — all
  mechanics: the 2–5s ambient ticker, the three message-type rolls
  (20% gameplay flavor / 30% chatter / 50% nonsense), real-event listeners,
  and building/animating/trimming the message list. Visual styling
  (StyleBoxFlat panels, Snapchat yellow `#FFFC00`, avatar circles) is built
  entirely in code, same pattern as `hud.gd`'s hotbar slots, rather than in
  the `.tscn` — only the static header (ghost emoji + title) and the
  `MessageList` `VBoxContainer` anchor point live in `scenes/snap_feed.tscn`.
- `scenes/snap_feed.tscn` — minimal: `Panel > VBox > (Header, MessageList)`.
  Instanced once into `scenes/hud.tscn` under a new `SnapFeedMargin`
  (top-left, 300×264) — a sibling of the existing right-side `Margin`
  (crowd/Grabuge/health) and bottom `HotbarMargin`, same
  `MarginContainer`-around-content pattern.

## Real-event wiring

Three actual gameplay signals inject a message immediately (and then kick
off a staggered 2–4 message reaction burst of chatter/nonsense, to read as
"a crowd reacting" rather than one isolated line):

- `GameState.crowd_count_changed` — only on an *increase* (feed tracks the
  previous value itself; `reset()` also emits this signal on restart, which
  is a decrease back to 1, so it's correctly ignored). → recruit message.
- `GameState.disruption_recorded` — object/prop destroyed
  (`destructible_prop.gd`'s `_die()`). → destruction message, using
  `GameState.DISRUPTION_GRABUGE_BASE` as the "+N GRABUGE" shown (the real
  per-destruction magnitude multiplier isn't threaded through the signal,
  so this is the base amount, not necessarily the exact value for that one
  kill — close enough for flavor text).
- `GameState.police_defeated` — **new signal**, added to
  `scripts/game_state.gd` alongside a `record_police_defeat()` entry point,
  called from `scripts/police.gd`'s `_on_died()` (mirrors the existing
  `destroyed` signal pattern already on both `Police` and
  `DestructibleProp`). This is the only change outside the feed itself —
  there was no existing global signal for "a cop died," only the per-instance
  `destroyed` signal `CrowdController` already consumes for its own
  one-shot cleanup, which isn't reachable generically from a HUD node
  without hooking every spawned `Police` instance individually.

Deliberately **not** wired to `GameState.grabuge_changed` directly — that
signal fires every physics frame from passive decay (see
`agents/grabuge-notes.md`), so listening to it directly would spam a
message every frame. The three signals above already fire only on the
actual discrete events that raise Grabuge.

## Verification

`task run-headless` after wiring: project loads and runs with no
parse/script errors. **Not verified by eye** — no display in this
environment. Someone should run `task run`, let the ambient ticker fire a
few times, recruit a protester, destroy a prop, and kill a cop, and confirm:
the feed looks unmistakably Snapchat (yellow accents, ghost logo, avatar
circles), new messages slide in at the top and push/dim older ones
downward, the list caps at 6 visible rows, and a real event's reaction
burst reads as multiple people piling on rather than a delayed duplicate.
