extends RefCounted
const H = preload("res://game/core/streamed_run_world.gd")
const F = preload("res://tests/core_world/new_streamed_helper_fixture.gd")
func run(t) -> void:
	_automatic_rebase(t)
	_inactive_attack_anchors(t)
	_active_anchors(t)
	_active_anchors(t,true)
	_many_chunks(t)
	var helper := H.new(F.definitions())
	var state := F.state(helper)
	state.player.position = [2176.75,-618.5]
	var needed := H.requirements(state)
	t.check(needed.get("ok",false),"G1 minimal: requirements admit the native refused player position")
	if not needed.get("ok",false): return
	t.check(needed.origin_chunk == ["2","-1"] and ["4","-1"] in needed.chunks,"G1 minimal: view needs absolute chunk 4 while authority is still at origin 0")
	var prepared := helper.prepare(state,F.hydration(needed))
	print("CITY_CONTINUITY_DIAG ",JSON.stringify({"stage":"prepare","player":state.player.position,"authority_origin":state.world.origin_chunk,"needed_origin":needed.origin_chunk,"result":prepared}))
	t.check(prepared.get("ok",false),"G1 minimal: admitted verified terrain must prepare beyond original-origin window")

const Core = preload("res://game/core/run_simulation.gd")
const City = preload("res://game/director/streamed_chapter_provider.gd")
const C = preload("res://tests/core/core_fixture.gd")
class FailingMoveHelper:
	extends "res://game/core/streamed_run_world.gd"
	var armed := false
	func fresh():
		var result := FailingMoveHelper.new(_definitions)
		result.armed = armed
		return result
	func move(position: Vector2, delta: Vector2, radius: float) -> Dictionary:
		return _query_result(failure("read_failed")) if armed else super.move(position,delta,radius)
func _automatic_rebase(t) -> void:
	var provider := City.new()
	var chapter: Dictionary = provider.load_chapter("chapter_01_shiganshina").chapter
	var core := Core.new(provider,FailingMoveHelper.new(chapter.world_definitions))
	var state := core.new_run(chapter,42,C.run_config())
	state.player.position = [1152.0,384.0]
	state.player.attack_ready_ticks = {"blade_slash":10000}
	var command := {"command_id":"continuity-spawn","kind":"spawn_enemy","origin_revision":0,"payload":{"entity_id":"continuity-walker","enemy_id":"walker","position":[1452,384],"spawned_tick":0}}
	var commands: Array[Dictionary] = [command]
	var original_commands := commands.duplicate(true)
	var hydration := F.hydration(H.requirements(state,commands))
	t.check(core.prepare_world(state,hydration,commands).get("ok",false),"boundary control prepares real Core and incoming spatial command")
	var before := state.duplicate(true)
	var old_helper = core._streamed
	old_helper.armed = true
	t.check(core.step(state,Vector2.RIGHT,commands).is_empty() and core.step_status().get("error_code") == "read_failed","late physical query failure is visible during rebase transaction")
	t.check(state == before and core._streamed == old_helper and commands == original_commands,"failed rebase tick preserves complete state, installed helper and caller command")
	old_helper.armed = false
	core.step(state,Vector2.RIGHT,commands)
	t.check(core.step_status().get("ok",false) and state.active_tick == 1,"verified rebase retry advances exactly one tick")
	t.check(state.world.origin_chunk == ["1","0"] and state.world.origin_revision == 1 and state.player.position == [386.5,384.0],"successful tick atomically rebases origin, revision and local player")
	t.check(commands == original_commands and state.entities.size() == 1 and state.entities[0].position[0] < 684,"rebase translates private command once and leaves caller input unchanged")
	t.check(state.escape_zone == [0.0,0.0,0.0,0.0],"automatic city rebase preserves inactive exit sentinel")
	var canonical: Dictionary = core.restore(JSON.parse_string(JSON.stringify(state,"",true,true)),hydration)
	t.check(canonical.get("ok",false) and canonical.state == state,"rebased actual Core state survives precise JSON cold restore")
	var installed = core._streamed
	for i in 5: core.step(state,Vector2.ZERO,[])
	t.check(core._streamed == installed and state.world.origin_revision == 1,"ordinary ticks reuse the same helper and do not rebase again")

