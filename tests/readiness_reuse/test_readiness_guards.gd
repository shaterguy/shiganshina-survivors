extends RefCounted
# Candidate-only product regression. Runs against unchanged product scripts.
# Private factory tests model its documented admitted pre-move handoff explicitly;
# only the ordinary-step test proves that the real Core selects and expires it.
const Support = preload("res://tests/readiness_reuse/readiness_support.gd")
const Query = preload("res://game/combat/enemy_world_query.gd")
const Address = preload("res://game/world/world_address.gd")
var support := Support.new()

func run(t) -> void:
	await _retained_lifetime(t)
	for mode in ["prepared_identity","world_revision","active_tick","query_status","outside_coverage"]:
		await _guard_case(t,mode)
	await _public_coverage(t)
	await _marker_early_return(t)

func _retained_lifetime(t) -> void:
	var app = support.make(t,"retained")
	if app == null: return
	var commands: Array[Dictionary] = []
	app.simulation.step(app.state,Vector2.ZERO,commands)
	t.check(app.simulation.step_status().get("ok",false),"READINESS GUARD actual native step succeeds")
	var query = app.simulation._role_tick_query
	t.check(query != null and query._admitted_tick == app.state.active_tick and not query._expired_status.is_empty(),"READINESS GUARD actual Core expires its private query immediately after running")
	if query == null: await support.dispose(t,app); return
	var status: Dictionary = query.status()
	var state_bytes: PackedByteArray = var_to_bytes(app.state)
	var query_bytes: PackedByteArray = var_to_bytes(status)
	var point: Vector2 = support.point(app.state)
	for result in [query.walkable(point,8.0),query.sweep(point,Vector2.ZERO,8.0),query.visibility({"requires_visibility":false},point)]:
		t.check(not result.get("ok",false) and result.get("error_code") == "world_not_ready","READINESS GUARD retained private query refuses geometry after Core return")
	t.check(status.get("ok",false) and var_to_bytes(query.status()) == query_bytes,"READINESS GUARD expiry preserves completed status and query counters")
	t.check(var_to_bytes(app.state) == state_bytes and app.simulation._streamed.query_status().get("ok",false),"READINESS GUARD rejected retained operations do not mutate committed state or helper status")
	app.simulation.step(app.state,Vector2.ZERO,commands)
	t.check(app.simulation.step_status().get("ok",false) and app.simulation._role_tick_query != query,"READINESS GUARD following tick creates a fresh private query")
	t.check(var_to_bytes(query.status()) == query_bytes,"READINESS GUARD retained prior query cannot absorb next tick state/status")
	await support.dispose(t,app)

func _guard_case(t,mode: String) -> void:
	var app = support.make(t,"guard_"+mode)
	if app == null: return
	var helper = app.simulation._streamed
	var state: Dictionary = app.state.duplicate(true)
	var ready: Dictionary = helper.begin_query_batch(state,[])
	t.check(ready.get("ok",false),"READINESS GUARD real full batch preflight succeeds")
	state.active_tick = int(state.active_tick)+1
	var query = Query._for_admitted_tick(helper,state,int(state.active_tick))
	t.check(query.status().get("ok",false),"READINESS GUARD private query starts only after arranged successful batch")
	var original_identity: Dictionary = helper._prepared_identity
	var expected_error := "world_not_ready"
	if mode == "prepared_identity": helper._prepared_identity = helper._prepared_identity.duplicate(true)
	elif mode == "world_revision": state.world.world_revision += 1
	elif mode == "active_tick": state.active_tick += 1
	elif mode == "query_status":
		# This error is deliberately injected into private test state, rather than
		# presented as a naturally occurring geometry failure.
		helper._query_failure = {"ok":false,"error_code":"readiness_test_prior_failure","detail":"owned"}
		expected_error = "readiness_test_prior_failure"
	var point: Vector2 = support.point(state)
	var before: PackedByteArray = var_to_bytes(state)
	var result: Dictionary
	if mode == "outside_coverage":
		# Real absent resident geometry; no synthetic success/failure query helper.
		var max_x := -100000.0
		for key in helper._world.chunk_keys():
			var chunk: Dictionary = helper._world.localized_chunk(key)
			max_x = maxf(max_x,float(chunk.local_origin.x)+768.0)
		var absent := Vector2(max_x+384.0,384.0)
		var address: Dictionary = Address.normalize(state.world.origin_chunk,absent)
		t.check(address.get("ok",false) and not Address.key(address.chunk) in helper._world.chunk_keys(),"READINESS GUARD absent chunk is proven by membership without issuing an earlier geometry query")
		t.check(helper.query_status().get("ok",false) and helper._world._last_error.is_empty(),"READINESS GUARD first actual failed geometry read belongs to private query")
		result = query.walkable(absent,8.0)
		t.check(result.get("error_code") == "world_not_ready" and not helper.query_status().get("ok",false),"READINESS GUARD genuine coverage failure is owned by helper")
	else: result = query.walkable(point,8.0)
	t.check(not result.get("ok",false) and result.get("error_code") == expected_error,"READINESS GUARD refuses "+mode+" with original error")
	t.check(var_to_bytes(state) == before,"READINESS GUARD failing geometry never mutates candidate state")
	var failed: Dictionary = query.status()
	query._expire_admitted_tick()
	t.check(query.status() == failed and query.sweep(point,Vector2.ZERO,8.0).get("error_code") == expected_error,"READINESS GUARD expiry retains preexisting owned failure: "+mode)
	# Restore only test-injected identity so app teardown has its original helper.
	helper._prepared_identity = original_identity
	await support.dispose(t,app)

func _public_coverage(t) -> void:
	var app = support.make(t,"public_coverage",[])
	if app == null: return
	var helper = app.simulation._streamed
	var state: Dictionary = app.state.duplicate(true)
	state.player.position = [20000.0,384.0]
	var before: PackedByteArray = var_to_bytes(state)
	var expected: Dictionary = helper.readiness(state)
	var query = Query.for_streamed(helper,state)
	t.check(not expected.get("ok",false) and not query.status().get("ok",false) and query.status().get("error_code") == expected.get("error_code"),"READINESS GUARD public factory keeps missing view-window readiness refusal")
	t.check(var_to_bytes(state) == before and helper.query_status().get("ok",false),"READINESS GUARD public preflight refusal remains read-only and never begins a batch")
	await support.dispose(t,app)

func _marker_early_return(t) -> void:
	var app = support.make(t,"marker_pause",[])
	if app == null: return
	var core = app.simulation
	var state: Dictionary = app.state.duplicate(true)
	state.pause_reasons.append("user")
	core._role_batch_tick = int(state.active_tick)
	core._role_batch_helper_id = core._streamed.get_instance_id()
	var before: PackedByteArray = var_to_bytes(state)
	var commands: Array[Dictionary] = []
	var events: Array[Dictionary] = core._step_running(state,Vector2.ZERO,commands)
	t.check(events.is_empty() and var_to_bytes(state) == before,"READINESS GUARD direct paused running call retains existing early-return semantics")
	t.check(core._role_batch_tick == -1 and core._role_batch_helper_id == 0,"READINESS GUARD marker consumption/reset precedes early paused return")
	await support.dispose(t,app)
