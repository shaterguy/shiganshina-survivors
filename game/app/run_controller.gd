extends Node
const Simulation = preload("res://game/core/run_simulation.gd")
const Director = preload("res://game/director/spawn_director.gd")
const Chapters = preload("res://game/director/chapter_catalog.gd")
const Router = preload("res://game/input/input_router.gd")
const Lifecycle = preload("res://game/input/lifecycle_guard.gd")
const UI = preload("res://game/ui/game_ui.gd")
const Audio = preload("res://game/presentation/audio_director.gd")
const Save = preload("res://game/persistence/game_save_store.gd")
const Supply = preload("res://game/economy/supply_service.gd")
const Progression = preload("res://game/progression/progression_view.gd")
const World = preload("res://game/presentation/world_view.gd")
const CityRuntime = preload("res://game/app/prepared_city_runtime.gd")
const WorldCheckpoint = preload("res://game/app/world_checkpoint_adapter.gd")
const Streamed = preload("res://game/core/streamed_run_world.gd")
const FinalEvacuationFlow = preload("res://game/app/final_evacuation_flow.gd")
var _final_intent: Dictionary = {}
var _final_error := ""
const TICK_DURATION := 1.0/60.0
const TERMINAL := ["dead","won","abandoned"]
var simulation = Simulation.new()
var director = Director.new()
var chapter: Dictionary = {}
var state: Dictionary = {}
# Validation and preparation never touch the active Core's runtime caches.
var validation_simulation = Simulation.new()
var candidate_simulation = Simulation.new()
var save_store = Save.new("user://saves",Callable(validation_simulation,"restore"))
var supply_service = Supply.new(Callable(candidate_simulation,"new_run"))
var progression_view = Progression.new()
var game_save: Dictionary = {}
# Compatibility rendering copy only. All writes go through game_save.
var profile: Dictionary = {}
var pending_checkpoint: Dictionary = {}
var _new_run_intent: Dictionary = {}
var _pending_transaction: Dictionary = {}
var _failed_growth: Dictionary = {}
var _presented_supply_revision := -1
var _presented_growth_key := ""
var _view_revision := 0
var _view_store_revision := -1
var _last_save_tick := -1
var _last_phase := ""
var input_router
var ui
var world
var audio
var _accumulator := 0.0
var _foreground := true
var _lifecycle_generation := 0
var _lifecycle_pause_intent := {"background":false,"controller_lost":false}
var _shop_open := false
var _startup_view: Dictionary = {}
var _startup_inspection: Dictionary = {}
var _recovery_offer: Dictionary = {}
var _recovery_selection: Dictionary = {}
var _pending_recovery: Dictionary = {}
var _initial_location_check := true
var _allow_fresh_initialization := false
var _allow_legacy_migration := false
var _observed_save_source := false
var _observed_v2_source := false
var _pending_initialization: Dictionary = {}
# Explicit opt-in for isolated city integration. The shipped scene stays finite.
var _city_runtime
var _city_provider
var _world_delta_store
var _pending_city_tick: Dictionary = {}
var _city_step_error := ""
var _city_render_error := ""
var _city_terrain_key := ""
var _city_terrain_view: Dictionary = {}
func configure_city_runtime(provider, runtime, world_store, directory: String) -> Dictionary:
	if is_inside_tree() or not game_save.is_empty() or directory.is_empty(): return {"ok":false,"error_code":"configuration_locked"}
	if not runtime is CityRuntime or runtime._provider != provider or runtime._world_store != world_store: return {"ok":false,"error_code":"content_mismatch"}
	var loaded: Dictionary = provider.load_chapter("chapter_01_shiganshina")
	if not loaded.get("ok",false) or loaded.get("chapter",{}).get("world_mode") != "streamed_city": return {"ok":false,"error_code":"content_mismatch"}
	_city_provider = provider
	_city_runtime = runtime
	_world_delta_store = world_store
	chapter = loaded.chapter
	_adopt_city_simulation(Simulation.new(provider))
	save_store = Save.new(directory,Callable(runtime,"validate_checkpoint"))
	supply_service = Supply.new(Callable(runtime,"new_run"))
	return {"ok":true}
func _adopt_city_simulation(core) -> void:
	simulation = core
	progression_view = Progression.new(core._catalog)
	chapter = core._chapter.duplicate(true)
func _select_checkpoint_chapter(snapshot: Dictionary) -> bool:
	if _city_runtime == null or _city_runtime._content_router == null: return true
	var selected: Dictionary = _city_runtime.resolve_content(snapshot)
	if not selected.get("ok",false): return false
	chapter = selected.chapter.duplicate(true)
	return true
func _ready() -> void:
	if _city_runtime == null: chapter = Chapters.new().load_chapter("chapter_01_shiganshina").chapter
	audio = Audio.new()
	audio.name = "AudioDirector"
	add_child(audio)
	world = World.new()
	world.name = "World"
	add_child(world)
	input_router = Router.new()
	input_router.name = "InputRouter"
	add_child(input_router)
	ui = UI.new()
	ui.name = "GameUI"
	add_child(ui)
	ui.audio_requested.connect(func(id: String):
		if not _lifecycle_blocked(): audio.play_sound(id))
	ui.recovery_start_requested.connect(func(): confirm_preserved_run_start(randi() & 0x7fffffff))
	ui.recovery_keep_requested.connect(keep_saved_authority)
	ui.recovery_retry_requested.connect(retry_save_recovery)
	ui.recovery_continue_requested.connect(request_recovery_continue)
	ui.recovery_supply_toggled.connect(toggle_recovery_supply)
	ui.new_run_requested.connect(func(): request_new_run(randi() & 0x7fffffff))
	ui.new_run_replacement_confirmed.connect(func(run_id: String): request_new_run(randi() & 0x7fffffff,true,run_id))
	ui.run_start_requested.connect(func(): start_run(randi() & 0x7fffffff))
	ui.resume_requested.connect(request_resume)
	ui.pause_changed.connect(set_user_pause)
	ui.end_run_requested.connect(request_end_run)
	ui.upgrade_chosen.connect(apply_upgrade)
	ui.upgrade_focus_changed.connect(func(id):
		if not state.is_empty(): simulation.set_offer_focus(state,id))
	ui.settings_changed.connect(_apply_settings)
	ui.purchase_requested.connect(apply_purchase)
	ui.loadout_changed.connect(apply_loadout)
	ui.character_selected.connect(apply_character_selection)
	ui.shop_open_requested.connect(_open_shop)
	ui.shop_closed.connect(_close_shop)
	ui.touch_move_changed.connect(input_router.set_touch_vector)
	input_router.ui_action.connect(ui.navigate)
	input_router.input_hint_changed.connect(ui.set_input_hint)
	input_router.active_controller_lost.connect(func():
		_latch_lifecycle_pause("controller_lost")
		if not state.is_empty(): _save_checkpoint()
		_present())
	get_viewport().size_changed.connect(_resize)
	_begin_startup()
	_resize()
	if not state.is_empty() and state.phase in TERMINAL:
		for receipt in game_save.settlement_receipts:
			if receipt.run_id == state.run_id: ui.present_action_result({"ok":true,"action":"settlement","receipt":receipt.duplicate(true)})
func _begin_startup() -> void:
	# Inspect bounded historical paths before the source-bound initializer.
	_startup_inspection = save_store.inspect_known_locations(save_store._directory.get_base_dir())
	if _startup_inspection.get("ok",false):
		var canonical: Dictionary = _startup_inspection.locations[0]
		var alternate: Dictionary = _startup_inspection.locations[1]
		if _initial_location_check:
			_allow_fresh_initialization = canonical.status == "absent" and alternate.status == "absent"
			# A first transient legacy read is eligible for explicit reinspection.
			# Its hash map is bound only after a successful validated inspection.
			_allow_legacy_migration = alternate.status == "absent" and (canonical.files.has("profile.json") or canonical.files.has("profile.json.bak")) and not (canonical.files.has("game_save.json") or canonical.files.has("game_save.json.bak"))
			_initial_location_check = false
		for location in _startup_inspection.locations:
			if not location.files.is_empty(): _observed_save_source = true
			if location.files.has("game_save.json") or location.files.has("game_save.json.bak"):
				_observed_v2_source = true
				_allow_fresh_initialization = false
				_allow_legacy_migration = false
	_recovery_offer.clear()
	_recovery_selection.clear()
	if not _startup_inspection.get("ok",false):
		_show_startup_block("blocked",str(_startup_inspection.get("error_code","invalid_game_save")))
		return
	var decision: String = str(_startup_inspection.decision)
	if decision == "choose_lineage":
		_show_startup_block("conflict","distinct_authorities")
		return
	if decision == "retry_read":
		_show_startup_block("retry","read_failed")
		return
	if not _pending_initialization.is_empty():
		_complete_startup_load(_attempt_initialization())
		return
	if decision == "blocked":
		var canonical: Dictionary = _startup_inspection.locations[0]
		if canonical.status == "checkpoint_incompatible":
			var offered: Dictionary = save_store.inspect_checkpoint_recovery()
			if offered.get("ok",false):
				_recovery_offer = offered.recovery_offer.duplicate(true)
				_recovery_selection = _recovery_offer.loadout.duplicate(true)
				_show_startup_block("checkpoint",str(_recovery_offer.compatibility_reason))
				return
			if offered.get("error_code") == "read_failed" and offered.get("diagnostics",{}).get("reason") != "oversize":
				_show_startup_block("retry","read_failed")
				return
		var oversize := false
		for location in _startup_inspection.locations:
			if location.get("diagnostics",{}).get("reason") == "oversize": oversize = true
		_show_startup_block("oversize" if oversize else "blocked", "oversize" if oversize else str(canonical.get("error_code","invalid_game_save")))
		return
	var canonical: Dictionary = _startup_inspection.locations[0]
	if canonical.status == "absent" and _observed_save_source:
		_show_startup_block("blocked","authority_missing")
		return
	var initialize: bool = (_allow_fresh_initialization and canonical.status == "absent" and not _observed_save_source) or (_allow_legacy_migration and not _observed_v2_source and canonical.status == "supported_legacy")
	if initialize:
		_pending_initialization = {"observed_files":canonical.files.duplicate(true),"career_id":Crypto.new().generate_random_bytes(16).hex_encode(),"lifecycle_generation":_lifecycle_generation}
	_complete_startup_load(_attempt_initialization() if initialize else save_store.read_game())
func _attempt_initialization() -> Dictionary:
	var intent := _pending_initialization.duplicate(true)
	if intent.has("candidate"):
		var current: Dictionary = save_store.read_game()
		if current.get("ok",false):
			if current.get("recovered",false) or current.get("source_sha256","") != intent.sha256 or not _same_json(current.game_save,intent.candidate): return {"ok":false,"error_code":"stale_revision"}
			return current
		if current.get("error_code") != "not_found": return current
	var result: Dictionary = save_store.initialize_game(intent.observed_files,intent.career_id)
	if result.get("error_code") == "commit_outcome_unknown":
		_pending_initialization.candidate = result.pending_initialization_candidate.duplicate(true)
		_pending_initialization.sha256 = result.pending_initialization_sha256
	return result
