extends RefCounted
# Headless controller/UI behavior against actual finite Core, Service and Store.
const Support = preload("res://tests/app/controller_test_support.gd")
const Controller = preload("res://game/app/run_controller.gd")
const Store = preload("res://game/persistence/game_save_store.gd")
const Core = preload("res://game/core/run_simulation.gd")
class ObservedStore:
	extends "res://game/persistence/game_save_store.gd"
	var inspected := false
	var loaded_before_inspection := false
	var load_count := 0
	func inspect_known_locations(root: Variant) -> Dictionary:
		inspected = true
		return super.inspect_known_locations(root)
	func read_game() -> Dictionary:
		loaded_before_inspection = loaded_before_inspection or not inspected
		return super.read_game()
	func load_game() -> Dictionary:
		load_count += 1
		loaded_before_inspection = loaded_before_inspection or not inspected
		return super.load_game()
func run(t) -> void:
	_test_offer_and_keep(t)
	_test_preserved_real_start(t)
	_test_known_locations(t)
	_test_transient_retry_and_oversize(t)
	_test_future_and_invalid_preservation(t)
	_test_unknown_same_id_retry(t)
	_test_prewrite_same_candidate_retry(t)
	_test_lifecycle_during_adoption(t)
	_test_exhausted_supply_choice(t)
	_test_conflict_appears_during_confirmation(t)
	_test_nonretryable_commit_failure(t)
	_test_late_live_lineage_conflict(t)
	_test_recovery_input_modal(t)
	_test_recovery_inspection_read_retry(t)
func _test_offer_and_keep(t) -> void:
	var fixture := _incompatible_fixture(t)
	var app = Support.new().restart(t,fixture.directory)
	t.check(app.game_save.is_empty() and app.state.is_empty(),"incompatible authority is not adopted before an explicit recovery decision")
	t.check(app.ui._mode == "save_recovery","known incompatible checkpoint presents a dedicated recovery screen")
	t.check(_button_ids(app.ui).has("recovery_start"),"preserved replacement has its own explicit action")
	t.check(_button_ids(app.ui).has("recovery_keep"),"preserve and return is a separate safe action")
	t.check(app.ui.focused_semantic_id() == "recovery_keep","recovery defaults to safe keep action")
	t.check(app.ui._buttons[1].text == "이전 전투 보관 후 새 출격","new departure is explicitly described as preservation then replacement")
	app.ui.navigate("cancel")
	t.check(app._startup_view.get("kind") == "kept" and app.game_save.is_empty(),"B/Escape keeps source and returns without selecting a lineage")
	t.check(FileAccess.get_file_as_string(fixture.directory.path_join("game_save.json")) == fixture.source,"keep leaves exact source bytes intact")
	t.check(not DirAccess.dir_exists_absolute(fixture.directory.path_join("archives")),"keep does not create archives or write an authority")
	app.ui.accept_released()
	app.ui.navigate("accept")
	t.check(app._startup_view.get("kind") == "checkpoint","explicit return reinspects and displays saved recovery choice")
	app.free()
