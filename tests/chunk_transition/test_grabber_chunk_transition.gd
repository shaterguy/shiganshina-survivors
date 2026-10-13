extends RefCounted
const Core = preload("res://game/core/run_simulation.gd")
const City = preload("res://game/director/streamed_chapter_provider.gd")
const H = preload("res://game/core/streamed_run_world.gd")
const Runtime = preload("res://game/app/prepared_city_runtime.gd")
const Disk = preload("res://game/persistence/world_delta_store.gd")
const Director = preload("res://game/director/spawn_director.gd")
const S = preload("res://tests/app_city_controller/controller_city_support.gd")
const Recovery = preload("res://tests/app_rebuild/test_save_recovery_ui.gd")
const HISTORICAL_PATH := "res://tests/chunk_transition/mixed_hold_snapshot.json"
const HISTORICAL_SHA256 := "7f4da5068095e70c540ba8bddf0f57c4e9e91d8cc16cdbb56c4d437914d700fd"
const HISTORICAL_FINGERPRINT := "410f0bb4c818320effe455e9517e103004323f162aad4988c2d1589a340e92ad"
const MIXED_COUNTS := {"boss_charger":1,"brute":12,"sweeper":12,"grabber":10,"walker":8,"runner":6}
func run(t) -> void:
	_historical_checkpoint_preserved(t)
	_historical_test_only_frozen_geometry_replay(t)
	_mixed_current_controller(t)
	t.check(FileAccess.get_sha256(HISTORICAL_PATH) == HISTORICAL_SHA256,"all three contracts leave exact historical fixture bytes unchanged")
func _snapshot() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(HISTORICAL_PATH))

func _historical_test_only_frozen_geometry_replay(t) -> void:
	# Synthetic TEST-ONLY identity/catalog rebind. The unknown 410f0... save is
	# NOT a formal dev4 save, and no original-content compatibility is claimed.
	# Frozen production definitions supply geometry; all 49 old actor records,
	# positions, attack relationships, clocks and progression remain untouched.
	var historical := _snapshot()
	var provider := City.new("dev4")
	var capture: Dictionary = provider.capture_validation_inputs()
	t.check(capture.get("ok",false),"TEST-ONLY frozen replay reads hash-pinned legacy definitions")
	if not capture.get("ok",false): return
	var parsed: Dictionary = provider.definitions_from_capture(capture)
	t.check(parsed.get("ok",false),"TEST-ONLY frozen replay validates immutable legacy definition bytes")
	if not parsed.get("ok",false): return
	var core := Core.new(provider,null,parsed.definitions)
	var baseline: Dictionary = core.new_run(parsed.chapter,historical.seed,historical.run_config)
	t.check(not baseline.has("error_code"),"TEST-ONLY frozen replay derives exact pinned rules via public new_run")
	if baseline.has("error_code"): return
	var rebound := _test_only_rebind_historical_to_frozen_geometry(t,historical,baseline)
	if rebound.is_empty(): return
	var disk := Disk.new("user://mixed_frozen_geometry_%d_%d/world"%[OS.get_process_id(),Time.get_ticks_usec()])
	var initialized: Dictionary = disk.prepare(rebound.world.delta_root,[],0)
	t.check(initialized.get("ok",false),"TEST-ONLY frozen replay prepares the fixture's original empty delta root")
	if not initialized.get("ok",false): return
	var runtime := Runtime.new(City.new(),disk)
	var pair := _prepare_pair(t,runtime,rebound,[],"TEST-ONLY unchanged historical actors on frozen geometry")
	if pair.is_empty(): return
	t.check(pair.state.entities.size() == 49 and _actor_counts(pair.state) == MIXED_COUNTS and pair.state.telegraphs.size() == 1,"full Core validator admits all 49 historical actors and their owned telegraph before any tick")
	var director := Director.new()
	var commands: Array[Dictionary] = director.plan(pair.state,parsed.chapter)
	t.check(pair.state.active_tick == 30256 and pair.state.player.position == [640.0,0.0] and commands.is_empty(),"TEST-ONLY frozen replay retains original tick30256 x640/y0 and empty boundary commands")
	pair = _step_pair(t,pair,runtime,Vector2.RIGHT,commands,"TEST-ONLY frozen historical boundary")
	if pair.is_empty(): return
	t.check(pair.state.active_tick == 30257 and pair.state.player.position[0] > 640.0,"all historical actors cross original frozen-geometry boundary in one accepted tick")
	var cold := _prepare_pair(t,runtime,JSON.parse_string(JSON.stringify(pair.state,"",true,true)),[],"TEST-ONLY frozen post-boundary JSON restore")
	if cold.is_empty(): return
	t.check(cold.state == pair.state and cold.simulation.enemy_attack_view(cold.state) == pair.simulation.enemy_attack_view(pair.state),"TEST-ONLY frozen cold restore preserves complete state and attack packet")
	for index in 30:
		commands = _planned_commands(director,pair.state,parsed.chapter)
		pair = _step_pair(t,pair,runtime,Vector2.RIGHT,commands,"TEST-ONLY frozen warm continuation "+str(index))
		cold = _step_pair(t,cold,runtime,Vector2.RIGHT,commands,"TEST-ONLY frozen cold continuation "+str(index))
		if pair.is_empty() or cold.is_empty(): return
		t.check(pair.state == cold.state and pair.events == cold.events and pair.simulation.enemy_attack_view(pair.state) == cold.simulation.enemy_attack_view(cold.state),"TEST-ONLY frozen warm/cold state events and attack packet match "+str(index))
	print("CHUNK_HISTORICAL_FROZEN_TEST_ONLY "+JSON.stringify({"historical_fingerprint":HISTORICAL_FINGERPRINT,"test_only_geometry_fingerprint":baseline.rules.content_fingerprint,"actors_before":49,"after_tick":pair.state.active_tick,"original_save_compatibility_claim":false},"",true,true))

