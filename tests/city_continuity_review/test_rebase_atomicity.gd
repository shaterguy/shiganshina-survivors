extends RefCounted
const Core = preload("res://game/core/run_simulation.gd")
const City = preload("res://game/director/streamed_chapter_provider.gd")
const H = preload("res://game/core/streamed_run_world.gd")
const S = preload("res://game/world/streamed_world.gd")
const F = preload("res://tests/core_world/new_streamed_helper_fixture.gd")
const C = preload("res://tests/core/core_fixture.gd")
func run(t) -> void:
	_failures(t)
	_stream_admission(t)
	_int64(t)
	_active_motion(t)
func _fixture() -> Dictionary:
	var provider = City.new()
	var chapter: Dictionary = provider.load_chapter("chapter_01_shiganshina").chapter
	var core = Core.new(provider)
	var state: Dictionary = core.new_run(chapter,42,C.run_config())
	state.player.position = [769.0,384.0]
	state.player.attack_ready_ticks = {"blade_slash":10000}
	return {"core":core,"state":state}
func _failures(t) -> void:
	for kind in ["origin_counter","tick_counter","stale"]:
		var f := _fixture()
		var state: Dictionary = f.state
		if kind == "origin_counter": state.world.origin_revision = 9007199254740991
		if kind == "tick_counter": state.active_tick = Core.MAX_COUNTER
		var hydration := F.hydration(H.requirements(state))
		t.check(f.core.prepare_world(state,hydration).get("ok",false),"review rollback fixture prepares: "+kind)
		var helper = f.core._streamed
		var before := state.duplicate(true)
		var view: Dictionary = f.core.world_render_view(state)
		var commands: Array = []
		if kind in ["tick_counter","stale"]:
			commands = [{"command_id":"review-spawn","kind":"spawn_enemy","origin_revision":1 if kind == "stale" else 0,"payload":{"entity_id":"review-spawn","enemy_id":"walker","position":[900.0,384.0],"spawned_tick":0}}]
		var command_before := commands.duplicate(true)
		var events := C.step(f.core,state,Vector2.RIGHT,commands)
		var status: Dictionary = f.core.step_status()
		print("REBASE_ROLLBACK ",JSON.stringify({"case":kind,"status":status,"unchanged":state == before,"helper_unchanged":f.core._streamed == helper}))
		t.check(not status.get("ok",false) and events.is_empty(),"review refusal surfaces on rebase: "+kind)
		t.check(state == before and f.core._streamed == helper and f.core.world_render_view(state) == view and commands == command_before,"review refusal preserves authority, installed geometry, commands: "+kind)
func _stream_admission(t) -> void:
	var h := H.new(F.definitions())
	var state := F.state(h)
	state.player.position = [2176.75,-618.5]
	var needed := H.requirements(state)
	var hydration := F.hydration(needed)
	var stream := S.new(h._generator,42)
	t.check(stream.prepare(needed.chunks,[],hydration,state.world.origin_chunk).get("error_code") == "outside_working_set","review legacy 4-argument admission keeps origin-centered semantics")
	t.check(stream.prepare(needed.chunks,[],hydration,state.world.origin_chunk,needed.origin_chunk).get("ok",false),"review player-centered 5-argument admission succeeds")
	var view: Dictionary = stream.render_view()
	t.check(view.origin_chunk == ["0","0"] and stream.localized_chunk("4,-1").local_origin == Vector2(3072,-768),"review admission center never substitutes geometry origin")
	t.check(stream.prepare([["9","0"]],[],{"9,0":[]},["0","0"],["9","0"]).get("error_code") == "outside_working_set" and stream.render_view() == view,"review rejected unlocalizable chunk leaves resident geometry unchanged")
	var all: Array = []
	var all_hydration := {}
	for y in range(-3,4):
		for x in range(-3,4):
			all.append([str(x),str(y)])
			all_hydration[str(x)+","+str(y)] = []
	var bounded := S.new(h._generator,42)
	t.check(bounded.prepare(all,[],all_hydration,["0","0"],["0","0"]).get("ok",false) and bounded.chunk_keys().size() == 49,"review full 7x7 admission remains exactly 49 chunks")
	var bad := all.duplicate(true)
	bad.append(["4","0"])
	t.check(not bounded.prepare(bad,[],all_hydration,["0","0"],["0","0"]).get("ok",false) and bounded.chunk_keys().size() == 49,"review a 50th out-of-window chunk cannot enter bounded cache")
