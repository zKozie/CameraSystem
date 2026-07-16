--!strict

--// SERVICES
local UserInputService = game:GetService("UserInputService")

--// MODULES
local ActionLayer = require(script.ActionLayer)

--// TYPES
local Types = require(script.Types)
type CameraConfig = Types.CameraConfig
type CameraController = Types.CameraController

--// MAIN
local CameraSystem = {}
CameraSystem.__index = CameraSystem

local OBSTRUCTION_BUFFER = 0.3 -- studs kept between the camera and a hit surface

-- Builds a controller for one camera: takes it Scriptable, hides the cursor
-- and enters InitialState
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
	self._occlusionParams = RaycastParams.new()
	self._previousCameraType = camera.CameraType
	self._previousMouseIconEnabled = UserInputService.MouseIconEnabled

	camera.CameraType = Enum.CameraType.Scriptable
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

	-- Obstruction rays ignore the subject's own rig and anything non-collidable
	local subjectRig: Instance = subject:FindFirstAncestorOfClass("Model") or subject
	self._occlusionParams.FilterType = Enum.RaycastFilterType.Exclude
	self._occlusionParams.FilterDescendantsInstances = { subjectRig }
	self._occlusionParams.RespectCanCollide = true
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
	self._activeAction = ActionLayer.start(action, self._config.DefaultReturnTime)
end

-- State-layer goal: look rig * state offset * vertical hover bob
function CameraSystem._computeStateCFrame(self: CameraController, lookRig: CFrame): CFrame
	local state = self._config.States[self.StateName]
	local hoverHeight = math.sin(self._clock * state.HoverFrequency * math.pi * 2) * state.HoverAmplitude
	return lookRig * state.Offset * self._extraOffset * CFrame.new(0, hoverHeight, 0)
end

-- Advances the action timeline and blends it over the state camera
function CameraSystem._applyActionLayer(self: CameraController, lookRig: CFrame, stateCFrame: CFrame, deltaTime: number): CFrame
	local activeAction = self._activeAction
	if not activeAction then return stateCFrame end

	-- The active state's offset acts as the action's implicit starting keyframe
	local startOffset = self._config.States[self.StateName].Offset
	local blendedCFrame, isFinished = ActionLayer.apply(activeAction, lookRig, stateCFrame, startOffset, self._extraOffset, deltaTime)
	if isFinished then
		self._activeAction = nil
	end
	return blendedCFrame
end

-- Pulls the camera in front of any geometry between the subject and its goal,
-- so walls never end up between the two
function CameraSystem._resolveObstruction(self: CameraController, subjectPosition: Vector3, goalCFrame: CFrame): CFrame
	local toCamera = goalCFrame.Position - subjectPosition
	local obstructionHit = workspace:Raycast(subjectPosition, toCamera, self._occlusionParams)
	if not obstructionHit then return goalCFrame end

	local pulledPosition = obstructionHit.Position - toCamera.Unit * OBSTRUCTION_BUFFER
	return goalCFrame.Rotation + pulledPosition
end

-- Advances both layers and writes the final camera CFrame; call every RenderStep
function CameraSystem.Update(self: CameraController, deltaTime: number)
	local subject = self.Subject
	if not subject then return end

	-- Core scripts reclaim these on respawn/state changes; full control re-asserts both
	if self.Camera.CameraType ~= Enum.CameraType.Scriptable then
		self.Camera.CameraType = Enum.CameraType.Scriptable
	end
	if UserInputService.MouseIconEnabled then
		UserInputService.MouseIconEnabled = false
	end

	self._clock += deltaTime
	-- The rig is subject position + mouse-look rotation; subject facing plays no part
	local lookRig = CFrame.new(subject.Position) * CFrame.fromEulerAnglesYXZ(self._lookPitch, self._lookYaw, 0)
	local stateGoal = CameraSystem._computeStateCFrame(self, lookRig)

	-- Exponential smoothing keeps follow speed framerate-independent; the CFrame
	-- lerp blends rotation too, which is what makes mouse-look feel smooth
	local smoothingAlpha = 1 - math.exp(-self._config.States[self.StateName].Smoothing * deltaTime)
	local smoothedCFrame = self.Camera.CFrame:Lerp(stateGoal, smoothingAlpha)

	local blendedCFrame = CameraSystem._applyActionLayer(self, lookRig, smoothedCFrame, deltaTime)
	self.Camera.CFrame = CameraSystem._resolveObstruction(self, subject.Position, blendedCFrame)
end

-- Restores the camera type and cursor and clears live references; controller is dead after this
function CameraSystem.Destroy(self: CameraController)
	self.Camera.CameraType = self._previousCameraType
	UserInputService.MouseIconEnabled = self._previousMouseIconEnabled
	self._activeAction = nil
	self.Subject = nil
end

return CameraSystem
