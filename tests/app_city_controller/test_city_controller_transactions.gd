extends RefCounted
const S = preload("res://tests/app_city_controller/controller_city_support.gd")
const Generator = preload("res://game/world/city_generator.gd")
class HiddenStore:
	extends "res://game/persistence/game_save_store.gd"
	var hidden := false
	func read_game() -> Dictionary:
		return {"ok":false,"error_code":"read_failed"} if hidden else super.read_game()
func run(t) -> void:
	_known_failures(t)
	for reason in ["background","controller_lost"]: _unknown_lifecycle(t,reason)
func _known_failures(t) -> void:
	var f := S.make(t)
	if f.is_empty(): return
	var app = f.app
	app.start_run(42)
	if app.state.is_empty():
		app.free()
		return
	var a = app.simulation
	var before: Dictionary = app.state.duplicate(true)
	var view: Dictionary = a._streamed.render_view(app.state)
	var authority: Dictionary = app.game_save.duplicate(true)
	var bytes := FileAccess.get_file_as_bytes(f.directory.path_join("game_save.json"))
	var candidate: Dictionary = app.game_save.duplicate(true)
	candidate.checkpoint.player.hp = 73.0
	var generated := Generator.new(app.chapter.world_definitions.templates,app.chapter.world_definitions.props).generate(42,["0","0"])
	var prop := {}
	for item in generated.props:
		if item.destructible: prop = item; break
	t.check(not prop.is_empty(),"controller terrain transaction uses actual generated destructible slot")
	candidate.checkpoint.world.world_revision = 1
	candidate.checkpoint.world.dirty_chunks = [{"chunk":["0","0"],"props":[{"slot_id":prop.slot_id,"hp":0,"destroyed":true}]}]
	var original := candidate.duplicate(true)
	f.disk._fault_injector = func(stage): return ERR_CANT_CREATE if stage == "after_pages_before_receipt" else OK
	app._commit_candidate(candidate,"checkpoint")
	t.check(app.state == before and app.simulation == a and app.game_save == authority and FileAccess.get_file_as_bytes(f.directory.path_join("game_save.json")) == bytes,"world-page staging failure cannot commit or publish B")
	f.disk._fault_injector = Callable()
	var invalid := candidate.duplicate(true)
	invalid.checkpoint.world.content_fingerprint = "0".repeat(64)
	app._commit_candidate(invalid,"checkpoint")
	t.check(app.state == before and app.simulation == a and FileAccess.get_file_as_bytes(f.directory.path_join("game_save.json")) == bytes,"private preparation failure cannot commit or publish B")
	for stage in ["write","flush","verify","backup","replace"]:
		app.save_store._fault_injector = func(value): return ERR_CANT_CREATE if value == stage else OK
		app._commit_candidate(candidate,"checkpoint")
		t.check(app.state == before and app.simulation == a and a._streamed.render_view(app.state) == view and app.game_save == authority,"failed "+stage+" keeps actual live Core/state/geometry/authority A")
		t.check(FileAccess.get_file_as_bytes(f.directory.path_join("game_save.json")) == bytes and candidate == original,"failed "+stage+" does not mutate durable authority or caller intent")
	app.save_store._fault_injector = Callable()
	app._commit_candidate(candidate,"checkpoint")
	t.check(app.simulation != a and app.state.player.hp == 73.0 and app.simulation._streamed.readiness(app.state).ok,"successful full authority confirmation adopts private B pair")
	t.check(app.state.world.dirty_chunks.is_empty() and app.state.world.delta_root != before.world.delta_root and f.disk.verify_root(app.state.world.delta_root).ok,"controller adopts exact accepted dirty-pages root receipt")
	t.check(app.simulation._streamed.render_view(app.state) != view and a._streamed.render_view(before) == view,"changed prepared geometry belongs to B; A remains unmodified")
	app.input_router.set_touch_vector(Vector2.RIGHT)
	app.advance_frame(1.0/60.0)
	t.check(app.state.active_tick == before.active_tick+1,"post-commit next controller tick actually runs")
	app.free()
func _unknown_lifecycle(t,reason: String) -> void:
	var f := S.make(t)
	if f.is_empty(): return
	var app = f.app
	var a = app.simulation
	var store := HiddenStore.new(f.directory,Callable(f.runtime,"validate_checkpoint"))
	store._fault_injector = func(stage):
		if stage == "after_replace_before_return":
			store.hidden = true
			return ERR_CANT_CREATE
		return OK
	app.save_store = store
	app.start_run(42)
	t.check(not app._pending_transaction.is_empty() and app.state.is_empty() and app.simulation == a,"unknown city start keeps prepared B private: "+reason)
	var intent: Dictionary = app._pending_transaction.duplicate(true)
	var committed_bytes := FileAccess.get_file_as_bytes(f.directory.path_join("game_save.json"))
	app.input_router.set_touch_vector(Vector2.RIGHT)
	if reason == "background": app._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	else: app._latch_lifecycle_pause("controller_lost")
	app.start_run(999)
	t.check(app._pending_transaction == intent and FileAccess.get_file_as_bytes(f.directory.path_join("game_save.json")) == committed_bytes,"unknown retry retains exact original request, seed and bytes: "+reason)
	store.hidden = false
	store._fault_injector = Callable()
	t.check(app.resolve_pending_transaction(),"same uncertain city transaction confirms by full readback: "+reason)
	t.check(app.simulation != a and app.state.seed == 42 and reason in app.state.pause_reasons and not reason in app.game_save.checkpoint.pause_reasons,"latest lifecycle generation overlays only adopted live B: "+reason)
	t.check(app.input_router.sample_move() == Vector2.ZERO and app.simulation._streamed.readiness(app.state).ok,"unknown adoption clears stale input and owns prepared geometry: "+reason)
	app.advance_frame(1.0/60.0)
	t.check(app.state.active_tick == 0,"late lifecycle pause prevents first B tick: "+reason)
	if reason == "background": app._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	app.advance_frame(1.0/60.0)
	t.check(app.state.active_tick == 0,"focus return never auto-resumes city: "+reason)
	app.request_resume()
	app.advance_frame(1.0/60.0)
	t.check(app.state.active_tick == 1 and app.game_save.next_run_serial == 2,"explicit continue advances exactly original city run: "+reason)
	# Save initiated while ambient pause is already latched must also be clean.
	app._latch_lifecycle_pause(reason)
	app._save_checkpoint()
	t.check(reason in app.state.pause_reasons and not reason in app.game_save.checkpoint.pause_reasons,"ordinary city checkpoint never persists ambient pause: "+reason)
	app.free()
