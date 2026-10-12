extends RefCounted
# Actual Controller/Core/Store/Thread; only the encounter and lifecycle events
# are arranged. No native/device/GPU validation is implied.
const S = preload("res://tests/app_city_controller/controller_city_support.gd")
const G = preload("res://tests/app_city_controller/grabber_controller_support.gd")
var _t
func check(value: bool, message: String) -> void:
	_t.check(value,message)
func run(t) -> void:
	_t = t
	await basic(false)
	await basic(true)
	await changed_generation(false)
	await changed_generation(true)
	await critical("upgrade")
	await critical("purchase")
	await _t.process_frame
	await _t.create_timer(0.3).timeout
func fixture() -> Dictionary:
	var value := S.make(_t)
	if value.is_empty(): return {}
	var setup := G.arrange(_t,value.app)
	if setup.is_empty(): value.app.free(); return {}
	if not G.at_tick(_t,value.app,int(setup.started_tick)+62): value.app.free(); return {}
	value.app.autosave_worker_enabled = true
	return value
func finished(app) -> bool:
	var deadline := Time.get_ticks_usec()+10000000
	while app._autosave_thread != null and app._autosave_thread.is_alive() and Time.get_ticks_usec() < deadline:
		await _t.create_timer(0.003).timeout
	var ready: bool = app._autosave_thread != null and not app._autosave_thread.is_alive()
	check(ready,"real worker reaches terminal before main-thread adoption")
	return ready
func settle(app) -> void:
	while app._autosave_thread != null:
		if not await finished(app): return
		app.advance_frame(0)
func combat(app) -> Dictionary:
	return {"tick":app.state.active_tick,"hp":app.state.player.hp,"event_seq":app.state.event_seq,"raw":app.state.enemy_attack_instances.duplicate(true),"attack_seq":app.state.attack_seq}
func basic(multi: bool) -> void:
	var value := fixture()
	if value.is_empty(): return
	var app = value.app
	if multi:
		app.simulation.set_pause(app.state,"rotation",true)
		app.simulation.set_pause(app.state,"user",true)
	var before := combat(app)
	var packet: Dictionary = app.simulation.enemy_attack_view(app.state)
	app._save_checkpoint()
	if not await finished(app): app.free(); return
	app.input_router.active_device = 5
	app.input_router._stick = Vector2.RIGHT
	app._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	if multi: app.input_router._on_connection(5,false)
	app.request_resume()
	app.advance_frame(1.0/60.0)
	check(combat(app) == before and app._autosave_intent.is_empty(),"background cannot accept Continue or advance a hand tick")
	check(app.input_router.sample_move() == Vector2.ZERO and not app.input_router._accept_armed,"focus/pad loss clears held movement and accept latch")
	app._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	check("background" in app.state.pause_reasons and (not multi or "controller_lost" in app.state.pause_reasons),"foreground alone retains every lifecycle pause")
	# Complete the coalesced background capture but leave its reservation intact.
	if app._autosave_thread != null and not await finished(app): app.free(); return
	app.request_resume()
	check(app._autosave_intent.get("action") == "resume","explicit Continue is retained while completed writer awaits adoption")
	app.advance_frame(0)
	await settle(app)
	check(app._autosave_intent.is_empty() and not app._lifecycle_blocked(),"one current-generation foreground Continue resolves the lifecycle hold")
	check(combat(app) == before and app.world._enemy_attack_packet == packet,"resume/adoption replays no tick, damage, ledger or packet")
	check(app.state.pause_reasons == (["rotation"] if multi else []),"Continue clears its four reasons while preserving unrelated rotation pause")
	if multi:
		check(app.input_router.active_device == -1 and app.input_router.sample_move() == Vector2.ZERO,"disconnected pad input stays released after Continue")
		app.advance_frame(1.0/60.0)
		check(combat(app) == before,"remaining independent pause still prevents simulation")
	print("LIFECYCLE_BASIC "+JSON.stringify({"multi":multi,"intent":app._autosave_intent,"pause":app.state.pause_reasons,"combat":combat(app),"reserved":app._worker_reserved()}))
	app.free()
