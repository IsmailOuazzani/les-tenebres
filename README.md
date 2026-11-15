# les tenebres — Protest Simulator

A chaotic, funny, first-person protest simulator set in Paris. Recruit
civilians with a megaphone, point them at something, shout *"À L'ATTAQUE!"*,
and survive escalating waves of police. Grabuge is the currency you spend on
upgrades between waves. See [`vision.md`](vision.md) for the game concept and
design pillars.

Now with **LAN co-op for 1-4 players**.

---

## Requirements

| | |
|---|---|
| Engine | **Godot 4.7** (developed against 4.7.2 stable) |
| Platform | Develop on macOS (Apple Silicon or Intel). Release builds are available for macOS and Windows x86_64. |
| Task runner | [`go-task`](https://taskfile.dev) (`brew install go-task`) |

The Godot binary is expected at `/Applications/Godot.app/Contents/MacOS/Godot`.
Override it anywhere with `GODOT_BIN`:

```sh
GODOT_BIN=/path/to/godot task run
```

### Export templates (only needed to build a release)

Release builds need the **export templates for the exact Godot version
you are running**. Install them once:

* In the editor: **Editor → Manage Export Templates → Download and Install**, or
* manually: download `Godot_v4.7.2-stable_export_templates.tpz` from the
  Godot downloads page and unpack its contents into
  `~/Library/Application Support/Godot/export_templates/4.7.2.stable/`
  (the folder must contain `macos.zip`).

`task export:macos` checks for this and fails with the exact expected path if
it is missing.

---

## Running the game

| Command | What it does |
|---|---|
| `task run` | Launch the game (no editor). Output → `logs/run.log` |
| `task run-headless` | Launch with no window or rendering. Output → `logs/run-headless.log` |
| `task editor` | Open the project in the Godot editor |
| `task verify:singleplayer` | Headless smoke test: match bootstrap, player spawn, replication wiring |
| `task test:lan` | Two headless Godot processes replicating over `127.0.0.1:7000` |
| `task export:macos` | Build a macOS `.app` into `dist/` |
| `task export:macos:zip` | Build a distributable macOS release ZIP into `dist/` |
| `task export:windows` | Build a distributable Windows x86_64 release ZIP into `dist/` |

The game boots to a main menu with three options: **Single Player**,
**Host LAN** and **Join LAN**.

---

## Hosting and joining a LAN session

Multiplayer is a **listen server**: one player hosts and plays in the same
process. Up to **4 players** total. Everyone must be on the same local
network (there is no matchmaking, no NAT traversal and no internet play).

### Host

1. Launch the game and click **HOST LAN**.
2. The lobby shows the address other players need, e.g.
   `Players join at  192.168.1.42 : 7000`.
3. Wait for players to appear in the list, then click **START MATCH**.
   Only the host can start the match, and there is **no late joining** — once
   the match starts, the lobby is closed.
4. After a game over, the host gets **BACK TO LOBBY**, which returns everyone
   to the lobby so another round can be started without relaunching.

### Join

1. Launch the game, type the host's IPv4 address into the **Host IPv4
   address** field, and click **JOIN LAN**.
2. Use `127.0.0.1` to join a host running on the same machine (handy for
   testing with two instances).
3. You land in the lobby and wait for the host to start.

### Networking details

* **UDP port 7000** (Godot's `ENetMultiplayerPeer`). If a firewall is in the
  way, allow incoming UDP 7000 on the **host** machine only.
* macOS will prompt *"Do you want the application to accept incoming network
  connections?"* the first time you host. Click **Allow** — hosting does not
  work if you deny it.
* Only the host needs to be reachable; joining players make an outbound
  connection.
* If the host quits, everyone else is returned to the main menu with a
  message. Host migration is not supported.
* A player who disconnects has their character removed, but the protesters
  they recruited stay in the shared crowd.

### What's shared and what isn't

| Shared across all players | Per player |
|---|---|
| One protest crowd (anyone can recruit into it) | Movement, camera, megaphone |
| Crowd commands — last valid command wins | Health (independent pools) |
| One Grabuge wallet | HUD, compass, protest feed presentation |
| Police, destruction, gameplay events | |
| The wave/Act loop and the upgrade shop | |

Dead players respawn after **5 seconds**; a death does not reset the protest.

---

## Building a macOS release

```sh
task export:macos        # -> dist/ProtestSimulator.app   (just run it)
task export:macos:zip    # -> dist/ProtestSimulator-macOS.zip (to hand to someone)
```

Both run the same release export; they differ only in the output format,
which the exporter picks from the extension it is given. Use the first one
locally — there is nothing to unarchive, just `open dist/ProtestSimulator.app`.
Either way you get a complete, self-contained `ProtestSimulator.app`:

* **Universal 2** binary (Apple Silicon + Intel).
* Release export, all game resources bundled inside the `.app`.
* **Ad-hoc code signed** (no Apple Developer account needed).
* Notarization **disabled**.
* Networking entitlements enabled, so hosting and joining work.
* Players do **not** need Godot installed.

Both tasks resolve the Godot binary (honouring `GODOT_BIN`), validate the
export templates, create `dist/`, run the headless release exporter, and then
verify the result — failing loudly at whichever step breaks. The `.app` build
goes furthest: as well as checking the executable, `Info.plist` and `.pck` are
present, it runs `codesign --verify` (a bundle whose signature does not cover
its contents refuses to launch on Apple Silicon, which no file listing would
reveal) and boots the real binary headlessly, which catches a mismatched
`.pck`, a missing main scene, or a script parse error.

`dist/` is gitignored.

### Distribution

Use `task export:macos:zip` and send `dist/ProtestSimulator-macOS.zip` to the
other players however you like (AirDrop, file share, USB) — a `.app` is a
directory, so it needs wrapping to survive most transfers intact. Each player
unzips it and drags
`ProtestSimulator.app` wherever they want — typically `/Applications` or the
Desktop.

### Running the exported application

The build is **ad-hoc signed and not notarized**, so macOS Gatekeeper will
refuse to open it on the first try. This is expected for a build that has not
gone through an Apple Developer account, and it only has to be worked around
once per machine.

Pick whichever is easiest:

* **Right-click → Open**, then confirm **Open** in the dialog. (A plain
  double-click gives *"cannot be opened because the developer cannot be
  verified"* with no Open button.)
* **System Settings → Privacy & Security**, scroll to the bottom, and click
  **Open Anyway** next to the blocked app, then launch it again.
* From a terminal, strip the quarantine attribute:

  ```sh
  xattr -dr com.apple.quarantine /Applications/ProtestSimulator.app
  ```

On recent macOS versions, files downloaded through a browser get a stricter
quarantine flag than files received via AirDrop or a USB stick — the
`xattr` command above clears it either way.

To ship a build that opens with a plain double-click you would need a paid
Apple Developer account for a Developer ID signature plus notarization; both
are deliberately out of scope here.

---

## Building a Windows release

With the Windows x86_64 export templates installed, run this from the project
root on your Mac:

```sh
task export:windows
```

Send `dist/ProtestSimulator-Windows.zip` to the other players. Have them extract
the whole ZIP and run `ProtestSimulator-Windows.exe` from the extracted folder.

---

## Project conventions

See [`CLAUDE.md`](CLAUDE.md). In short: design notes live in
[`agents/`](agents/), `vision.md` stays short and high-level, and existing
addons are preferred over homegrown systems.

Multiplayer architecture, network ownership tables, replication rates and the
list of known gaps are documented in
[`agents/multiplayer-notes.md`](agents/multiplayer-notes.md).