func _test_preserved_real_start(t) -> void:
	var fixture := _incompatible_fixture(t,true)
	var app = Support.new().restart(t,fixture.directory)
	var live_core = app.simulation
	app.confirm_preserved_run_start(146)
	t.check(not app.state.is_empty() and app.state.seed == 146,"explicit recovery commits and adopts an actual Core initial run")
	if app.state.is_empty():
		app.free()
		return
	t.check(app.game_save.career_id == fixture.save.career_id and app.state.run_serial == fixture.save.next_run_serial,"recovery keeps career and uses the next run serial")
	t.check(app.game_save.next_run_serial == fixture.save.next_run_serial+1,"recovery advances next serial once")
	t.check(app.game_save.profile.settings == fixture.save.profile.settings and app.game_save.profile.unlocked_character_ids == fixture.save.profile.unlocked_character_ids,"recovery retains settings and unlocks")
	t.check(app.game_save.profile.supply_credits == fixture.save.profile.supply_credits and app.game_save.settlement_receipts == fixture.save.settlement_receipts and app.game_save.settled_through_serial == fixture.save.settled_through_serial,"old incompatible run receives no settlement or refund")
	t.check(app.game_save.profile.consumables.field_bandage == fixture.save.profile.consumables.field_bandage-1,"selected replacement supply is debited exactly once")
	t.check(app.game_save.get("recovery_fixture_note") == fixture.save.get("recovery_fixture_note"),"preserved replacement retains user metadata")
	var digest: String = fixture.source.sha256_text()
	t.check(FileAccess.get_file_as_string(fixture.directory.path_join("archives").path_join(digest+".json")) == fixture.source,"recovery archives exact source authority bytes")
	t.check(FileAccess.get_file_as_string(fixture.directory.path_join("game_save.json.bak")) == fixture.backup,"recovery leaves original backup bytes intact")
	var pins = JSON.parse_string(FileAccess.get_file_as_string(fixture.directory.path_join("archives").path_join(digest+".pins.json")))
	t.check(pins is Dictionary and pins.pins_all_world_storage and app._same_json(pins.world_roots,[fixture.save.checkpoint.world.delta_root]),"recovery preserves opaque world root with permanent conservative pins")
	t.check(FileAccess.get_file_as_string(fixture.directory.path_join("world/opaque-page")) == "opaque original world bytes","recovery preserves original world storage bytes")
	t.check(app.validation_simulation != live_core and app.candidate_simulation != live_core,"validation and candidate construction never use live Core A")
	t.check(app.ui._mode == "play","only confirmed recovery authority reaches play")
	var committed: Dictionary = app.save_store.load_game()
	t.check(committed.ok and app._same_json(committed.game_save,app.game_save),"recovery adoption corresponds to verified current authority")
	app.advance_frame(1.0/60.0)
	t.check(app.state.active_tick == 1,"actual recovery initial run advances a fresh finite Core tick")
	app.free()
	var restarted = Support.new().restart(t,fixture.directory)
	t.check(restarted.ui._mode == "title" and not restarted.pending_checkpoint.is_empty(),"fresh restart exposes confirmed replacement only through explicit resume")
	restarted.request_resume()
	t.check(not restarted.state.is_empty() and restarted.state.seed == 146,"replacement restores with fresh real Core on restart")
	restarted.free()
func _test_known_locations(t) -> void:
	var fixture := Support.new().make(t)
	var app = fixture.app
	t.check(app._startup_view.is_empty() and app.ui._mode == "title","fresh install has no unnecessary recovery choice")
	app.start_run(147)
	var source: String = FileAccess.get_file_as_string(fixture.directory.path_join("game_save.json"))
	app.free()
	var alternate: String = fixture.directory.get_base_dir().path_join("game_save.json")
	_write(alternate,source)
	app = _restart_observed(t,fixture.directory)
	t.check(app.save_store.inspected and not app.save_store.loaded_before_inspection,"bounded locations inspection precedes load or migration")
	t.check(app._startup_inspection.duplicate_copy and app._startup_view.is_empty() and not app.pending_checkpoint.is_empty(),"byte-identical supported duplicate permits canonical authority")
	app.free()
	var distinct: Dictionary = JSON.parse_string(source)
	distinct.profile.settings.reduce_effects = not distinct.profile.settings.reduce_effects
	var distinct_source := JSON.stringify(distinct,"",true,true)
	_write(alternate,distinct_source)
	app = _restart_observed(t,fixture.directory)
	t.check(app._startup_view.get("kind") == "conflict" and app.game_save.is_empty() and app.state.is_empty(),"distinct authorities are diagnosed and neither lineage is adopted")
	t.check(app.save_store.load_count == 0,"conflicting locations block load and implicit migration")
	app.start_run(148)
	app.confirm_preserved_run_start(148)
	t.check(FileAccess.get_file_as_string(fixture.directory.path_join("game_save.json")) == source and FileAccess.get_file_as_string(alternate) == distinct_source,"conflict preserves both exact authority files")
	t.check(not _button_ids(app.ui).has("recovery_start"),"conflict cannot be silently resolved by new departure")
	app.free()
	var directory: String = _unique_directory("legacy")
	var legacy := {"schema_version":1,"settings":{"deadzone":0.20,"audio_master":0.8,"screen_shake":0.4,"reduce_effects":false},"cleared_chapter_ids":[],"unlocked_character_ids":["garrison_01"],"best_runs":{}}
	_write(directory.path_join("profile.json"),JSON.stringify(legacy))
	_write(directory.path_join("checkpoint.json"),"legacy checkpoint exact bytes")
	app = _restart_observed(t,directory)
	t.check(app.save_store.inspected and not app.save_store.loaded_before_inspection and app._startup_view.is_empty(),"ordinary dev1 legacy profile migrates only after inspection without a recovery choice")
	t.check(app.game_save.legacy_checkpoint_present and FileAccess.get_file_as_string(directory.path_join("checkpoint.json")) == "legacy checkpoint exact bytes","dev1 migration preserves legacy checkpoint bytes")
	app.free()
