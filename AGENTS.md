# Immersive Ephemeral Jeopardy — Agent & Developer Guide

This Godot **4.6.2 (GL Compatibility)** project is a reusable **5-Projector Single-Touch Immersive Room Template** featuring a complete **Ephemeral Jeopardy** environment.

---

## 1. Physical Projector Rig Invariants (`Player.tscn` & `player.gd`)

**DO NOT MODIFY** the camera positions, rotations, FOV, `keep_aspect`, or `SubViewportContainer` ordering in `Player.tscn` unless recalibrating physical projectors.

- **Room Origin**: `Player` at `(0, 0, 0)`, all 5 `Camera3D` nodes fixed at **`(0, 1.5, 0)`**.
- **Projection Mode**: `keep_aspect = KEEP_WIDTH (0)`, **`fov = 90.0`** horizontal on every camera.
- **Viewport Strip Order** (left-to-right in `HBoxContainer`, 5 equal horizontal slices):
  1. `ViewportLeft` (`index 0`) -> `CameraLeft` looking **`-X`** (Left Wall)
  2. `ViewportCenter` (`index 1`) -> `CameraCenter` looking **`-Z`** (Center Wall)
  3. `ViewportRight` (`index 2`) -> `CameraRight` looking **`+X`** (Right Wall)
  4. `ViewportBack` (`index 3`) -> `CameraBack` looking **`+Z`** (Back Wall)
  5. `ViewportFloor` (`index 4`) -> `CameraFloor` looking **`-Y`** (Floor, screen top faces `-Z` Center Wall)
- **Camera Motion Rule**: **NEVER** shake, tilt, or move the 5 cameras during gameplay. All transitions and feedback animate world objects, shaders, lighting, and particles instead.

### Safe Frustum Coordinates (Guaranteed Unclipped on 16:9, 16:10, 4:3, and 1:1 Projectors)
- **4 Walls at distance `D = 4.0m`** (`Center (0, 1.5, -4)`, `Left (-4, 1.5, 0)`, `Right (4, 1.5, 0)`, `Back (0, 1.5, 4)`):
  - Local `+Z` faces viewer `(0, 1.5, 0)`; local `+X` is viewer's right; local `+Y` is up.
  - Keep all interactive elements inside local **`x ∈ [-3.35, +3.35]`**, **`y ∈ [-1.35, +1.50]`** (world `y ∈ [0.15, 3.00]`, strictly above the `y = 0` floor plane).
- **Floor at `y = 0.0`** (`1.5m` below `CameraFloor`):
  - Keep primary interactive floor pads inside **`x ∈ [-1.25, +1.25]`**, **`z ∈ [-0.70, +0.70]`**.

### Desktop Developer Hotkeys (Non-Intrusive, Off by Default)
- `F1` — Toggle projector wall calibration labels (`Left`, `Center`, `Right`, `Back`, `Floor`)
- `F2` — Toggle FPS & viewport diagnostics HUD
- `F3` — Cycle single-wall desktop preview (`All 5 -> Left -> Center -> Right -> Back -> Floor`)
- `0` — Snap back to full 5-wall projector mode

---

## 2. Single-Touch Architecture (`interaction_bus.gd`, `mouse.gd`, `scripts/core/`)

- `project.godot` keeps `pointing/emulate_touch_from_mouse=true` and `emulate_mouse_from_touch=false` so mouse clicks simulate single-touch wall taps on desktop.
- `mouse.gd` (`MultitouchMouse`) enforces `single_touch_only = true` by default with tap debounce (`tap_cooldown_sec = 0.14`), exact `SubViewportContainer` bounds hit-testing, clean `ray_exit` on release, and ethereal screen ripples.
- All 3D interactive elements inherit from `ImmersiveInteractable3D` (`StaticBody3D`), which automatically sets `collision_layer = 0` whenever hidden in the scene tree so inactive walls/screens never capture stray raycasts.
- `GlassButton3D` (`scripts/core/glass_button_3d.gd`) provides reusable luminous frosted-glass monolith buttons using `shaders/glass_tile.gdshader`.

---

## 3. Adding Custom Jeopardy Question Packs (`data/packs/*.json`)

Drop any `.json` file matching the schema below into `res://data/packs/` — `JeopardyPack.discover_pack_paths()` automatically detects and loads it into the pack switcher!

```json
{
  "id": "my_pack",
  "title": "My Custom Pack",
  "subtitle": "Short description",
  "accent_color": "#5ce1e6",
  "timer_seconds": 25,
  "categories": [
    {
      "name": "CATEGORY NAME",
      "short_name": "CATEGORY\nNAME",
      "clues": [
        {
          "value": 200,
          "clue": "Clue text (recommended <= 130 chars)",
          "choices": ["A", "B", "C", "D"],
          "correct_index": 0,
          "answer": "What is A?",
          "fact": "Optional short follow-up echo."
        }
      ]
    }
  ],
  "final_jeopardy": {
    "category": "FINAL CATEGORY",
    "clue": "Final clue text",
    "choices": ["A", "B", "C", "D"],
    "correct_index": 1,
    "answer": "What is B?",
    "fact": "Optional echo."
  }
}
```

---

## 4. Installed CLI Dev Tools & Verification Workflow

