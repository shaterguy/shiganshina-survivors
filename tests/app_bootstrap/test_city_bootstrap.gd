extends RefCounted
# Actual project main scene, real Controller/Core/Store; all paths injected
# before tree entry. Never read the real user://saves directory.
const Finite = preload("res://tests/app/controller_test_support.gd")
const Recovery = preload("res://tests/app_rebuild/test_save_recovery_ui.gd")
class RefusingProvider:
	extends "res://game/director/streamed_chapter_provider.gd"
	func load_chapter(_id: String) -> Dictionary:
		return {"ok":false,"error_code":"definition_missing"}

func run(t) -> void:
	_fresh_and_cold_city(t)
	_ordinary_dev1(t)
	_current_revision_finite(t)
	_incompatible_history(t)
	_configuration_failure(t)
	_empty_directory_failure(t)

func _main(t):
	var scene = load(ProjectSettings.get_setting("application/run/main_scene"))
	t.check(scene is PackedScene,"project main scene is loadable")
	if not scene is PackedScene: return null
	var boot = scene.instantiate()
	var is_bootstrap: bool = boot.get_script().resource_path == "res://game/app/city_bootstrap.gd"
	t.check(is_bootstrap,"project main scene selects the explicit city bootstrap")
	if not is_bootstrap:
		boot.free()
		return null
	t.check(boot.save_directory == "user://saves","shipped bootstrap retains the existing canonical save directory")
	return boot

func _enter(t, boot, directory: String) -> void:
	boot.save_directory = directory
	t.check(not boot.is_inside_tree(),"isolated directory is injected before main scene enters the tree")
	t.root.add_child(boot)
	if is_instance_valid(boot.app):
		boot.app.set_process(false)
		boot.app.world.set_process(false)

func _fresh_and_cold_city(t) -> void:
	var boot = _main(t)
	if boot == null: return
	var directory := _directory("fresh")
	_enter(t,boot,directory)
	t.check(boot.startup_result.get("ok",false) and is_instance_valid(boot.app),"main bootstrap successfully configures a real controller")
	if not is_instance_valid(boot.app):
		boot.free()
		return
	var app = boot.app
	t.check(app.chapter.get("world_mode") == "streamed_city" and app._city_runtime != null,"normal main entry is city rather than finite")
	t.check(app.chapter.content_revision == "ch01.3-rebuild.7-grabber-hand","integrated A4 content revision is explicit")
	t.check(app.save_store._directory == directory and app._world_delta_store._directory == directory.path_join("world"),"controller and immutable world pages share the injected canonical save root")
	t.check(app.autosave_worker_enabled,"bootstrap keeps the actual default autosave worker enabled")
	t.check(app._startup_view.is_empty() and app.ui._mode == "title" and app.game_save.store_revision == 1,"fresh install initializes once without a recovery prompt")
	t.check(app.state.is_empty() and app.pending_checkpoint.is_empty(),"startup waits for the user's departure rather than starting a run")
	app.ui.run_start_requested.emit()
	t.check(not app.state.is_empty() and app.state.has("world") and app.ui._mode == "play","actual main UI departure commits and adopts a streamed city run")
	if app.state.is_empty():
		boot.free()
		return
	t.check(app.simulation._streamed.readiness(app.state).ok,"main departure adopts a ready Core and world state")
	var saved: Dictionary = app.game_save.duplicate(true)
	var source := _bytes(directory.path_join("game_save.json"))
	_export_cold_evidence(directory,saved,source)
	app.input_router.set_touch_vector(Vector2.RIGHT)
	app.advance_frame(1.0/60.0)
	t.check(app.state.active_tick == 1 and app.simulation.step_status().ok,"main city processes a real movement tick without QA health or trace code")
	boot.free()
	boot = _main(t)
	if boot == null: return
	_enter(t,boot,directory)
	app = boot.app
	t.check(app._startup_view.is_empty() and app.state.is_empty() and not app.pending_checkpoint.is_empty(),"compatible city cold startup offers explicit resume without recovery")
	t.check(_bytes(directory.path_join("game_save.json")) == source and app.game_save == saved,"cold main startup retains exact authority bytes and all saved fields")
	app.ui.resume_requested.emit()
	t.check(not app.state.is_empty() and app.simulation._streamed.readiness(app.state).ok,"actual resume UI restores the prepared city pair")
	boot.free()