func _complete_startup_load(loaded: Dictionary) -> void:
	if not loaded.get("ok",false):
		var code: String = str(loaded.get("error_code","invalid_game_save"))
		var kind := "blocked"
		if loaded.get("diagnostics",{}).get("reason") == "oversize": kind = "oversize"
		elif code in ["read_failed","write_failed","verify_failed","backup_failed","replace_failed","commit_outcome_unknown"]: kind = "retry"
		if kind == "retry" and not _pending_initialization.is_empty(): kind = "initialization_retry"
		_show_startup_block(kind,code)
		return
	var terminal_pair := {}
	if _city_runtime != null and loaded.game_save.checkpoint is Dictionary and loaded.game_save.checkpoint.phase in TERMINAL:
		terminal_pair = _prepare_city_load(loaded.game_save)
		if not terminal_pair.get("ok",false):
			_show_startup_block("retry",str(terminal_pair.get("error_code","world_not_ready")))
			return
	_pending_initialization.clear()
	_startup_view.clear()
	_install_authority(loaded.game_save)
	state = {}
	pending_checkpoint = {}
	if game_save.checkpoint is Dictionary:
		if not _select_checkpoint_chapter(game_save.checkpoint) or not checkpoint_matches_chapter(game_save.checkpoint,chapter):
			_show_startup_block("blocked","content_mismatch")
			return
		if game_save.checkpoint.phase in TERMINAL:
			if not terminal_pair.is_empty():
				_adopt_city_simulation(terminal_pair.simulation)
				state = terminal_pair.state
			else: state = game_save.checkpoint.duplicate(true)
		else: pending_checkpoint = game_save.checkpoint.duplicate(true)
	ui.set_checkpoint_available(not pending_checkpoint.is_empty(),str(pending_checkpoint.get("run_id","")))
	_apply_lifecycle_pause(state)
	_install_settings(profile.settings)
	if loaded.get("recovered",false): ui.set_save_notice("이전 안전 저장 지점에서 복구했습니다.")
	elif loaded.get("notice_code","") == "legacy_checkpoint_preserved": ui.set_save_notice("이전 버전 전투는 그대로 보관했습니다. 새 출격을 준비할 수 있습니다.")
	else: ui.set_save_notice("")
	if _lifecycle_blocked():
		_show_startup_block("startup_ready","lifecycle_pause")
		return
	_present()
func _show_startup_block(kind: String, code: String) -> void:
	_pending_city_tick.clear()
	_startup_view = {"kind":kind,"error_code":code,"offer":_recovery_offer.duplicate(true),"selection":_recovery_selection.duplicate(true),"has_pending_request":not _pending_recovery.is_empty() or not _pending_initialization.is_empty(),"locations":_startup_inspection.get("locations",[]).duplicate(true)}
	_accumulator = 0
	if is_instance_valid(input_router): input_router.clear_transient_input()
	_present()
func keep_saved_authority() -> void:
	if _startup_view.is_empty() or _lifecycle_blocked(): return
	_show_startup_block("kept",str(_startup_view.get("error_code","")))
func retry_save_recovery() -> void:
	if _lifecycle_blocked(): return
	if not _final_intent.is_empty() or not _final_error.is_empty():
		if _startup_view.get("error_code") == "authority_mismatch" and not _pending_transaction.is_empty():
			_retry_city_authority()
			return
		retry_final_transition()
		return
	if _worker_recovery_active():
		retry_worker_recovery()
		return
	if _city_runtime != null and not _pending_transaction.is_empty():
		_retry_city_authority()
	elif not _pending_recovery.is_empty():
		_attempt_preserved_commit()
	elif not _pending_initialization.is_empty() or _startup_view.get("kind") in ["retry","kept","checkpoint","recovery_retry"]:
		_begin_startup()
func request_recovery_continue() -> void:
	if not _foreground or (_startup_view.is_empty() and not _worker_recovery_active() and _final_intent.is_empty() and _final_error.is_empty()): return
	# Returning to save recovery never grants permission to resume combat.
	if _worker_recovery_active() and not state.is_empty(): simulation.set_pause(state,"user",true)
	_lifecycle_generation += 1
	_lifecycle_pause_intent = {"background":false,"controller_lost":false}
	if not _final_intent.is_empty() or not _final_error.is_empty():
		for reason in ["background","controller_lost"]: simulation.set_pause(state,reason,false)
	input_router.clear_transient_input()
	if _startup_view.get("kind") == "startup_ready": _startup_view.clear()
	_present()
func toggle_recovery_supply() -> void:
	if _startup_view.get("kind") != "checkpoint" or _lifecycle_blocked() or not _pending_recovery.is_empty(): return
	if str(_recovery_offer.get("loadout",{}).get("supply_item_id","")).is_empty(): return
	_recovery_selection.supply_item_id = "" if not str(_recovery_selection.get("supply_item_id","")).is_empty() else _recovery_offer.loadout.supply_item_id
	_show_startup_block("checkpoint",str(_recovery_offer.compatibility_reason))
func confirm_preserved_run_start(seed: int) -> void:
	if _startup_view.get("kind") != "checkpoint" or _recovery_offer.is_empty() or not _pending_recovery.is_empty() or _lifecycle_blocked(): return
	# Reinspect both known locations on the explicit choice; a new conflict cannot
	# be resolved by silently selecting whichever save was shown earlier.
	if not _recovery_locations_safe(): return
	var offer := _recovery_offer.duplicate(true)
	var preserved: Dictionary = save_store.preserve_checkpoint_authority(offer.source_sha256,int(offer.store_revision))
	if not preserved.get("ok",false):
		_recovery_failed(str(preserved.get("error_code","write_failed")))
		return
	var request_id := "recover:%s:%s:%d" % [offer.career_id,offer.source_sha256,int(offer.next_run_serial)]
	var prepared: Dictionary = supply_service.prepare_preserved_run_start(preserved.source,chapter,seed & 0x7fffffff,_recovery_selection,request_id,preserved.archive_receipt,int(offer.store_revision))
	if not prepared.get("ok",false):
		var code: String = str(prepared.get("error_code","invalid_snapshot"))
		_show_startup_block("checkpoint" if code == "invalid_loadout" else "blocked",code)
		return
	_pending_recovery = {"candidate":prepared.candidate.duplicate(true),"source_sha256":offer.source_sha256,"request_id":request_id,"expected_revision":int(offer.store_revision),"receipt":prepared.receipt.duplicate(true),"lifecycle_generation":_lifecycle_generation}
	_show_startup_block("recovery_retry","prepared_request")
	_attempt_preserved_commit()
func _recovery_locations_safe() -> bool:
	_startup_inspection = save_store.inspect_known_locations(save_store._directory.get_base_dir())
	if not _startup_inspection.get("ok",false):
		_show_startup_block("blocked","invalid_game_save")
		return false
	if _startup_inspection.decision == "choose_lineage":
		_show_startup_block("conflict","distinct_authorities")
		return false
	if _startup_inspection.decision == "retry_read":
		_show_startup_block("recovery_retry","read_failed")
		return false
	for location in _startup_inspection.locations:
		if location.get("diagnostics",{}).get("reason") == "oversize":
			_show_startup_block("oversize","oversize")
			return false
	return true
func _attempt_preserved_commit() -> void:
	if _pending_recovery.is_empty() or _lifecycle_blocked() or not _recovery_locations_safe(): return
	var transaction := _pending_recovery.duplicate(true)
	if _city_runtime != null:
		var prepared := _prepare_city_candidate(transaction.candidate)
		if not prepared.get("ok",false):
			_show_startup_block("recovery_retry",str(prepared.get("error_code","world_not_ready")))
			return
		transaction.candidate = prepared.candidate
		_pending_recovery.candidate = prepared.candidate.duplicate(true)
	# The special Store API first checks its durable same-ID receipt and returns
	# current authority without a write. Never call mutating load_game here.
	var committed: Dictionary = save_store.commit_preserved_run_start(transaction.candidate,transaction.source_sha256,transaction.request_id,transaction.expected_revision)
	if committed.get("ok",false):
		var pair := {}
		if _city_runtime != null:
			pair = _city_runtime.confirm_candidate(save_store)
			if not pair.get("ok",false):
				_show_startup_block("recovery_pending",str(pair.get("error_code","commit_outcome_unknown")))
				return
		_publish_preserved_start(committed.game_save,transaction,pair)
		return
	var code: String = str(committed.get("error_code","write_failed"))
	_recovery_failed(code)
func _recovery_failed(code: String) -> void:
	if code == "not_found":
		# Missing source does not settle an outstanding request's outcome. Keep
		# its exact candidate/ID available for an explicit preserved-source retry.
		_show_startup_block("blocked","authority_missing")
	elif code == "commit_outcome_unknown":
		_show_startup_block("recovery_pending",code)
	elif code in ["read_failed","write_failed","verify_failed","backup_failed","replace_failed"]:
		_show_startup_block("recovery_retry",code)
	else:
		# Store has definitively rejected this candidate/source identity. Preserve
		# every file; require a new inspection/choice rather than retry forever.
		_pending_recovery.clear()
		_show_startup_block("blocked",code)
func _publish_preserved_start(authority: Dictionary, transaction: Dictionary, prepared_pair: Dictionary = {}) -> void:
	# Only confirmed authority is installed. Latest environmental generation is
	# overlaid after adopting exact durable bytes, never folded into the candidate.
	_pending_recovery.clear()
	_startup_view.clear()
	_recovery_offer.clear()
	ui.present_recovery({})
	_publish_transaction(authority,{"replace_state":true,"events":[],"reset_presentation":true,"action":"recovery_start","receipt":transaction.receipt,"lifecycle_generation":transaction.lifecycle_generation},prepared_pair)
	_install_settings(profile.settings)
	ui.set_save_notice("이전 전투를 보관하고 새로 출격했습니다. 이전 전투 보상과 보급품 환급은 없습니다.")
func supply_view() -> Dictionary:
	if game_save.is_empty(): return {}
	var view: Dictionary = supply_service.shop_view(game_save,str(chapter.chapter_id))
	view.view_revision = _view_revision
	if not _pending_transaction.is_empty():
		view.can_shop = false
		view.can_start = false
		view.lock_reason = "commit_outcome_unknown"
		view.start_blocked_reason = "commit_outcome_unknown"
		for row in view.items:
			row.can_purchase = false
			row.blocked_reason = "commit_outcome_unknown"
		for rows in view.loadout_options.values():
			for row in rows:
				row.can_select = false
				row.blocked_reason = "commit_outcome_unknown"
		for row in view.get("character_options",[]):
			row.can_select = false
			row.blocked_reason = "commit_outcome_unknown"
	return view
func apply_purchase(item_id: String, view_revision: int) -> void:
	if _defer_worker_command("purchase",[item_id],view_revision): return
	if not _command_ready("purchase",view_revision): return
	var request_id := "purchase:%s:%d:%s" % [game_save.career_id,int(game_save.store_revision),item_id]
	var prepared: Dictionary = supply_service.prepare_purchase(game_save,item_id,request_id,int(game_save.store_revision))
	if not prepared.ok:
		_action_failed("purchase",prepared.error_code)
		return
	if prepared.get("already_applied",false):
		_action_succeeded("purchase",prepared.receipt)
		return
	_commit_candidate(prepared.candidate,"purchase",prepared.receipt)
func apply_loadout(selection: Dictionary, view_revision: int) -> void:
	if _defer_worker_command("loadout",[selection.duplicate(true)],view_revision): return
	if not _command_ready("loadout",view_revision): return
	var prepared: Dictionary = supply_service.prepare_loadout(game_save,selection,int(game_save.store_revision))
	if not prepared.ok:
		_action_failed("loadout",prepared.error_code)
		return
	_commit_candidate(prepared.candidate,"loadout")
