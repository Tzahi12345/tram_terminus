local vec3 = require "::/scripts/vec3.tl"
local transf = require "::/scripts/mat4.tl"
local laneutil = require "::/scripts/construction/laneutil.lua"
local modulesutil = require "::/scripts/construction/modulesutil.lua"

local constructionutil = require "::/scripts/construction/constructionutil.lua"

local function mul(mat, vec) 
	return {
		mat[1]*vec[1] + mat[5]*vec[2] + mat[ 9]*vec[3] + mat[13],
		mat[2]*vec[1] + mat[6]*vec[2] + mat[10]*vec[3] + mat[14],
		mat[3]*vec[1] + mat[7]*vec[2] + mat[11]*vec[3] + mat[15]
	}
end

local function transform(curve, mat)
	local ret = {}
	for i=1, #curve do
		local points = curve[i]
		local transfCurv = {}
		for j = 1, #points do
			transfCurv[j] = mul(mat, points[j])
		end
		ret[i] = transfCurv
	end

	return ret
end

local function makeCircleEdges(depth, radius, split_deg)
	local function arc_to_bezier(r, a0, a1, depth)
		local theta = a1 - a0
		local mid = (a0 + a1) / 2
		local cos0, sin0 = math.cos(a0), math.sin(a0)
		local cos1, sin1 = math.cos(a1), math.sin(a1)
		local cosM, sinM = math.cos(mid), math.sin(mid)

		local p0 = { r * cos0, r * sin0, depth }
		local p2 = { r * cos1, r * sin1, depth }

		local control_radius = r / math.cos(theta / 2)
		local p1 = { control_radius * math.cos(mid), control_radius * math.sin(mid), depth }

		return { p0, p1, p2 }
	end

	-- Collect all breakpoints (≤45° + custom splits)
	local breaks = {}
	for a = 0, 360, 45 do
		table.insert(breaks, a)
	end
	table.insert(breaks, split_deg % 360)
	table.insert(breaks, (split_deg + 180) % 360)

	-- Sort and deduplicate
	table.sort(breaks)
	local unique = {}
	for _, a in ipairs(breaks) do
		if #unique == 0 or math.abs(a - unique[#unique]) > 1e-6 then
			table.insert(unique, a)
		end
	end
	if unique[#unique] < 360 then
		table.insert(unique, 360)
	end

	-- Create segments
	local segments = {}
	for i = 1, #unique - 1 do
		local a0, a1 = math.rad(unique[i]), math.rad(unique[i + 1])
		table.insert(segments, arc_to_bezier(radius, a0, a1, depth))
	end

	return segments
end

local function makeEdge(origin, direction, length)
	return {{  
			{ origin[1] + direction[1] * length, origin[2] + direction[2] * length, origin[3] }, { origin[1], origin[2], origin[3] }, 
		}}
end

local function makePassengerLane(origin, direction, length, stairDistance)
	local dynamicLength = length - stairDistance
	local fixedLength = stairDistance * 2.0

	local start = { origin[1] + direction[1] * length, origin[2] + direction[2] * length, origin[3] }
	local stair1 = { start[1] - direction[1] * dynamicLength, start[2] - direction[2] * dynamicLength, origin[3] }
	local stair2 = { start[1] - direction[1] * (dynamicLength + fixedLength), start[2] - direction[2] * (dynamicLength + fixedLength), origin[3] }
	local farSide = { start[1] - direction[1] * length * 2.0, start[2] - direction[2] * length * 2.0, origin[3] }

	return { 
		{ start, stair1, },
		{ stair1, stair2, },
		{ stair2, farSide, },
	}
end

local function makeVehicleLane(origin, direction, length)
	return { 
		{ { origin[1] + direction[1] * length, origin[2] + direction[2] * length, origin[3] }, { origin[1], origin[2], origin[3] }, },
		{ { origin[1], origin[2], origin[3] }, { origin[1] - direction[1] * length, origin[2] - direction[2] * length, origin[3] }, },
	}
end

-- Circular arc from angle a0 to a1 (radians, either direction), split into quadratic pieces of at most 30 degrees
local function makeArc(center, radius, a0, a1, z)
	local segments = {}
	local count = math.max(1, math.ceil(math.abs(a1 - a0) / math.rad(30)))
	local step = (a1 - a0) / count
	local controlRadius = radius / math.cos(step / 2)
	for i = 0, count - 1 do
		local s0 = a0 + step * i
		local s1 = s0 + step
		local mid = (s0 + s1) / 2
		table.insert(segments, {
			{ center[1] + radius * math.cos(s0), center[2] + radius * math.sin(s0), z },
			{ center[1] + controlRadius * math.cos(mid), center[2] + controlRadius * math.sin(mid), z },
			{ center[1] + radius * math.cos(s1), center[2] + radius * math.sin(s1), z },
		})
	end
	return segments
end

local oneWayDoubleLoopTrack = "tzahi_tram_terminus::/stations/street/tram_terminus/tram_loop_one_way_double.street_template"
local tramTrack = "::/infrastructure/street/tram/tram_new.street_template"

-- A single module slot that accepts no modules. The station window only offers "Configure" (which opens the
-- editor for settings marked postConstructionModifiable) for constructions with slots, so this makes the
-- turnaround settings reachable on stops that are already placed
local settingsSlotType = "tzahi_tram_terminus_settings"

-- The turning loop: a two-way stub continues the platform tracks in one wide tunnel (like the base stop), then
-- at a junction splits into a one-way teardrop loop: two tracks leave at +-30 degrees and meet round a circle of
-- the given radius.
-- The loop uses the one-way double track (see tram_loop_one_way_double.street_template.lua for why), which keeps
-- the whole loop in a wide tunnel. It is built backwards (from the far end, with backward lanes), which in game
-- makes trams keep to one of its tracks instead of switching tracks at the junction.
-- Returns the stub (one piece) and the loop pieces in build order.
local stubLength = 10.0
local splitAngle = math.rad(30)

local function makeSplitLoopEdges(x0, radius, z)
	local junction = { x0 - stubLength, 0, z }
	local center = { junction[1] - radius / math.sin(splitAngle), 0 }
	local tangentAngle = math.pi / 2 - splitAngle
	local upper = { center[1] + radius * math.cos(tangentAngle), radius * math.sin(tangentAngle), z }
	local lower = { center[1] + radius * math.cos(tangentAngle), -radius * math.sin(tangentAngle), z }

	local stub = { { { x0, 0, z }, junction } }
	-- in driving order, the upper branch comes first: an arriving tram (y = +2.5 side, heading -x) turns right into it
	local driving = { { junction, upper } }
	for _, s in ipairs(makeArc(center, radius, tangentAngle, 2 * math.pi - tangentAngle, z)) do
		table.insert(driving, s)
	end
	table.insert(driving, { lower, junction })

	-- built backwards
	local loop = {}
	for i = #driving, 1, -1 do
		local piece = {}
		for j = #driving[i], 1, -1 do
			table.insert(piece, driving[i][j])
		end
		table.insert(loop, piece)
	end
	return stub, loop
end

local edgeBuffer = 0.5

--Begin Generated
local generatedData = {
	["static"] = {
		curves = {
			["ground_face"] = {
				{ { 8.0, 8.0, 0.0 }, { -8.0, 8.0, 0.0 }, { -8.0, 24.0, 0.0 }, { 8.0, 24.0, 0.0 }, },
			},
		},
	},
	["base"] = {
		curves = {
			["passenger_entrance_link"] = {
				-- top level
				{ { 3, 9, 0 }, { 3, 20, 0 }, },
				{ { 3, 20, 0 }, { 0, 20, 0 }, },

			},
			["passenger_entrance"] = {
				-- top level
				{ { -3, 9, 0 }, { -3, 20, 0 }, },
				{ { -3, 20, 0 }, { 0, 20, 0 }, },

				{ { 0, 20, 0 }, { 0, 17.51, 0.057 }, },

				-- stairs
				{ { 0, 17.51, 0.057 }, { 0, 1.5, -9 }, },
				{ { 0, 1.5, -9 }, { 0, 0, -9 }, },

				{ { 0, 0, -9 }, { 1.5, 0, -9 }, },
				{ { 1.5, 0, -9 }, { 6.7, 0, -12 }, },
				{ { 6.7, 0, -12 }, { 8.5, 0, -12 }, },

				{ { 0, 0, -9 }, { -1.5, 0, -9 }, },
				{ { -1.5, 0, -9 }, { -6.7, 0, -12 }, },
				{ { -6.7, 0, -12 }, { -8.5, 0, -12 }, },
			},
			["collider"] = {
				{ 
					{ 8.0, 9.0, 20.0 }, { -8.0, 9.0, 20.0 }, { -8.0, 24.0, 20.0 }, { 8.0, 24.0, 20.0 }, 
					{ 8.0, 9.0, -7.4 }, { -8.0, 9.0, -7.4 }, { -8.0, 24.0, -7.4 }, { 8.0, 24.0, -7.4 }, 
				},
			},
		},
		meshes = {
			["equal"] = {
				{ 
					{ { 8.0, 9.0, 0.0 }, { -8.0, 24.0, 0.0 }, { -8.0, 9.0, 0.0 }, },
					{ { -8.0, 24.0, 0.0 }, { 8.0, 9.0, 0.0 }, { 8.0, 24.0, 0.0 }, },
				}
			},

		},
		models = {
			["::/stations/street/underground_station/models/underground_station_surface.mdl"] = {
				{ 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 },
			},
			["::/assets/stations/rail/era_c_street_pillar.mdl"] = {
				{ 0, -1, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 1.5, 8, 0, 1, },
				{ 0, -1, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, -1.5, 8, 0, 1, },
				{ 0, -1, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 3.5, 8, 0, 1, },
				{ 0, -1, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, -3.5, 8, 0, 1, },
			},
			["::/assets/buildings/com/advertisements/column_c_01.mdl"] = {
				{ 0, -1, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 9.5, 0, 1, },
			},
			["::/assets/buildings/res/hedges/hdg_02_3m.mdl"] = {
				{ 0, 1, 0, 0, -1, 0, 0, 0, 0, 0, 1, 0, 6.5, 11, 0, 1, },
				{ 0, 1, 0, 0, -1, 0, 0, 0, 0, 0, 1, 0, -6.5, 11, 0, 1, },
				{ 0, 1, 0, 0, -1, 0, 0, 0, 0, 0, 1, 0, 6.5, 17, 0, 1, },
				{ 0, 1, 0, 0, -1, 0, 0, 0, 0, 0, 1, 0, -6.5, 17, 0, 1, },
				{ 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, -5, 23.5, 0, 1, },
				{ 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 1, 23.5, 0, 1, },
			},
			["::/assets/buildings/com/misc/trashcan_c_01.mdl"] = {
				{ 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 5, 14, 0, 1, },
				{ -1, 0, 0, 0, 0, -1, 0, 0, 0, 0, 1, 0, -5, 14, 0, 1, },
				{ 0, 1, 0, 0, -1, 0, 0, 0, 0, 0, 1, 0, 0, 22, 0, 1, },
			},
			["::/assets/buildings/res/garden_lamp/garden_lamp_c_stand.mdl"] = {
				{ 0, -1, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 5, 11, 0, 1, },
				{ 0, -1, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 5, 17, 0, 1, },
				{ 0, 1, 0, 0, -1, 0, 0, 0, 0, 0, 1, 0, -5, 11, 0, 1, },
				{ 0, 1, 0, 0, -1, 0, 0, 0, 0, 0, 1, 0, -5, 17, 0, 1, },
				{ 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, -3.5, 22, 0, 1, },
				{ 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 3.5, 22, 0, 1, },
			},
			["::/assets/buildings/res/grd_frn/bench_c_metal.mdl"] = {
				{ -1, 0, 0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 5, 15.5, 0, 1, },
				{ -1, 0, 0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 5, 12.5, 0, 1, },
				{ 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, -5, 15.5, 0, 1, },
				{ 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, -5, 12.5, 0, 1, },
				{ 0, -1, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 1.5, 22, 0, 1, },
				{ 0, -1, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, -1.5, 22, 0, 1, },
			},
			["::/assets/buildings/res/hedges/hdg_02.mdl"] = {
				{ 0, 1, 0, 0, -1, 0, 0, 0, 0, 0, 1, 0, 6.5, 9, 0, 1, },
				{ 0, 1, 0, 0, -1, 0, 0, 0, 0, 0, 1, 0, -6.5, 9, 0, 1, },
				{ 0, 1, 0, 0, -1, 0, 0, 0, 0, 0, 1, 0, 6.5, 23, 0, 1, },
				{ 0, 1, 0, 0, -1, 0, 0, 0, 0, 0, 1, 0, -6.5, 23, 0, 1, },
			},
		}
	},
	["rotated"] = {
		curves = {
			["passenger_passageway"] = {
				-- inside
				{ { 0, 8.5, -12 }, { 0, 11.75, -12 }, },
				{ { 0, 11.75, -12 }, { 3.33, 11.75, -12 }, },
				{ { 3.33, 11.75, -12 }, { 13.33, 11.75, -17.65 }, },
				{ { 13.33, 11.75, -17.65 }, { 14.66, 11.75, -17.65 }, },
				{ { 14.66, 11.75, -17.65 }, { 14.66, 5, -17.65 }, },

				{ { 0, 11.75, -12 }, { -3.33, 11.75, -12 }, },
				{ { -3.33, 11.75, -12 }, { -13.33, 11.75, -17.65 }, },
				{ { -13.33, 11.75, -17.65 }, { -14.66, 11.75, -17.65 }, },
				{ { -14.66, 11.75, -17.65 }, { -14.66, 5, -17.65 }, },

				{ { 0, -8.5, -12 }, { 0, -11.75, -12 }, },
				{ { 0, -11.75, -12 }, { 3.33, -11.75, -12 }, },
				{ { 3.33, -11.75, -12 }, { 13.33, -11.75, -17.65 }, },
				{ { 13.33, -11.75, -17.65 }, { 14.66, -11.75, -17.65 }, },
				{ { 14.66, -11.75, -17.65 }, { 14.66, -5, -17.65 }, },

				{ { 0, -11.75, -12 }, { -3.33, -11.75, -12 }, },
				{ { -3.33, -11.75, -12 }, { -13.33, -11.75, -17.65 }, },
				{ { -13.33, -11.75, -17.65 }, { -14.66, -11.75, -17.65 }, },
				{ { -14.66, -11.75, -17.65 }, { -14.66, -5, -17.65 }, },
			},
			["collider"] = {
				{ 
					{ 20.0, -14.0, -7.5 }, { -20.0, -14.0, -7.5 }, { -20.0, 14.0, -7.5 }, { 20.0, 14.0, -7.5 }, 
					{ 20.0, -14.0, -20.0 }, { -20.0, -14.0, -20.0 }, { -20.0, 14.0, -20.0 }, { 20.0, 14.0, -20.0 }, 
				},
			},
		},
		models = {
			["::/stations/street/underground_station/models/underground_station_stairs.mdl"] = {
				{ 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 },
			},
			["::/assets/stations/street/tickets_era_c_1.mdl"] = {
				{ 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 12.7, -12, 1, },
				{ -1, 0, 0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 0, -12.7, -12, 1, },
				{ 0, -1, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 15.4, 12, -17.65, 1, },
				{ 0,-1, 0, 0, -1, 0, 0, 0, 0, 0, 1, 0, -15.4, 12, -17.65, 1, },
				{ 0, -1, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 15.4, -12, -17.65, 1, },
				{ 0,-1, 0, 0, -1, 0, 0, 0, 0, 0, 1, 0, -15.4, -12, -17.65, 1, },
			},
			["::/assets/stations/rail/era_c_station_name.mdl"] = {
				{ 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 5, 7.15, -16.15, 1, },
				{ 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, -5, 7.15, -16.15, 1, },
				
				{ 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 5, -7.15, -16.15, 1, },
				{ 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, -5, -7.15, -16.15, 1, },
			},
			["::/assets/buildings/com/misc/trashcan_c_01.mdl"] = {
				{ 0, 1, 0, 0, -1, 0, 0, 0, 0, 0, 1, 0, 10, 6.5, -17.65, 1, },
				{ 0, 1, 0, 0, -1, 0, 0, 0, 0, 0, 1, 0, 0, 6.5, -17.65, 1, },
				{ 0, 1, 0, 0, -1, 0, 0, 0, 0, 0, 1, 0, -10, 6.5, -17.65, 1, },
				
				{ 0, -1, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 10, -6.5, -17.65, 1, },
				{ 0, -1, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, -6.5, -17.65, 1, },
				{ 0, -1, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, -10, -6.5, -17.65, 1, },
			},
			["::/assets/buildings/res/grd_frn/bench_c_metal.mdl"] = {
				{ 0, -1, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 11.5, 6.5, -17.65, 1, },
				{ 0, -1, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 8.5, 6.5, -17.65, 1, },
				{ 0, -1, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 1.5, 6.5, -17.65, 1, },
				{ 0, -1, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, -1.5, 6.5, -17.65, 1, },
				{ 0, -1, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, -11.5, 6.5, -17.65, 1, },
				{ 0, -1, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, -8.5, 6.5, -17.65, 1, },

				{ 0, 1, 0, 0, -1, 0, 0, 0, 0, 0, 1, 0, 11.5, -6.5, -17.65, 1, },
				{ 0, 1, 0, 0, -1, 0, 0, 0, 0, 0, 1, 0, 8.5, -6.5, -17.65, 1, },
				{ 0, 1, 0, 0, -1, 0, 0, 0, 0, 0, 1, 0, 1.5, -6.5, -17.65, 1, },
				{ 0, 1, 0, 0, -1, 0, 0, 0, 0, 0, 1, 0, -1.5, -6.5, -17.65, 1, },
				{ 0, 1, 0, 0, -1, 0, 0, 0, 0, 0, 1, 0, -11.5, -6.5, -17.65, 1, },
				{ 0, 1, 0, 0, -1, 0, 0, 0, 0, 0, 1, 0, -8.5, -6.5, -17.65, 1, },
			},
		}
	},
	["extended"] = {
		curves = {
			["collider"] = {
				{ 
					{ 9.0, -10.0, -11.5 }, { 0.0, -10.0, -11.5 }, { 0.0, 10.0, -11.5 }, { 9.0, 10.0, -11.5 }, 
					{ 9.0, -10.0, -20.0 }, { 0.0, -10.0, -20.0 }, { 0.0, 10.0, -20.0 }, { 9.0, 10.0, -20.0 }, 
				},
			},
		},
		models = {
			["::/stations/street/underground_station/models/underground_station_extension.mdl"] = {
				{ 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 },
			},
			["::/assets/stations/rail/era_c_station_name.mdl"] = {
				{ 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 5, 7.15, -16.15, 1, },
				
				{ 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 5, -7.15, -16.15, 1, },
			},
			["::/assets/buildings/com/misc/trashcan_c_01.mdl"] = {
				{ 0, 1, 0, 0, -1, 0, 0, 0, 0, 0, 1, 0, 0, 6.5, -17.65, 1, },
				{ 0, -1, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, -6.5, -17.65, 1, },
			},
			["::/assets/buildings/res/grd_frn/bench_c_metal.mdl"] = {
				{ 0, -1, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 1.5, 6.5, -17.65, 1, },
				{ 0, -1, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, -1.5, 6.5, -17.65, 1, },
				{ 0, 1, 0, 0, -1, 0, 0, 0, 0, 0, 1, 0, 1.5, -6.5, -17.65, 1, },
				{ 0, 1, 0, 0, -1, 0, 0, 0, 0, 0, 1, 0, -1.5, -6.5, -17.65, 1, },
			},
		}
	},
}
--End Generated

function data()
	local config = {
		tramTrackTypes = { "YES", "ELECTRIC" },
		costs = { 8300, 9800 }
	}
	
return {
	createTemplateFn = function(captureParams, params)
		local result = {}
		return result
	end,
	updateFn = function(captureParams, params)
		local updateParams = captureParams
		local platformLenghts = updateParams.platformLengths
		local stepIncrement = updateParams.stepIncrement
		local platformAngle = (params.platformOrientation - 1) * stepIncrement

		-- Turnaround: 1 = off (plain underground stop, track at both ends), 2 = turn at end 1 (-x), 3 = turn at end 2 (+x)
		local turnaround = params.tramTurnaround or 1
		if turnaround > 3 then
			-- removed "Show end" options from development versions: a plain stop
			turnaround = 1
		end
		if turnaround == 3 then
			-- the platform is symmetric, so turning it round moves the closed end to the other side
			platformAngle = platformAngle + 180
		end
		local platformTransform = transf.rotZ( math.rad(platformAngle))

		local index = (params.tramCatenary == 2 and 1 or 0) + 1

		local result = {}
		result.subconstructions = {}

		local freeNodesList = { 0 }
		local snapNodes = { 0 }

		local halfLength = platformLenghts[params.platformLength] * 0.5

		-- Track always leaves at the +x end; the -x end gets either track too (turnaround off) or the turn
		local edge1 = makeEdge({ halfLength + edgeBuffer, 0.0, -18 }, { 1.0, 0.0, 0.0 }, 10.0)

		constructionutil.addEdges(transform(edge1, platformTransform), result, "STREET", {
			type = "::/infrastructure/street/tram/tram_new.street_template", tramTrackType = config.tramTrackTypes[index], edgeType = "TUNNEL", edgeTypeName = "::/infrastructure/tunnel/tunnel_b_car.tunnel" }, false, snapNodes, freeNodesList)

		if turnaround == 1 then
			local edge2 = makeEdge({ -halfLength - edgeBuffer, 0.0, -18 }, { -1.0, 0.0, 0.0 }, 10.0)

			constructionutil.addEdges(transform(edge2, platformTransform), result, "STREET", {
				type = "::/infrastructure/street/tram/tram_new.street_template", tramTrackType = config.tramTrackTypes[index], edgeType = "TUNNEL", edgeTypeName = "::/infrastructure/tunnel/tunnel_b_car.tunnel" }, false, snapNodes, freeNodesList)
		end

		local mainSubconstruction = {}

		mainSubconstruction.laneLists = {}

		local lane = laneutil.createLane(generatedData["base"].curves["passenger_entrance_link"], {"PERSON",}, 2, 2, true) -- 0
		table.insert(mainSubconstruction.laneLists, lane)

		local lane = laneutil.createLane(generatedData["base"].curves["passenger_entrance"], {"PERSON",}, 2, 2, false) -- 1
		table.insert(mainSubconstruction.laneLists, lane)

		lane = laneutil.createLane(makeCircleEdges(-12, 8.5, platformAngle - 90), {"PERSON",}, 2, 2, false) -- 2
		table.insert(mainSubconstruction.laneLists, lane)

		lane = laneutil.createLane(transform(generatedData["rotated"].curves["passenger_passageway"], platformTransform), {"PERSON",}, 2, 2, false) -- 3
		table.insert(mainSubconstruction.laneLists, lane)

		local passengerPlatform1 = makePassengerLane({ 0, -5, -17.65 }, { -1.0, 0.0, 0.0 }, halfLength, 14.66)
		local passengerPlatform2 = makePassengerLane({ 0, 5, -17.65 }, { 1.0, 0.0, 0.0 }, halfLength, 14.66)

		lane = laneutil.createLane(transform(passengerPlatform1, platformTransform), {"PERSON",}, 2, 2, false)  -- 4
		table.insert(mainSubconstruction.laneLists, lane)

		lane = laneutil.createLane(transform(passengerPlatform2, platformTransform), {"PERSON",}, 2, 2, false)  -- 5
		table.insert(mainSubconstruction.laneLists, lane)

		local vehicle1 = makeVehicleLane({ 0, -2.5, -18 }, { -1.0, 0.0, 0.0 }, halfLength + edgeBuffer)
		local vehicle2 = makeVehicleLane({ 0, 2.5, -18 }, { 1.0, 0.0, 0.0 }, halfLength + edgeBuffer)

		lane = laneutil.createLane(transform(vehicle1, platformTransform), {"TRAM", "ELECTRIC_TRAM",}, 40, 2, false)  -- 6
		table.insert(mainSubconstruction.laneLists, lane)

		lane = laneutil.createLane(transform(vehicle2, platformTransform), {"TRAM", "ELECTRIC_TRAM",}, 40, 2, false)  -- 7
		table.insert(mainSubconstruction.laneLists, lane)

		if turnaround == 1 then
			-- no turn: plain underground stop
		else
			-- Visible tram track (tunnel) looping from the end of lane 7 (arriving, y = +2.5) back to the start of
			-- lane 6 (departing, y = -2.5); the loop itself is one-way, so trams can only go round one way and
			-- never meet oncoming trams
			local loopRadius = updateParams.loopRadii[params.loopRadius or updateParams.defaultLoopRadius]
			local x0 = -halfLength - edgeBuffer
			local stub, loop = makeSplitLoopEdges(x0, loopRadius, -18)

			constructionutil.addEdges(transform(stub, platformTransform), result, "STREET", {
				type = tramTrack, tramTrackType = config.tramTrackTypes[index], edgeType = "TUNNEL", edgeTypeName = "::/infrastructure/tunnel/tunnel_b_car.tunnel" }, false, {}, {})

			constructionutil.addEdges(transform(loop, platformTransform), result, "STREET", {
				type = oneWayDoubleLoopTrack, tramTrackType = config.tramTrackTypes[index], edgeType = "TUNNEL", edgeTypeName = "::/infrastructure/tunnel/tunnel_b_car.tunnel" }, false, {}, {})
		end

		-- on the stairs entrance, which is part of every stop and never moves
		result.slots = {
			{
				id = 1,
				transf = transf.transl(vec3.new(0, 16, 0)),
				type = settingsSlotType,
				spacing = { 1, 1, 1, 1 },
			},
		}

		mainSubconstruction.models = { }

		
		constructionutil.addModelsAndGroups(params, generatedData["base"], mainSubconstruction)
		constructionutil.addModelsAndGroups(params, generatedData["rotated"], mainSubconstruction, nil, platformTransform)

		mainSubconstruction.models[#mainSubconstruction.models + 1] = {
			id = "::/stations/street/underground_station/models/underground_station_end.mdl",
			transf = transf.mul(transf.rotZ(math.rad(platformAngle)), transf.transl(vec3.new(halfLength, 0, 0)))
		}
		mainSubconstruction.models[#mainSubconstruction.models + 1] = {
			id = "::/stations/street/underground_station/models/underground_station_end.mdl",
			transf = transf.mul(transf.rotZ(math.rad(platformAngle + 180)), transf.transl(vec3.new(halfLength, 0, 0)))
		}

		for i = 20, halfLength - 10, 10 do 
			constructionutil.addModelsAndGroups(params, generatedData["extended"], mainSubconstruction, nil, transf.mul(transf.rotZ(math.rad(platformAngle)), transf.transl(vec3.new(i, 0, 0))))
			constructionutil.addModelsAndGroups(params, generatedData["extended"], mainSubconstruction, nil, transf.mul(transf.rotZ(math.rad(platformAngle + 180)), transf.transl(vec3.new(i, 0, 0))))
		end

		local station = {
			terminals = {},
			tag = 1,
			pool = {
				edges = {},
				capacity = 0
			},
		}

		local terminal1 = {
			personEdges = { { 4, 2 }, { 4, 0 }, { 4, 1 }, },
			personNodes = { { 4, 2 }, { 4, 0 }, { 4, 1 }, },
			vehicleNode = { 6, 1 },
			transportModes = {"TRAM", "ELECTRIC_TRAM"},
		}

		terminal1.passengers = true
		terminal1.cargo = false

		local terminal2 = {
			personEdges = { { 5, 2 }, { 5, 0 }, { 5, 1 }, },
			personNodes = { { 5, 2 }, { 5, 0 }, { 5, 1 }, },
			vehicleNode = { 7, 1 },
			transportModes = {"TRAM", "ELECTRIC_TRAM"},
		}

		terminal2.passengers = true
		terminal2.cargo = false

		table.insert(station.terminals, terminal1)
		table.insert(station.terminals, terminal2)

		station.catchmentAreas = {}

		local catchmentArea = {
			position = { 0.0, 0.0, 0.0 },
			radius = 200
		}

		table.insert(station.catchmentAreas, catchmentArea)

		mainSubconstruction.station = station

		constructionutil.addStationCapacities(mainSubconstruction)
		
		local groundTexture = "::/stations/street/underground_station/underground_station.gtex"
		modulesutil.addGroundFaces(groundTexture, generatedData, mainSubconstruction)


		table.insert(result.subconstructions, mainSubconstruction)

		result.maintenanceCost = 150000
		result.cost = result.maintenanceCost * 6
		
		result.snapPoint = {
			transf = transf.transl(vec3.new(0, 8.0, 0)),

			snapToBaseEdgeTypes = {"STREET"},
			
			allowSnapToBaseEdgeEnds = true,
		}

		return result
	end
}

end