func _ordinary_dev1(t) -> void:
	var boot = _main(t)
	if boot == null: return
	var directory := _directory("dev1")
	var legacy := {"schema_version":1,"settings":{"deadzone":0.25,"audio_master":0.4,"screen_shake":0.2,"reduce_effects":true},"cleared_chapter_ids":["chapter_01_shiganshina"],"unlocked_character_ids":["garrison_01"],"best_runs":{"chapter_01_shiganshina":{"survival_tick":36000,"kills":123,"won":true}},"user_note":"retained dev1 metadata"}
	var profile_source := JSON.stringify(legacy,"  ")+"\n"
	var checkpoint_source := "dev1 opaque checkpoint: preserve exactly\n"
	_write(directory.path_join("profile.json"),profile_source)
	_write(directory.path_join("checkpoint.json"),checkpoint_source)
	_enter(t,boot,directory)
	var app = boot.app
	t.check(app._startup_view.is_empty() and app.ui._mode == "title" and not app.game_save.is_empty(),"ordinary dev1 migrates through existing guarded startup without forced recovery")
	t.check(app.profile.settings == legacy.settings and app.profile.best_runs == legacy.best_runs and app.profile.cleared_chapter_ids == legacy.cleared_chapter_ids and app.profile.unlocked_character_ids == legacy.unlocked_character_ids,"dev1 settings and progression survive main city startup")
	t.check(app.profile.get("user_note") == legacy.user_note and app.game_save.legacy_checkpoint_present,"dev1 metadata and legacy checkpoint notice survive")
	t.check(_bytes(directory.path_join("profile.json")) == profile_source and _bytes(directory.path_join("checkpoint.json")) == checkpoint_source,"dev1 original profile and checkpoint bytes are preserved")
	var career: String = app.game_save.career_id
	var authority := _bytes(directory.path_join("game_save.json"))
	boot.free()
	boot = _main(t)
	if boot == null: return
	_enter(t,boot,directory)
	t.check(boot.app.game_save.career_id == career and _bytes(directory.path_join("game_save.json")) == authority and boot.app._startup_view.is_empty(),"dev1 second startup reuses the migrated career without another write or prompt")
	boot.app.ui.run_start_requested.emit()
	t.check(not boot.app.state.is_empty() and boot.app.state.has("world") and boot.app.game_save.career_id == career,"dev1 explicit departure starts city within the same migrated career")
	boot.free()

func _current_revision_finite(t) -> void:
	# Real current-revision finite runs: no revision/world/authority edits. Both initial
	# null backup and a terminal finite backup must preserve the primary lineage.
	for terminal_backup in [false,true]:
		var fixture := Finite.new().make(t)
		var finite = fixture.app
		finite.start_run(145)
		if terminal_backup:
			finite.request_end_run()
			finite.start_run(146)
		t.check(not finite.state.is_empty() and not finite.state.has("world") and finite.state.content_revision == "ch01.3-rebuild.7-grabber-hand","real current-revision finite checkpoint is available for compatibility classification")
		var old: Dictionary = finite.game_save.duplicate(true)
		var source := _bytes(fixture.directory.path_join("game_save.json"))
		var backup := _bytes(fixture.directory.path_join("game_save.json.bak"))
		if terminal_backup:
			var historical: Dictionary = JSON.parse_string(backup)
			t.check(historical.checkpoint.phase == "abandoned" and old.settlement_receipts.size() == 1,"real finite service produced a terminal backup and one actual settlement receipt")
		finite.free()
		var boot = _main(t)
		if boot == null: return
		_enter(t,boot,fixture.directory)
		var app = boot.app
		t.check(app._startup_view.get("kind") == "checkpoint" and app.game_save.is_empty(),"current-revision finite primary offers preserved-new-run instead of silently adopting an older backup")
		t.check(Recovery.new()._button_ids(app.ui).has("recovery_start"),"current-revision finite save exposes explicit preserved-new-run choice")
		t.check(_bytes(fixture.directory.path_join("game_save.json")) == source and _bytes(fixture.directory.path_join("game_save.json.bak")) == backup,"current finite inspection preserves exact original primary and backup bytes")
		if app._startup_view.get("kind") != "checkpoint": boot.free(); continue
		app.ui.recovery_keep_requested.emit()
		t.check(app._startup_view.get("kind") == "kept" and _bytes(fixture.directory.path_join("game_save.json")) == source,"current finite keep preserves exact primary authority")
		app.ui.recovery_retry_requested.emit()
		app.ui.recovery_start_requested.emit()
		t.check(not app.state.is_empty() and app.state.has("world") and app.ui._mode == "play","explicit preserved-new-run replaces known current finite with ready city")
		if not app.state.is_empty():
			t.check(app.game_save.career_id == old.career_id and app.game_save.profile == old.profile and app.game_save.purchase_receipts == old.purchase_receipts and app.game_save.settlement_receipts == old.settlement_receipts and app.game_save.settled_through_serial == old.settled_through_serial,"known finite replacement preserves profile balance receipts career and settlement high-water")
			t.check(app.state.run_serial == old.next_run_serial and app.game_save.next_run_serial == old.next_run_serial+1,"known finite replacement allocates exactly one fresh serial")
			t.check(_bytes(fixture.directory.path_join("archives").path_join(source.sha256_text()+".json")) == source and _bytes(fixture.directory.path_join("game_save.json.bak")) == backup,"known finite replacement archives exact primary and leaves original backup bytes intact")
		boot.free()

