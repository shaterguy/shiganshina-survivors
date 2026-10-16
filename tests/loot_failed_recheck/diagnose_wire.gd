extends SceneTree
const Wire = preload("res://tests/app_async_autosave/test_wire_authority.gd")
const Final = preload("res://tests/final_runtime/final_support.gd")
const Loot = preload("res://game/loot/loot_rules.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok: failures += 1
	print("WIRE_CHECK ",ok," ",message)
func _init() -> void:
	call_deferred("run")
func run() -> void:
	var app = Wire.new()._fixture(self,"wire_diagnostic")
	if app == null: quit(2); return
	app.state.active_tick = 107999
	app.state.survival_tick = 107999
	var stepped: Dictionary = app._step_city_tick()
	print("WIRE_STEP ",JSON.stringify(stepped)," loot=",JSON.stringify(app.state.get("loot",{})))
	var original: Dictionary = app.simulation.restore(app.state,app.simulation._streamed._hydration)
	print("WIRE_BEFORE_INTEGER ",JSON.stringify({"ok":original.get("ok"),"error_code":original.get("error_code"),"errors":original.get("errors"),"loot_valid":Loot.validate(app.state),"world_query":app.simulation._streamed.query_status()}))
	if app.state.telegraphs.size() == 1:
		for field in ["damage","length","width"]: app.state.telegraphs[0][field] = int(app.state.telegraphs[0][field])
		var checked: Dictionary = app.simulation.restore(app.state,app.simulation._streamed._hydration)
		print("WIRE_AFTER_INTEGER ",JSON.stringify({"ok":checked.get("ok"),"error_code":checked.get("error_code"),"errors":checked.get("errors"),"loot_valid":Loot.validate(app.state),"state":app.state}))
	app.free()
	var fixture: Dictionary = Final.make(self,"",false)
	if not fixture.is_empty():
		Final.boundary(fixture)
		print("FINAL_BOUNDARY_PREPARED ",JSON.stringify({"tick":fixture.app.state.active_tick,"phase":fixture.app.state.phase,"city_error":fixture.app._city_step_error,"final_error":fixture.app._final_error,"loot_valid":Loot.validate(fixture.app.state),"selected":fixture.app.state.world.evacuation}))
		fixture.app.free()
	print("DIAGNOSTIC_COMPLETE ",JSON.stringify({"fixture_failures":failures}))
	quit(0)
