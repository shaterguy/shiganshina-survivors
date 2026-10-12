extends RefCounted
const S = preload("res://tests/final_runtime/final_support.gd")
const Faults = preload("res://tests/app_city_controller/test_city_controller_transactions.gd")
func run(t) -> void:
	for action in ["passage_selection","dock_transition"]:
		for stage in ["write","flush","verify","backup","replace","world_stage"]: _known_failure(t,action,stage)
		_unknown_lifecycle(t,action)
	_geometry_not_outside(t)
func _ready_for(f: Dictionary, action: String) -> void:
	if action == "passage_selection":
		f.app.start_run(42)
		f.app.state.active_tick = 107999
		f.app.state.survival_tick = 107999
		f.app.state.player.position = [384.0,384.0]
	else: S.boundary(f,[384.0,384.0])
func _known_failure(t, action: String, stage: String) -> void:
	var f := S.make(t,"",false)
	if f.is_empty(): return
	var app = f.app
	_ready_for(f,action)
	var a = app.simulation
	var authority: Dictionary = app.game_save.duplicate(true)
	var bytes := FileAccess.get_file_as_bytes(f.directory.path_join("game_save.json"))
	if stage == "world_stage": f.disk._fault_injector = func(value): return ERR_CANT_CREATE if value == "after_pages_before_receipt" else OK
	else: app.save_store._fault_injector = func(value): return ERR_CANT_CREATE if value == stage else OK
	app.advance_frame(1.0/60.0)
	t.check(not app._final_intent.is_empty() and app._final_intent.action == action and not app._final_error.is_empty(),action+" retains frozen candidate after "+stage+" failure")
	if app._final_intent.is_empty(): app.free(); return
	var intent: Dictionary = app._final_intent.duplicate(true)
	var live: Dictionary = app.state.duplicate(true)
	var cached = app.simulation
	for frame in 3: app.advance_frame(0.25)
	t.check(app.state == live and app.simulation == cached and app.game_save == authority and FileAccess.get_file_as_bytes(f.directory.path_join("game_save.json")) == bytes,action+" failed save preserves live authority/cache and consumes no extra tick")
	app._save_checkpoint(); app.request_end_run()
	t.check(app._final_intent == intent and app.state == live,"background save or abandon cannot overwrite held final intent")
	app.retry_save_recovery()
	t.check(app._final_intent == intent and app.state == live,action+" failed retry reuses exact candidate and original timing")
	app.save_store._fault_injector = Callable(); f.disk._fault_injector = Callable()
	app.retry_save_recovery()
	t.check(app._final_intent.is_empty() and app._final_error.is_empty() and S.count_actions(app,action) == 1,action+" explicit retry confirms one original transaction")
	t.check(app.state.active_tick == live.active_tick and app.game_save.checkpoint.active_tick == live.active_tick and app.simulation != cached,"successful retry adopts B without consuming an extra simulation tick")
	t.check(app._same_json(app.state.entities,intent.candidate.checkpoint.entities) and app._same_json(app.state.telegraphs,intent.candidate.checkpoint.telegraphs) and app.state.final_started_tick == 108000,"known retry publishes the same final actor and warning deadlines without rearming")
	app.free()
func _unknown_lifecycle(t, action: String) -> void:
	var f := S.make(t,"",false)
	if f.is_empty(): return
	var app = f.app
	_ready_for(f,action)
	var store := Faults.HiddenStore.new(f.directory,Callable(f.runtime,"validate_checkpoint"))
	store._fault_injector = func(stage):
		if stage == "after_replace_before_return": store.hidden = true; return ERR_CANT_CREATE
		return OK
	app.save_store = store
	app.advance_frame(1.0/60.0)
	t.check(not app._pending_transaction.is_empty() and not app._final_intent.is_empty(),action+" unknown outcome keeps existing Store transaction and exact final intent")
	var candidate: Dictionary = app._final_intent.duplicate(true)
	var live_tick: int = app.state.active_tick
	var a = app.simulation
	var bytes := FileAccess.get_file_as_bytes(f.directory.path_join("game_save.json"))
	app._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	app.retry_save_recovery(); app.advance_frame(0.25)
	t.check(app._final_intent == candidate and app.simulation == a and app.state.active_tick == live_tick and FileAccess.get_file_as_bytes(f.directory.path_join("game_save.json")) == bytes,"unknown plus background preserves same immutable candidate and disk bytes")
	store.hidden = false; store._fault_injector = Callable()
	t.check(app.resolve_pending_transaction(),"actual readback confirms uncertain "+action+" once")
	t.check(app._final_intent.is_empty() and app._final_error.is_empty() and "background" in app.state.pause_reasons and not "background" in app.game_save.checkpoint.pause_reasons,"late lifecycle overlay never enters saved final candidate")
	app._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	app.advance_frame(1.0/60.0)
	t.check(app.state.active_tick == live_tick and S.count_actions(app,action) == 1,"foreground return never advances or replays completed final transaction")
	t.check(app._same_json(app.state.entities,candidate.candidate.checkpoint.entities) and app._same_json(app.state.telegraphs,candidate.candidate.checkpoint.telegraphs) and app.state.final_started_tick == 108000,"unknown confirmation retains exact final actor and warning timing through lifecycle pause")
	app.free()
func _geometry_not_outside(t) -> void:
	var f := S.make(t,"",false)
	if f.is_empty(): return
	var app = f.app
	S.boundary(f)
	app.advance_frame(1.0/60.0)
	t.check(app._final_error.is_empty() and app.state.world.stage == "city","outside selected passage is normal walking state")
	var dock: Dictionary = app.chapter.authored_dock.duplicate(true)
	app.chapter.authored_dock.geometry = {}
	app.state.player.position = [384.0,340.0]
	app.advance_frame(1.0/60.0)
	t.check(app._final_error == "invalid_dock_definition" and app._final_intent.is_empty(),"invalid geometry at actual passage entry is a blocking diagnostic")
	var tick: int = app.state.active_tick
	app.advance_frame(1.0/60.0)
	t.check(app.state.active_tick == tick,"geometry failure stops rather than silently simulating forever")
	app._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	app._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	app.request_recovery_continue()
	t.check(not app._lifecycle_blocked(),"final recovery UI explicitly resumes lifecycle before retry")
	app.chapter.authored_dock = dock
	app.state.player.position = [384.0,280.0]
	app.retry_save_recovery(); app.advance_frame(1.0/60.0)
	t.check(app._final_error.is_empty() and app.state.active_tick == tick+1,"corrected geometry retries while outside passage without false transition")
	app.free()