func _test_transient_retry_and_oversize(t) -> void:
	var fixture := Support.new().make(t)
	var source: String = FileAccess.get_file_as_string(fixture.directory.path_join("game_save.json"))
	fixture.app.free()
	var faults := {"read":true,"count":0}
	var fault := func(stage):
		if stage == "read_primary":
			faults.count += 1
			if faults.read: return ERR_CANT_OPEN
		return OK
	var app = _restart_observed(t,fixture.directory,fault)
	t.check(app._startup_view.get("kind") == "retry" and app.save_store.load_count == 0,"transient inspection read failure waits for explicit retry without migrating")
	var count: int = faults.count
	for frame in 8: app.advance_frame(1.0/60.0)
	t.check(faults.count == count,"read failure is not retried each frame")
	faults.read = false
	app.retry_save_recovery()
	t.check(app._startup_view.is_empty() and not app.game_save.is_empty(),"explicit retry resumes startup after a transient read succeeds")
	t.check(FileAccess.get_file_as_string(fixture.directory.path_join("game_save.json")) == source,"successful read retry does not rewrite existing authority")
	app.free()
	var directory: String = _unique_directory("oversize")
	var file := FileAccess.open(directory.path_join("game_save.json"),FileAccess.WRITE)
	file.seek(Store.MAX_BYTES)
	file.store_8(32)
	file.close()
	app = _restart_observed(t,directory)
	t.check(app._startup_view.get("kind") == "oversize" and app.ui._subtitle.text.contains("16 MiB"),"oversize receives a distinct actionable size diagnosis")
	t.check(not _button_ids(app.ui).has("recovery_retry") and not _button_ids(app.ui).has("recovery_start"),"oversize has no endless retry or replacement action")
	t.check(app.save_store.load_count == 0 and FileAccess.get_file_as_bytes(directory.path_join("game_save.json")).size() == Store.MAX_BYTES+1,"oversize file is preserved without load or migration")
	app.free()
func _test_future_and_invalid_preservation(t) -> void:
	for variant in ["whole_future","profile_future","checkpoint_future","invalid_economy","unknown_checkpoint"]:
		var fixture := _incompatible_fixture(t)
		var hostile: Dictionary = fixture.save.duplicate(true)
		match variant:
			"whole_future": hostile.schema_version = 99
			"profile_future": hostile.profile.schema_version = 2147483648
			"checkpoint_future": hostile.checkpoint.schema_version = 99
			"unknown_checkpoint": hostile.checkpoint = {"schema_version":2,"content_revision":"unrecognized"}
			"invalid_economy": hostile.profile.supply_credits = -1
		var source := JSON.stringify(hostile,"",true,true)
		_write(fixture.directory.path_join("game_save.json"),source)
		var app = _restart_observed(t,fixture.directory)
		t.check(app.game_save.is_empty() and app.state.is_empty() and not _button_ids(app.ui).has("recovery_start"),variant+" cannot offer or adopt replacement")
		app.confirm_preserved_run_start(149)
		app.advance_frame(1.0)
		t.check(app.save_store.load_count == 0 and FileAccess.get_file_as_string(fixture.directory.path_join("game_save.json")) == source,variant+" exact authority remains untouched")
		app.free()
func _test_unknown_same_id_retry(t) -> void:
	var fixture := _incompatible_fixture(t,true)
	var fault_count := {"replaces":0}
	var fault := func(stage):
		if stage == "after_replace_before_return":
			fault_count.replaces += 1
			return ERR_CANT_CREATE
		return OK
	var app = _restart_observed(t,fixture.directory,fault)
	app.confirm_preserved_run_start(150)
	t.check(app._startup_view.get("kind") == "recovery_pending" and not app._pending_recovery.is_empty(),"unknown recovery outcome retains immutable same-ID request")
	t.check(app.state.is_empty() and app.game_save.is_empty(),"unknown write never publishes an unconfirmed runtime or economic authority")
	var request: String = app._pending_recovery.request_id
	var candidate: Dictionary = app._pending_recovery.candidate.duplicate(true)
	for frame in 8: app.advance_frame(1.0/60.0)
	t.check(fault_count.replaces == 1 and app._pending_recovery.request_id == request,"unknown recovery does not automatically repeat writes")
	app.retry_save_recovery()
	t.check(not app.state.is_empty() and app.state.seed == 150 and app._pending_recovery.is_empty(),"explicit same-ID readback adopts confirmed replacement")
	t.check(fault_count.replaces == 1 and app.game_save.store_revision == candidate.store_revision+1 and app.game_save.next_run_serial == candidate.next_run_serial,"confirmed readback does not repeat revision, serial or supply debit")
	t.check(app.game_save.profile.consumables.field_bandage == candidate.profile.consumables.field_bandage,"unknown recovery debits supply only once")
	app.free()