func _test_only_rebind_historical_to_frozen_geometry(t, historical: Dictionary, frozen: Dictionary) -> Dictionary:
	var compatible := true
	for id in historical.rules.enemy_catalog:
		var same := _same_json(frozen.rules.enemy_catalog.get(id),historical.rules.enemy_catalog[id])
		t.check(same,"TEST-ONLY frozen rebind retains original enemy definition: "+id)
		compatible = compatible and same
	for key in historical.rules:
		if key not in ["content_fingerprint","enemy_catalog","allowed_equipment_ids"]:
			var same := _same_json(historical.rules[key],frozen.rules[key])
			t.check(same,"TEST-ONLY frozen rebind retains unrelated rule: "+key)
			compatible = compatible and same
	var equipment: Array = historical.rules.allowed_equipment_ids.duplicate()
	equipment.append_array(["chain_lightning","fire_zone"])
	var additions_match := _same_json(frozen.rules.allowed_equipment_ids,equipment)
	t.check(additions_match,"TEST-ONLY frozen catalog admits exactly the two later fantasy equipment IDs")
	var extra_enemies: Array = frozen.rules.enemy_catalog.keys().filter(func(id): return not historical.rules.enemy_catalog.has(id))
	extra_enemies.sort()
	var enemies_match: bool = extra_enemies == ["quadruped","stone_thrower"]
	t.check(enemies_match,"TEST-ONLY frozen catalog adds exactly two later enemy definitions without changing historical ones")
	if not compatible or not additions_match or not enemies_match: return {}
	var rebound := historical.duplicate(true)
	rebound.rules.allowed_equipment_ids = frozen.rules.allowed_equipment_ids.duplicate()
	rebound.rules.enemy_catalog = frozen.rules.enemy_catalog.duplicate(true)
	rebound.rules.content_fingerprint = frozen.rules.content_fingerprint
	rebound.world.content_fingerprint = frozen.world.content_fingerprint
	var unchanged := rebound.duplicate(true)
	unchanged.rules = historical.rules.duplicate(true)
	unchanged.world.content_fingerprint = historical.world.content_fingerprint
	t.check(_same_json(unchanged,historical) and rebound.entities.size() == 49,"TEST-ONLY rebind changes only declared catalog/identity fields, never historical actors or relationships")
	return rebound

