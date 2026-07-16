--!strict

--// SERVICES
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

--// TYPES
local Types = require(script.Types)
type CameraConfig = Types.CameraConfig
type CameraController = Types.CameraController
type CameraActionEntry = Types.CameraActionEntry
type ActiveAction = Types.ActiveAction

--// MAIN
local CameraSystem = {}
CameraSystem.__index = CameraSystem

-- Sums an action's keyframe durations; cached once when the action starts
function CameraSystem._resolveKeyframeLength(action: CameraActionEntry): number
	local keyframeLength = 0
	for _, keyframe in action.Keyframes do
		keyframeLength += keyframe.Duration
	end
	return keyframeLength
end

-- Builds a controller for one camera: takes it Scriptable and enters InitialState
function CameraSystem.new(camera: Camera, config: CameraConfig): CameraController
	assert(config.States[config.InitialState], "InitialState not found in States: " .. config.InitialState)

	local self = setmetatable({}, CameraSystem) :: CameraController
	self.Camera = camera
	self.StateName = config.InitialState
	self.Subject = nil
	self._config = config
	self._clock = 0
	self._activeAction = nil
	self._extraOffset = CFrame.identity
	self._lookYaw = 0
	self._lookPitch = 0
	self._previousCameraType = camera.CameraType
	self._previousMouseIconEnabled = UserInputService.MouseIconEnabled

	camera.CameraType = Enum.CameraType.Scriptable
	-- Full control includes the cursor: hidden for the controller's lifetime
	UserInputService.MouseIconEnabled = false
	return self
end

-- Points the camera at a new subject and seeds the look yaw from its facing,
-- so the camera starts behind it; nil freezes the camera until one is set
function CameraSystem.SetSubject(self: CameraController, subject: BasePart?)
	self.Subject = subject
	if not subject then return end

	local subjectFacing = subject.CFrame.LookVector
	self._lookYaw = math.atan2(-subjectFacing.X, -subjectFacing.Z)
	self._lookPitch = 0
end

-- Steers the look rig by radians; pitch is clamped to config.PitchLimits
function CameraSystem.AddLookDelta(self: CameraController, yawDelta: number, pitchDelta: number)
	local pitchLimits = self._config.PitchLimits
	self._lookYaw += yawDelta
	self._lookPitch = math.clamp(self._lookPitch + pitchDelta, pitchLimits.Min, pitchLimits.Max)
end

-- Unit vector the look rig faces along; feed this to character-facing logic
function CameraSystem.GetLookDirection(self: CameraController): Vector3
	return CFrame.fromEulerAnglesYXZ(self._lookPitch, self._lookYaw, 0).LookVector
end

-- Sets a runtime offset composed after every state/action offset (shoulder cam,
-- aiming); persists across state changes and actions, nil clears it
function CameraSystem.SetOffset(self: CameraController, offset: CFrame?)
	self._extraOffset = offset or CFrame.identity
end

-- Switches the state-layer truth; takes effect on the next Update
function CameraSystem.SetState(self: CameraController, stateName: string)
	assert(self._config.States[stateName], "Unknown camera state: " .. stateName)
	self.StateName = stateName
end

-- Starts a one-shot action; replaces any action already playing
function CameraSystem.PlayAction(self: CameraController, actionName: string)
	local action = self._config.Actions[actionName]
	assert(action, "Unknown camera action: " .. actionName)

	self._activeAction = {
		Entry = action,
		Elapsed = 0,
		KeyframeLength = CameraSystem._resolveKeyframeLength(action),
		ReturnTime = action.ReturnTime or self._config.DefaultReturnTime,
	}
end

-- State-layer goal: look rig * state offset * vertical hover bob
function CameraSystem._computeStateCFrame(self: CameraController, lookRig: CFrame): CFrame
	local state = self._config.States[self.StateName]
	local hoverHeight = math.sin(self._clock * state.HoverFrequency * math.pi * 2) * state.HoverAmplitude
	return lookRig * state.Offset * self._extraOffset * CFrame.new(0, hoverHeight, 0)
