extends RefCounted
# Candidate-only unchanged-product contracts. Custom classes intentionally test
# extension fallback; they are NEVER used as evidence for native call savings.
const Support = preload("res://tests/readiness_reuse/readiness_support.gd")
const Core = preload("res://game/core/run_simulation.gd")
const Helper = preload("res://game/core/streamed_run_world.gd")
const Query = preload("res://game/combat/enemy_world_query.gd")
const Legacy = preload("res://game/core/legacy_player_mobility_v1.gd")
var support := Support.new()

class CustomCore:
	extends "res://game/core/run_simulation.gd"
	var calls := 0
	var offered_marker := 0
	func _step_running(state: Dictionary, move: Vector2, commands: Array[Dictionary]) -> Array[Dictionary]:
		calls += 1
		offered_marker = _role_batch_tick
		return super._step_running(state,move,commands)

class CustomHelper:
	extends "res://game/core/streamed_run_world.gd"
	var readiness_calls := 0
	func readiness(state: Dictionary, commands: Array = []) -> Dictionary:
		readiness_calls += 1
		return super.readiness(state,commands)

class CustomWorld:
	extends "res://game/world/cached_streamed_world.gd"
	pass

class CustomQueryCore:
	extends "res://game/core/run_simulation.gd"
	var sentinel := RefCounted.new()
	func _step_running(state: Dictionary, move: Vector2, commands: Array[Dictionary]) -> Array[Dictionary]:
		var events: Array[Dictionary] = super._step_running(state,move,commands)
		_role_tick_query = sentinel # No expiry API. Custom ownership remains valid.
		return events

class FailedQueryCore:
	extends "res://game/core/run_simulation.gd"
	func _move_player(state: Dictionary, _move: Vector2) -> void:
		# Existing custom extension seam, genuine absent geometry underneath.
		var max_x := -100000.0
		for key in _streamed._world.chunk_keys():
			var chunk: Dictionary = _streamed._world.localized_chunk(key)
			max_x = maxf(max_x,float(chunk.local_origin.x)+768.0)
		var result: Dictionary = _role_query(state).walkable(Vector2(max_x+384.0,384.0),8.0)
		_role_failure(result)

func run(t) -> void:
	for mode in ["commands","population","rebase","custom_core","custom_helper","custom_world","legacy","near_max","max"]:
		await _case(t,mode)
	await _custom_rollback(t)
	await _custom_query_owner(t)
	await _dock_router(t)
	await _mismatched_helper_marker(t)

func _public_query(t,core,label: String) -> void:
	t.check(core._role_tick_query != null,"READINESS FALLBACK creates role query: "+label)
	if core._role_tick_query != null:
		t.check(core._role_tick_query._admitted_tick == -1 and core._role_tick_query._expired_status.is_empty(),"READINESS FALLBACK preserves public query lifetime: "+label)
	t.check(core._role_batch_tick == -1 and core._role_batch_helper_id == 0,"READINESS FALLBACK clears handoff markers: "+label)

