extends RefCounted
# Run ONLY in helper-counter isolated QA trees. No timing from this suite.
# Baseline and candidate both parse: candidate detection uses property metadata.
const Support = preload("res://tests/readiness_reuse/readiness_support.gd")
const Query = preload("res://game/combat/enemy_world_query.gd")
var support := Support.new()

func run(t) -> void:
	for roles in [[],["grabber"],["grabber","quadruped","stone_thrower"]]:
		await _case(t,roles)
	await _case(t,["grabber"],true)

func _case(t,roles: Array, absent_mobility := false) -> void:
	var app = support.make(t,"counts_"+str(roles.size()),roles)
	if app == null: return
	var core = app.simulation
	if absent_mobility: app.state.erase("player_mobility")
	var helper = core._streamed
	var injected: bool = support.has_property(helper,"qa_readiness_calls")
	t.check(injected,"READINESS COUNT requires exact-source QA counter, never subclass instrumentation")
	if not injected: await support.dispose(t,app); return
	var candidate: bool = support.has_property(core,"_role_batch_tick")
	t.check(core.get_script() == load("res://game/core/run_simulation.gd") and helper.get_script() == load("res://game/core/streamed_run_world.gd") and helper._world.get_script() == load("res://game/world/cached_streamed_world.gd"),"READINESS COUNT exercises exact native Core/helper/world scripts")
	var commands: Array[Dictionary] = []
	for index in 2:
		support.reset_count(helper)
		var before: int = int(app.state.active_tick)
		core.step(app.state,Vector2.ZERO,commands)
		var status: Dictionary = core.step_status()
		t.check(status.get("ok",false) and int(app.state.active_tick) == before+1,"READINESS COUNT ordinary tick commits")
		t.check(core._streamed == helper and not status.get("population",{}).get("changed",true) and status.get("rebase_motion",[]).is_empty(),"READINESS COUNT fixture truly has same helper, unchanged population and no rebase")
		var expected := 1 if roles.is_empty() or candidate else 2
		t.check(support.counts(helper) == expected,"READINESS COUNT exact live-role duplicate changes 2 to 1; role count="+str(roles.size())+" expected="+str(expected)+" actual="+str(support.counts(helper)))
		if roles.is_empty():
			t.check(core._role_tick_query == null,"READINESS COUNT no live role allocates no role query")
		else:
			t.check(core._role_tick_query != null,"READINESS COUNT live roles share one bound query")
			if core._role_tick_query != null:
				var calls: int = support.counts(helper)
				t.check(core._role_query(core._role_tick_state) == core._role_tick_query and support.counts(helper) == calls,"READINESS COUNT remaining same-state role users reuse the same cached query")
		if candidate:
			t.check(core.get("_role_batch_tick") == -1 and core.get("_role_batch_helper_id") == 0,"READINESS COUNT per-call scalar markers are consumed before return")
		print("READINESS_COUNT_ROW ",JSON.stringify({"candidate":candidate,"roles":roles.size(),"absent_mobility":absent_mobility,"tick":app.state.active_tick,"readiness_calls":support.counts(helper),"expected":expected},"",true,true))
	# Public construction always pays full readiness even in the candidate tree.
	support.reset_count(helper)
	var public_query = Query.for_streamed(helper,app.state)
	t.check(public_query.status().get("ok",false) and support.counts(helper) == 1,"READINESS COUNT public for_streamed keeps original full readiness")
	await support.dispose(t,app)
