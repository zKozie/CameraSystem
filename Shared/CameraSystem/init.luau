--!strict

--// SERVICES
local TweenService = game:GetService("TweenService")

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
	self._previousCameraType = camera.CameraType

	camera.CameraType = Enum.CameraType.Scriptable
	return self
end

-- Points the camera at a new subject; nil freezes the camera until one is set
function CameraSystem.SetSubject(self: CameraController, subject: BasePart?)
	self.Subject = subject
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

-- State-layer goal: subject * state offset * vertical hover bob
function CameraSystem._computeStateCFrame(self: CameraController, subjectCFrame: CFrame): CFrame
	local state = self._config.States[self.StateName]
	local hoverHeight = math.sin(self._clock * state.HoverFrequency * math.pi * 2) * state.HoverAmplitude
	return subjectCFrame * state.Offset * CFrame.new(0, hoverHeight, 0)
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
function CameraSystem._applyActionLayer(self: CameraController, subjectCFrame: CFrame, stateCFrame: CFrame, deltaTime: number): CFrame
	local activeAction = self._activeAction
	if not activeAction then return stateCFrame end

	activeAction.Elapsed += deltaTime
	local actionCFrame = subjectCFrame * CameraSystem._computeActionOffset(self, activeAction)
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

	self._clock += deltaTime
	local subjectCFrame = subject.CFrame
	local stateGoal = CameraSystem._computeStateCFrame(self, subjectCFrame)

	-- Exponential smoothing keeps follow speed framerate-independent
	local smoothingAlpha = 1 - math.exp(-self._config.States[self.StateName].Smoothing * deltaTime)
	local smoothedCFrame = self.Camera.CFrame:Lerp(stateGoal, smoothingAlpha)

	self.Camera.CFrame = CameraSystem._applyActionLayer(self, subjectCFrame, smoothedCFrame, deltaTime)
end

-- Restores the camera type and clears live references; controller is dead after this
function CameraSystem.Destroy(self: CameraController)
	self.Camera.CameraType = self._previousCameraType
	self._activeAction = nil
	self.Subject = nil
end

return CameraSystem