func _mixed_current_controller(t) -> void:
	# A separate current-content fixture: genuine public spawn commands and
	# action ticks own its records. No historical positions are repurposed.
	var f := S.make(t)
	if f.is_empty(): return
	var app = f.app
	app.start_run(42)
	if app.state.is_empty(): t.check(false,"current mixed Controller starts a real run"); app.free(); return
	var pair := _build_current_mixed_state(t,f)
	if pair.is_empty(): app.free(); return
	app._adopt_city_simulation(pair.simulation)
	app.state = pair.state
	app.input_router.set_touch_vector(Vector2.RIGHT)
	var commands: Array[Dictionary] = app.director.plan(app.state,app.chapter)
	t.check(app.state.active_tick == 30256 and app.state.player.position == [640.0,96.0] and commands.is_empty(),"new current-content mixed state reaches real x640/y96 boundary without director commands")
	var before: Dictionary = app.game_save.duplicate(true)
	var save_path: String = f.directory.path_join("game_save.json")
	var save_bytes := FileAccess.get_file_as_bytes(save_path)
	var boundary_core = app.simulation
	var result: Dictionary = app._step_city_tick()
	print("CHUNK_TRANSITION_OBSERVED "+JSON.stringify({"fixture":"current_public_spawn_mixed","before":30256,"after":app.state.active_tick,"position":app.state.player.position,"result":result},"",true,true))
	t.check(result.get("ok",false) and app.state.active_tick == 30257 and app.state.player.position[0] > 640.0,"current mixed Controller commits boundary exactly once instead of repeat world_not_ready")
	if not result.get("ok",false): app.free(); return
	var missing: Dictionary = app.simulation._streamed.readiness(app.state)
	t.check(not missing.get("ok",false) and not missing.get("missing_delta_keys",[]).is_empty(),"actual crossing expands next coverage; preparation did not pad away the retry")
	t.check(app._pending_city_tick.is_empty() and app._city_step_error.is_empty() and app.game_save == before,"successful boundary clears hold without a save mutation")
	var cold := _prepare_pair(t,f.runtime,JSON.parse_string(JSON.stringify(app.state,"",true,true)),[],"current mixed post-boundary JSON restore")
	if cold.is_empty(): app.free(); return
	t.check(cold.state == app.state and cold.simulation.enemy_attack_view(cold.state) == app.simulation.enemy_attack_view(app.state),"current mixed cold restore preserves complete state and attack packet")
	for index in 30:
		commands = _planned_commands(app.director,app.state,app.chapter)
		var tick: int = app.state.active_tick
		cold = _step_pair(t,cold,f.runtime,Vector2.RIGHT,commands,"current mixed cold continuation "+str(index))
		if cold.is_empty(): break
		result = app._step_city_tick()
		t.check(result.get("ok",false) and app.state.active_tick == tick+1,"actual Controller advances exactly one continuation tick "+str(index))
		if not result.get("ok",false): break
		if index == 0: t.check(app.simulation != boundary_core,"actual post-crossing world_not_ready refresh installs one successful replacement Core")
		t.check(app.state == cold.state and result.events == cold.events and app.simulation.enemy_attack_view(app.state) == cold.simulation.enemy_attack_view(cold.state),"warm/cold boundary continuation state events and attack packet match "+str(index))
		t.check(app._pending_city_tick.is_empty() and app._city_step_error.is_empty() and app.game_save == before,"coverage retry clears held input and leaves save authority unchanged "+str(index))
	t.check(app.state.active_tick == 30287 and app.state.entities.size() == 49,"current mixed Controller completes all 30 continuation ticks with the 49 spawned actors")
	t.check(FileAccess.get_file_as_bytes(save_path) == save_bytes,"all current boundary and continuation ticks preserve exact saved authority bytes")
	app.free()

