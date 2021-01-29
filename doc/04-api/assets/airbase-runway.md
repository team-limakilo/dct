## Runway Geometry Database

There exist data files, one per map, that contain various airbase geometry
data.  This data is generated periodically by a special DCS hook and mission
that accesses the Terrain module to export information about various airbases.

The storage format is json and each map database is stored in
`<mod-root>/dct/data/airbases/<mapname>.json`.

The data format is the following:

```
{
 "<airbase-name>":{airbase-data},
}
```

Where `<airbase-name>` is the name of an airbase as accessable by
`Airbase.getByName(name)` and `airbase-data` is a json table conforming to
the below definition:

```
{
"runways": [
	{
		"name": edge1name.."_"..edge2name,
		"geometry": {
			"A":{x:edge1x, y:edge1y},
			"B":{calculated},
			"C":{x:edge2x, y:edge2y},
		},
	},],
}
```

## Generating Runway Geometry

Generating runway geometry can be done via a hook and a mission that sets a
single named flag "DCT_TERRAIN_EXPORT", when this flag is true the hook,
available at `<mod-root>/hooks/dct-terrain-export.lua`, will export the needed
terrain information to a file located at
`<dcs-saved-games>/Logs/<theater-name>.json`

Some rought pesudo code for accessing and exporting the Terrain data is
as follows:

```
if _G.Terrain == nil then
	_G.Terrain = require "terrain"
end
local json = require("libs.json")

local function calculateB(A, C, theta)
end

local airbases = {}
for _, ab in pairs(Terrain.GetTerrainConfig("Airdromes")) do
	local airbase = {}
	airbase.name = ab.id
	airbase.runways = {}
	for _, rwy in pairs(Terrain.getRunwayList(ab.roadnet)) do
		local runway = {}
		runway.name = rwy.edge1name.."_"..rwy.edge2name
		runway.geometry = {
			["A"] = { x = rwy.edge1x, y = rwy.edge1y },
			["C"] = { x = rwy.edge2x, y = rwy.edge2y },
		}
		runway.geometry.B = calculateB(runway.geometry.A,
					runway.geometry.C, rwy.course)
		airbase.runways[runway.name] = runway
	end
end

-- export data
f.write(json:export_pretty(airbases))
```


```
local airdromes = Terrain.GetTerrainConfig("Airdromes")
local ryws = Terrain.getRunwayList(airdromes[22].roadnet)

This example would be for Batumi I think. The content of rwys is in this example:
{ {
    course = -0.95011871958868,
    edge1name = "31",
    edge1x = -356412.75,
    edge1y = 618228.3125,
    edge2name = "13",
    edge2x = -355208.625,
    edge2y = 616544.0625
  } }

Look into `Mods\terrains\Caucasus\AirfieldsCfgs` there is a config per
airfield, looks similar to the below:
Airdromes[22] = {
    id = "Batumi",
    code = "UGSB",
    class = "2",
    civilian = true,
    abandoned = false,
    display_name = _("Batumi"),
    names = { en = "Batumi", },
    reference_point = { x = 0, y = 0 },
    roadnet = dir.."AirfieldsTaxiways/Batumi.rn4",
    roadnet5 = dir.."AirfieldsTaxiways/Batumi.rn5",
}

All the available Terrain functions:
  Terrain = <8278>{
    Create = <function 6277>,
    FindNearestPoint = <function 6278>,
    FindOptimalPath = <function 6279>,
    GetHeight = <function 6280>,
    GetMGRScoordinates = <function 6281>,
    GetSeasons = <function 6282>,
    GetSurfaceHeightWithSeabed = <function 6283>,
    GetSurfaceType = <function 6284>,
    GetTerrainConfig = <function 6285>,
    Init = <function 6286>,
    InitLight = <function 6287>,
    Release = <function 6288>,
    convertLatLonToMeters = <function 6289>,
    convertMGRStoMeters = <function 6290>,
    convertMetersToLatLon = <function 6291>,
    findPathOnRoads = <function 6292>,
    getBeacons = <function 6293>,
    getClosestPointOnRoads = <function 6294>,
    getClosestValidPoint = <function 6295>,
    getCrossParam = <function 6296>,
    getObjectPosition = <function 6297>,
    getObjectsAtMapPoint = <function 6298>,
    getRadio = <function 6299>,
    getRunwayHeading = <function 6300>,
    getRunwayList = <function 6301>,
    getStandList = <function 6302>,
    getTechSkinByDate = <function 6303>,
    getTempratureRangeByDate = <function 6304>,
    isVisible = <function 6305>
  },
```

## Tasks

- [ ] define a database format for runway data
- [ ] create tool to export and preprocess airbase data
- [ ] Caucasus: runway geometry
- [ ] Nevada: runway geometry
- [ ] Normandy: runway geometry
- [ ] Persian Gulf: runway geometry
- [ ] Channel: runway geometry
- [ ] Syria: runway geometry
