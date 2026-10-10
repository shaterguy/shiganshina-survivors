extends RefCounted
# Real WorldView traversal with only raster emission recorded. Moving warning
# drawing back below any opaque enemy/final sprite must fail these checks.
class LayerCapture extends "res://game/presentation/world_view.gd":
	var layers: Array[String] = []
	func _draw_city() -> void: layers.append("city")
	func _draw_props() -> void: layers.append("props")
	func _draw_telegraph(_hazard: Dictionary) -> void: layers.append("warning")
	func _sprite(asset_id: String, _world: Vector2, _animation: String, _scale_value: float, _flip := false, _seconds := -1.0) -> void:
		layers.append(asset_id)
func run(t) -> void:
	var view := LayerCapture.new()
	view.load_manifest()
	var simulation = load("res://game/core/run_simulation.gd").new()
	var chapter: Dictionary = load("res://tests/core/core_fixture.gd").chapter()
	var state: Dictionary = simulation.new_run(chapter,42)
	state.phase = "evacuation"
	state.telegraphs = [{"shape":"circle","origin":[0,0],"radius":56,"active_from_tick":95}]
	state.entities = [{"id":7,"enemy_id":"walker","position":[0,0],"velocity":[0,0],"hp":100,"action_state":"move"}]
	state.rules.enemy_catalog = {"walker":{"art_id":"titan_basic"}}
	view.present(simulation.snapshot(state))
	view._draw()
	var warning := view.layers.find("warning")
	t.check(warning > view.layers.find("armored_titan"),"final armored threat cannot obscure the attack warning")
	t.check(warning > view.layers.find("titan_basic"),"ordinary enemy sprites cannot obscure the attack warning")
	t.check(warning < view.layers.find("garrison_01"),"playable soldier remains above the warning raster")
	t.check(view.layers.count("warning") == 1,"each hazard is drawn once without duplicate alpha accumulation")
	view.free()