func _build_current_mixed_state(t, f: Dictionary) -> Dictionary:
	var state: Dictionary = f.app.state.duplicate(true)
	# Test-only clock/player/cooldown arrangement, independently restored before
	# public setup. This is not a claim to have played the preceding 30205 ticks.
	state.active_tick = 30205
	state.survival_tick = 30205
	state.player.position = [640.0,96.0]
	state.player.attack_ready_ticks = {"blade_slash":2147483647}
	var pair := _prepare_pair(t,f.runtime,state,[],"fresh current mixed clock and boundary lane")
	if pair.is_empty(): return {}
	var commands: Array[Dictionary] = [
		_spawn_command(pair.state,1,"sweeper",[640.0,160.0]),
		_spawn_command(pair.state,2,"grabber",[470.0,96.0])]
	pair = _step_pair(t,pair,f.runtime,Vector2.ZERO,commands,"current mixed public sweeper/grabber spawn")
	if pair.is_empty(): return {}
	t.check(pair.state.entities.size() == 2 and pair.state.telegraphs.size() == 1 and pair.state.enemy_attack_instances.size() == 1,"public setup creates owned sweeper telegraph and genuine raw grabber attack")
	if pair.state.entities.size() != 2 or pair.state.telegraphs.size() != 1 or pair.state.enemy_attack_instances.size() != 1: return {}
	while pair.state.active_tick < 30255:
		pair = _step_pair(t,pair,f.runtime,Vector2.ZERO,[],"current mixed owned-action setup")
		if pair.is_empty(): return {}
	commands = []
	var next_id: int = pair.state.next_entity_id
	var index := 0
	for enemy in ["boss_charger","brute","sweeper","grabber","walker","runner"]:
		var count: int = MIXED_COUNTS[enemy]-(1 if enemy in ["sweeper","grabber"] else 0)
		for unused in count:
			# Actual authored horizontal street, safely inside the pre-crossing
			# view. Core still checks each body and may reject a bad arrangement.
			var point := Vector2(-128+64*(index%16),320+64*int(index/16))
			var walk: Dictionary = pair.simulation._streamed.walkable(point,float(pair.state.rules.enemy_catalog[enemy].radius))
			t.check(walk.get("ok",false) and walk.get("walkable",false),"new current mixed spawn is legal in actual map: "+str(index))
			if not walk.get("ok",false) or not walk.get("walkable",false): return {}
			commands.append(_spawn_command(pair.state,next_id,enemy,[point.x,point.y]))
			next_id += 1
			index += 1
	pair = _step_pair(t,pair,f.runtime,Vector2.ZERO,commands,"current mixed public 47-actor spawn batch")
	if pair.is_empty(): return {}
	t.check(pair.state.entities.size() == 49 and _actor_counts(pair.state) == MIXED_COUNTS,"new current mixed fixture retains the complete six-kind 49-actor workload")
	var hazard: Dictionary = pair.state.telegraphs[0] if not pair.state.telegraphs.is_empty() else {}
	t.check(hazard.get("behavior_attack",false) and hazard.get("source_id") == "1" and hazard.get("active_from_tick") == 30266 and hazard.get("expires_tick") == 30278,"new current fixture owns the same meaningful telegraph warning/active boundary clocks")
	t.check(pair.state.enemy_attack_instances.size() == 1 and pair.state.enemy_attack_instances[0].source_id == "2" and pair.state.enemy_attack_instances[0].active_from_tick == 30266,"new current fixture adds an ongoing real grabber attack through boundary continuation")
	# Full real validator gate, including all actor geometry and relationships,
	# before the Controller receives this independent fixture.
	return _prepare_pair(t,f.runtime,JSON.parse_string(JSON.stringify(pair.state,"",true,true)),[],"new current mixed full validation before Controller boundary")

func _spawn_command(state: Dictionary, id: int, enemy: String, point: Array) -> Dictionary:
	var payload := {"entity_id":id,"enemy_id":enemy,"position":point,"spawned_tick":int(state.active_tick)+1}
	var kind := "spawn_enemy"
	if enemy == "boss_charger":
		kind = "spawn_boss"
		payload.erase("spawned_tick")
		payload.boss_id = "ch01_b05"
		payload.scheduled_tick = 18000
	return {"command_id":"current-mixed-spawn:"+str(id),"kind":kind,"payload":payload,"origin_revision":state.world.origin_revision}