Installed on PATH (`%USERPROFILE%\.local\bin\`):
- `godot` (Godot 4.6.2-stable console runner) & `godot-gui`
- `gdlint`, `gdformat`, `gdparse`, `gdradon` (via `gdtoolkit`)
- `python` + `Pillow` (audio synthesis & texture/screenshot tooling)

Use `tools/godot_dev.ps1` for one-command workflows:
```powershell
.\tools\godot_dev.ps1 check       # Headless Godot import + gdlint + automated tests
.\tools\godot_dev.ps1 test        # Headless unit & 3D scene integration test suite
.\tools\godot_dev.ps1 preview     # Renders 5-wall strips & HD individual wall PNGs to tools/screenshots/
.\tools\godot_dev.ps1 export-web  # Exports index.html (all 5), walls.html (4 walls), and floor.html (synced floor)
.\tools\godot_dev.ps1 serve       # Serves exports/web/ + WebSocket room sync on http://127.0.0.1:8080
.\tools\godot_dev.ps1 deploy-pages # check + export-web, then publish exports/web/ as a 1-commit gh-pages branch
.\tools\godot_dev.ps1 lint        # Run gdlint across all project .gd files
.\tools\godot_dev.ps1 format      # Auto-format GDScript via gdformat
.\tools\godot_dev.ps1 run         # Launch Ephemeral Jeopardy
.\tools\godot_dev.ps1 editor      # Open project in Godot 4.6.2 Editor
```

### Per-Surface Browser Projection Setup (5 Individual URLs)
Each projector surface has its own synced HTML entrypoint sharing one `index.wasm` & `index.pck`:
- **Center Wall (Authoritative Host + Audio):** `https://dem1323.github.io/immersive-template-3d/center.html`
- **Left Wall (Team Podiums & Controls):** `https://dem1323.github.io/immersive-template-3d/left.html`
- **Right Wall (Echoes Chronicle / Timer / Wager):** `https://dem1323.github.io/immersive-template-3d/right.html`
- **Back Wall (Spectator Mirror & Controls):** `https://dem1323.github.io/immersive-template-3d/back.html`
- **Floor (Mandala & Team Touch Pads):** `https://dem1323.github.io/immersive-template-3d/floor.html`
- *(Legacy combined URLs still exported: `walls.html` for 4 walls, `index.html` for all 5.)*

When running locally via `.\tools\godot_dev.ps1 serve` (or `tools/start_room_server.bat`), the exact same 5 URLs work at `http://127.0.0.1:8080/{left,center,right,back,floor}.html` with automatic hybrid `BroadcastChannel` + `/ws` WebSocket sync (works even across isolated browser profiles/sandboxes).

### Editing Visually in the Godot Editor
All 6 modular environment & wall scenes (`SanctuaryEnvironment.tscn`, `CenterWallStage.tscn`, `LeftWallStage.tscn`, `RightWallStage.tscn`, `BackWallStage.tscn`, `FloorStage.tscn`) are baked as real editable scenes instanced (with editable children) inside `scenes/jeopardy/EphemeralJeopardyWorld.tscn`.
- `GlassButton3D` and `JeopardyTile3D` are `@tool` nodes: tweak `panel_size`, `primary_text`, `secondary_text`, `base_color`, `rim_color`, `accent_color`, or transform directly in the Godot Editor with live 3D updates.
- Select `EphemeralJeopardyWorld` (or `CenterWallStage` / `RightWallStage`) and use the **`Editor Preview Screen`** Inspector dropdown to switch between `Board (5x5)`, `Setup Lobby`, `Daily Double Wager`, `Active Clue (Quiz)`, `Active Clue (Host)`, `Clue Result`, and `Finale` live in the Editor.
- Runtime scripts bind to existing saved scene nodes without overwriting manual position/size/color edits.

### GitHub Pages Deployment (No Local Server Needed)
Repo: **https://github.com/DEM1323/immersive-template-3d** (source on `main`; build output only on `gh-pages`).

```powershell
.\tools\godot_dev.ps1 deploy-pages
```
Runs `check` + `export-web` (aborts if either fails), stages only `exports/web/*` (incl. `.nojekyll`) into a temp dir, creates a fresh orphan single-commit `gh-pages` branch, and force-pushes it to `origin`. `main` never tracks `index.wasm`/`index.pck`, and `gh-pages` stays 1 commit deep so repo size never grows across redeploys.

WebSocket relay resolution (`RoomRole.resolve_ws_url()`):
- On public static hosts (e.g. `*.github.io`) no `/ws` connection is attempted; all 5 surfaces sync over `BroadcastChannel`, which requires **windows in the same browser profile**.
- Same-origin `ws(s)://<host>/ws` is auto-used only on local/LAN hosts (`localhost`, `127.0.0.1`, `[::1]`, `*.local`, `10.*`, `192.168.*`, `172.16-31.*`).
- `?ws=wss://your-relay.example/ws` forces an external relay (for isolated browser profiles / separate devices); `?ws=none` (or `off`/`false`) disables WebSocket entirely. Combine with `?room=<id>` to separate rooms.

---

## 5. GL Compatibility Rules

This project targets **`gl_compatibility`** (Desktop OpenGL & WebGL2 exports):
- Keep custom shaders clean OpenGL ES 3 / WebGL2 compatible (no Forward+-only SDFGI/VolumetricFog/VoxelGI or `hint_screen_texture` feedback loops).
- Prefer `unshaded` spatial shaders with procedural Fresnel/glow for glass panels and `CPUParticles3D` for cross-platform reliability.
- Regenerate procedural `.wav` assets anytime via `python tools/generate_audio.py`.
