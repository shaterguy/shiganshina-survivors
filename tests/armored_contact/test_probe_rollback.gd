extends RefCounted
const R = preload("res://tests/armored_actor/test_armored_rebase.gd")
const S = preload("res://tests/armored_actor/armored_support.gd")
const H = preload("res://game/core/streamed_run_world.gd")
class FaultProbe:
	extends "res://game/core/streamed_run_world.gd"
	var armed := false
	func props_query(rectangle: Rect2) -> Dictionary:
		if armed: return _query_result(failure("world_not_ready"))
		return super.props_query(rectangle)
func run(t) -> void:
	var f := R.new()._make(t)
	if f.is_empty(): return
	t.check(R.new()._until(f,"attack"),"late shoulder-probe failure starts in real active charge")
	var core := S.Core.new(f.provider,FaultProbe.new(f.chapter.world_definitions))
	t.check(core.prepare_world(f.state,f.core._streamed._hydration).get("ok",false),"fault-probe uses same actual city geometry and valid charge state")
	f.core = core
	var before: Dictionary = f.state.duplicate(true)
	core._streamed.armed = true
	var events := S.step(f)
	t.check(events.is_empty() and f.state == before and core._final_sweeps.is_empty() and core.step_status().get("error_code") == "world_not_ready","probe query after body sweep atomically rolls back clock/state/damage/witness")
	core._streamed.armed = false
	S.step(f)
	t.check(f.state.active_tick == before.active_tick+1 and core.step_status().get("ok",false),"probe query recovery retries one original tick")
