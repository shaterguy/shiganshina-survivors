extends RefCounted
const Core = preload("res://game/core/run_simulation.gd")
const City = preload("res://game/director/streamed_chapter_provider.gd")
const H = preload("res://game/core/streamed_run_world.gd")
const Runtime = preload("res://game/app/prepared_city_runtime.gd")
const Disk = preload("res://game/persistence/world_delta_store.gd")
const Director = preload("res://game/director/spawn_director.gd")
const S = preload("res://tests/app_city_controller/controller_city_support.gd")
const Recovery = preload("res://tests/app_rebuild/test_save_recovery_ui.gd")
func run(t) -> void:
	_historical_checkpoint_preserved(t)
	_mixed_controller(t)
func _snapshot() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://tests/chunk_transition/mixed_hold_snapshot.json"))
func _mixed_controller(t) -> void:
	# Historical spatial state rebound only to current content in this test.
	# This is NOT an original-content cold-restore compatibility claim.
	var snapshot := _snapshot()
	var f := S.make(t)
	if f.is_empty(): return
	var app = f.app
	app.start_run(42)
	app.state = _rebind_current_content_for_boundary_fixture(t,snapshot,app.state)
	app.input_router.set_touch_vector(Vector2.RIGHT)
	var commands: Array[Dictionary] = app.director.plan(app.state,app.chapter)
	t.check(snapshot.active_tick == 30256 and snapshot.player.position == [640.0,0.0] and commands.is_empty(),"current-content rebound retains observed tick30256 x640 right without commands")
	var before: Dictionary = app.game_save.duplicate(true)
	var result: Dictionary = app._step_city_tick()
	print("CHUNK_TRANSITION_OBSERVED "+JSON.stringify({"before":30256,"after":app.state.active_tick,"position":app.state.player.position,"result":result},"",true,true))
	t.check(result.get("ok",false) and app.state.active_tick == 30257 and app.state.player.position[0] > 640.0,"current-content rebound Controller commits boundary tick instead of repeat world_not_ready")
	if not result.get("ok",false): app.free(); return
	t.check(app._pending_city_tick.is_empty() and app._city_step_error.is_empty() and app.game_save == before,"successful derived coverage retry clears hold without a save mutation")
	var cold: Dictionary = f.runtime.refresh_coverage(JSON.parse_string(JSON.stringify(app.state,"",true,true)))
	t.check(cold.get("ok",false) and cold.state == app.state,"current-content rebound post-boundary state cold-restores with its new real coverage")
	if not cold.get("ok",false): app.free(); return
	var cold_core = cold.simulation
	var cold_state: Dictionary = cold.state
	for index in 30:
		commands = app.director.plan(app.state,app.chapter)
		for command in commands:
			if H.spatial_command(command): command.origin_revision = app.state.world.origin_revision
		var events: Array = cold_core.step(cold_state,Vector2.RIGHT,commands)
		var status: Dictionary = cold_core.step_status()
		if status.get("error_code") == "world_not_ready":
			cold = f.runtime.refresh_coverage(cold_state,commands)
			if cold.get("ok",false):
				cold_core = cold.simulation; cold_state = cold.state
				events = cold_core.step(cold_state,Vector2.RIGHT,commands)
				status = cold_core.step_status()
		result = app._step_city_tick()
		t.check(result.get("ok",false) and status.get("ok",false),"actual Controller and cold restored Core advance boundary continuation "+str(index))
		if not result.get("ok",false) or not status.get("ok",false): break
		t.check(app.state == cold_state and result.events == events and app.simulation.enemy_attack_view(app.state) == cold_core.enemy_attack_view(cold_state),"warm/cold boundary continuation state events and attack packet match "+str(index))
	app.free()

func _rebind_current_content_for_boundary_fixture(t, historical: Dictionary, current: Dictionary) -> Dictionary:
	for id in historical.rules.enemy_catalog:
		t.check(_same_json(current.rules.enemy_catalog.get(id),historical.rules.enemy_catalog[id]),"rebind verifies original enemy definition unchanged: "+id)
	for key in historical.rules:
		if key not in ["content_fingerprint","enemy_catalog","allowed_equipment_ids"]:
			t.check(_same_json(historical.rules[key],current.rules[key]),"rebind verifies unrelated rule unchanged: "+key)
	# Current test-only replay explicitly admits the two added fantasy weapons.
	# No historical authority is migrated or relabeled by this fixture helper.
	var expected_equipment: Array = historical.rules.allowed_equipment_ids.duplicate()
	expected_equipment.append_array(["chain_lightning","fire_zone"])
	t.check(_same_json(current.rules.allowed_equipment_ids,expected_equipment),"rebind admits exactly two new fantasy IDs and preserves historical equipment order")
	var rebound := historical.duplicate(true)
	rebound.rules.allowed_equipment_ids = current.rules.allowed_equipment_ids.duplicate()
	rebound.rules.enemy_catalog = current.rules.enemy_catalog.duplicate(true)
	rebound.rules.content_fingerprint = current.rules.content_fingerprint
	rebound.world.content_fingerprint = current.world.content_fingerprint
	return rebound

func _historical_checkpoint_preserved(t) -> void:
	var snapshot := _snapshot()
	var source_hash := FileAccess.get_sha256("res://tests/chunk_transition/mixed_hold_snapshot.json")
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