func _case(t,mode: String) -> void:
	var app = support.make(t,"fallback_"+mode)
	if app == null: return
	var core = app.simulation
	var original_helper = core._streamed
	var commands: Array[Dictionary] = []
	if mode == "commands":
		# Valid nonspatial no-op: command presence alone disqualifies reuse.
		commands.append({"command_id":"readiness:ignored","kind":"readiness_test_noop","payload":{}})
	elif mode == "population":
		# Normal drop writer; actual Population parks it during this very step.
		# Suspended records require shape validation, not active resident geometry.
		core._add_drop(app.state,[2688.0,384.0],7)
	elif mode == "rebase":
		# Setup spawns directly before any ordinary tick. Baseline initializes role
		# action fields inside _move_enemies, after rebase reconciliation. Advance
		# one real tick at home first so this case exercises an initialized live
		# actor's rebase, rather than the separate preexisting pre-first-tick edge.
		var setup_tick: int = int(app.state.active_tick)
		core.step(app.state,Vector2.ZERO,commands)
		var advanced: bool = core.step_status().get("ok",false) and int(app.state.active_tick) == setup_tick+1
		t.check(advanced,"READINESS FALLBACK rebase setup completes one ordinary role tick before relocation")
		if not advanced: await support.dispose(t,app); return
		var initialized: bool = not app.state.entities.is_empty()
		for entity in app.state.entities:
			if core._is_live_role(entity): initialized = initialized and entity.has_all(["action_state","role_hand_reach","role_wait_since","role_retry_tick"]) and core._role_owner_valid(app.state,entity)
		t.check(initialized,"READINESS FALLBACK rebase actor action fields are initialized and owned by actual Core tick")
		if not initialized: await support.dispose(t,app); return
		app.state.player.position = [1152.0,384.0]
		if not support.city.refresh(t,app,"readiness rebase source"):
			await support.dispose(t,app); return
		core = app.simulation
		original_helper = core._streamed
	elif mode == "custom_core":
		var custom = CustomCore.new(core._chapter_provider,core._world_template,core._gameplay_definitions)
		var prepared: Dictionary = custom.prepare_world(app.state,core._streamed._hydration)
		t.check(prepared.get("ok",false),"READINESS FALLBACK custom Core uses original public preparation")
		if not prepared.get("ok",false): await support.dispose(t,app); return
		app._adopt_city_simulation(custom)
		core = custom
	elif mode == "custom_helper":
		var custom = CustomHelper.new(core._streamed._definitions)
		var prepared: Dictionary = custom.prepare(app.state,core._streamed._hydration)
		t.check(prepared.get("ok",false),"READINESS FALLBACK custom helper prepares real geometry")
		if not prepared.get("ok",false): await support.dispose(t,app); return
		core._streamed = custom
		custom.readiness_calls = 0
	elif mode == "custom_world":
		var helper = core._streamed
		var custom = CustomWorld.new(helper._generator,int(app.state.seed))
		var needed: Dictionary = Helper.requirements(app.state,[])
		t.check(needed.get("ok",false),"READINESS FALLBACK custom world has real requirements")
		if not needed.get("ok",false): await support.dispose(t,app); return
		var prepared: Dictionary = custom.prepare(needed.chunks,[],helper._hydration,app.state.world.origin_chunk,needed.origin_chunk)
		t.check(prepared.get("ok",false),"READINESS FALLBACK custom world hydrates same verified chunk packets")
		if not prepared.get("ok",false): await support.dispose(t,app); return
		helper._world = custom
		helper._navigation = Helper.Navigation.new(Helper.NavigationView.new(custom))
	elif mode == "legacy":
		# Deliberately install a valid admission-only legacy record. The ordinary
		# tick must still refuse migration exactly as before, without publishing it.
		app.state.player_mobility = Legacy.initial()
	elif mode in ["near_max","max"]:
		# Counter-edge fixture, not a claim of a naturally elapsed run.
		app.state.active_tick = Core.MAX_COUNTER-1 if mode == "near_max" else Core.MAX_COUNTER
	var source: PackedByteArray = var_to_bytes(app.state)
	var tick: int = int(app.state.active_tick)
	var origin: Array = app.state.world.origin_chunk.duplicate()
	var events: Array[Dictionary] = core.step(app.state,Vector2.ZERO,commands)
	var status: Dictionary = core.step_status()
	_public_query(t,core,mode)
	if mode == "legacy":
		t.check(not status.get("ok",false) and status.get("error_code") == "mobility_migration_required" and events.is_empty() and var_to_bytes(app.state) == source,"READINESS FALLBACK legacy migration refusal preserves original state/events")
	elif mode in ["near_max","max"]:
		# Full existing counter validation owns the final status. This candidate
		# contract proves no private admission and atomicity, not counter-edge parity.
		if not status.get("ok",false): t.check(events.is_empty() and var_to_bytes(app.state) == source,"READINESS FALLBACK counter-edge failure remains atomic")
	else:
		t.check(status.get("ok",false) and int(app.state.active_tick) == tick+1,"READINESS FALLBACK original path still commits: "+mode)
	if mode == "population": t.check(status.get("population",{}).get("changed",false) and status.get("population",{}).get("parked_drops") == 1,"READINESS FALLBACK actual population writer changed this tick")
	if mode == "rebase": t.check(app.state.world.origin_chunk != origin and core._streamed != original_helper,"READINESS FALLBACK actual rebase replaced helper before running")
	if mode == "custom_core": t.check(core.calls == 1 and core.offered_marker == -1,"READINESS FALLBACK custom three-argument override called once without native marker")
	if mode == "custom_helper": t.check(core._streamed.readiness_calls == 2,"READINESS FALLBACK custom helper retains both original readiness callbacks")
	print("READINESS_FALLBACK_ROW ",JSON.stringify({"case":mode,"status":status,"events_sha256":support.digest(events),"state_sha256":support.digest(app.state),"rng_state":str(app.state.rng_state),"progression_rng_state":str(app.state.progression_rng_state)},"",true,true))
	await support.dispose(t,app)

