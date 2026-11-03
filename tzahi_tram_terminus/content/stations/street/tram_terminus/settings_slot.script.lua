-- Underground stops only show the Configure button (and so the turnaround settings) when they have the settings
-- slot that tram_terminus.script.lua adds, and a placed stop only gets it when it is rebuilt. Stops built before
-- the mod was installed would never be rebuilt, so once per session this rebuilds every underground stop that
-- has no slot yet, with its settings unchanged (the same replace the Configure panel does). Nothing else about
-- the stop changes; stops that already have the slot are left alone.

local undergroundStop = "underground_station/underground_station.con"

local done = false

local function addMissingSlots()
	local stops = {}
	api.engine.forEachEntityWithComponent(function(entity)
		local construction = api.engine.getComponent(entity, api.type.ComponentType.CONSTRUCTION)
		if construction and string.find(construction.fileName, undergroundStop, 1, true) and #construction.slots == 0 then
			table.insert(stops, entity)
		end
	end, api.type.ComponentType.CONSTRUCTION)

	for _, entity in ipairs(stops) do
		local construction = api.engine.getComponent(entity, api.type.ComponentType.CONSTRUCTION)
		local proposal = api.engine.util.proposal.createProposalReplaceConstruction(entity, construction.params)
		if proposal then
			api.cmd.sendCommand(api.cmd.makeWorldBuildProposalCmd(proposal, nil, false, false))
		end
	end

	if #stops > 0 then
		print("tzahi_tram_terminus: added the settings slot to " .. #stops .. " underground stop(s)")
	end
end

local ret = {
	guiUpdate = function(userParams, state, guiState)
		if done then
			return
		end
		done = true
		addMissingSlots()
	end,
}

-- script files are read either way: returning the functions, or through data()
function data()
	return ret
end

return ret