func _test_prewrite_same_candidate_retry(t) -> void:
	var fixture := _incompatible_fixture(t)
	var faults := {"fail":true,"writes":0}
	var fault := func(stage):
		if stage == "write":
			faults.writes += 1
			if faults.fail: return ERR_CANT_CREATE
		return OK
	var app = _restart_observed(t,fixture.directory,fault)
	app.confirm_preserved_run_start(151)
	t.check(app._startup_view.get("kind") == "recovery_retry" and app.state.is_empty(),"prewrite failure preserves source and waits for explicit recovery retry")
	var request: String = app._pending_recovery.request_id
	var candidate: Dictionary = app._pending_recovery.candidate.duplicate(true)
	t.check(FileAccess.get_file_as_string(fixture.directory.path_join("game_save.json")) == fixture.source,"prewrite failure keeps exact source authoritative")
	faults.fail = false
	app.retry_save_recovery()
	t.check(not app.state.is_empty() and app.state.seed == candidate.checkpoint.seed and app.game_save.checkpoint_recovery_receipt.request_id == request,"prewrite retry uses identical candidate seed and request ID")
	t.check(faults.writes == 2 and app.game_save.next_run_serial == fixture.save.next_run_serial+1,"one failed write and one successful write advance serial only once")
	app.free()
func _test_lifecycle_during_adoption(t) -> void:
	for reason in ["background","controller_lost"]:
		var fixture := _incompatible_fixture(t)
		var app = _restart_observed(t,fixture.directory)
		app.save_store._fault_injector = func(stage):
			if stage == "after_replace_before_return":
				if reason == "background": app._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
				else:
					app.input_router.active_device = 0
					app.input_router._on_connection(0,false)
			return OK
		app.input_router.set_touch_vector(Vector2.RIGHT)
		app.confirm_preserved_run_start(152)
		t.check(not app.state.is_empty() and reason in app.state.pause_reasons,"recovery adoption overlays latest "+reason+" generation")
		if app.state.is_empty():
			app.free()
			continue
		t.check(not reason in app.game_save.checkpoint.pause_reasons,"recovery "+reason+" remains environmental intent outside immutable committed bytes")
		var before: Dictionary = app.simulation.snapshot(app.state)
		var sounds: Dictionary = app.audio._last_played.duplicate(true)
		app.advance_frame(1.0)
		t.check(app.state.active_tick == before.active_tick and app.state.player.position == before.player.position and app.input_router.sample_move() == Vector2.ZERO,"recovery "+reason+" blocks tick and clears movement")
		t.check(app.audio._music.stream_paused and app.audio._last_played == sounds,"recovery "+reason+" keeps audio silent and paused")
		if reason == "background": app._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
		app.advance_frame(1.0/60.0)
		t.check(app.state.active_tick == before.active_tick,"recovery "+reason+" never resumes just from focus return")
		app.save_store._fault_injector = Callable()
		app.request_resume()
		app.advance_frame(1.0/60.0)
		t.check(app.state.active_tick == before.active_tick+1,"recovery "+reason+" needs explicit continue before ticking")
		app.free()
func _test_exhausted_supply_choice(t) -> void:
	var fixture := _incompatible_fixture(t)
	fixture.save.profile.loadout.supply_item_id = "field_bandage"
	fixture.save.profile.consumables.field_bandage = 0
	fixture.source = JSON.stringify(fixture.save,"",true,true)
	_write(fixture.directory.path_join("game_save.json"),fixture.source)
	var app = _restart_observed(t,fixture.directory)
	app.confirm_preserved_run_start(153)
	t.check(app._startup_view.get("kind") == "checkpoint" and app.state.is_empty(),"exhausted configured supply returns to explicit recovery choice without hidden loadout change")
	t.check(_button_ids(app.ui).has("recovery_supply"),"recovery provides explicit no-supply choice when prior preparation cannot be reused")
	if app._startup_view.get("kind") == "checkpoint" and _button_ids(app.ui).has("recovery_supply"):
		app.ui._restore_focus("recovery_supply")
		app.ui.accept_released()
		app.ui.navigate("accept")
		app.confirm_preserved_run_start(153)
		t.check(not app.state.is_empty() and app.state.run_config.prepared_supply == "" and app.game_save.profile.loadout.supply_item_id == "","explicit no-supply selection starts actual replacement without debit")
	t.check(FileAccess.get_file_as_string(fixture.directory.path_join("archives").path_join(fixture.source.sha256_text()+".json")) == fixture.source,"exhausted supply attempt preserves exact source archive")
	app.free()
