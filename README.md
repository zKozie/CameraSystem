# CameraSystem

A small, config-driven camera controller for Roblox. Designed to be dropped into any project as a Git submodule — add it once, define your own states and actions in a config table.

The camera is a mouse-look rig (shift-lock style) with two blended layers on top:

- **Look rig** — subject position + yaw/pitch angles steered by `AddLookDelta`. The subject's own rotation plays no part; instead your character-facing logic reads `GetLookDirection()` and turns the character to follow the camera.
- **State layer** — the source of truth. The active state defines where the camera belongs (an offset from the look rig), a procedural hover bob, and how quickly the camera converges there. The camera always settles here when nothing else is happening.
- **Action layer** — one-shot overlays. An action plays a keyframed camera movement at full override weight, then smoothly blends back into the live state camera — the return target is wherever the state camera is *by then*, so it stays correct even if the subject moved.

The controller never binds its own loop — you drive `Update(deltaTime)` from RenderStep, so it contains no behaviour it doesn't own.

---

## Structure

```
CameraSystem/
└── Shared/
    └── CameraSystem/       → place into ReplicatedStorage
        ├── init.luau       → the controller implementation
        ├── ActionLayer.luau→ keyframe playback math for one-shot actions
        ├── Types.luau      → CameraConfig / CameraController type exports
        └── Config.luau     → shipped config template (Idle / Walking / Running states)
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
    UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter -- core scripts reset this
    controller:Update(deltaTime)
end)

-- Mouse steers the look rig
local MOUSE_SENSITIVITY = 0.003
UserInputService.InputChanged:Connect(function(changedInput)
    if changedInput.UserInputType ~= Enum.UserInputType.MouseMovement then return end
    controller:AddLookDelta(-changedInput.Delta.X * MOUSE_SENSITIVITY, -changedInput.Delta.Y * MOUSE_SENSITIVITY)
end)

controller:SetState("Running")   -- the state layer is now the Running truth
controller:PlayAction("Impact")  -- one-shot; blends back to Running when done
```

- `CameraSystem.new(camera, config)` — builds the controller, sets the camera `Scriptable`, and enters `config.InitialState`.
- `controller:SetSubject(part)` — the part the camera follows; seeds the look yaw from the part's facing so the camera starts behind it. `Update` is a no-op while `nil` (pass `nil` between respawns).
- `controller:AddLookDelta(yawDelta, pitchDelta)` — steers the look rig, radians; pitch clamps to `config.PitchLimits`. Feed it mouse deltas (negate both axes, scale by sensitivity).
- `controller:GetLookDirection()` — unit vector the rig faces along; drive character rotation from this.
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
    PitchLimits = { Min = math.rad(-80), Max = math.rad(80) }, -- mouse-look clamp

    States = {
        Walking = {
            Offset = CFrame.new(3, 2, 10), -- relative to the look rig; +X = right shoulder
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

- The mouse cursor is hidden (`MouseIconEnabled = false`) for the controller's lifetime — re-asserted every `Update`, since core scripts re-enable it.
- **Wall occlusion**: every `Update` raycasts from the subject to the goal position and pulls the camera in front of anything hit, so walls never sit between the camera and the character. The ray excludes the subject's own model and ignores `CanCollide = false` decoration.
- `Destroy` restores the `CameraType` and cursor visibility captured at construction, handing the camera back to Roblox.
- Disable Roblox's own shift-lock switch so it can't fight the rig — it's a Studio/Rojo property, out of a LocalScript's reach: set `StarterPlayer.EnableMouseLockOption = false` (in Rojo: `"StarterPlayer": { "$properties": { "EnableMouseLockOption": false } }`).

---

## Rules

- Offsets are relative to the **look rig**: `+Z` sits behind the look direction, `+X` to its right (shoulder cam). The subject's own rotation never affects the camera.
- An action's first keyframe travels from the **active state's offset**, so actions read naturally from any state.
- `EasingStyle` / `EasingDirection` default to `Quad` / `Out` per keyframe.
- One controller per camera lifetime — call `Destroy` before constructing another.