func _incompatible_history(t) -> void:
	var boot = _main(t)
	if boot == null: return
	# Construct history with the real finite service/store; only fixture funding
	# and historical content identity are arranged explicitly in this test.
	var fixture := Finite.new().make(t)
	var finite = fixture.app
	var funded: Dictionary = finite.game_save.duplicate(true)
	funded.profile.supply_credits = 100
	funded.profile.settings.reduce_effects = true
	funded.profile.best_runs = {"chapter_01_shiganshina":{"survival_tick":18000,"kills":23,"won":false}}
	finite.free()
	_write(fixture.directory.path_join("game_save.json"),JSON.stringify(funded,"",true,true))
	finite = Finite.new().restart(t,fixture.directory)
	t.check(finite.game_save == funded,"historical fixture funding and progression pass real Store validation")
	if finite.game_save.is_empty():
		finite.free(); boot.free(); return
	finite.apply_purchase("field_bandage",finite._view_revision)
	finite.start_run(145)
	finite.request_end_run()
	finite.start_run(146)
	var old: Dictionary = finite.game_save.duplicate(true)
	t.check(old.purchase_receipts.size() == 1 and old.settlement_receipts.size() == 1 and old.settled_through_serial == 1,"historical fixture has real purchase and settlement receipts")
	finite.free()
	old.checkpoint.content_revision = "ch01.old-preserved"
	old.checkpoint.world = {"delta_root":{"opaque_future_version":9,"preserved_token":"exact-root"}}
	var source := JSON.stringify(old,"",true,true)+"\n"
	_write(fixture.directory.path_join("game_save.json"),source)
	_write(fixture.directory.path_join("world/opaque-page"),"opaque original world bytes")
	var backup := _bytes(fixture.directory.path_join("game_save.json.bak"))
	_enter(t,boot,fixture.directory)
	var app = boot.app
	t.check(app._startup_view.get("kind") == "checkpoint" and app.ui._mode == "save_recovery" and app.game_save.is_empty() and app.state.is_empty(),"main reuses explicit preserved-checkpoint recovery instead of replacing history")
	t.check(app.ui.focused_semantic_id() == "recovery_keep" and Recovery.new()._button_ids(app.ui).has("recovery_start"),"main recovery has existing keep and preserved-new-run choices with safe default")
	app.ui.recovery_keep_requested.emit()
	t.check(app._startup_view.get("kind") == "kept" and _bytes(fixture.directory.path_join("game_save.json")) == source,"keep choice preserves exact historical authority")
	app.ui.recovery_retry_requested.emit()
	app.ui.recovery_start_requested.emit()
	t.check(not app.state.is_empty() and app.state.has("world") and app.ui._mode == "play","explicit preserved-start UI enters real city gameplay")
	if not app.state.is_empty():
		t.check(app.game_save.career_id == old.career_id and app.game_save.profile == old.profile,"preserved city replacement retains career, settings, balance and progression")
		t.check(app.game_save.purchase_receipts == old.purchase_receipts and app.game_save.settlement_receipts == old.settlement_receipts and app.game_save.settled_through_serial == old.settled_through_serial,"preserved city replacement neither rewrites purchases nor settles the unsupported run")
		t.check(app.state.run_serial == old.next_run_serial and app.game_save.next_run_serial == old.next_run_serial+1,"preserved new departure consumes exactly one new run serial")
		t.check(_bytes(fixture.directory.path_join("archives").path_join(source.sha256_text()+".json")) == source and _bytes(fixture.directory.path_join("game_save.json.bak")) == backup,"explicit replacement archives exact historical source and preserves existing backup")
		t.check(_bytes(fixture.directory.path_join("world/opaque-page")) == "opaque original world bytes","bootstrap and recovery preserve opaque historical world storage")
	boot.free()

