class_name CoreEnvSource
extends Node
## The sea renderer's environment source (the SeaEnvSource calls) on a CoreSimSource, for the Sea node's
## `source`: wave components, exposure, wind state with the live puff patches and the current, straight from the
## core world the boats sail in.

var sim: CoreSimSource


func sea_components() -> Array:
	return sim.sea_components()


func sea_exposure() -> Dictionary:
	return sim.sea_exposure()


func wind_state(t_ms: float) -> Dictionary:
	return sim.wind_state(t_ms)


func current_at(x: float, y: float, t_ms: float) -> Vector2:
	return sim.current_at(x, y, t_ms)


## wind.md §8 the venue's land-effect wind field as the venue file holds it ({grid, sectors}, data_format.md
## §6.2), {} without a venue or a field. The Sea draws its speed factor (water_render.md §4.3).
func venue_wind_field() -> Dictionary:
	return SeaEnvSource.read_wind_field(sim.venue_path)