func _inactive_attack_anchors(t) -> void:
	var helper := H.new(F.definitions())
	var state := F.state(helper)
	state.world.origin_chunk = ["3","0"]
	state.player.position = [770.0,384.0]
	state.entities = [{"position":[-1053.4945068359375,353.3705749511719],"radius":18,"speed":28,"action_state":"move","locked_origin":[-1345.29736328125,298.80206298828125],"locked_target":[-1620,384]}]
	var required := H.requirements(state)
	t.check(required.get("ok",false),"inactive move-state attack history cannot request distant terrain")
	state.entities[0].locked_target = [NAN,384]
	t.check(H.requirements(state).get("error_code") == "invalid_snapshot","inactive anchors remain structurally validated")
	state.entities[0].locked_target = [-1620,384]
	state.entities[0].action_state = "windup"
	t.check(H.requirements(state).get("error_code") == "outside_working_set","active attack anchors still require complete physical coverage")

func _active_anchors(t, with_boost := false) -> void:
	var provider := City.new()
	var chapter: Dictionary = provider.load_chapter("chapter_01_shiganshina").chapter
	var core := Core.new(provider)
	var state := core.new_run(chapter,42,C.run_config())
	# Keep the supported optional-field-absent checkpoint as the independent
	# locked-anchor control, then run the same runner against genuine v2 boost
	# and the normal caller's hydration/retry boundary. Neither is a synthetic
	# injected movement phase or a claim of captured historical provenance.
	if not with_boost: state.erase("player_mobility")
	state.player.position = [384.0,384.0]
	state.player.attack_ready_ticks = {"blade_slash":10000}
	var command := {"command_id":"active-anchor-spawn","kind":"spawn_enemy","origin_revision":0,"payload":{"entity_id":"active-runner","enemy_id":"runner","position":[500,384],"spawned_tick":0}}
	var hydration := F.hydration(H.requirements(state,[command]))
	t.check(core.prepare_world(state,hydration,[command]).get("ok",false),"active anchor fixture is fully verified")
	var admitted: Dictionary = core.restore(state,hydration)
	t.check(admitted.get("ok",false) and admitted.get("state",{}).has("player_mobility") == with_boost,"anchor fixture explicitly admits its selected optional-mobility checkpoint shape")
	C.step(core,state,Vector2.ZERO,[command])
	t.check(state.entities.size() == 1 and state.entities[0].action_state == "windup","real runner enters its authored attack")
	if state.entities.is_empty(): return
	var anchors := [state.entities[0].locked_origin.duplicate(),state.entities[0].locked_target.duplicate()]
	var observed := {}
	var saw_boost := false
	var coverage_refreshes := 0
	for i in 100:
		var action: String = state.entities[0].action_state
		if action == "move": break
		observed[action] = true
		t.check([state.entities[0].locked_origin,state.entities[0].locked_target] == anchors,"active attack/recovery anchors remain immutable: "+action)
		var before: Dictionary = core.snapshot(state)
		var before_tick: int = state.active_tick
		C.step(core,state,Vector2.LEFT*0.1)
		if not core.step_status().get("ok",false):
			t.check(core.step_status().get("error_code") == "world_not_ready" and state == before,"boost coverage refusal preserves the entire pre-tick authority")
			if core.step_status().get("error_code") != "world_not_ready": break
			var needed: Dictionary = H.requirements(state)
			hydration = F.hydration(needed)
			var prepared: Dictionary = core.prepare_world(state,hydration)
			t.check(needed.get("ok",false) and prepared.get("ok",false),"genuine boost refreshes newly required runner/route coverage")
			if not prepared.get("ok",false): break
			coverage_refreshes += 1
			C.step(core,state,Vector2.LEFT*0.1)
		saw_boost = saw_boost or state.get("player_mobility",{}).get("phase") == "boost"
		t.check(core.step_status().get("ok",false) and state.active_tick == before_tick+1,"locked-anchor invariant advances a real accepted tick exactly once: "+action)
		if state.active_tick != before_tick+1: break
	t.check(observed.has_all(["windup","attack","recover"]),"immutable anchor check crosses real windup, attack and recovery")
	if with_boost:
		t.check(saw_boost and coverage_refreshes > 0,"runner locked-anchor invariant crosses genuine v2 activation and terrain refresh")
	hydration = F.hydration(H.requirements(state))
	var cold := Core.new(provider)
	var restored: Dictionary = cold.restore(JSON.parse_string(JSON.stringify(state,"",true,true)),hydration)
	t.check(restored.get("ok",false) and restored.get("state",{}) == state and cold.prepare_world(restored.get("state",{}),hydration).get("ok",false),"active motion remains exactly cold-restorable after city anchor maintenance")

