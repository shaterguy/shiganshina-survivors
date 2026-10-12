extends RefCounted
const Core = preload("res://game/core/run_simulation.gd")
const City = preload("res://game/director/streamed_chapter_provider.gd")
const H = preload("res://game/core/streamed_run_world.gd")
const F = preload("res://tests/core_world/new_streamed_helper_fixture.gd")
const C = preload("res://tests/core/core_fixture.gd")
func run(t) -> void:
	_drop_precision(t)
	_active_geometry(t)
func _fixture() -> Dictionary:
	var provider = City.new()
	var chapter: Dictionary = provider.load_chapter("chapter_01_shiganshina").chapter
	var core = Core.new(provider)
	var state: Dictionary = core.new_run(chapter,42,C.run_config())
	state.player.attack_ready_ticks = {"blade_slash":10000}
	return {"core":core,"state":state}
func _drop_precision(t) -> void:
	var f := _fixture()
	var state: Dictionary = f.state
	state.player.position = [769.0,384.0]
	state.drops = [{"id":1,"position":[-1.2345678806304932,384.0],"xp":1}]
	state.next_entity_id = 2
	var hydration := F.hydration(H.requirements(state))
	t.check(f.core.prepare_world(state,hydration).get("ok",false),"review drop fixture starts as an accepted full Core state")
	var before: Dictionary = f.core.restore(state,hydration)
	t.check(before.get("ok",false) and before.state == state,"review drop fixture is canonical before rebase")
	C.step(f.core,state,Vector2.ZERO)
	t.check(f.core.step_status().get("ok",false) and state.world.origin_revision == 1,"review drop tick rebases successfully")
	var restored: Dictionary = f.core.restore(JSON.parse_string(JSON.stringify(state,"",true,true)),hydration)
	print("REBASE_DROP_PRECISION ",JSON.stringify({"live_drop":state.drops,"restored_ok":restored.get("ok",false),"cold_drop":restored.get("state",{}).get("drops",[]),"equal":restored.get("state",{}) == state},"",true,true))
	t.check(restored.get("ok",false) and restored.state == state,"review rebased stationary drop is canonical under precise JSON restore")
	if restored.get("ok",false):
		var cold: Dictionary = restored.state
		var other := _fixture()
		t.check(other.core.prepare_world(cold,hydration).get("ok",false),"review cold drop world installs")
		var a := C.step(f.core,state,Vector2.ZERO)
		var b := C.step(other.core,cold,Vector2.ZERO)
		t.check(a == b and state == cold,"review rebased stationary drop cold replay equals warm state")
func _active_geometry(t) -> void:
	for enemy in ["runner","brute","sweeper","grabber"]:
		var f := _fixture()
		var state: Dictionary = f.state
		state.player.position = [740.0,384.0]
		var command := {"command_id":"review-active-spawn","kind":"spawn_enemy","origin_revision":0,"payload":{"entity_id":"review-active","enemy_id":enemy,"position":[670.2345581054688,385.1234436035156],"spawned_tick":0}}
		var hydration := F.hydration(H.requirements(state,[command]))
		t.check(f.core.prepare_world(state,hydration,[command]).get("ok",false),"review active fixture prepares: "+enemy)
		C.step(f.core,state,Vector2.ZERO,[command])
		var failure := {}
		var noncanonical := {}
		var rebase_action := ""
		for i in 145:
			var old_revision: int = state.world.origin_revision
			C.step(f.core,state,Vector2.RIGHT if i < 13 else Vector2.ZERO)
			if not f.core.step_status().get("ok",false):
				failure = {"kind":"tick","step":i,"status":f.core.step_status()}
				break
			if state.world.origin_revision != old_revision: rebase_action = state.entities[0].action_state
			var restored: Dictionary = f.core.restore(JSON.parse_string(JSON.stringify(state,"",true,true)),hydration)
			if not restored.get("ok",false):
				failure = {"kind":"restore","step":i,"status":restored,"entity":state.entities[0]}
				break
			if restored.state != state and noncanonical.is_empty():
				noncanonical = {"step":i,"live_entity":state.entities[0],"cold_entity":restored.state.entities[0],"live_hazards":state.telegraphs,"cold_hazards":restored.state.telegraphs}
		print("REBASE_ACTIVE_REVIEW ",JSON.stringify({"enemy":enemy,"rebase_action":rebase_action,"failure":failure,"noncanonical":noncanonical},"",true,true))
		t.check(failure.is_empty(),"review active attack remains cold-restorable across rebase: "+enemy)
		t.check(noncanonical.is_empty(),"review active attack remains canonical across rebase: "+enemy)