func apply_character_selection(character_id: String, view_revision: int) -> void:
	if _defer_worker_command("character_selection",[character_id],view_revision): return
	if not _command_ready("character_selection",view_revision): return
	var prepared: Dictionary = supply_service.prepare_character_selection(game_save,str(chapter.chapter_id),character_id,int(game_save.store_revision))
	if not prepared.ok:
		_action_failed("character_selection",prepared.error_code)
		return
	_commit_candidate(prepared.candidate,"character_selection")
func request_new_run(seed: int, replace_existing: bool = false, expected_run_id: String = "") -> void:
	# The UI's replacement confirmation is bound to the run it displayed. A
	# repeated/late confirmation can never abandon a newer run.
	if not _new_run_intent.is_empty(): return
	if not _foreground:
		_action_failed("new_run","lifecycle_changed")
		return
	if not _pending_transaction.is_empty():
		resolve_pending_transaction()
		_action_failed("new_run","retry_pending_choice")
		return
	if _defer_worker_command("new_run",[seed,replace_existing,expected_run_id]): return
	if not _command_ready("new_run"): return
	var saved = game_save.checkpoint
	if replace_existing and (expected_run_id.is_empty() or not saved is Dictionary or saved.get("run_id") != expected_run_id):
		_action_failed("new_run","stale_pending_request")
		return
	var already_ended: bool = saved is Dictionary and state.get("run_id") == saved.run_id and state.get("phase","") in TERMINAL
	if saved is Dictionary and not saved.phase in TERMINAL and not already_ended and not replace_existing:
		_action_failed("new_run","active_run")
		return
	if not _final_intent.is_empty() or not _final_error.is_empty():
		_action_failed("new_run","transition_pending")
		return
	# A fresh, explicit foreground sortie request also releases ambient pause.
	# Deferred requests must first pass their original lifecycle-generation check.
	_lifecycle_generation += 1
	_lifecycle_pause_intent = {"background":false,"controller_lost":false}
	if saved == null or (saved.phase in TERMINAL and int(saved.run_serial) <= int(game_save.settled_through_serial)):
		start_run(seed)
		return
	if state.is_empty():
		# Cold startup keeps the active checkpoint offscreen. Prepare it without
		# resuming combat or changing environmental pause ownership.
		var prepared: Dictionary = _prepare_city_load(game_save) if _city_runtime != null else simulation.restore(pending_checkpoint)
		if not prepared.get("ok",false):
			_action_failed("new_run",str(prepared.get("error_code","invalid_snapshot")))
			return
		if _city_runtime != null: _adopt_city_simulation(prepared.simulation)
		state = prepared.state
		pending_checkpoint.clear()
		ui.set_checkpoint_available(false)
	if state.get("run_id") != saved.run_id:
		_action_failed("new_run","stale_pending_request")
		return
	_new_run_intent = {"seed":seed,"run_id":saved.run_id,"run_serial":int(saved.run_serial),"lifecycle_generation":_lifecycle_generation}
	if state.phase in TERMINAL: _record_result()
	else: request_end_run()
	_continue_new_run()
func _continue_new_run() -> void:
	if _new_run_intent.is_empty(): return
	if _lifecycle_blocked() or _new_run_intent.lifecycle_generation != _lifecycle_generation:
		_new_run_intent.clear()
		_action_failed("new_run","lifecycle_changed")
		return
	if not _pending_transaction.is_empty() or not _startup_view.is_empty() or _worker_reserved(): return
	var intent := _new_run_intent
	if state.get("run_id") != intent.run_id or game_save.checkpoint.get("run_id") != intent.run_id:
		_new_run_intent.clear()
		_action_failed("new_run","stale_pending_request")
		return
	if not state.phase in TERMINAL or int(game_save.settled_through_serial) < int(intent.run_serial): return
	var seed: int = intent.seed
	_new_run_intent.clear()
	start_run(seed)
func start_run(seed: int) -> void:
	if _defer_worker_command("run_start",[seed]): return
	if not game_save.is_empty() and not state.is_empty() and state.phase in TERMINAL and int(state.run_serial) > int(game_save.settled_through_serial):
		_record_result()
		return
	if not _command_ready("run_start"): return
	var request_id := "start:%s:%d" % [game_save.career_id,int(game_save.next_run_serial)]
	var next_chapter: Dictionary = chapter
	if _city_runtime != null and _city_runtime._content_router != null:
		var current: Dictionary = _city_runtime.resolve_content()
		if not current.get("ok",false):
			_action_failed("run_start",str(current.get("error_code","content_mismatch")))
			return
		next_chapter = current.chapter
	var prepared: Dictionary = supply_service.prepare_run_start(game_save,next_chapter,seed & 0x7fffffff,request_id,int(game_save.store_revision))
	if not prepared.ok:
		_action_failed("run_start",prepared.error_code)
		return
	if prepared.get("already_applied",false):
		_action_succeeded("run_start",prepared.receipt)
		return
	_commit_candidate(prepared.candidate,"run_start",prepared.receipt,true,[],true)
func _process(delta: float) -> void:
	advance_frame(delta)
func advance_frame(delta: float) -> void:
	if autosave_worker_enabled:
		_poll_autosave_worker()
		_retry_worker_terminal()
		_retry_worker_command()
	_continue_new_run()
	if _worker_recovery_active() and not _autosave_retry_held_tick:
		_accumulator = 0
		_present()
		return
	if not _startup_view.is_empty():
		_accumulator = 0
		_present()
		return
	if not _pending_transaction.is_empty():
		resolve_pending_transaction()
		_accumulator = 0
		_present()
		return
	if not _final_intent.is_empty() or not _final_error.is_empty():
		_accumulator = 0
		_present()
		return
	if state.is_empty(): return
	if not _city_step_error.is_empty() or not _city_render_error.is_empty():
		_present()
		return
	if _shop_open or _lifecycle_blocked() or not state.pause_reasons.is_empty() or state.phase in TERMINAL:
		_apply_lifecycle_pause(state)
		_accumulator = 0
		_present()
		return
	if _pending_city_tick.is_empty(): _accumulator += maxf(delta,0)
	if _accumulator > 2.0:
		simulation.set_pause(state,"slow_frame",true)
		_present()
		return
	var ticks := 0
	while _accumulator + 0.00000001 >= TICK_DURATION and ticks < 8:
		var events: Array[Dictionary] = []
		if _city_runtime != null:
			var stepped := _step_city_tick()
			if not stepped.get("ok",false): break
			events.assign(stepped.events)
		else:
			var commands: Array[Dictionary] = director.plan(state,chapter)
			events = simulation.step(state,input_router.sample_move(),commands)
		audio.consume_events(events)
		var successful_snapshot: Dictionary = simulation.snapshot(state)
		world.observe_render_tick(successful_snapshot)
		world.consume_combat_events(events,successful_snapshot)
		world.consume_events(events)
		ui.consume_loot_events(events,str(state.get("run_id","")))
		for event in events:
			if event.type == "run_ended": _record_result()
		var final_boundary := _advance_final_flow()
		if state.is_empty(): break
		if not state.phase in TERMINAL and not final_boundary:
			if int(state.active_tick)-_last_save_tick >= 1800 or state.phase != _last_phase or not state.upgrade_offer.is_empty():
				_save_checkpoint()
			else:
				for event in events:
					if event.type == "boss_spawned":
						_save_checkpoint()
						break
		_accumulator = maxf(0,_accumulator-TICK_DURATION)
		ticks += 1
		if not _startup_view.is_empty() or not _pending_transaction.is_empty() or not state.pause_reasons.is_empty() or state.phase in TERMINAL or _worker_recovery_active() or not _final_intent.is_empty() or not _final_error.is_empty(): break
	_present()
func _step_city_tick() -> Dictionary:
	if _pending_city_tick.is_empty():
		var planned: Array[Dictionary] = director.plan(state,chapter)
		for command in planned:
			# New local coordinates get the current stamp; stale stamped input
			# is never silently relabeled without translating its coordinates.
			if Streamed.spatial_command(command) and not command.has("origin_revision"):
				command.origin_revision = state.world.origin_revision
		_pending_city_tick = {"move":input_router.sample_move(),"commands":planned}
	var commands: Array[Dictionary] = []
	commands.assign(_pending_city_tick.commands)
	var move: Vector2 = _pending_city_tick.move
	var events: Array[Dictionary] = simulation.step(state,move,commands)
	var status: Dictionary = simulation.step_status()
	if status.get("error_code") == "world_not_ready":
		var generation := _lifecycle_generation
		var starting_tick: int = int(state.active_tick)
		var native: bool = get_script() == load("res://game/app/run_controller.gd") and _city_runtime.get_script() == CityRuntime and _city_runtime._can_continue_controller(self)
		var refreshed: Variant = _city_runtime._refresh_controller_coverage(self,commands) if native else _city_runtime.refresh_live_coverage(simulation,state,commands)
		if generation != _lifecycle_generation or _lifecycle_blocked(): return {"ok":false,"error_code":"lifecycle_pause"}
		var valid: bool = _city_continuation_result_valid(refreshed,starting_tick) if native else _city_coverage_result_valid(refreshed)
		if not valid:
			refreshed = {"ok":false,"error_code":"world_not_ready"}
		if refreshed.ok:
			# Keep the replacement private until its one retry actually succeeds.
			# A false-ready result cannot displace the last live Core/state A.
			var retry_events: Variant = refreshed.simulation.step(refreshed.state,move,commands)
			var retry_status: Variant = refreshed.simulation.step_status()
			status = retry_status if retry_status is Dictionary and retry_status.get("ok") is bool else {"ok":false,"error_code":"world_not_ready"}
			if status.get("ok",false):
				# A default/stale success status after a callee fault is not an
				# accepted tick. Core publishes its caller state only on success.
				if not retry_events is Array or not retry_events.all(func(event): return event is Dictionary) or not Simulation.Catalog.integer_valid(refreshed.state.get("active_tick")) or refreshed.state.active_tick != starting_tick+1:
					status = {"ok":false,"error_code":"world_not_ready"}
			if status.get("ok",false):
				if generation != _lifecycle_generation or _lifecycle_blocked(): return {"ok":false,"error_code":"lifecycle_pause"}
				events.assign(retry_events)
				_adopt_city_simulation(refreshed.simulation)
				state = refreshed.state
				_apply_lifecycle_pause(state)
		else: status = refreshed
	if not status.get("ok",false):
		_city_step_error = str(status.get("error_code","world_not_ready"))
		# Hash only at an exceptional refusal, not on ordinary fixed ticks.
		_pending_city_tick.state_sha256 = JSON.stringify(state,"",true,true).sha256_text()
		_pending_city_tick.store_revision = game_save.store_revision
		_action_failed("world",_city_step_error)
		return status
	_clear_city_tick()
	return {"ok":true,"events":events}
# Called only after the exact synchronous Runtime method selected above.
# External/custom returned pairs still use the full validator below.
func _city_continuation_result_valid(value: Variant, starting_tick: int) -> bool:
	if not value is Dictionary or not value.get("ok") is bool: return false
	if not value.ok: return value.get("error_code") is String and not value.error_code.is_empty()
	var core: Variant = value.get("simulation")
	var candidate: Variant = value.get("state")
	if not core is Object or not is_instance_valid(core) or core.get_script() != Simulation or core == simulation: return false
	if not candidate is Dictionary or is_same(candidate,state) or not candidate.get("world") is Dictionary: return false
	return Simulation.Catalog.integer_valid(candidate.get("active_tick")) and candidate.active_tick == starting_tick and core._streamed != null and core._configuration_admitted
