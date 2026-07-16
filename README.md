# CameraSystem

A small, config-driven camera controller for Roblox. Designed to be dropped into any project as a Git submodule — add it once, define your own states and actions in a config table.

The camera is driven by two blended layers:

- **State layer** — the source of truth. The active state defines where the camera belongs (an offset from the subject), a procedural hover bob, and how quickly the camera converges there. The camera always settles here when nothing else is happening.
- **Action layer** — one-shot overlays. An action plays a keyframed camera movement at full override weight, then smoothly blends back into the live state camera — the return target is wherever the state camera is *by then*, so it stays correct even if the subject moved.

The controller never binds its own loop — you drive `Update(deltaTime)` from RenderStep, so it contains no behaviour it doesn't own.

---

## Structure

```
CameraSystem/
└── Shared/
    └── CameraSystem/       → place into ReplicatedStorage
        ├── init.luau       → the controller implementation
        ├── Types.luau      → CameraConfig / CameraController type exports
        └── Config.luau     → shipped config template (Walking / Running states)
```

**Shared** owns the whole system — the controller is pure logic against a `Camera` and a `BasePart` subject, so it lives in ReplicatedStorage. Only clients should construct it, since only the local client owns its camera.

---

## Adding to a Project

### 1 — Add as a submodule

```bash
git submodule add https://github.com/zKozie/CameraSystem.git modules/CameraSystem
```

### 2 — Point Rojo at it

In your game's `default.project.json`:

```json
"ReplicatedStorage": {
  "$path": "modules/CameraSystem/Shared"
}
```

Rojo places `Shared/CameraSystem` into `ReplicatedStorage` automatically, so the module resolves at `ReplicatedStorage.CameraSystem`.

---

## Usage

```lua
local RunService = game:GetService("RunService")

local CameraSystem = require(game.ReplicatedStorage.CameraSystem)
local CameraConfig = require(game.ReplicatedStorage.CameraSystem.Config)

local controller = CameraSystem.new(workspace.CurrentCamera, CameraConfig)
controller:SetSubject(character:WaitForChild("HumanoidRootPart"))

RunService:BindToRenderStep("CameraSystem", Enum.RenderPriority.Camera.Value, function(deltaTime)
    controller:Update(deltaTime)
end)

controller:SetState("Running")   -- the state layer is now the Running truth
controller:PlayAction("Impact")  -- one-shot; blends back to Running when done
```

- `CameraSystem.new(camera, config)` — builds the controller, sets the camera `Scriptable`, and enters `config.InitialState`.
- `controller:SetSubject(part)` — the part the camera follows; `Update` is a no-op while `nil` (pass `nil` between respawns).
- `controller:SetState(name)` — switches the state-layer truth; the camera converges there at the new state's `Smoothing` rate.
- `controller:SetOffset(offset)` — runtime offset composed after every state/action offset (shoulder cam, aiming). Persists across state changes and actions; `nil` clears it.
- `controller:PlayAction(name)` — starts a one-shot action, replacing any action already playing.
- `controller:Update(deltaTime)` — advances both layers and writes the camera CFrame; call every RenderStep.
- `controller:Destroy()` — restores the previous `CameraType` and clears live references.

The system decides nothing about *when* to change states — that logic belongs to the caller (input, humanoid speed, your own state machine).

---

## Config Shape

```lua
return {
    InitialState = "Walking",
    DefaultReturnTime = 0.4, -- action blend-back seconds when ReturnTime is nil

    States = {
        Walking = {
            Offset = CFrame.new(0, 2, 10), -- relative to the subject's CFrame
            HoverAmplitude = 0.15,         -- bob height in studs; 0 disables
            HoverFrequency = 0.8,          -- bob cycles per second
            Smoothing = 8,                 -- follow rate; higher converges faster
        },
    },

    Actions = {
        Impact = {
            Keyframes = {
                -- travels from the state offset to each keyframe in order
                { Offset = CFrame.new(0, 1.5, 6), Duration = 0.12 },
                { Offset = CFrame.new(0, 1.5, 7), Duration = 0.25, EasingStyle = Enum.EasingStyle.Sine },
            },
            ReturnTime = 0.5, -- blend back to the state camera over this long
        },
    },
}
```

---

## Full Control

The controller owns the camera completely while alive:

- `CameraType = Scriptable` is set at construction and **re-asserted every `Update`** — Roblox core scripts reset it on respawn and seating, and the controller wins that fight.
- With `Scriptable` held, player scroll-zoom and orbit input have no effect. For belt-and-suspenders zoom locking, also equalize the zoom range on the client:

```lua
local localPlayer = game:GetService("Players").LocalPlayer
localPlayer.CameraMaxZoomDistance = localPlayer.CameraMinZoomDistance
```

- `Destroy` restores the `CameraType` captured at construction, handing the camera back to Roblox.

---

## Rules

- Offsets are relative to the subject: `+Z` sits behind a subject facing `-Z` (HumanoidRootPart convention).
- An action's first keyframe travels from the **active state's offset**, so actions read naturally from any state.
- `EasingStyle` / `EasingDirection` default to `Quad` / `Out` per keyframe.
- One controller per camera lifetime — call `Destroy` before constructing another.
