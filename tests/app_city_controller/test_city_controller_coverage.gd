extends RefCounted
const S = preload("res://tests/app_city_controller/controller_city_support.gd")
const Core = preload("res://game/core/run_simulation.gd")
class ControlledRuntime:
	extends "res://game/app/prepared_city_runtime.gd"
	var blocked := true
	var leave_unready := false
	var refreshes := 0
	var received: Array = []
	func refresh_coverage(current_state: Dictionary, commands: Array = []) -> Dictionary:
		refreshes += 1
		received = commands.duplicate(true)
		if blocked: return {"ok":false,"error_code":"read_failed"}
		var result := super.refresh_coverage(current_state,commands)
		if leave_unready and result.get("ok",false): result.simulation._streamed = null
		return result
func run(t) -> void:
	var f := S.make(t)
	if f.is_empty(): return
	var app = f.app
	app.start_run(42)
	if app.state.is_empty():
		app.free()
		return
	# Actual Core lacks coverage after this arranged world position change.
	app.state.player.position = [1920.0,384.0]
	app.state.active_tick = 119
	app.state.survival_tick = 119
	app._last_save_tick = 119
	app._last_phase = app.state.phase
	app.state.world.origin_revision = 2147483648
	var a = app.simulation
	var before: Dictionary = app.state.duplicate(true)
	var authority: Dictionary = app.game_save.duplicate(true)
	var bytes := FileAccess.get_file_as_bytes(f.directory.path_join("game_save.json"))
	var controlled := ControlledRuntime.new(f.provider,f.disk)
	app._city_runtime = controlled
	app.input_router.set_touch_vector(Vector2.RIGHT)
	app.advance_frame(1.0/60.0)
	t.check(app.state == before and app.simulation == a,"coverage preparation failure retains complete live A and its cache")
	t.check(is_equal_approx(app._accumulator,1.0/60.0),"refused tick retains accumulator instead of consuming time")
	t.check(controlled.refreshes == 1,"world_not_ready triggers exactly one private refresh attempt")
	t.check(not controlled.received.is_empty() and controlled.received[0].origin_revision == 2147483648,"director spatial commands use untruncated current-origin stamp")
	app.advance_frame(1.0)
	t.check(controlled.refreshes == 1 and is_equal_approx(app._accumulator,1.0/60.0),"held coverage failure does not reprepare or accumulate time each frame")
	app.input_router.set_touch_vector(Vector2.LEFT)
	controlled.blocked = false
	var expected_commands: Array[Dictionary] = []
	expected_commands.assign(controlled.received)
	var expected: Dictionary = controlled.refresh_coverage(before,expected_commands)
	var expected_events: Array = expected.simulation.step(expected.state,Vector2.RIGHT,expected_commands)
	controlled.refreshes = 0
	t.check(app.ui._mode == "pause","coverage hold exposes existing explicit continue action")
	app.ui.accept_released()
	app.ui.navigate("accept")
	t.check(app.state.active_tick == 120 and app.state == expected.state,"retry uses retained input and original commands and advances exactly once")
	t.check(controlled.refreshes == 1 and app.simulation != a,"retry adopts private pair once without rebuilding for each actor")
	t.check(app.state.entities.size() == 1 and expected_commands[0].command_id in app.state.command_ids_applied,"real stamped director spawn executes once on the next tick")
	t.check(is_zero_approx(app._accumulator) and app.game_save == authority and FileAccess.get_file_as_bytes(f.directory.path_join("game_save.json")) == bytes,"coverage refresh has no save transaction or lost time")
	# A nominally prepared pair that still refuses must never cause a retry loop.
	app.simulation = Core.new(f.provider)
	controlled.leave_unready = true
	controlled.refreshes = 0
	before = app.state.duplicate(true)
	a = app.simulation
	app.advance_frame(1.0/60.0)
	t.check(controlled.refreshes == 1 and app.simulation == a and app.state == before and is_equal_approx(app._accumulator,1.0/60.0),"second refusal is bounded and preserves the fixed tick")
	t.check(app.ui._notice.text.contains("world_not_ready"),"second refusal surfaces recoverable coverage diagnostic")
	app.free()