func _city_coverage_result_valid(value: Variant) -> bool:
	if not value is Dictionary or not value.get("ok") is bool: return false
	if not value.ok: return value.get("error_code") is String and not value.error_code.is_empty()
	var core: Variant = value.get("simulation")
	if not core is Object or not is_instance_valid(core) or not value.get("state") is Dictionary: return false
	var candidate: Dictionary = value.state
	# A coverage callback may canonicalize numeric representation, but may not
	# change gameplay authority or return a malformed state for the retry.
	if not candidate.has("world") or not Simulation.Contracts.new().validate_snapshot(candidate).is_empty(): return false
	if not _same_json(candidate,state): return false
	# Preserve derived/custom Core callbacks; only require the retry/adoption
	# interface, never an exact script identity at this consumer boundary.
	return core.has_method("step") and core.has_method("step_status") and core.get("_catalog") is Object and core.get("_chapter") is Dictionary
func _clear_city_tick() -> void:
	_pending_city_tick.clear()
	_city_step_error = ""
func _retry_city_hold() -> void:
	var refresh_hand: bool = _pending_city_tick.is_empty() and _city_render_error.begins_with("attack_view_")
	if not _pending_city_tick.is_empty():
		if _pending_city_tick.get("store_revision") != game_save.store_revision or _pending_city_tick.get("state_sha256") != JSON.stringify(state,"",true,true).sha256_text():
			_clear_city_tick()
			_accumulator = 0
			_city_step_error = "stale_world_tick"
			_action_failed("world",_city_step_error)
			return
	_city_step_error = ""
	_city_render_error = ""
	_city_terrain_key = ""
	ui.set_save_notice("")
	if not _pending_city_tick.is_empty():
		_autosave_retry_held_tick = _worker_reserved()
		_accumulator = TICK_DURATION
		advance_frame(0)
		_autosave_retry_held_tick = false
	else:
		if refresh_hand:
			# Rebuild only the harmless current presentation sample, never replay
			# a held damage tick or adopt a different durable checkpoint.
			var prepared: Dictionary = _city_runtime.refresh_coverage(state) if _city_runtime != null else simulation.restore(state)
			if not prepared.get("ok",false):
				_city_step_error = str(prepared.get("error_code","attack_view_unavailable"))
				_action_failed("world",_city_step_error)
				_present()
				return
			if _city_runtime != null: _adopt_city_simulation(prepared.simulation)
			else:
				var hand: Dictionary = simulation.prepare_enemy_attack_view(prepared.state)
				if not hand.get("ok",false):
					_city_render_error = str(hand.get("error_code","attack_view_unavailable"))
					_action_failed("world",_city_render_error)
					return
			state = prepared.state
			_apply_lifecycle_pause(state)
		_present()
func apply_upgrade(offer_id: String, option_id: String) -> void:
	if _defer_worker_command("upgrade",[offer_id,option_id]): return
	if state.is_empty() or not _command_ready("upgrade"): return
	if not _failed_growth.is_empty() and (_failed_growth.offer_id != offer_id or _failed_growth.option_id != option_id):
		_action_failed("upgrade","retry_pending_choice")
		return
	var next_state := state.duplicate(true)
	var choice_core = simulation
	var result: Dictionary = choice_core.choose_upgrade(next_state,offer_id,option_id)
	if not result.get("ok",false) and result.get("error_code") == "world_not_ready" and _city_runtime != null:
		# A movement/XP tick can open the offer at a new coverage boundary.
		# No following combat tick runs while it is paused, so prepare the same
		# authority here. Keep the replacement private until durable adoption.
		var generation := _lifecycle_generation
		var refreshed: Dictionary = _city_runtime.refresh_coverage(state)
		if generation != _lifecycle_generation or _lifecycle_blocked():
			_action_failed("upgrade","lifecycle_changed")
			return
		if not refreshed.get("ok",false):
			_action_failed("upgrade",str(refreshed.get("error_code","world_not_ready")))
			return
		choice_core = refreshed.simulation
		next_state = refreshed.state
		result = choice_core.choose_upgrade(next_state,offer_id,option_id)
	if not result.ok:
		_action_failed("upgrade",result.error_code)
		return
	var candidate := game_save.duplicate(true)
	candidate.checkpoint = choice_core.snapshot(next_state)
	_failed_growth = {"offer_id":offer_id,"option_id":option_id}
	_commit_candidate(candidate,"upgrade",{},true,result.events)
func set_user_pause(enabled: bool) -> void:
	if state.is_empty(): return
	_clear_city_tick()
	simulation.set_pause(state,"user",enabled)
	_save_checkpoint()
	input_router.clear_transient_input()
	_present()
func _open_shop() -> void:
	_shop_open = true
	if not state.is_empty() and not state.phase in TERMINAL:
		_save_checkpoint()
	_accumulator = 0
	input_router.clear_transient_input()
	_present()
func _close_shop() -> void:
	_shop_open = false
	_accumulator = 0
	input_router.clear_transient_input()
	_present()
func request_resume() -> void:
	if not _foreground or not _pending_transaction.is_empty(): return
	var requested_generation := _lifecycle_generation
	# A held tick predates durable adoption. Retry only that frozen tick while
	# reserving the writer; this is not acceptance of a resume or save command.
	if autosave_worker_enabled and _worker_reserved() and not _pending_city_tick.is_empty() and not _lifecycle_blocked():
		_accumulator = maxf(_accumulator,TICK_DURATION)
		_retry_city_hold()
		return
	var cancelled_choice := false
	if _lifecycle_blocked() and not _autosave_intent.is_empty() and (_autosave_intent.action != "resume" or _autosave_intent.lifecycle_generation != requested_generation):
		# A retained choice has not executed. An explicit foreground Continue
		# replaces obsolete intent, without applying a purchase/upgrade on resume.
		_worker_event({"kind":"lifecycle_intent_cancelled","action":_autosave_intent.action})
		_autosave_intent.clear()
		cancelled_choice = true
	var deferred := _defer_worker_command("resume",[])
	if cancelled_choice: ui.set_save_notice("환경이 바뀌어 대기 중인 선택을 취소했습니다. 필요한 항목은 다시 선택해 주세요.")
	if deferred: return
	if not _command_ready("resume"): return
	if (not _city_step_error.is_empty() or not _city_render_error.is_empty()) and not _lifecycle_blocked():
		if requested_generation == _lifecycle_generation: _retry_city_hold()
		return
	if state.is_empty() and not pending_checkpoint.is_empty():
		if not checkpoint_matches_chapter(pending_checkpoint,chapter): return
		var restored: Dictionary = _prepare_city_load(game_save) if _city_runtime != null else simulation.restore(pending_checkpoint)
		if not restored.ok:
			_action_failed("resume",restored.error_code)
			return
		if _city_runtime == null:
			var hand: Dictionary = simulation.prepare_enemy_attack_view(restored.state)
			if not hand.get("ok",false):
				_action_failed("resume",str(hand.get("error_code","attack_view_unavailable")))
				return
		world.reset_presentation()
		audio.reset_presentation()
		if _city_runtime != null: _adopt_city_simulation(restored.simulation)
		state = restored.state
		pending_checkpoint.clear()
		ui.set_checkpoint_available(false)
	if state.is_empty() or state.phase in TERMINAL: return
	if requested_generation != _lifecycle_generation or not _foreground:
		_apply_lifecycle_pause(state)
		_present()
		return
	_lifecycle_generation += 1
	_lifecycle_pause_intent = {"background":false,"controller_lost":false}
	input_router.clear_transient_input()
	for reason in ["user","background","controller_lost","slow_frame"]:
		simulation.set_pause(state,reason,false)
	_accumulator = 0
	_save_checkpoint()
	_present()
func request_end_run() -> void:
	if not _final_intent.is_empty() or not _final_error.is_empty(): return
	if _defer_worker_command("end_run",[]): return
	if state.is_empty() or not _pending_transaction.is_empty(): return
	if autosave_worker_enabled and not _worker_command_barrier("end_run"): return
	var events: Array[Dictionary] = simulation.abandon_run(state)
	world.consume_events(events)
	audio.consume_events(events)
	_record_result()
	_present()
func _record_result() -> void:
	if state.is_empty() or not state.phase in TERMINAL: return
	if autosave_worker_enabled and _worker_reserved():
		# Automatic run_ended is not a retryable user click. Retain one stamped
		# settlement intent, cancel only precommit autosave, then settle once.
		_autosave_terminal = {"generation":_autosave_generation,"run_id":state.run_id,"run_serial":state.run_serial}
		_worker_command_barrier("settlement")
		return
	if not _command_ready("settlement"): return
	_autosave_terminal.clear()
	var prepared: Dictionary = supply_service.prepare_settlement(game_save,simulation.snapshot(state))
	if not prepared.ok:
		_action_failed("settlement",prepared.error_code)
		return
	if prepared.get("already_applied",false):
		_action_succeeded("settlement",prepared.receipt)
		return
	_commit_candidate(prepared.candidate,"settlement",prepared.receipt,true)
func _apply_settings(values: Dictionary) -> void:
	if _defer_worker_command("settings",[values.duplicate(true)]): return
	if not _command_ready("settings"): return
	var candidate := game_save.duplicate(true)
	candidate.profile.settings = values.duplicate(true)
	if not state.is_empty() and not state.phase in TERMINAL: candidate.checkpoint = simulation.snapshot(state)
	_commit_candidate(candidate,"settings")
func _install_settings(values: Dictionary) -> void:
	ui.set_settings(values)
	world.reduce_effects = values.reduce_effects
	world.screen_shake = float(values.screen_shake)
	input_router.deadzone = float(values.deadzone)
	AudioServer.set_bus_volume_linear(0,float(values.audio_master))
var save_scope_enabled := true
var last_save_scope := {}
var last_reconciliation_scope := {}
func _save_checkpoint() -> void:
	if not _final_intent.is_empty() or not _final_error.is_empty(): return
	if autosave_worker_enabled and _city_runtime != null:
		_queue_worker_autosave()
		return
	var scope = null
	if save_scope_enabled and _city_runtime != null and save_store.get_script() == Save and not game_save.is_empty():
		scope = preload("res://game/app/save_validation_scope.gd").create(_city_runtime,save_store._directory,int(game_save.store_revision))
	_save_checkpoint_in_scope(scope)
	if scope != null:
		last_save_scope = scope.diagnostics()
		scope.close()
func _save_checkpoint_in_scope(scope) -> void:
	if state.is_empty() or not _pending_transaction.is_empty(): return
	if state.phase in TERMINAL:
		if int(state.run_serial) > int(game_save.get("settled_through_serial",0)): _record_result()
		return
	if not _command_ready("checkpoint",-1,scope): return
	var candidate := game_save.duplicate(true)
	candidate.checkpoint = simulation.snapshot(state)
	_commit_candidate(candidate,"checkpoint",{},false,[],false,scope)