func _test_conflict_appears_during_confirmation(t) -> void:
	var fixture := _incompatible_fixture(t)
	var app = _restart_observed(t,fixture.directory)
	var alternate: String = fixture.directory.get_base_dir().path_join("game_save.json")
	_write(alternate,fixture.backup)
	app.confirm_preserved_run_start(154)
	t.check(app._startup_view.get("kind") == "conflict" and app.state.is_empty(),"new alternate lineage appearing before explicit choice blocks preservation and replacement")
	t.check(FileAccess.get_file_as_string(fixture.directory.path_join("game_save.json")) == fixture.source and FileAccess.get_file_as_string(alternate) == fixture.backup,"late lineage conflict preserves both exact sources")
	t.check(not DirAccess.dir_exists_absolute(fixture.directory.path_join("archives")),"late lineage conflict is caught before source archive mutation")
	app.free()
func _test_nonretryable_commit_failure(t) -> void:
	var fixture := _incompatible_fixture(t)
	var app = _restart_observed(t,fixture.directory)
	var changed: Dictionary = fixture.save.duplicate(true)
	changed.recovery_fixture_note = "new external authority"
	var changed_source := JSON.stringify(changed,"",true,true)
	app.save_store._fault_injector = func(stage):
		if stage == "replace": _write(fixture.directory.path_join("game_save.json"),changed_source)
		return OK
	app.confirm_preserved_run_start(155)
	t.check(app._startup_view.get("kind") == "blocked" and not _button_ids(app.ui).has("recovery_retry"),"stale source commit is diagnosed as preserve-only rather than an endless same-ID retry")
	t.check(app._pending_recovery.is_empty() and app.state.is_empty() and app.game_save.is_empty(),"confirmed stale source abandons no authority and publishes no candidate")
	app.keep_saved_authority()
	t.check(app._startup_view.get("kind") == "kept" and FileAccess.get_file_as_string(fixture.directory.path_join("game_save.json")) == changed_source,"stale source preserve-only screen can return while retaining changed bytes")
	app.free()
func _test_late_live_lineage_conflict(t) -> void:
	var fixture := Support.new().make(t)
	var app = fixture.app
	app.start_run(156)
	var source: String = FileAccess.get_file_as_string(fixture.directory.path_join("game_save.json"))
	var distinct: Dictionary = app.game_save.duplicate(true)
	distinct.profile.settings.reduce_effects = true
	var alternate: String = fixture.directory.get_base_dir().path_join("game_save.json")
	var distinct_source := JSON.stringify(distinct,"",true,true)
	_write(alternate,distinct_source)
	var settings: Dictionary = app.profile.settings.duplicate(true)
	settings.audio_master = 0.4
	app._apply_settings(settings)
	t.check(app._startup_view.get("kind") == "conflict","a distinct lineage appearing during play blocks the next authority command")
	var tick: int = app.state.active_tick
	app.advance_frame(1.0/60.0)
	t.check(app.state.active_tick == tick and app.audio._music.stream_paused,"late live lineage conflict owns the clock and audio")
	t.check(FileAccess.get_file_as_string(fixture.directory.path_join("game_save.json")) == source and FileAccess.get_file_as_string(alternate) == distinct_source,"late live conflict prevents ordinary writes to either lineage")
	app.free()
