--!strict

-- One camera state definition — the "truth" placement of the camera while the
-- state is active. Owned by CameraSystem. `Offset` is relative to the subject's
-- CFrame, so the camera follows the subject's position and facing.
export type CameraStateEntry = {
	Offset: CFrame, -- camera placement relative to the subject
	HoverAmplitude: number, -- vertical hover bob height in studs; 0 disables it
	HoverFrequency: number, -- hover bob cycles per second
	Smoothing: number, -- follow responsiveness per second; higher converges faster
}

-- One keyframe inside a camera action timeline.
-- Owned by CameraSystem. The action travels from the previous keyframe's
-- `Offset` (or the active state's Offset for the first keyframe) to this one.
export type CameraKeyframe = {
	Offset: CFrame, -- target offset relative to the subject at this keyframe
	Duration: number, -- seconds to travel from the previous keyframe to this one
	EasingStyle: Enum.EasingStyle?, -- nil falls back to Quad
	EasingDirection: Enum.EasingDirection?, -- nil falls back to Out
}

-- A one-shot camera movement. Plays its keyframes at full override weight,
-- then blends back into the live state camera over `ReturnTime` — the return
-- target is wherever the state camera is by then, not where the action began.
export type CameraActionEntry = {
	Keyframes: {CameraKeyframe},
	ReturnTime: number?, -- blend-back seconds; nil falls back to DefaultReturnTime
}

-- The single configuration table passed to CameraSystem.new.
-- Owned by CameraSystem. Config.luau is the shipped template; a game may pass
-- its own table of the same shape instead of editing the module.
export type CameraConfig = {
	InitialState: string, -- key into States entered at construction
	DefaultReturnTime: number, -- blend-back seconds for actions without ReturnTime
	States: {[string]: CameraStateEntry},
	Actions: {[string]: CameraActionEntry},
}

-- Internal playback record for the action currently overriding the state layer.
-- Owned by CameraSystem. Created by PlayAction, cleared by Update once the
-- return blend completes.
export type ActiveAction = {
	Entry: CameraActionEntry, -- config entry being played
	Elapsed: number, -- seconds since PlayAction was called
	KeyframeLength: number, -- summed keyframe durations, cached at start
	ReturnTime: number, -- resolved blend-back duration
}

-- A camera controller returned by CameraSystem.new.
-- Owned by CameraSystem. Takes the camera Scriptable on construction,
-- re-asserts it every Update (full control — core scripts reset it on
-- respawn), and restores the previous CameraType on Destroy. Drive Update
-- externally (RenderStep) — the controller never binds its own loop.
-- Underscore fields are internal bookkeeping; consume the methods only.
export type CameraController = {
	Camera: Camera, -- camera being driven, captured at construction
	StateName: string, -- key of the active state in config.States
	Subject: BasePart?, -- part the camera follows; Update is a no-op while nil
	SetSubject: (self: CameraController, subject: BasePart?) -> (),
	SetState: (self: CameraController, stateName: string) -> (),
	SetOffset: (self: CameraController, offset: CFrame?) -> (),
	PlayAction: (self: CameraController, actionName: string) -> (),
	Update: (self: CameraController, deltaTime: number) -> (),
	Destroy: (self: CameraController) -> (),
	_config: CameraConfig, -- internal: config captured at construction
	_clock: number, -- internal: accumulated time driving the hover bob
	_activeAction: ActiveAction?, -- internal: nil when no action is playing
	_extraOffset: CFrame, -- internal: runtime offset from SetOffset; identity when unset
	_previousCameraType: Enum.CameraType, -- internal: restored on Destroy
}

return nil