func _custom_rollback(t) -> void:
	var app = support.make(t,"rollback")
	if app == null: return
	var old = app.simulation
	var core = FailedQueryCore.new(old._chapter_provider,old._world_template,old._gameplay_definitions)
	var prepared: Dictionary = core.prepare_world(app.state,old._streamed._hydration)
	t.check(prepared.get("ok",false),"READINESS FALLBACK custom failure fixture publicly prepares")
	if not prepared.get("ok",false): await support.dispose(t,app); return
	app._adopt_city_simulation(core)
	var source: PackedByteArray = var_to_bytes(app.state)
	var view: PackedByteArray = var_to_bytes(core._attack_view_cache)
	var helper = core._streamed
	var chunks: PackedByteArray = var_to_bytes(helper._world._chunks)
	var commands: Array[Dictionary] = []
	var events: Array[Dictionary] = core.step(app.state,Vector2.ZERO,commands)
	t.check(events.is_empty() and core.step_status().get("error_code") == "world_not_ready","READINESS FALLBACK real out-of-coverage query makes streamed transaction refuse")
	t.check(var_to_bytes(app.state) == source and var_to_bytes(core._attack_view_cache) == view and core._streamed == helper and var_to_bytes(helper._world._chunks) == chunks,"READINESS FALLBACK failed query preserves state/RNG/view/helper/terrain authority")
	_public_query(t,core,"custom rollback")
	await support.dispose(t,app)

func _custom_query_owner(t) -> void:
	var app = support.make(t,"custom_query")
	if app == null: return
	var old = app.simulation
	var core = CustomQueryCore.new(old._chapter_provider,old._world_template,old._gameplay_definitions)
	var prepared: Dictionary = core.prepare_world(app.state,old._streamed._hydration)
	t.check(prepared.get("ok",false),"READINESS FALLBACK custom query owner publicly prepares")
	if not prepared.get("ok",false): await support.dispose(t,app); return
	app._adopt_city_simulation(core)
	var commands: Array[Dictionary] = []
	var tick: int = int(app.state.active_tick)
	core.step(app.state,Vector2.ZERO,commands)
	t.check(core.step_status().get("ok",false) and int(app.state.active_tick) == tick+1 and core._role_tick_query == core.sentinel,"READINESS FALLBACK custom Core query object receives no added expiry callback")
	await support.dispose(t,app)

func _dock_router(t) -> void:
	var app = support.make(t,"dock_route",[])
	if app == null: return
	# Router-only scene discriminant probe. This does not claim a committed dock
	# transition; the full evacuation/dock integration remains its existing suite.
	var dock: Dictionary = app.state.duplicate(true)
	dock.world.stage = "dock"
	dock.world.scene_id = "authored_dock"
	dock.active_tick = 1
	var refused = Query._for_admitted_tick(app.simulation._streamed,dock,1)
	t.check(not refused.status().get("ok",false) and refused.status().get("error_code") == "world_not_ready","READINESS FALLBACK private city factory refuses dock scene")
	var routed = app.simulation._role_query(dock,app.simulation._streamed)
	t.check(routed._helper == null and routed._admitted_tick == -1 and routed.status().get("ok",false),"READINESS FALLBACK Core dock query still routes to authored finite geometry")
	await support.dispose(t,app)

func _mismatched_helper_marker(t) -> void:
	var app = support.make(t,"marker_identity")
	if app == null: return
	var core = app.simulation
	var candidate: Dictionary = core._tick_candidate(app.state)
	core._role_batch_tick = int(candidate.active_tick)
	core._role_batch_helper_id = 0 # Never a real instance ID.
	var commands: Array[Dictionary] = []
	core._step_running(candidate,Vector2.ZERO,commands)
	_public_query(t,core,"mismatched helper handoff")
	await support.dispose(t,app)
