-- Game script that gives underground stops built before the mod was installed the settings slot (see
-- settings_slot.script.lua). Without it they never show the Configure button.
function data()
	return {
		guiUpdateScript = {
			fileName = "settings_slot.script@guiUpdate",
		},
	}
end
