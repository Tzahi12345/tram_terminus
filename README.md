# Underground Tram Turnaround

A Transport Fever 3 mod that lets tram lines end at an underground stop, without building a separate turnaround.

It adds a **Turnaround** option to the base game underground stop. Pick an end, and the stop closes that end and builds a one-way turning loop of underground track past it: both tracks continue in one wide tunnel, which forks into the loop. Trams arrive, go round the loop and leave on the other platform.

## How to use

Works on new stops and on stops you already placed:

1. Select the underground stop and click **Configure** (the wrench button in the station window).
2. Set **Turnaround**:
   - **Off**: the normal stop, with track at both ends.
   - **End 1** / **End 2**: trams turn past that end. Pick the end with **no track connected**; if nothing changes, that end has track on it, so try the other one.
   - **Show end 1**: the normal stop with a floating arrow above end 1, to see which end is which. Switch it off afterwards.
3. Set **Loop Radius** (10 to 30 m). Smaller loops need less room.

Changes apply immediately (the Configure panel shows no preview). Press **G** for underground view to see the loop. If there isn't room for the loop, nothing changes.

Room needed past the end of the platforms:

| Loop Radius | Length | Width |
|---|---|---|
| 10 m | ~40 m | ~20 m |
| 15 m | ~55 m | ~30 m |
| 30 m | ~100 m | ~60 m |

## Good to know

- The loop is one-way, so trams never meet oncoming trams in it. It has two tracks (so it fits the wide tunnel), and trams use one of them.
- Stops keep their shape until they are rebuilt: changing any setting rebuilds a stop.
- **Removing the mod** from a save with turnarounds: the stops go back to normal stops when rebuilt, but the loop track uses a track type from this mod. Back up your save first.

## Repository layout

```
tzahi_tram_terminus/      the mod folder (this is what goes into the game / onto mod.io)
  mod.json                mod id, revision, run script
  _metadata/modinfo.json  name, description, tags
  content/
    mod.script.lua        adds the settings to the base underground stop as it loads
    stations/street/tram_terminus/
      tram_terminus.script.lua                     builds the stop, the loop and the end marker
      turnaround_params.lua                        the Turnaround and Loop Radius settings
      tram_loop_one_way_double.street_template.lua the one-way loop track
```

To develop it, link the mod folder into the game's staging area (Windows, PowerShell):

```powershell
New-Item -ItemType Junction -Path "<Steam>\userdata\<your Steam ID>\3493540\local\staging_area\tzahi_tram_terminus" -Target "<this repo>\tzahi_tram_terminus"
```

The game reloads staged mods when you return to the main menu, but construction scripts and track types are only read when a game is loaded. The game log is `<Steam>\userdata\<your Steam ID>\3493540\local\crash_dump\stdout.txt`.

## Credits

By Tzahi. Based on the base game underground stop by Urban Games.
