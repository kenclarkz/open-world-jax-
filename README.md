# open-world-jax-

A Godot 4 open-world walking/driving game prototype set in **downtown Jacksonville,
Florida**, generated on the fly from real, freely available geographic data
(OpenStreetMap + terrain elevation).

The game ships with a built-in **playable prototype district** (downtown JAX with
real street names, Hemming Park and the St. Johns River) so it runs with **zero
downloads**. Drop in real OSM/elevation files and the same code rebuilds the city
from data instead.

## Requirements

- Godot 4.2+ (verified with 4.2.2 stable). Import the project folder in the
  Godot editor and press **Play** (F5), or run headless:
  `godot --headless --path .`
- A GPU normally; built entirely with built-in Godot nodes (no add-ons).

## Playing

| Key | Action |
| --- | --- |
| `W/A/S/D` | Walk (third person) |
| `Shift` | Run |
| `Space` | Jump |
| `E` | Get in / out of a car (cars are marked `car` group) |
| `W/S` + `A/D` | Drive (forward/back, steer) when in a vehicle |
| `Space`/`Shift` in car | Brake / handbrake |
| `R` | Re-orient camera behind player |
| `F5` / `F9` | Save / load game (position + vehicle state) |
| `Esc` | Toggle mouse capture |

The world is streamed in **500 m tiles** around the player (`TileStreamer`), so
geometry, traffic, pedestrians and the day/night + weather systems only update
near you.

## How the pipeline works

```
OSM (XML or Overpass JSON) ──► OSMImporter ──► OsmData (projected to local XZ)
                                                       │  cached to .tres
Elevation (.asc heightmap) ──► ElevationImporter ──► heightmap ─┐
                                                       │         │
WorldGenerator.build_tile ──► terrain + roads + buildings + parks + water
TileStreamer (500m tiles) ──► always keeps a 3-tile radius around the player
```

- Coordinates are **equirectangular-projected** with the game origin at
  Jacksonville city center (30.3322° N, 81.6557° W); `X` = east, `Z` = south.
- The first import writes a binary cache (`.tres`) next to the source file, and
  subsequent launches load that instead of re-parsing (fast for a whole city).

## Getting real Jacksonville data

Drop files into the project's user data folder
`user://` (Linux: `~/.local/share/godot/app_userdata/OpenWorld JAX/`). The game
checks exactly these paths:

| File | Purpose |
| --- | --- |
| `jax_data/osm/jacksonville.osm` | OSM XML extract (road/building/park/water/POI geometries) |
| `jax_data/osm/jacksonville.json` | same data as Overpass JSON (used if `.osm` absent) |
| `jax_data/elevation/jacksonville.asc` | ESRI ASCII Grid heightmap |

### Option A – OSM via Overpass (easiest)

You can use [Overpass Turbo](https://overpass-turbo.eu/) (Export → download the
raw `data`), or query the API directly with e.g. `curl`. The importer reads the
Overpass JSON format (`out body`). Query in this order and merge, or just run it
once with all clauses:

```
[out:json][timeout:120];
(
  way["highway"](30.15,-81.75,30.45,-81.55);
  way["building"](30.15,-81.75,30.45,-81.55);
  way["leisure"~"park|garden"](30.15,-81.75,30.45,-81.55);
  way["natural"~"water|coastline|riverbank"](30.15,-81.75,30.45,-81.55);
  node["amenity"](30.15,-81.75,30.45,-81.55);
); out body;
```

Save the response as `user://jax_data/osm/jacksonville.json`.

`osmium`/`JOSM` users: export the same bbox as `.osm` XML and save it as
`jacksonville.osm` instead.

### Option B – OSM via Geofabrik (bigger city, offline)

1. Download the Florida extract:
   <https://download.geofabrik.de/north-america/us/florida.html>
2. Crop Jacksonville's bbox (30.15, -81.75 to 30.45, -81.55) with osmium:

   ```
   osmium extract -b 30.15,-81.75,30.45,-81.55 \
     florida-latest.osm.pbf -o jacksonville.osm.pbf
   osmium export jacksonville.osm.pbf -f osm -o jacksonville.osm
   ```

   (or use `osmosis --bounding-box ...` / `osmium tags-filter --expressions`).
3. Save as `user://jax_data/osm/jacksonville.osm`.

### Terrain elevation (optional)

Jacksonville is nearly flat, so the built-in generated terrain is fine by
default. For the real ground truth:

- <https://portal.opentopography.org> → **SRTM 1-arcsecond (~30 m)** or
  **USGS 3DEP** around 30.3, -81.65, download the GeoTIFF and convert to an
  ESRI ASCII grid (`.asc`) in QGIS / GDAL:
  `gdal_translate -of AAIGrid tile.tif jacksonville.asc`
- Save as `user://jax_data/elevation/jacksonville.asc`.

The heightmap is read top-down (row 0 = north) and approximated to the city
center; the underlying grid needs to cover the Jacksonville area.

## Project structure

```
import_data/osm/sample.osm    sample extract used to validate the importer
scenes/                       Main, Player, Vehicle, TrafficCar, Pedestrian
scripts/
  gis/        OsmData + OsmRoad/Building/Park/WaterBody/PoI, OSMImporter,
              ElevationImporter, GeoUtils (projection)
  procgen/    ProceduralGen (meshes, ear-clipping triangulation), PrototypeGen
              (built-in downtown district)
  streaming/  TileStreamer
  world/      World (autoload), WorldGenerator (per-tile builder), Main
  player/     Player (third-person CharacterBody3D)
  vehicles/   Vehicle (arcade style car), TrafficCar (AI road followers)
  npc/        Pedestrian (random walkers)
  systems/    DayNight, Weather, Game (autoload: save/load)
  ui/         HUD, Minimap (renders the road network to a cached texture)
project.godot autoloads (Game, World, TileStreamer, OSMImporter, ProceduralGen)
              + full input map
```

## Notes

- First launch (or when the cached `.tres` is deleted) re-parses the OSM file;
  watch the console for `[OSMImporter] Importing ...`.
- `sample.osm` / `sample.json` in `import_data/osm/` come from the repo and
  double as import smoke tests.