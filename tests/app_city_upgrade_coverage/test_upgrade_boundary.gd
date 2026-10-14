extends RefCounted
const S = preload("res://tests/app_city_controller/controller_city_support.gd")
const H = preload("res://game/core/streamed_run_world.gd")
const HF = preload("res://tests/core_world/new_streamed_helper_fixture.gd")
class RefusingRuntime:
	extends "res://game/app/prepared_city_runtime.gd"
	var refuse_refresh := false
	var refreshes := 0
	func refresh_coverage(current_state: Dictionary, commands: Array = []) -> Dictionary:
		refreshes += 1
		if refuse_refresh: return {"ok":false,"error_code":"read_failed"}
		return super.refresh_coverage(current_state,commands)
func run(t) -> void:
	await _default_worker_choice(t,false)
	await _default_worker_choice(t,true)
	_failed_prepare(t)
	await t.create_timer(0.25).timeout
func _arrange_boundary(t, app, advance_frame: bool) -> void:
	app.start_run(42)
	t.check(not app.state.is_empty(),"boundary growth starts through actual Controller/Supply/Core")
	if app.state.is_empty(): return
	app.state.player.position = [639.0,384.0]
	app.state.player.attack_ready_ticks.blade_slash = 10000
	app.state.player.xp = int(app.simulation._catalog.progression.base_xp)-1
	app.simulation._add_drop(app.state,[641.5,384.0],1)
	var hydration := HF.hydration(H.requirements(app.state))
	t.check(app.simulation.prepare_world(app.state,hydration).get("ok",false),"arranged XP pickup and pre-boundary state pass real Core admission")
	t.check(app.simulation._streamed.readiness(app.state).get("ok",false),"pre-level-up terrain is fully ready")
	app.input_router.set_touch_vector(Vector2.RIGHT)
	if advance_frame: app.advance_frame(1.0/60.0)
	else: app._step_city_tick()
	t.check(app.state.active_tick == 1 and app.state.player.position == [641.5,384.0] and not app.state.upgrade_offer.is_empty(),"one accepted movement/XP tick opens the real paused level-up across coverage boundary")
	t.check(app.simulation._streamed.readiness(app.state).get("error_code") == "world_not_ready","newly required view chunks remain outside the previous tick's prepared cache")
func _drain(t, app) -> void:
	var deadline := Time.get_ticks_usec()+10000000
	while (app._autosave_thread != null or not app._autosave_intent.is_empty()) and Time.get_ticks_usec() < deadline:
		app.advance_frame(0)
		await t.create_timer(0.003).timeout
	t.check(app._autosave_thread == null and app._autosave_intent.is_empty() and app._autosave_blocker.is_empty(),"default worker and any retained choice resolve without a recovery blocker")
func _default_worker_choice(t, while_pending: bool) -> void:
	var f := S.make(t)
	if f.is_empty(): return
	var app = f.app
	app.autosave_worker_enabled = true
	_arrange_boundary(t,app,true)
	if app.state.upgrade_offer.is_empty(): app.free(); return
	if not while_pending: await _drain(t,app)
	var saved_revision: int = app.game_save.store_revision
	var before: Dictionary = app.state.duplicate(true)
	var offer: Dictionary = before.upgrade_offer
	var option: Dictionary = offer.options[0]
	app.ui.upgrade_chosen.emit(offer.offer_id,option.option_id)
	if while_pending: await _drain(t,app)
	t.check(app.state.upgrade_offer.is_empty() and not "upgrade" in app.state.pause_reasons,"real UI choice commits after preparing coverage, including retained worker choice")
	t.check(app.state.equipment.get(option.item_id,0) == option.next_level,"the originally selected upgrade applies exactly its requested level")
	t.check(app.state.active_tick == before.active_tick and app.state.player.position == before.player.position and app.state.rng_state == before.rng_state and app.state.progression_rng_state == before.progression_rng_state,"coverage preparation and selection replay no combat tick or RNG draw")
	t.check(app.state.reward_ids_claimed.count("offer:"+offer.offer_id) == 1,"the same offer is claimed exactly once")
	var committed_revision: int = app.game_save.store_revision
	t.check(committed_revision > saved_revision and app.game_save.checkpoint.upgrade_offer.is_empty(),"durable checkpoint contains the completed selected upgrade")
	var stable: Dictionary = app.state.duplicate(true)
	app.ui.upgrade_chosen.emit(offer.offer_id,option.option_id)
	t.check(app.game_save.store_revision == committed_revision and app.state == stable,"duplicate UI selection cannot apply or commit a second upgrade")
	var disk: Dictionary = app.save_store.read_game()
	t.check(disk.get("ok",false) and app._same_json(disk.game_save,app.game_save),"cold durable authority equals the confirmed upgrade checkpoint")
	app.free()
func _failed_prepare(t) -> void:
	var directory := "user://upgrade_coverage_failure_%d_%d/saves" % [OS.get_process_id(),Time.get_ticks_usec()]
	var provider := S.City.new()
	var disk := S.Disk.new(directory.path_join("world"))
	var runtime := RefusingRuntime.new(provider,disk)
	var app := S.Controller.new()
	app.autosave_worker_enabled = false
	t.check(app.configure_city_runtime(provider,runtime,disk,directory).get("ok",false),"failure fixture configures explicit real city dependencies")
	t.root.add_child(app)
	app.set_process(false); app.world.set_process(false)
	_arrange_boundary(t,app,false)
	if app.state.upgrade_offer.is_empty(): app.free(); return
	var before: Dictionary = app.state.duplicate(true)
	var authority: Dictionary = app.game_save.duplicate(true)
	var original_core = app.simulation
	var offer: Dictionary = before.upgrade_offer
	var option: Dictionary = offer.options[0]
	var original_bytes := FileAccess.get_file_as_bytes(directory.path_join("game_save.json"))
	runtime.refuse_refresh = true
	app.ui.upgrade_chosen.emit(offer.offer_id,option.option_id)
	t.check(runtime.refreshes == 1 and app.ui._notice.text.contains("read_failed"),"coverage read failure remains visible and is never ignored")
	t.check(app.state == before and app.simulation == original_core and app.game_save == authority and FileAccess.get_file_as_bytes(directory.path_join("game_save.json")) == original_bytes,"failed preparation preserves live Core, full offer authority and durable bytes")
	runtime.refuse_refresh = false
	app.ui.upgrade_chosen.emit(offer.offer_id,"equipment:unknown")
	t.check(app.state == before and app.game_save == authority and app.ui._notice.text.contains("invalid_option"),"coverage refresh never bypasses invalid-option validation")
	app.save_store._fault_injector = func(stage): return ERR_CANT_CREATE if stage == "write" else OK
	app.ui.upgrade_chosen.emit(offer.offer_id,option.option_id)
	t.check(app.ui._notice.text.contains("write_failed"),"a prepared coverage pair still requires a successful durable upgrade commit")
	t.check(app.state == before and app.simulation == original_core and app.game_save == authority and FileAccess.get_file_as_bytes(directory.path_join("game_save.json")) == original_bytes,"failed durable commit never publishes the refreshed Core, choice, or save authority")
	app.save_store._fault_injector = Callable()
	app.ui.upgrade_chosen.emit(offer.offer_id,option.option_id)
	t.check(app.state.upgrade_offer.is_empty() and app.state.equipment.get(option.item_id,0) == option.next_level and app.game_save.store_revision == authority.store_revision+1,"same explicit selection succeeds once after coverage recovery")
	app.free()