func _configuration_failure(t) -> void:
	var boot = _main(t)
	if boot == null: return
	var directory := _directory("refused")
	_write(directory.path_join("game_save.json"),"pre-existing opaque authority\n")
	_write(directory.path_join("world/opaque-page"),"retained world")
	var original_files := _directory_bytes(directory)
	boot.city_provider = RefusingProvider.new()
	_enter(t,boot,directory)
	t.check(boot.startup_result.get("ok") == false and boot.startup_result.get("error_code") == "content_mismatch","configuration refusal returns a clear failure result")
	t.check(not is_instance_valid(boot.app) and boot.get_node_or_null("CityController") == null,"failed configuration never adds a finite controller to the tree")
	var notice = boot.get_node_or_null("StartupFailure")
	t.check(notice is Label and notice.text.contains("content_mismatch") and notice.text.contains("저장 데이터는 변경하지 않았습니다"),"configuration refusal displays visible diagnosis and preservation guidance")
	t.check(_bytes(directory.path_join("game_save.json")) == "pre-existing opaque authority\n" and _bytes(directory.path_join("world/opaque-page")) == "retained world","configuration refusal leaves existing save and world bytes untouched")
	t.check(not FileAccess.file_exists(directory.path_join("game_save.json.bak")) and not DirAccess.dir_exists_absolute(directory.path_join("archives")),"configuration refusal does not create a career, backup or recovery archive")
	t.check(_directory_bytes(directory) == original_files,"provider failure leaves the complete isolated save tree byte-identical")
	t.check(notice.theme == load("res://game/ui/korean_ui_theme.tres") and notice.get_theme_font("font") != null,"startup failure uses Source20 bundled Korean theme")
	boot.free()

func _empty_directory_failure(t) -> void:
	var boot = _main(t)
	if boot == null: return
	var canonical_before := _directory_bytes("user://saves")
	_enter(t,boot,"")
	t.check(boot.startup_result.get("ok") == false and not is_instance_valid(boot.app) and boot.get_node_or_null("StartupFailure") != null,"empty storage configuration fails visibly before any controller startup")
	t.check(_directory_bytes("user://saves") == canonical_before,"empty directory does not write the isolated canonical save tree")
	t.check(boot.get_node("StartupFailure").theme == load("res://game/ui/korean_ui_theme.tres"),"empty-directory failure keeps the bundled Korean theme")
	boot.free()

func _directory(label: String) -> String:
	return "user://bootstrap_%s_%d_%d/saves" % [label,OS.get_process_id(),Time.get_ticks_usec()]
func _write(path: String, value: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(value)
	file.close()
func _bytes(path: String) -> String:
	return FileAccess.get_file_as_string(path)

func _directory_bytes(directory: String) -> Dictionary:
	var result := {}
	var folder := DirAccess.open(directory)
	if folder == null: return result
	for file in folder.get_files():
		result[file] = FileAccess.get_file_as_bytes(directory.path_join(file)).hex_encode()
	for sub in folder.get_directories():
		var nested := _directory_bytes(directory.path_join(sub))
		for key in nested: result[sub.path_join(key)] = nested[key]
	return result

func _export_cold_evidence(directory: String, authority: Dictionary, source: String) -> void:
	var path := OS.get_environment("SOURCE20_BOOTSTRAP_EVIDENCE")
	if path.is_empty(): return
	_write(path,JSON.stringify({"save_directory":directory,"authority":authority,"source_sha256":source.sha256_text(),"source_bytes":source.to_utf8_buffer().size()},"  "))
