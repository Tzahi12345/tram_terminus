local turnaround_params = ug_require "/stations/street/tram_terminus/turnaround_params.lua"

-- Adds the turnaround options to the base game underground stop, so stops that are already placed can get one too.
-- With the turnaround off it builds exactly like the base stop.
local terminusScript = "tzahi_tram_terminus::/stations/street/tram_terminus/tram_terminus.script@updateFn"

function data()
return {
	runFn = function (captureParams, settings)
		addModifier("loadConstruction", function (fileName, data)
			if not string.find(fileName, "underground_station/underground_station.con", 1, true) then
				return data
			end

			table.insert(data.params, turnaround_params.makeTurnaroundParam())
			table.insert(data.params, turnaround_params.makeLoopRadiusParam())

			data.updateScript.fileName = terminusScript
			data.updateScript.params.loopRadii = turnaround_params.loopRadiusValues
			data.updateScript.params.defaultLoopRadius = turnaround_params.defaultLoopRadius

			print("tzahi_tram_terminus: added turnaround to " .. fileName)
			return data
		end)
	end
}
end