func _many_chunks(t) -> void:
	var provider := City.new()
	var chapter: Dictionary = provider.load_chapter("chapter_01_shiganshina").chapter
	var core := Core.new(provider)
	var state := core.new_run(chapter,42,C.run_config())
	# The exact 13-rebase oracle intentionally measures 4000 normal 2.5px
	# steps, using the supported optional-mobility-absent checkpoint shape.
	# Boost distance/rebase replay has its own genuine corridor regression.
	state.erase("player_mobility")
	state.player.position = [384.0,384.0]
	state.world.origin_chunk = ["9007199254740993","-9007199254740994"]
	var hydration := F.hydration(H.requirements(state))
	t.check(core.prepare_world(state,hydration).get("ok",false),"multi-chunk control retains exact int64 addresses")
	var admitted: Dictionary = core.restore(state,hydration)
	t.check(admitted.get("ok",false) and not admitted.get("state",{}).has("player_mobility"),"fixed-speed address fixture explicitly admits the optional-mobility-absent checkpoint")
	var max_resident := 0
	var failed := {}
	for i in 4000:
		C.step(core,state,Vector2.RIGHT)
		if not core.step_status().get("ok",false):
			var needed := H.requirements(state)
			if core.step_status().get("error_code") != "world_not_ready" or not needed.get("ok",false):
				failed = core.step_status()
				break
			hydration = F.hydration(needed)
			var prepared := core.prepare_world(state,hydration)
			if not prepared.get("ok",false):
				failed = prepared
				break
			C.step(core,state,Vector2.RIGHT)
		max_resident = maxi(max_resident,int(core.world_status().resident_chunks))
	t.check(failed.is_empty() and state.active_tick == 4000,"unbounded city travel crosses old eight-chunk limit without a refused tick: "+str(failed))
	t.check(state.world.origin_chunk == ["9007199254741006","-9007199254740994"] and state.player.position == [400.0,384.0],"13 sequential rebases preserve exact absolute position beyond JSON-safe integer addresses")
	t.check(max_resident <= 49 and core.world_status().resident_hydration <= 49,"long travel keeps derived geometry and hydration bounded")
	var cold := Core.new(City.new())
	var restored := cold.restore(JSON.parse_string(JSON.stringify(state,"",true,true)),hydration)
	t.check(restored.get("ok",false) and cold.prepare_world(restored.get("state",{}),hydration).get("ok",false),"multi-chunk JSON cut installs an independent cold world")
	if not restored.get("ok",false): return
	for i in 12:
		var left := C.step(core,state,Vector2.LEFT)
		var right := C.step(cold,restored.state,Vector2.LEFT)
		t.check(left == right and state == restored.state,"warm/cold replay agrees after long absolute-address travel")