func _command_ready(action: String, supplied_view: int = -1, scope = null) -> bool:
	if not _final_intent.is_empty() and action != _final_intent.action: return false
	if autosave_worker_enabled and not _worker_command_barrier(action): return false
	if not _startup_view.is_empty(): return false
	if not _pending_transaction.is_empty():
		resolve_pending_transaction()
		# Resolving a previous request never turns the current input into a new one.
		return false
	if game_save.is_empty():
		_action_failed(action,"save_unavailable")
		return false
	if action in ["purchase","loadout","character_selection","run_start","settings","upgrade"] and not state.is_empty() and state.phase in TERMINAL and int(state.run_serial) > int(game_save.settled_through_serial):
		_action_failed(action,"settlement_pending")
		return false
	if supplied_view >= 0 and (supplied_view != _view_revision or _view_store_revision != int(game_save.store_revision)):
		_action_failed(action,"stale_revision")
		return false
	if not _inspect_authority_command(scope): return false
	var loaded: Dictionary = save_store.read_game_scoped(scope) if scope != null else save_store.read_game()
	if not loaded.ok:
		_action_failed(action,loaded.error_code)
		return false
	if not _same_json(loaded.game_save,game_save):
		_quarantine_authority(loaded.game_save)
		_action_failed(action,"stale_revision")
		return false
	return true
func _inspect_authority_command(scope = null) -> bool:
	if autosave_worker_enabled and _worker_reserved(): return false
	_startup_inspection = save_store.inspect_known_locations_scoped(save_store._directory.get_base_dir(),scope) if scope != null else save_store.inspect_known_locations(save_store._directory.get_base_dir())
	if not _startup_inspection.get("ok",false):
		_show_startup_block("blocked","invalid_game_save")
		return false
	match str(_startup_inspection.decision):
		"choose_lineage":
			_show_startup_block("conflict","distinct_authorities")
			return false
		"retry_read":
			_show_startup_block("retry","read_failed")
			return false
		"blocked":
			for location in _startup_inspection.locations:
				if location.get("diagnostics",{}).get("reason") == "oversize":
					_show_startup_block("oversize","oversize")
					return false
			_show_startup_block("blocked",str(_startup_inspection.locations[0].get("error_code","invalid_game_save")))
			return false
	# A disappeared authority is not a new installation. Never let load_game
	# manufacture a new career while a live revision or pending commit exists.
	if _startup_inspection.locations[0].status == "absent" and not game_save.is_empty():
		_show_startup_block("blocked","authority_missing")
		return false
	return true
func _prepare_city_load(authority: Dictionary) -> Dictionary:
	var prepared: Dictionary = _city_runtime.prepare_load(authority)
	return _city_runtime.confirm_candidate(save_store) if prepared.get("ok",false) else prepared
func _prepare_city_candidate(candidate: Dictionary, scope = null) -> Dictionary:
	var staged := candidate.duplicate(true)
	# Ambient lifecycle intent is overlaid only on an adopted live state.
	for reason in ["background","controller_lost"]: staged.checkpoint.pause_reasons.erase(reason)
	var world_state: Dictionary = staged.checkpoint.world
	var pages: Dictionary = _world_delta_store.prepare(world_state.delta_root,world_state.dirty_chunks,int(world_state.world_revision))
	if not pages.get("ok",false): return pages
	var accepted: Dictionary = WorldCheckpoint.accept_receipt(world_state,pages.receipt)
	if not accepted.get("ok",false): return accepted
	staged.checkpoint.world = accepted.world
	var prepared: Dictionary = _city_runtime.prepare_commit_scoped(staged,[],scope) if scope != null else _city_runtime.prepare_commit(staged)
	if not prepared.get("ok",false): return prepared
	return {"ok":true,"candidate":staged}
func _commit_candidate(candidate: Dictionary, action: String, receipt: Dictionary = {}, replace_state: bool = false, events: Array = [], reset_presentation: bool = false, scope = null) -> void:
	var city_pair: bool = _city_runtime != null and candidate.get("checkpoint") is Dictionary
	if city_pair:
		var prepared := _prepare_city_candidate(candidate,scope)
		if not prepared.get("ok",false):
			_action_failed(action,str(prepared.get("error_code","world_not_ready")))
			return
		candidate = prepared.candidate
	var transaction := {"candidate":candidate.duplicate(true),"expected_revision":int(candidate.store_revision),"action":action,"receipt":receipt.duplicate(true),"replace_state":replace_state,"events":events.duplicate(true),"reset_presentation":reset_presentation,"lifecycle_generation":_lifecycle_generation,"city_pair":city_pair}
	var result: Dictionary = save_store.commit_game_scoped(candidate,int(candidate.store_revision),scope) if scope != null else save_store.commit_game(candidate,int(candidate.store_revision))
	if result.get("ok",false) and not city_pair:
		_publish_transaction(result.game_save,transaction)
	elif result.get("ok",false) or result.get("error_code") == "commit_outcome_unknown":
		_pending_transaction = transaction
		if result.get("error_code") == "commit_outcome_unknown" and scope != null:
			scope.close()
			scope = null
		if not resolve_pending_transaction(scope): _action_failed(action,"commit_outcome_unknown")
	else: _action_failed(action,str(result.get("error_code","write_failed")))
func resolve_pending_transaction(scope = null) -> bool:
	if autosave_worker_enabled and _worker_reserved(): return false
	var owned_scope = null
	if scope == null and save_scope_enabled and _pending_transaction.get("action") == "checkpoint" and _city_runtime != null and save_store.get_script() == Save:
		owned_scope = preload("res://game/app/save_validation_scope.gd").create(_city_runtime,save_store._directory,int(_pending_transaction.expected_revision))
		scope = owned_scope
	var resolved := _resolve_pending_transaction_in_scope(scope)
	if owned_scope != null:
		last_reconciliation_scope = owned_scope.diagnostics()
		owned_scope.close()
	return resolved
func _resolve_pending_transaction_in_scope(scope = null) -> bool:
	if _pending_transaction.is_empty(): return true
	var transaction := _pending_transaction.duplicate(true)
	if not _inspect_authority_command(scope): return false
	if transaction.get("city_pair",false):
		var confirmed: Dictionary = _city_runtime.confirm_candidate_scoped(save_store,scope) if scope != null else _city_runtime.confirm_candidate(save_store)
		if confirmed.get("ok",false):
			_pending_transaction.clear()
			_publish_transaction(confirmed.game_save,transaction,confirmed)
			return true
		# Only a verified unchanged prior authority proves this intent not applied.
		var prior: Dictionary = save_store.read_game_scoped(scope) if scope != null else save_store.read_game()
		if prior.get("ok",false) and not prior.get("recovered",false) and _same_json(prior.game_save,game_save):
			_pending_transaction.clear()
			_action_failed(transaction.action,"commit_not_applied")
			return true
		if confirmed.get("error_code") == "authority_mismatch" and prior.get("ok",false):
			_show_startup_block("retry","authority_mismatch")
			ui.set_save_notice("저장 내용이 변경되었습니다. 재시도를 선택하면 현재 저장 내용을 확인한 뒤 이어서 출격할 수 있습니다.")
		return false
	var loaded: Dictionary = save_store.read_game_scoped(scope) if scope != null else save_store.read_game()
	if not loaded.ok or loaded.get("recovered",false): return false
	var disk: Dictionary = loaded.game_save
	var expected: int = transaction.expected_revision
	var committed := false
	if int(disk.store_revision) > expected:
		var receipt: Dictionary = transaction.receipt
		if not receipt.is_empty() and transaction.action in ["purchase","settlement"]:
			var receipts: Array = disk.purchase_receipts if transaction.action == "purchase" else disk.settlement_receipts
			for prior in receipts:
				if _same_json(prior,receipt): committed = true
		else:
			var canonical: Dictionary = transaction.candidate.duplicate(true)
			canonical.store_revision = expected+1
			committed = int(disk.store_revision) == expected+1 and _same_json(canonical,disk)
	if committed:
		_pending_transaction.clear()
		_publish_transaction(disk,transaction)
		return true
	if int(disk.store_revision) == expected and _same_json(disk,game_save):
		_pending_transaction.clear()
		_action_failed(transaction.action,"commit_not_applied")
		return true
	return false
func _retry_city_authority() -> void:
	if not _inspect_authority_command(): return
	var observed: Dictionary = save_store.read_game()
	if not observed.get("ok",false):
		_show_startup_block("retry",str(observed.get("error_code","read_failed")))
		return
	var prepared: Dictionary
	if observed.game_save.checkpoint == null:
		# No run means no prepared pair. Confirm this explicit profile choice
		# by exact source bytes and full authority, without initializing/writing.
		prepared = save_store.read_game()
		if prepared.get("ok",false) and (prepared.get("source_sha256") != observed.get("source_sha256") or not _same_json(prepared.game_save,observed.game_save)):
			prepared = {"ok":false,"error_code":"authority_mismatch"}
	else: prepared = _prepare_city_load(observed.game_save)
	if not prepared.get("ok",false):
		_show_startup_block("retry",str(prepared.get("error_code","world_not_ready")))
		return
	_pending_transaction.clear()
	_startup_view.clear()
	_quarantine_authority(prepared.game_save,prepared)
	_present()
func _publish_transaction(authority: Dictionary, transaction: Dictionary, prepared_pair: Dictionary = {}) -> void:
	var final_notice: String = _final_intent.get("notice", "") if transaction.action in ["passage_selection","dock_transition"] else ""
	if transaction.action == "run_start": _autosave_generation += 1
	if _city_runtime != null and authority.get("checkpoint") is Dictionary:
		if not prepared_pair.get("ok",false) or not _same_json(prepared_pair.game_save,authority):
			_action_failed(str(transaction.action),"world_not_ready")
			return
		# Single synchronous adoption boundary: never expose B with A's cache.
		_adopt_city_simulation(prepared_pair.simulation)
		state = prepared_pair.state
		_clear_city_tick()
		_city_render_error = ""
	_install_authority(authority)
	if transaction.replace_state and _city_runtime == null:
		var adopted_core = Simulation.new()
		var restored: Dictionary = adopted_core.restore(game_save.checkpoint)
		if not restored.get("ok",false):
			_show_startup_block("blocked",str(restored.get("error_code","invalid_snapshot")))
			return
		var hand: Dictionary = simulation.prepare_enemy_attack_view(restored.state)
		if not hand.get("ok",false):
			_show_startup_block("blocked",str(hand.get("error_code","attack_view_unavailable")))
			return
		state = restored.state
	if transaction.replace_state:
		_pending_city_tick.clear()
		_accumulator = 0
		input_router.clear_transient_input()
	if _city_runtime != null or transaction.replace_state or transaction.lifecycle_generation != _lifecycle_generation:
		_apply_lifecycle_pause(state)
	if transaction.reset_presentation:
		ui.finish_new_run_navigation()
		ui.reset_progression_feedback()
		ui.set_save_notice("")
		world.reset_presentation()
		audio.reset_presentation()
		pending_checkpoint.clear()
		ui.set_checkpoint_available(false)
		if _shop_open: ui.close_supply_shop()
	if transaction.action in ["passage_selection","dock_transition"]:
		_final_intent.clear()
		_final_error = ""
		if transaction.action == "dock_transition": world.reset_presentation()
	if transaction.action == "upgrade": _failed_growth.clear()
	if transaction.action == "settings": _install_settings(profile.settings)
	if not state.is_empty():
		_last_save_tick = int(state.active_tick)
		_last_phase = state.phase
	if not transaction.events.is_empty():
		var events: Array[Dictionary] = []
		events.assign(transaction.events)
		ui.present_confirmed_upgrades(events,progression_view.build(state))
		if not _lifecycle_blocked(): audio.consume_events(events)
		world.consume_combat_events(events,simulation.snapshot(state))
		world.consume_events(events)
	if transaction.action == "purchase" and not _lifecycle_blocked(): audio.play_sound("select")
	if transaction.action in ["passage_selection","dock_transition"]:
		_refresh_view()
		ui.set_save_notice(final_notice)
	elif not transaction.action in ["checkpoint","settings"]: _action_succeeded(transaction.action,transaction.receipt)
	else: _present()
