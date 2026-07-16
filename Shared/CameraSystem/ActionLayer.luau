--!strict

--// SERVICES
local TweenService = game:GetService("TweenService")

--// TYPES
local Types = require(script.Parent.Types)
type CameraActionEntry = Types.CameraActionEntry
type ActiveAction = Types.ActiveAction

--// MAIN
-- Keyframe playback math for one-shot camera actions. Stateless: the
-- controller owns the ActiveAction record; this module advances and samples it.
local ActionLayer = {}

-- Builds a playback record for an action; keyframe durations are summed once here
function ActionLayer.start(entry: CameraActionEntry, defaultReturnTime: number): ActiveAction
	local keyframeLength = 0
	for _, keyframe in entry.Keyframes do
		keyframeLength += keyframe.Duration
	end

	return {
		Entry = entry,
		Elapsed = 0,
		KeyframeLength = keyframeLength,
		ReturnTime = entry.ReturnTime or defaultReturnTime,
	}
end

-- Offset at the current elapsed time (keyframe walk with easing); `startOffset`
-- is the implicit first keyframe the action travels from
function ActionLayer._computeOffset(activeAction: ActiveAction, startOffset: CFrame): CFrame
	local previousOffset = startOffset
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

-- Blend weight of the action: 1 during keyframes, eased 1 -> 0 over ReturnTime
function ActionLayer._computeWeight(activeAction: ActiveAction): number
	local returnElapsed = activeAction.Elapsed - activeAction.KeyframeLength
	if returnElapsed <= 0 then return 1 end
	if returnElapsed >= activeAction.ReturnTime then return 0 end

	local returnAlpha = returnElapsed / activeAction.ReturnTime
	return 1 - TweenService:GetValue(returnAlpha, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
end

-- Advances the timeline and blends the action over the state camera; the second
-- return is true once the return blend has handed control back to the state layer
function ActionLayer.apply(activeAction: ActiveAction, lookRig: CFrame, stateCFrame: CFrame, startOffset: CFrame, extraOffset: CFrame, deltaTime: number): (CFrame, boolean)
	activeAction.Elapsed += deltaTime
	-- Extra offset applies here too, so shoulder-cam style offsets survive actions
	local actionCFrame = lookRig * ActionLayer._computeOffset(activeAction, startOffset) * extraOffset
	local actionWeight = ActionLayer._computeWeight(activeAction)

	local isFinished = activeAction.Elapsed >= activeAction.KeyframeLength + activeAction.ReturnTime
	return stateCFrame:Lerp(actionCFrame, actionWeight), isFinished
end

return ActionLayer