func _prepare_pair(t, runtime, state: Dictionary, commands: Array, label: String) -> Dictionary:
	var pair: Dictionary = runtime.refresh_coverage(state,commands)
	t.check(pair.get("ok",false),label+" passes complete Core restore and exact hydration")
	if not pair.get("ok",false): print("CHUNK_FIXTURE_PREPARE_FAILED ",label," ",pair); return {}
	return pair

func _step_pair(t, pair: Dictionary, runtime, move: Vector2, values: Array, label: String) -> Dictionary:
	var commands: Array[Dictionary] = []
	commands.assign(values)
	var before: Dictionary = pair.state.duplicate(true)
	var events: Array = pair.simulation.step(pair.state,move,commands)
	var status: Dictionary = pair.simulation.step_status()
	if status.get("error_code") == "world_not_ready":
		t.check(pair.state == before and events.is_empty(),label+" coverage refusal consumes no state or events")
		pair = _prepare_pair(t,runtime,pair.state,commands,label+" coverage retry")
		if pair.is_empty(): return {}
		events = pair.simulation.step(pair.state,move,commands)
		status = pair.simulation.step_status()
	t.check(status.get("ok",false) and pair.state.active_tick == int(before.active_tick)+1,label+" commits exactly one public Core tick")
	if not status.get("ok",false) or pair.state.active_tick != int(before.active_tick)+1: print("CHUNK_FIXTURE_STEP_FAILED ",label," ",status); return {}
	pair.events = events
	return pair

func _planned_commands(director, state: Dictionary, chapter: Dictionary) -> Array[Dictionary]:
	var commands: Array[Dictionary] = director.plan(state,chapter)
	for command in commands:
		if H.spatial_command(command) and not command.has("origin_revision"): command.origin_revision = state.world.origin_revision
	return commands

func _actor_counts(state: Dictionary) -> Dictionary:
	var result := {}
	for actor in state.entities: result[actor.enemy_id] = int(result.get(actor.enemy_id,0))+1
	return result

func _historical_checkpoint_preserved(t) -> void:
	var snapshot := _snapshot()
	var source_hash := FileAccess.get_sha256(HISTORICAL_PATH)
	t.check(source_hash == HISTORICAL_SHA256 and snapshot.rules.content_fingerprint == HISTORICAL_FINGERPRINT and snapshot.world.content_fingerprint == HISTORICAL_FINGERPRINT and HISTORICAL_FINGERPRINT != City.DEV4_FINGERPRINT,"unaltered historical bytes retain the unknown 410f0 identity, never formal dev4 identity")
	var f := S.make(t)
	if f.is_empty(): return
	var app = f.app
	app.start_run(42)
	var denied: Dictionary = f.runtime.validate_checkpoint(snapshot)
	t.check(not denied.get("ok",false) and denied.get("error_code") == "content_mismatch","unaltered historical checkpoint remains incompatible with current content")
	# Put the exact historical checkpoint into an isolated valid authority envelope.
	var old: Dictionary = app.game_save.duplicate(true)
	old.career_id = snapshot.run_id.get_slice(":",0)
	old.checkpoint = snapshot.duplicate(true)
	var source := JSON.stringify(old,"",true,true)
	var path: String = f.directory.path_join("game_save.json")
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(source)
	file.close()
	app.free()
	f = S.make(t,f.directory)
	if f.is_empty(): return
	app = f.app
	t.check(app.state.is_empty() and app.game_save.is_empty() and app._startup_view.get("kind") == "checkpoint","actual historical checkpoint opens preservation UI rather than silently resuming")
	t.check(Recovery.new()._button_ids(app.ui).has("recovery_start") and app.ui.focused_semantic_id() == "recovery_keep","historical checkpoint retains explicit preserved-new-run choice and safe keep default")
	t.check(FileAccess.get_file_as_string(path) == source,"historical inspection keeps exact authority and career bytes")
	t.check(FileAccess.get_sha256("res://tests/chunk_transition/mixed_hold_snapshot.json") == source_hash,"rebind never edits the historical snapshot file")
	app.free()


func _same_json(left: Variant, right: Variant) -> bool:
	return JSON.parse_string(JSON.stringify(left,"",true,true)) == JSON.parse_string(JSON.stringify(right,"",true,true))