func _quarantine_authority(authority: Dictionary, prepared_pair: Dictionary = {}) -> void:
	_new_run_intent.clear()
	_final_intent.clear()
	_final_error = ""
	# A changed disk authority invalidates every writable checkpoint derived from
	# the old revision. Hold its validated checkpoint for a new explicit resume.
	if _city_runtime != null and authority.checkpoint is Dictionary and authority.checkpoint.phase in TERMINAL:
		if prepared_pair.is_empty(): prepared_pair = _prepare_city_load(authority)
		if not prepared_pair.get("ok",false):
			_show_startup_block("retry",str(prepared_pair.get("error_code","world_not_ready")))
			return
	_clear_city_tick()
	_city_render_error = ""
	_install_authority(authority)
	state = {}
	pending_checkpoint = {}
	_failed_growth.clear()
	_accumulator = 0
	_last_save_tick = -1
	_last_phase = ""
	_presented_growth_key = ""
	if game_save.checkpoint is Dictionary and _select_checkpoint_chapter(game_save.checkpoint) and checkpoint_matches_chapter(game_save.checkpoint,chapter):
		if game_save.checkpoint.phase in TERMINAL:
			if not prepared_pair.is_empty():
				_adopt_city_simulation(prepared_pair.simulation)
				state = prepared_pair.state
			else: state = game_save.checkpoint.duplicate(true)
			_apply_lifecycle_pause(state)
		else: pending_checkpoint = game_save.checkpoint.duplicate(true)
	input_router.clear_transient_input()
	world.reset_presentation()
	audio.reset_presentation()
	_shop_open = false
	ui.reset_obsolete_presentation(simulation.snapshot(state) if not state.is_empty() else {},not pending_checkpoint.is_empty(),str(pending_checkpoint.get("run_id","")))
	_install_settings(profile.settings)
func _install_authority(authority: Dictionary) -> void:
	_observed_save_source = true
	_allow_fresh_initialization = false
	_allow_legacy_migration = false
	game_save = authority.duplicate(true)
	profile = game_save.profile.duplicate(true)
	_view_revision += 1
	_view_store_revision = int(game_save.store_revision)
func _action_succeeded(action: String, receipt: Dictionary) -> void:
	if is_instance_valid(ui): ui.present_action_result({"ok":true,"action":action,"receipt":receipt.duplicate(true),"message":"" if action == "upgrade" else "저장했습니다."})
	_refresh_view()
func _action_failed(action: String, code: String) -> void:
	if action in ["settlement","new_run"] and code != "commit_outcome_unknown": _new_run_intent.clear()
	if action in ["passage_selection","dock_transition"]: _final_error = code
	if action == "settings" and not profile.is_empty() and is_instance_valid(ui): _install_settings(profile.settings)
	if is_instance_valid(ui): ui.present_action_result({"ok":false,"action":action,"error_code":code,"message":"저장/요청을 완료하지 못했습니다 (%s)." % code})
	_refresh_view()
func _refresh_view() -> void:
	_view_revision += 1
	_view_store_revision = int(game_save.get("store_revision",-1))
	_present()
func _same_json(a: Variant, b: Variant) -> bool:
	return JSON.parse_string(JSON.stringify(a,"",true,true)) == JSON.parse_string(JSON.stringify(b,"",true,true))
func _present() -> void:
	if not is_instance_valid(ui): return
	var view: Dictionary = simulation.snapshot(state) if not state.is_empty() else {}
	# Local modal ownership never alters the durable Core pause schema.
	if _shop_open and not view.is_empty(): view.pause_reasons.append("shop")
	if not state.is_empty():
		var growth_key := "%s:%d:%s" % [state.get("run_id",""),int(state.get("view_revision",0)),state.get("upgrade_offer",{}).get("selected_option_id","")]
		if growth_key != _presented_growth_key:
			_presented_growth_key = growth_key
			ui.present_progression(progression_view.build(state))
	var recovery_view := _startup_view.duplicate(true)
	if _worker_recovery_active():
		recovery_view = {"kind":"recovery_pending","error_code":_autosave_blocker if not _autosave_blocker.is_empty() else ("commit_outcome_unknown" if not _autosave_unknown.is_empty() else "autosave_pending"),"has_pending_request":true}
	if not _final_intent.is_empty() or not _final_error.is_empty():
		recovery_view = {"kind":"recovery_pending","error_code":_final_error if not _final_error.is_empty() else "final_transition_pending","has_pending_request":true}
	if not recovery_view.is_empty():
		recovery_view.lifecycle_blocked = _lifecycle_blocked()
		recovery_view.foreground = _foreground
	var render_active: bool = not state.is_empty() and state.get("phase","") in ["survival","evacuation"] and state.get("pause_reasons",[]).is_empty() and not _shop_open and not _lifecycle_blocked() and _startup_view.is_empty() and _pending_transaction.is_empty() and not _worker_recovery_active() and _final_intent.is_empty() and _final_error.is_empty() and _city_step_error.is_empty() and _city_render_error.is_empty() and _pending_city_tick.is_empty()
	world.begin_render_frame(_accumulator/TICK_DURATION,not render_active)
	_present_world(view)
	if not _city_render_error.is_empty(): world.set_render_alpha(1.0,true)
	if not view.is_empty() and (not _city_step_error.is_empty() or not _city_render_error.is_empty()): view.pause_reasons.append("world_not_ready")
	ui.present_recovery(recovery_view)
	ui.present(view)
	ui.set_upgrade_pending(_pending_transaction.get("action","") == "upgrade" or _autosave_intent.get("action","") == "upgrade")
	if not game_save.is_empty() and _presented_supply_revision != _view_revision:
		_presented_supply_revision = _view_revision
		ui.present_supply(supply_view())
	var audio_suspended := not _startup_view.is_empty() or _worker_recovery_active() or _lifecycle_blocked() or not _city_step_error.is_empty() or not _city_render_error.is_empty() or not _final_intent.is_empty() or not _final_error.is_empty()
	audio.present(view,audio_suspended)
	if audio_suspended:
		audio._music.stream_paused = true
		for voice in audio._voices: voice.stream_paused = true
	else:
		for voice in audio._voices: voice.stream_paused = false
func _present_world(view: Dictionary) -> void:
	if view.is_empty():
		world.present(view)
		_city_render_error = ""
		return
	if _city_runtime == null:
		world.present(view)
		var shown: Dictionary = world.present_enemy_attacks(simulation.enemy_attack_view(state))
		_city_render_error = "" if shown.get("ok",false) else str(shown.get("error_code","attack_view_unavailable"))
		if not _city_render_error.is_empty(): ui.set_save_notice("적 공격 표시를 다시 준비해 주세요 (%s). 계속을 선택하면 재시도합니다."%_city_render_error)
		return
	var status: Dictionary = simulation.world_status()
	var identity: Array = [simulation.get_instance_id(),status.get("coverage_revision",-1),status.get("world_revision",-1),state.world.world_revision,state.world.stage,state.world.scene_id,state.world.origin_chunk,state.world.origin_revision,state.world.content_fingerprint]
	var key := JSON.stringify(identity,"",true,true)
	if key != _city_terrain_key:
		_city_terrain_key = key
		_city_terrain_view = simulation.world_render_view(state)
		_city_terrain_view.cache_identity = key
		_city_terrain_view.world_revision = status.get("world_revision",state.world.world_revision)
	var rendered: Dictionary = world.present_city(view,_city_terrain_view)
	# Attack time is independent of the cached terrain identity. Snapshot first.
	var attacks: Dictionary = world.present_enemy_attacks(simulation.enemy_attack_view(state))
	_city_render_error = "" if rendered.get("ok",false) else str(rendered.get("error_code","world_not_ready"))
	if _city_render_error.is_empty() and not attacks.get("ok",false): _city_render_error = str(attacks.get("error_code","attack_view_unavailable"))
	if not _city_render_error.is_empty(): ui.set_save_notice("도시 표시를 다시 준비해 주세요 (%s). 계속을 선택하면 재시도합니다."%_city_render_error)
func _resize() -> void:
	if not is_instance_valid(ui): return
	# Reflow is synchronous: retain Core pause ownership and held pad/key input.
	# Only old touch coordinates are invalidated; reflow cancels the touch ID.
	input_router.set_touch_vector(Vector2.ZERO)
	var viewport := Vector2i(get_viewport().get_visible_rect().size)
	var safe_area := Rect2i(Vector2i.ZERO,viewport)
	if OS.has_feature("android") or OS.has_feature("ios"):
		safe_area = Lifecycle.new().map_safe_area(viewport,DisplayServer.window_get_size(),DisplayServer.get_display_safe_area(),DisplayServer.window_get_position())
	ui.reflow(viewport,safe_area)
	_present()
func _lifecycle_blocked() -> bool:
	return not _foreground or _lifecycle_pause_intent.background or _lifecycle_pause_intent.controller_lost
func _apply_lifecycle_pause(runtime: Dictionary) -> void:
	if runtime.is_empty(): return
	# Environmental intent belongs to this controller generation, not to the
	# immutable candidate whose exact committed bytes/receipt we are verifying.
	for reason in _lifecycle_pause_intent:
		if _lifecycle_pause_intent[reason]: simulation.set_pause(runtime,reason,true)
	if not _foreground: simulation.set_pause(runtime,"background",true)
func _latch_lifecycle_pause(reason: String) -> void:
	_lifecycle_generation += 1
	_lifecycle_pause_intent[reason] = true
	_clear_city_tick()
	_accumulator = 0
	input_router.clear_transient_input()
	_apply_lifecycle_pause(state)
func _notification(what: int) -> void:
	if not is_instance_valid(input_router): return
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT,NOTIFICATION_APPLICATION_PAUSED]:
		_foreground = false
		input_router.set_active(false)
		_latch_lifecycle_pause("background")
		if not state.is_empty(): _save_checkpoint()
		_present()
	elif what in [NOTIFICATION_APPLICATION_FOCUS_IN,NOTIFICATION_APPLICATION_RESUMED]:
		_foreground = true
		_lifecycle_generation += 1
		input_router.set_active(true)
		# Focus return changes availability, not the user's resume decision.
		_present()
func _unhandled_key_input(event: InputEvent) -> void:
	if not OS.has_feature("debug") or OS.has_feature("mobile"): return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F9:
		_capture_validation_frame()
func _capture_validation_frame() -> void:
	await RenderingServer.frame_post_draw
	var directory := "res://dist/screenshots"
	DirAccess.make_dir_recursive_absolute(directory)
	var path := directory.path_join("game-%d.png" % Time.get_unix_time_from_system())
	var result := get_viewport().get_texture().get_image().save_png(path)
	var meta := {"phase":state.get("phase","title"),"tick":state.get("active_tick",0),"panel_size":str(ui._panel.size),"panel_minimum":str(ui._panel.get_combined_minimum_size()),"panel_position":str(ui._panel.position),"viewport":str(get_viewport().get_visible_rect().size)}
	var file := FileAccess.open(path+".json",FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(meta))
	print("VALIDATION_CAPTURE ",path," result=",result," phase=",state.get("phase","title")," tick=",state.get("active_tick",0)," viewport=",get_viewport().get_visible_rect().size)