func _int64(t) -> void:
	for origin in [["9223372036854775803","-9223372036854775804"],["9007199254740993","-9007199254740993"]]:
		var f := _fixture()
		f.state.world.origin_chunk = origin.duplicate()
		var hydration := F.hydration(H.requirements(f.state))
		t.check(f.core.prepare_world(f.state,hydration).get("ok",false),"review exact high int64 world prepares")
		C.step(f.core,f.state,Vector2.ZERO)
		t.check(f.core.step_status().get("ok",false) and f.state.world.origin_chunk == [str(origin[0].to_int()+1),origin[1]],"review automatic rebase preserves exact int64 origin")
func _active_motion(t) -> void:
	for scenario in ["negative_windup","negative_charge","positive_charge","boss_charge"]:
		var f := _fixture()
		var state: Dictionary = f.state
		state.player.position = [1.0,384.0] if scenario.begins_with("negative") else [766.0,384.0]
		var enemy := "boss_charger" if scenario == "boss_charge" else "runner"
		if scenario == "boss_charge": state.active_tick = 17999; state.survival_tick = 17999; state.player.attack_ready_ticks = {"blade_slash":20000}
		var command := {"command_id":"review-motion-spawn","kind":"spawn_enemy","origin_revision":0,"payload":{"entity_id":"review-motion","enemy_id":enemy,"position":[80.12345123291016,387.9876403808594] if scenario.begins_with("negative") else [655.1234741210938,387.9876403808594],"spawned_tick":0}}
		if scenario == "boss_charge": command.kind = "spawn_boss"; command.payload.erase("spawned_tick"); command.payload.boss_id = "ch01_b05"; command.payload.scheduled_tick = 18000
		var hydration := F.hydration(H.requirements(state,[command]))
		t.check(f.core.prepare_world(state,hydration,[command]).get("ok",false),"review motion fixture prepares: "+scenario)
		C.step(f.core,state,Vector2.ZERO,[command])
		t.check(state.entities.size() == 1,"review motion actor spawns: "+scenario)
		if state.entities.size() != 1: continue
		var failure := {}
		var noncanonical := {}
		var rebase_action := ""
		var move_at := 0 if scenario == "negative_windup" else (120 if scenario == "boss_charge" else 52)
		for i in 155:
			var old_revision: int = state.world.origin_revision
			var direction := Vector2.LEFT if scenario.begins_with("negative") else Vector2.RIGHT
			C.step(f.core,state,direction if i >= move_at and i < move_at+3 else Vector2.ZERO)
			if not f.core.step_status().get("ok",false):
				failure = {"kind":"tick","step":i,"status":f.core.step_status()}
				break
			if state.world.origin_revision != old_revision: rebase_action = state.entities[0].action_state
			if state.world.origin_revision == old_revision and i not in [move_at-1,move_at,move_at+5,move_at+15,154]: continue
			var restored: Dictionary = f.core.restore(JSON.parse_string(JSON.stringify(state,"",true,true)),hydration)
			if not restored.get("ok",false):
				var actor: Dictionary = state.entities[0]
				var profile: Dictionary = Core.Behaviors.profile(actor)
				var recomputed := Vector2(actor.locked_origin[0],actor.locked_origin[1])
				var delta := Vector2(actor.locked_direction[0],actor.locked_direction[1])*float(profile.get("rush_speed",0))/60.0
				for j in int(state.active_tick)-int(actor.action_started_tick)+1:
					var swept: Dictionary = f.core._streamed.sweep(recomputed,delta,float(actor.radius))
					if not swept.get("ok",false): break
					recomputed = swept.position
				failure = {"kind":"restore","step":i,"status":restored,"entity":actor,"validator_position":[recomputed.x,recomputed.y],"distance_error":Vector2(actor.position[0],actor.position[1]).distance_to(recomputed)}
				break
			if restored.state != state and noncanonical.is_empty():
				noncanonical = {"step":i,"live_entity":state.entities[0],"cold_entity":restored.state.entities[0]}
		print("REBASE_MOTION_REVIEW ",JSON.stringify({"scenario":scenario,"rebase_action":rebase_action,"failure":failure,"noncanonical":noncanonical},"",true,true))
		t.check(failure.is_empty(),"review mid-motion rebase cold-restores: "+scenario)
		t.check(noncanonical.is_empty(),"review mid-motion rebase stays canonical: "+scenario)
