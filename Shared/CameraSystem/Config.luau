--!strict

local Types = require(script.Parent.Types)

-- The single camera configuration consumed by CameraSystem.new.
-- Tune offsets and hover values per game; add states and actions as the
-- camera gains behaviours. Offsets are relative to the subject's CFrame,
-- so +Z sits behind a subject facing -Z (HumanoidRootPart convention).
return {
	InitialState = "Walking",
	DefaultReturnTime = 0.4,

	States = {
		Walking = {
			Offset = CFrame.new(0, 2, 10),
			HoverAmplitude = 0.15,
			HoverFrequency = 0.8,
			Smoothing = 8,
		},
		Running = {
			-- Pulled back and higher than Walking, with a stronger faster bob
			Offset = CFrame.new(0, 2.5, 12),
			HoverAmplitude = 0.35,
			HoverFrequency = 1.6,
			Smoothing = 12,
		},
	},

	Actions = {
		-- Quick punch-in toward the subject, brief hold, then blend back out
		Impact = {
			Keyframes = {
				{ Offset = CFrame.new(0, 1.5, 6), Duration = 0.12 },
				{ Offset = CFrame.new(0, 1.5, 7), Duration = 0.25, EasingStyle = Enum.EasingStyle.Sine },
			},
			ReturnTime = 0.5,
		},
	},
} :: Types.CameraConfig
