-- Construction params for the tram turnaround, added to the base underground stop by mod.script.lua

local turnaround_params = {}

-- starts at 10 m: below that the loop's tunnel collides with itself where its two sides meet (seen in game)
turnaround_params.loopRadiusValues = {10, 12, 15, 18, 20, 25, 30}
turnaround_params.defaultLoopRadius = 3 -- 15 m

local function makeMeterValues(list)
	local result = { }

	for i = 1, #list do
		result[#result + 1] = "{value} m" % { value = list[i] }
	end

	return result
end

turnaround_params.makeTurnaroundParam = function()
	return {
			key = "tramTurnaround",
			name = _("Turnaround"),
			tooltip = _("Close one end of the stop and let trams turn there.\nPick the end that has no track connected."),
			values = { _("Off"), _("End 1"), _("End 2") },
			tooltips = {
				_("Normal stop with track at both ends."),
				_("Trams turn past end 1. If nothing changes, end 1 has track connected: try End 2."),
				_("Trams turn past end 2. If nothing changes, end 2 has track connected: try End 1."),
			},
			defaultIndex = 1,
			postConstructionModifiable = true,
			displayMode = "Horizontal",
		}
end

turnaround_params.makeLoopRadiusParam = function()
	return {
			key = "loopRadius",
			name = _("Loop Radius"),
			tooltip = _("Radius of the loop trams turn on, past the closed end of the stop. Smaller loops need less room."),
			values = makeMeterValues(turnaround_params.loopRadiusValues),
			defaultIndex = turnaround_params.defaultLoopRadius,
			postConstructionModifiable = true,
			displayMode = "Sparse",
			uiType = "Slider"
		}
end

return turnaround_params