func checkpoint_matches_chapter(snapshot: Dictionary, current_chapter: Dictionary) -> bool:
	return snapshot.get("chapter_id","") == current_chapter.get("chapter_id","") and snapshot.get("content_revision","") == current_chapter.get("content_revision","") and snapshot.get("rules",{}).get("world_geometry",{}) == current_chapter.get("world_geometry",{}) and (_city_runtime == null or snapshot.get("rules",{}).get("content_fingerprint") == current_chapter.get("content_fingerprint"))

# Single-writer city autosave. Active Core/Node/UI remain exclusively on main.
const AutosaveWorker = preload("res://game/app/autosave_worker.gd")
var autosave_worker_enabled := true
var autosave_test_fault: Dictionary = {}
var autosave_test_prepare_delay_ms := 0
var autosave_events: Array = []
var autosave_metrics := {"capture_usec":[],"poll_usec":[],"submit_usec":[],"results":[],"coalesced":0}
var _autosave_generation := 0
var _autosave_sequence := 0
var _autosave_thread: Thread
var _autosave_worker
var _autosave_job: Dictionary = {}
var _autosave_pending: Dictionary = {}
var _autosave_unknown: Dictionary = {}
var _autosave_blocker := ""
var _autosave_terminal: Dictionary = {}
var _autosave_intent: Dictionary = {}
var _autosave_ack_retry: Dictionary = {}
var _autosave_retry_held_tick := false
var _autosave_known_failure := false
func _retry_worker_terminal() -> void:
	if _autosave_terminal.is_empty() or _worker_reserved() or not _pending_transaction.is_empty() or not _startup_view.is_empty(): return
	if _autosave_terminal.generation != _autosave_generation or state.get("run_id") != _autosave_terminal.run_id or state.get("run_serial") != _autosave_terminal.run_serial:
		_autosave_terminal.clear()
		return
	if int(game_save.settled_through_serial) >= int(_autosave_terminal.run_serial):
		_autosave_terminal.clear()
		return
	_record_result()
func _catalog_context(contracts) -> Dictionary:
	var catalog = contracts._catalog
	return {"items":catalog._items.duplicate(true),"doctrines":catalog._doctrines.duplicate(true),"errors":catalog._errors.duplicate(),"target_evolution_ids":contracts._target_evolution_ids.duplicate()}
func _capture_worker_job(sequence: int) -> Dictionary:
	var before := Time.get_ticks_usec()
	var job := {"directory":save_store._directory,"authority":game_save.duplicate(true),"snapshot":simulation.snapshot(state),"content_route":{"rules_version":simulation._chapter_provider.rules_version(),"content_fingerprint":simulation._chapter.content_fingerprint},"generation":_autosave_generation,"sequence":sequence,"lifecycle_generation":_lifecycle_generation,"fault":autosave_test_fault.duplicate(true),"prepare_delay_ms":autosave_test_prepare_delay_ms,"validator_context":{"chapter":_city_runtime._validator._chapter.duplicate(true),"definitions":_city_runtime._validator._gameplay_definitions.duplicate(true),"content_error":_city_runtime._validator._content_error},"runtime_catalog":_catalog_context(_city_runtime._contracts),"store_catalog":_catalog_context(save_store._contracts)}
	_worker_metric("capture_usec",Time.get_ticks_usec()-before)
	return job
func _worker_reserved() -> bool:
	return _autosave_thread != null or not _autosave_unknown.is_empty() or not _autosave_blocker.is_empty() or not _autosave_ack_retry.is_empty()
func _worker_command_barrier(action: String) -> bool:
	if not _worker_reserved(): return true
	_autosave_pending.clear()
	var cancel_accepted := false
	if _autosave_worker != null: cancel_accepted = _autosave_worker.cancel_before_commit()
	_worker_event({"kind":"critical_refused","action":action,"cancel_accepted":cancel_accepted})
	# Explicit not-accepted result. Critical intent is never coalesced or silently sent.
	_action_failed(action,"autosave_pending")
	return false
func _queue_worker_autosave() -> void:
	if state.is_empty() or game_save.is_empty() or not _pending_transaction.is_empty() or not _startup_view.is_empty(): return
	if state.phase in TERMINAL:
		if int(state.run_serial) > int(game_save.settled_through_serial): _record_result()
		return
	if not _autosave_unknown.is_empty() or not _autosave_blocker.is_empty(): return
	# Worker eligibility is narrower than normal synchronous saved-game support.
	if save_store.get_script() != Save or _city_runtime.get_script() != CityRuntime or _city_runtime._provider.get_script() != preload("res://game/director/streamed_chapter_provider.gd") or _world_delta_store.get_script() != preload("res://game/persistence/world_delta_store.gd"):
		_worker_submission_failed("worker_unsupported"); return
	if save_store._fault_injector.is_valid() or _world_delta_store._fault_injector.is_valid() or _city_runtime._validator.get_script() != Simulation or save_store._contracts._validator != Callable(_city_runtime,"validate_checkpoint"):
		_worker_submission_failed("worker_unsupported"); return
	_autosave_sequence += 1
	if not _autosave_intent.is_empty(): return
	if _autosave_thread != null:
		if not _autosave_pending.is_empty(): autosave_metrics.coalesced += 1
		_autosave_pending = {"sequence":_autosave_sequence}
		return
	_start_autosave_job(_capture_worker_job(_autosave_sequence))
func _start_autosave_job(job: Dictionary) -> void:
	var before := Time.get_ticks_usec()
	# Reject opaque/mutable aliases before any value crosses a thread boundary.
	if not save_store._contracts._json_safe(job):
		_worker_submission_failed("worker_unsupported"); return
	_autosave_job = job
	_autosave_worker = AutosaveWorker.new(job)
	_autosave_thread = Thread.new()
	var started := _autosave_thread.start(Callable(_autosave_worker,"run"))
	if started != OK:
		_autosave_thread = null; _autosave_worker = null; _autosave_job = {}
		_worker_submission_failed("worker_start_failed")
	_worker_metric("submit_usec",Time.get_ticks_usec()-before)
func _admit_worker_result(result: Dictionary, job: Dictionary) -> String:
	if typeof(result.get("ok")) != TYPE_BOOL or (not result.ok and typeof(result.get("error_code")) != TYPE_STRING): return "worker_envelope_invalid"
	if typeof(result.get("sequence")) != TYPE_INT or result.sequence != job.sequence or typeof(result.get("generation")) != TYPE_INT or result.generation != job.generation or job.generation != _autosave_generation or job.snapshot.run_id != state.get("run_id"):
		return "stale_worker_generation"
	if var_to_bytes(game_save) != var_to_bytes(job.authority): return "stale_worker_predecessor"
	var code: String = str(result.get("error_code",""))
	if result.get("ok") != true and code != "commit_outcome_unknown":
		if code == "commit_not_applied":
			if (not job.get("reconcile",false) and not result.get("was_unknown",false)) or not result.get("authority") is Dictionary or not _same_json(result.authority,job.authority): return "worker_envelope_invalid"
			# A may be read-normalized: bind its semantic authority separately
			# from the exact primary bytes that produced the validated SHA.
			var wire: Variant = result.get("authority_wire")
			if not wire is String or wire.to_utf8_buffer().size() > Save.MAX_BYTES or wire.sha256_text() != result.get("source_sha256"): return "worker_envelope_invalid"
			var parsed: Variant = JSON.parse_string(wire)
			if not parsed is Dictionary or parsed != JSON.parse_string(JSON.stringify(result.authority,"",true,true)): return "worker_envelope_invalid"
		return ""
	var receipt: Variant = result.get("receipt")
	if not receipt is Dictionary: return "worker_envelope_invalid"
	var accepted: Dictionary = preload("res://game/app/world_checkpoint_adapter.gd").accept_receipt(job.snapshot.world,receipt)
	if not accepted.get("ok",false): return "worker_envelope_invalid"
	var expected: Dictionary = job.authority.duplicate(true)
	expected.store_revision = int(expected.store_revision)+1
	expected.checkpoint = job.snapshot.duplicate(true)
	expected.checkpoint.world = accepted.world
	for reason in ["background","controller_lost"]: expected.checkpoint.pause_reasons.erase(reason)
	var authority: Variant = result.get("authority") if result.get("ok") == true else result.get("pending_canonical")
	if not authority is Dictionary or not _same_json(authority,expected): return "worker_envelope_invalid"
	if result.get("ok") == true and result.get("source_sha256") != JSON.stringify(authority,"",true,true).sha256_text(): return "worker_envelope_invalid"
	return ""
func _poll_autosave_worker() -> void:
	var before := Time.get_ticks_usec()
	if _autosave_thread == null or _autosave_thread.is_alive():
		_worker_metric("poll_usec",Time.get_ticks_usec()-before)
		return
	# Let the already planned live tick finish before changing world metadata.
	if not _pending_city_tick.is_empty():
		_worker_metric("poll_usec",Time.get_ticks_usec()-before)
		return
	_autosave_thread.wait_to_finish()
	var result: Dictionary = _autosave_worker.result()
	var job := _autosave_job
	_autosave_thread = null; _autosave_worker = null; _autosave_job = {}
	_worker_metric("results",result.duplicate(true))
	var admission := _admit_worker_result(result,job)
	if not admission.is_empty():
		_autosave_blocker = admission
		_worker_event({"kind":"refused_adoption","error_code":admission})
		_action_failed("checkpoint",admission)
		_worker_metric("poll_usec",Time.get_ticks_usec()-before)
		return
	if not result.get("ok",false):
		if result.get("error_code") == "commit_outcome_unknown":
			_autosave_unknown = job.duplicate(true)
			_autosave_unknown.pending_canonical = result.pending_canonical.duplicate(true)
			_autosave_unknown.receipt = result.get("receipt",{}).duplicate(true)
		else:
			if result.get("error_code") == "commit_not_applied": _autosave_unknown.clear()
			elif result.get("error_code") != "autosave_cancelled":
				_autosave_known_failure = true
				_autosave_blocker = str(result.error_code)
				_autosave_pending.clear()
			_worker_event({"kind":"failed","error_code":result.get("error_code","")})
		if result.get("error_code") != "autosave_cancelled": _action_failed("checkpoint",str(result.get("error_code","worker_failed")))
	else:
		if result.generation != _autosave_generation or job.snapshot.run_id != state.get("run_id") or int(game_save.store_revision) != int(job.authority.store_revision):
			_autosave_blocker = "stale_worker_generation"
			_worker_event({"kind":"refused_adoption","error_code":_autosave_blocker})
		else:
			var ack := {"ok":true}
			if not job.snapshot.world.dirty_chunks.is_empty() or not _same_json(job.snapshot.world.delta_root,result.authority.checkpoint.world.delta_root):
				if simulation.has_method("acknowledge_autosave_world"):
					ack = simulation.acknowledge_autosave_world(state,job.snapshot,result.receipt,result.authority.checkpoint.world)
				else: ack = {"ok":false,"error_code":"ack_unavailable"}
			# This is durable-only adoption: never assign simulation, state, position,
			# RNG or pending gameplay events from the worker's older checkpoint.
			_install_authority(result.authority)
			_last_save_tick = int(job.snapshot.active_tick)
			_last_phase = state.phase
			_autosave_unknown.clear()
			if not ack.ok:
				_autosave_ack_retry = {"job":job,"result":result}
				_autosave_blocker = str(ack.get("error_code","world_ack_required"))
				_worker_event({"kind":"durable_ack_refused","error_code":_autosave_blocker})
			else:
				_autosave_ack_retry.clear()
				_autosave_blocker = ""
				_autosave_known_failure = false
				_worker_event({"kind":"saved","sequence":result.sequence,"revision":game_save.store_revision})
	if not _autosave_pending.is_empty() and not _worker_reserved() and _autosave_terminal.is_empty() and _autosave_intent.is_empty():
		var sequence := int(_autosave_pending.sequence)
		_autosave_pending.clear()
		# Previous commit changed revision/root. Recapture latest live data now.
		_start_autosave_job(_capture_worker_job(sequence))
	_worker_metric("poll_usec",Time.get_ticks_usec()-before)
