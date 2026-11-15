# Act atmosphere

| Act | Soviet Decay panorama | Cue |
|---|---|---|
| I | 08 Clear Summer Day | Daylight is ready as soon as the map loads. |
| II | 07 Thunderstorm | The storm arrives behind the Act I scoreboard. One thunderclap plays when Act II starts. |
| III | 10 Nuclear Winter Ash | Intersection lamps turn on and drifting ash follows the local camera. |
| IV and later | 05 Blood Sky, Black Sun | The eclipse appears after the Act III scoreboard and stays for later Acts. Its corona is above the north-south streets. |

`scripts/act_atmosphere.gd` uses the existing replicated `WaveManager` events. Each peer applies the panorama, lighting and local effects from the same Act. Within-Act wave breaks leave the sky alone. Streetlights are part of the generated intersection lamp scene. Regenerate `scenes/map_geometry.tscn` with `python3 tools/generate_map_geometry.py` after editing its generator.