func changed_generation(rechoose: bool) -> void:
	var value := fixture()
	if value.is_empty(): return
	var app = value.app
	var before := combat(app)
	app.simulation.set_pause(app.state,"user",true)
	app._save_checkpoint()
	if not await finished(app): app.free(); return
	app.request_resume()
	var old_generation: int = app._autosave_intent.lifecycle_generation
	app._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	app._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	if rechoose:
		app.request_resume()
		check(app._autosave_intent.get("lifecycle_generation") == app._lifecycle_generation and app._lifecycle_generation > old_generation,"new explicit Continue replaces an unexecuted stale-generation resume")
	app.advance_frame(0)
	await settle(app)
	if rechoose:
		check(app._autosave_intent.is_empty() and not app._lifecycle_blocked(),"reselected Continue runs once after confirmed writer")
	else:
		check(app._autosave_intent.is_empty() and app._lifecycle_blocked() and "background" in app.state.pause_reasons,"obsolete Continue is discarded without resuming newer lifecycle")
		app.request_resume()
		await settle(app)
		check(not app._lifecycle_blocked(),"fresh Continue after stale rejection is not permanently locked")
	check(combat(app) == before,"lifecycle generation changes cannot replay active hand")
	app.free()
func critical(action: String) -> void:
	var value := fixture()
	if value.is_empty(): return
	var app = value.app
	var offer := {}
	if action == "upgrade":
		app.state.player.xp = int(app.state.rules.progression.base_xp)
		app.advance_frame(1.0/60.0)
		offer = app.state.upgrade_offer.duplicate(true)
		check(not offer.is_empty(),"real Core creates an upgrade choice while hand remains live")
		if offer.is_empty(): app.free(); return
		await settle(app)
	var before := combat(app)
	var receipts: Array = app.game_save.purchase_receipts.duplicate(true)
	var profile: Dictionary = app.profile.duplicate(true)
	app._save_checkpoint()
	if not await finished(app): app.free(); return
	if action == "upgrade": app.apply_upgrade(offer.offer_id,offer.options[0].option_id)
	else: app.apply_purchase("field_bandage",app._view_revision)
	check(app._autosave_intent.get("action") == action,"critical selection remains unexecuted behind actual writer")
	app._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	app.advance_frame(1.0/60.0)
	check(app._autosave_intent.get("action") == action and combat(app) == before,"background neither applies nor advances retained critical selection")
	app._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	app.request_resume()
	check(app._autosave_intent.get("action","") != action and app.ui._notice.text.contains("다시 선택"),"foreground Continue visibly cancels old critical choice for explicit reselection")
	app.advance_frame(0)
	await settle(app)
	check(app._autosave_intent.is_empty() and not app._lifecycle_blocked() and combat(app) == before,"cancelled critical request cannot lock foreground Continue or replay combat")
	check(app.game_save.purchase_receipts == receipts and app.profile.supply_credits == profile.supply_credits and app.profile.consumables == profile.consumables,"Continue does not apply a purchase or debit inventory/credits")
	if action == "upgrade":
		check(app.state.upgrade_offer == offer and "upgrade" in app.state.pause_reasons,"unselected real upgrade and its independent pause remain intact")
		if not app._lifecycle_blocked() and app._autosave_intent.is_empty():
			var revision: int = app.game_save.store_revision
			app.apply_upgrade(offer.offer_id,offer.options[0].option_id)
			app.apply_upgrade(offer.offer_id,offer.options[0].option_id)
			await settle(app)
			check(app.state.upgrade_offer.is_empty() and not "upgrade" in app.state.pause_reasons and app.game_save.store_revision == revision+1,"explicit upgrade reselection commits once despite duplicate input")
	app.free()