func retry_worker_unknown() -> bool:
	if _autosave_thread != null or _autosave_unknown.is_empty(): return false
	var job := _autosave_unknown.duplicate(true)
	job.reconcile = true
	job.fault = autosave_test_fault.duplicate(true)
	_start_autosave_job(job)
	return true
func _exit_tree() -> void:
	if _autosave_thread != null:
		_autosave_worker.cancel_before_commit()
		# Orderly shutdown barrier, never ordinary gameplay polling. Once commit
		# started it must finish/read back before the writer object is released.
		_autosave_thread.wait_to_finish()
		_autosave_thread = null; _autosave_worker = null

func _worker_metric(key: String, value: Variant) -> void:
	var samples: Array = autosave_metrics[key]
	if samples.size() == 32: samples.pop_front()
	samples.append(value)
func _worker_event(value: Dictionary) -> void:
	if autosave_events.size() == 32: autosave_events.pop_front()
	autosave_events.append(value)
func _worker_recovery_active() -> bool:
	return not _autosave_intent.is_empty() or not _autosave_unknown.is_empty() or not _autosave_blocker.is_empty() or not _autosave_ack_retry.is_empty()
func _defer_worker_command(action: String, arguments: Array, supplied_view: int = -1) -> bool:
	if not autosave_worker_enabled or (not _worker_reserved() and _autosave_intent.is_empty()): return false
	# Reject stale UI input before accepting it. Autosave itself never changes
	# economy; the retained intent can be replayed against its confirmed revision.
	if supplied_view >= 0 and (supplied_view != _view_revision or _view_store_revision != int(game_save.store_revision)):
		_action_failed(action,"stale_revision")
		return true
	if not save_store._contracts._json_safe(arguments):
		_action_failed(action,"invalid_request")
		return true
	if not _autosave_intent.is_empty():
		if _autosave_intent.action != action or not _same_json(_autosave_intent.arguments,arguments): _action_failed(action,"retry_pending_choice")
		return true
	_autosave_intent = {"action":action,"arguments":arguments.duplicate(true),"generation":_autosave_generation,"career_id":game_save.career_id,"run_id":state.get("run_id",""),"run_serial":state.get("run_serial",0),"lifecycle_generation":_lifecycle_generation,"economy":save_store._economy(game_save).duplicate(true)}
	_autosave_pending.clear()
	if _autosave_worker != null: _autosave_worker.cancel_before_commit()
	input_router.clear_transient_input()
	_accumulator = 0
	ui.set_save_notice("저장 확인 후 선택한 요청을 한 번 처리합니다.")
	_present()
	return true
func _retry_worker_command() -> void:
	if _autosave_intent.is_empty() or _worker_reserved() or not _foreground or not _pending_transaction.is_empty() or not _startup_view.is_empty(): return
	# Current explicit Continue is what releases lifecycle pauses. All other
	# retained actions still wait; generation validation below remains mandatory.
	if _lifecycle_blocked() and not _autosave_intent.action in ["resume","new_run"]: return
	var intent := _autosave_intent
	_autosave_intent = {}
	if intent.generation != _autosave_generation or intent.career_id != game_save.career_id or intent.run_id != state.get("run_id","") or intent.run_serial != state.get("run_serial",0) or not _same_json(intent.economy,save_store._economy(game_save)):
		_action_failed(intent.action,"stale_pending_request")
		return
	if intent.action in ["resume","new_run"] and intent.lifecycle_generation != _lifecycle_generation:
		_action_failed(intent.action,"lifecycle_changed")
		return
	match str(intent.action):
		"purchase": apply_purchase(intent.arguments[0],_view_revision)
		"loadout": apply_loadout(intent.arguments[0],_view_revision)
		"character_selection": apply_character_selection(intent.arguments[0],_view_revision)
		"run_start": start_run(intent.arguments[0])
		"new_run": request_new_run(intent.arguments[0],intent.arguments[1],intent.arguments[2])
		"upgrade": apply_upgrade(intent.arguments[0],intent.arguments[1])
		"settings": _apply_settings(intent.arguments[0])
		"end_run": request_end_run()
		"resume": request_resume()
	_present()
func retry_worker_recovery() -> void:
	if _autosave_thread != null:
		if not _pending_city_tick.is_empty(): _retry_city_hold()
		return
	if not _autosave_unknown.is_empty():
		retry_worker_unknown()
		return
	if not _autosave_ack_retry.is_empty():
		var job: Dictionary = _autosave_ack_retry.job
		var result: Dictionary = _autosave_ack_retry.result
		var ack: Dictionary = simulation.acknowledge_autosave_world(state,job.snapshot,result.receipt,result.authority.checkpoint.world)
		if ack.get("ok",false):
			_autosave_blocker = ""
			_autosave_ack_retry.clear()
			ui.set_save_notice("")
		else:
			# A rebase can legitimately invalidate the narrow ack. Freeze the live
			# state and prove it still contains every captured modification before
			# committing that newest snapshot over the confirmed durable revision.
			# The worker still prepares/validates all pages; no saved Core is adopted.
			var proof := _latest_world_contains_saved(job,result)
			if not proof.ok:
				_action_failed("checkpoint",str(proof.error_code))
			elif state.phase in TERMINAL:
				# Terminal economy must settle with the latest snapshot. This is the
				# existing synchronous critical boundary, not a terminal autosave.
				var retained := _autosave_ack_retry
				_autosave_ack_retry = {}
				_autosave_blocker = ""
				_autosave_known_failure = false
				_autosave_pending.clear()
				_record_result()
				if _pending_transaction.is_empty() and not state.is_empty() and int(game_save.settled_through_serial) < int(state.run_serial):
					_autosave_ack_retry = retained
					_autosave_blocker = "settlement_pending"
					_autosave_terminal = {"generation":_autosave_generation,"run_id":state.run_id,"run_serial":state.run_serial}
			else:
				_autosave_blocker = ""
				_autosave_pending.clear()
				_autosave_sequence += 1
				_start_autosave_job(_capture_worker_job(_autosave_sequence))
	elif _autosave_known_failure:
		_autosave_known_failure = false
		_autosave_blocker = ""
		if not _autosave_terminal.is_empty(): _retry_worker_terminal()
		elif _autosave_intent.is_empty(): _queue_worker_autosave()
	_retry_worker_command()
	_present()

func _latest_world_contains_saved(job: Dictionary, result: Dictionary) -> Dictionary:
	if not _same_json(game_save,result.authority) or job.generation != _autosave_generation: return {"ok":false,"error_code":"stale_worker_predecessor"}
	for field in ["run_id","run_serial","seed","run_config","chapter_id","content_revision"]:
		if not _same_json(state.get(field),job.snapshot.get(field)): return {"ok":false,"error_code":"world_ack_identity"}
	if state.active_tick < job.snapshot.active_tick or not _same_json(state.world.delta_root,job.snapshot.world.delta_root) or state.world.world_revision < job.snapshot.world.world_revision: return {"ok":false,"error_code":"world_ack_stale"}
	if state.world.stage == "dock":
		# World records use absolute chunks and survive the finite dock transition.
		# Prove monotone containment without pretending old city geometry is live.
		var Codec = preload("res://game/world/world_delta_codec.gd")
		var checked: Dictionary = Codec.normalize_records(state.world.dirty_chunks)
		if not checked.ok or not _same_json(checked.records,state.world.dirty_chunks): return {"ok":false,"error_code":"world_ack_invalid"}
		var records := {}
		for record in checked.records: records[JSON.stringify(record.chunk)] = record
		for record in job.snapshot.world.dirty_chunks:
			var key := JSON.stringify(record.chunk)
			if not records.has(key): return {"ok":false,"error_code":"world_ack_incomplete"}
			var slots := {}
			for prop in records[key].props: slots[prop.slot_id] = prop
			for prop in record.props:
				if not slots.has(prop.slot_id) or slots[prop.slot_id].hp > prop.hp or (prop.destroyed and not slots[prop.slot_id].destroyed): return {"ok":false,"error_code":"world_ack_incomplete"}
		return {"ok":true}
	if simulation._streamed == null or simulation._streamed._world == null or state.world.stage != "city": return {"ok":false,"error_code":"world_ack_stage"}
	return simulation._streamed._world._prepare_persisted_subset(state.world.dirty_chunks,job.snapshot.world.dirty_chunks,int(state.world.world_revision))

func _worker_submission_failed(code: String) -> void:
	_autosave_known_failure = true
	_autosave_blocker = code
	_autosave_pending.clear()
	_action_failed("checkpoint",code)

# Existing scenario/save boundary only. No clock, combat, schema or reward owner.
func _advance_final_flow() -> bool:
	if _city_runtime == null or state.is_empty() or state.get("phase") != "evacuation" or state.world.stage != "city": return false
	if not _pending_city_tick.is_empty() or not _pending_transaction.is_empty() or not _startup_view.is_empty() or _lifecycle_blocked() or not state.pause_reasons.is_empty(): return false
	if _worker_reserved() or _worker_recovery_active(): return false
	var proposal: Dictionary = FinalEvacuationFlow.prepare(simulation,state,game_save,chapter)
	if not proposal.get("ok",false):
		_final_error = str(proposal.get("error_code","world_not_ready"))
		_action_failed("dock_transition",_final_error)
		return true
	if proposal.get("waiting",false): return false
	if not _command_ready(proposal.action): return true
	# Fixed after the writer barrier and exact authority check. Neither failed
	# staging nor an unknown commit may rebuild, retime or consume this intent.
	_final_intent = proposal.duplicate(true)
	_final_intent.source_authority = game_save.duplicate(true)
	_attempt_final_intent()
	return true
func _attempt_final_intent() -> void:
	if _final_intent.is_empty() or _lifecycle_blocked() or _worker_reserved() or _worker_recovery_active() or not _pending_transaction.is_empty(): return
	if not _same_json(game_save,_final_intent.source_authority):
		_final_error = "stale_revision"
		return
	_commit_candidate(_final_intent.candidate,_final_intent.action,{},_final_intent.replace_state)
func retry_final_transition() -> void:
	if _lifecycle_blocked() or _worker_reserved() or _worker_recovery_active(): return
	if not _pending_transaction.is_empty():
		resolve_pending_transaction()
		return
	_final_error = ""
	if _final_intent.is_empty():
		_advance_final_flow()
	else:
		if not _command_ready(_final_intent.action): return
		_attempt_final_intent()
	_present()
