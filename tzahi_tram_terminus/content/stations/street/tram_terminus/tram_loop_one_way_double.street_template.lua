-- One-way tram track for the turnaround loop, based on the base tram track (tram_new).
-- It keeps tram_new's two lanes, so it joins the two-way stub at the fork (in game, a single-lane one-way loop
-- won't build there) and the whole loop gets the wide tunnel. Being one-way, trams never meet oncoming trams.
-- The loop is built backwards with both lanes running backwards (trams still go the same way round): built
-- forwards, trams switched tracks at the fork; built backwards they keep to one track (the inner one) all the way.
-- Neither an empty lane nor a slow lane could make them use the outer one instead (seen in game).
function data()
return { 
		availability = {
			yearFrom = 1925,
			yearTo = 0,
			notifyWhenAvailable = false,
		},
		borderGroundTex = "::/infrastructure/street/shared/street_border.gtex",
		cost = 120,
		country = true,
		description = { 
			description = _("One-way double tram track used by tram turning loops."),
			icon = "::/infrastructure/street/tram/tram_new.tga",
			name = _("Tram Loop Track (Double)"),
			previewIcon = "::/infrastructure/street/tram/tram_new_preview.tga",
		},
		emissions = { 
			noise = 0,
			pollution = 0,
			pollutionRadius = 0,
			radius = 0,
		},
		fillGroundTex = "::/infrastructure/street/shared/street_fill.gtex",
		laneConfigs = {
			{
				-- both lanes have to carry trams: at the fork the loop only builds when both tram tracks of the stub
				-- continue (seen in game)
				forward = false,
				height = 0,
				offset = -0.25,
				speed = 27.77777862548828125,
				transportModes = { "TRAM", "ELECTRIC_TRAM", },
				width = 5.5,
			},
			{
				forward = false,
				height = 0,
				offset = 0.25,
				speed = 27.77777862548828125,
				transportModes = { "TRAM", "ELECTRIC_TRAM", },
				width = 5.5,
			},
		},
		maintenanceCost = 20,
		-- empty menu category keeps it out of the build menu (not initiallyLocked: locked types can't be built by players)
		menuCategory = { categories = {} },
		modifiers = { 
			maxSpeedModifier = 0,
			noiseModifier = 0,
			pollutionModifier = 0,
		},
		priority = 100,
		roadType = "STREET",
		sidewalkFillGroundTex = "::/infrastructure/street/shared/street_sidewalk_fill.gtex",
		streetStyle = "::/infrastructure/street/tram/tram_new.street",
		transportModesStreet = { "TRAM", "ELECTRIC_TRAM", },
		builderAudioRes = "::/gui/construction/sound/buildoze_street.builder_audio",
	}
end