func _test_recovery_input_modal(t) -> void:
	var fixture := _incompatible_fixture(t)
	var app = _restart_observed(t,fixture.directory)
	app._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	t.check(app.ui._mode == "save_recovery" and app.ui._buttons.is_empty(),"background recovery screen exposes no actionable controls")
	app.ui.recovery_start_requested.emit()
	t.check(app.state.is_empty() and not DirAccess.dir_exists_absolute(fixture.directory.path_join("archives")),"background input cannot bypass explicit recovery choice")
	app._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	t.check(_button_ids(app.ui) == ["recovery_continue"],"focus return requires explicit recovery continue")
	var press := InputEventKey.new()
	press.keycode = KEY_ENTER
	press.pressed = true
	app.input_router.handle_event(press)
	t.check(not app._lifecycle_blocked() and app.ui.focused_semantic_id() == "recovery_keep","keyboard confirm clears only lifecycle overlay and returns to safe choice")
	app.input_router.handle_event(press)
	t.check(app._startup_view.get("kind") == "checkpoint","held keyboard confirm cannot carry over into recovery action")
	var release := InputEventKey.new()
	release.keycode = KEY_ENTER
	app.ui._input(release)
	var down := InputEventJoypadButton.new()
	down.device = 0
	down.button_index = JOY_BUTTON_DPAD_DOWN
	down.pressed = true
	app.input_router.handle_event(down)
	app.input_router._process(0.01)
	t.check(app.ui.focused_semantic_id() == "recovery_start","gamepad direction reaches explicit preserved start")
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	touch.position = Vector2(20,400)
	app.ui._input(touch)
	t.check(app.ui._touch_id == -1 and app.input_router.sample_move().x == 0,"touch movement cannot leak behind recovery modal")
	# Button pressed is the same Control signal used by native touch activation;
	# this is a headless signal-path check, not a rendered touch-hit-test claim.
	app.ui._buttons[1].pressed.emit()
	t.check(not app.state.is_empty() and app.ui._mode == "play","recovery button signal reaches actual verified authority adoption")
	app.free()
func _test_recovery_inspection_read_retry(t) -> void:
	var fixture := _incompatible_fixture(t)
	var reads := {"count":0,"blocked":true}
	var fault := func(stage):
		if stage == "read_primary":
			reads.count += 1
			# Three bounded-location reads precede recovery offer validation.
			if reads.blocked and reads.count == 4: return ERR_CANT_OPEN
		return OK
	var app = _restart_observed(t,fixture.directory,fault)
	t.check(app._startup_view.get("kind") == "retry" and _button_ids(app.ui).has("recovery_retry"),"transient recovery-offer read failure keeps explicit read retry available")
	t.check(FileAccess.get_file_as_string(fixture.directory.path_join("game_save.json")) == fixture.source and not DirAccess.dir_exists_absolute(fixture.directory.path_join("archives")),"recovery-offer read failure preserves source without archival writes")
	reads.blocked = false
	app.retry_save_recovery()
	t.check(app._startup_view.get("kind") == "checkpoint" and not app._recovery_offer.is_empty(),"explicit retry after offer-read failure recovers the validated choice")
	app.free()
func _incompatible_fixture(t,with_world: bool = false) -> Dictionary:
	var fixture := Support.new().make(t)
	fixture.app.start_run(145)
	var old: Dictionary = fixture.app.game_save.duplicate(true)
	fixture.app.free()
	old.checkpoint.content_revision = "ch01.old-preserved"
	old.profile.settings.reduce_effects = true
	old.recovery_fixture_note = "retained user metadata"
	if with_world:
		old.profile.consumables.field_bandage = 3
		old.profile.loadout.supply_item_id = "field_bandage"
		old.checkpoint.world = {"delta_root":{"opaque_future_version":9,"preserved_token":"exact-root"}}
		_write(fixture.directory.path_join("world/opaque-page"),"opaque original world bytes")
	var source := JSON.stringify(old,"",true,true)
	_write(fixture.directory.path_join("game_save.json"),source)
	return {"directory":fixture.directory,"save":old,"source":source,"backup":FileAccess.get_file_as_string(fixture.directory.path_join("game_save.json.bak"))}
func _restart_observed(t,directory: String,fault: Callable = Callable()):
	var app = Controller.new()
	var validator = Core.new()
	app.set_meta("recovery_test_validator",validator)
	app.save_store = ObservedStore.new(directory,Callable(validator,"restore"),fault)
	t.root.add_child(app)
	app.set_process(false)
	app.world.set_process(false)
	return app
func _unique_directory(label: String) -> String:
	var directory := "user://recovery_ui_%s_%d_%d/saves" % [label,OS.get_process_id(),Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(directory)
	return directory
func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(text)
	file.close()
func _button_ids(ui) -> Array:
	var result := []
	for button in ui._buttons: result.append(str(button.get_meta("semantic_id","")))
	return result