end

-- Action-layer offset at the current elapsed time (keyframe walk with easing)
function CameraSystem._computeActionOffset(self: CameraController, activeAction: ActiveAction): CFrame
	-- The active state's offset acts as the implicit starting keyframe
	local previousOffset = self._config.States[self.StateName].Offset
	local segmentTime = math.min(activeAction.Elapsed, activeAction.KeyframeLength)

	for _, keyframe in activeAction.Entry.Keyframes do
		if segmentTime >= keyframe.Duration then
			segmentTime -= keyframe.Duration
			previousOffset = keyframe.Offset
			continue
		end
		local easedAlpha = TweenService:GetValue(
			segmentTime / keyframe.Duration,
			keyframe.EasingStyle or Enum.EasingStyle.Quad,
			keyframe.EasingDirection or Enum.EasingDirection.Out
		)
		return previousOffset:Lerp(keyframe.Offset, easedAlpha)
	end
	-- Past the last keyframe: hold its offset while the return blend runs
	return previousOffset
end

-- Blend weight of the action layer: 1 during keyframes, eased 1 -> 0 over ReturnTime
function CameraSystem._computeActionWeight(activeAction: ActiveAction): number
	local returnElapsed = activeAction.Elapsed - activeAction.KeyframeLength
	if returnElapsed <= 0 then return 1 end
	if returnElapsed >= activeAction.ReturnTime then return 0 end

	local returnAlpha = returnElapsed / activeAction.ReturnTime
	return 1 - TweenService:GetValue(returnAlpha, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
end

-- Advances the action timeline and blends it over the state camera
function CameraSystem._applyActionLayer(self: CameraController, lookRig: CFrame, stateCFrame: CFrame, deltaTime: number): CFrame
	local activeAction = self._activeAction
	if not activeAction then return stateCFrame end

	activeAction.Elapsed += deltaTime
	-- Extra offset applies here too, so shoulder-cam style offsets survive actions
	local actionCFrame = lookRig * CameraSystem._computeActionOffset(self, activeAction) * self._extraOffset
	local actionWeight = CameraSystem._computeActionWeight(activeAction)

	-- Release once the return blend has fully handed control back to the state layer
	if activeAction.Elapsed >= activeAction.KeyframeLength + activeAction.ReturnTime then
		self._activeAction = nil
	end
	return stateCFrame:Lerp(actionCFrame, actionWeight)
end

-- Advances both layers and writes the final camera CFrame; call every RenderStep
function CameraSystem.Update(self: CameraController, deltaTime: number)
	local subject = self.Subject
	if not subject then return end

	-- Core scripts reset CameraType on respawn/seating; full control means re-asserting it
	if self.Camera.CameraType ~= Enum.CameraType.Scriptable then
		self.Camera.CameraType = Enum.CameraType.Scriptable
	end

	self._clock += deltaTime
	-- The rig is subject position + mouse-look rotation; subject facing plays no part
	local lookRig = CFrame.new(subject.Position) * CFrame.fromEulerAnglesYXZ(self._lookPitch, self._lookYaw, 0)
	local stateGoal = CameraSystem._computeStateCFrame(self, lookRig)

	-- Exponential smoothing keeps follow speed framerate-independent; the CFrame
	-- lerp blends rotation too, which is what makes mouse-look feel smooth
	local smoothingAlpha = 1 - math.exp(-self._config.States[self.StateName].Smoothing * deltaTime)
	local smoothedCFrame = self.Camera.CFrame:Lerp(stateGoal, smoothingAlpha)

	self.Camera.CFrame = CameraSystem._applyActionLayer(self, lookRig, smoothedCFrame, deltaTime)
end

-- Restores the camera type and cursor and clears live references; controller is dead after this
function CameraSystem.Destroy(self: CameraController)
	self.Camera.CameraType = self._previousCameraType
	UserInputService.MouseIconEnabled = self._previousMouseIconEnabled
	self._activeAction = nil
	self.Subject = nil
end

return CameraSystem
