extends RefCounted
# Unexecuted draft. Real Controller/Store/worker/ACK/cold-read boundaries.
# Timers bound worker observations; they are not performance acceptance limits.
const Support = preload("res://tests/loot_city/loot_city_support.gd")
const Loot = preload("res://game/loot/loot_rules.gd")
var support := Support.new()

func run(t) -> void:
	await _late_ack_then_cold_controller(t)
	await _retained_chest_choice(t)
	await _choice_write_failure(t)
	await _unknown_autosave_ack(t)
	await t.create_timer(0.3).timeout

func _late_ack_then_cold_controller(t) -> void:
	var app = support.make(t,"late_ack")
	if app == null: return
	var chest := support.field(t,app)
	if chest.is_empty() or chest.status != "placed": app.free(); return
	var id: String = chest.id
	var placed: Dictionary = app.state.loot.duplicate(true)
	var revision: int = app.game_save.store_revision
	app._save_checkpoint()
	t.check(app._autosave_thread != null and app.game_save.store_revision == revision,"LOOT ACK submission retains old durable revision")
	if not await support.finished_unpolled(t,app,"placed predecessor"): app.free(); return
	# Complete the old disk write without main-thread ACK, then collect on the
	# live real resident Core. This is deterministic, without a worker sleep hook.
	if not support.collect(t,app,id): app.free(); return
	var collected: Dictionary = app.state.loot.duplicate(true)
	var live: Dictionary = app.state.duplicate(true)
	var core = app.simulation
	t.check(collected.gold == 5 and Loot.find_chest(app.state,id).status == "claimed","LOOT ACK live gold pickup precedes older acknowledgement")
	if not await support.drain(t,app,"older placed snapshot"): app.free(); return
	t.check(app.game_save.store_revision == revision+1 and support.same(app.game_save.checkpoint.loot,placed),"LOOT ACK confirms the exact captured predecessor")
	t.check(app.simulation == core and app.state == live and support.same(app.state.loot,collected),"LOOT ACK older completion never rewinds current Core or collected loot")
	t.check(app._autosave_blocker.is_empty() and app._autosave_unknown.is_empty(),"LOOT ACK older successful save leaves no recovery blocker")
	app._save_checkpoint()
	if not await support.drain(t,app,"latest collected snapshot"): app.free(); return
	t.check(app.game_save.store_revision == revision+2 and app.simulation == core and app.state == live,"LOOT ACK latest gold snapshot commits without live replacement")
	support.cold_read(t,app,collected,"latest collected gold")
	var directory: String = app.save_store._directory
	var durable_revision: int = app.game_save.store_revision
	app.free()
	var cold = await support.reopen(t,directory,collected,durable_revision)
	if cold == null: return
	if not cold.state.is_empty():
		var events: Array[Dictionary] = []
		cold.simulation._update_loot(cold.state,events)
		t.check(cold.state.loot.gold == 5 and support.same(cold.state.loot,collected) and events.is_empty(),"LOOT ACK actual cold Controller cannot repay claimed field chest")
	cold.free()

func _retained_chest_choice(t) -> void:
	var app = support.make(t,"reserved_chest")
	if app == null: return
	var offer := support.boss_offer(t,app)
	if offer.is_empty(): app.free(); return
	var revision: int = app.game_save.store_revision
	var live: Dictionary = app.state.duplicate(true)
	app._save_checkpoint()
	if not await support.finished_unpolled(t,app,"chest choice predecessor"): app.free(); return
	app.apply_upgrade(offer.offer_id,offer.selected_option_id)
	app.apply_upgrade(offer.offer_id,offer.selected_option_id)
	t.check(app._autosave_intent.get("action") == "upgrade" and app._autosave_intent.get("arguments",[]) == [offer.offer_id,offer.selected_option_id],"LOOT CHOICE duplicate input retains one exact chest selection")
	t.check(app.state == live and app.game_save.store_revision == revision,"LOOT CHOICE writer reservation prevents visible mutation before ACK")
	if not await support.drain(t,app,"retained chest choice"): app.free(); return
	_check_chosen(t,app,offer,revision+2,"retained duplicate")
	t.check(app._autosave_intent.is_empty() and app._failed_growth.is_empty() and app._pending_transaction.is_empty(),"LOOT CHOICE retained selection completes without another user action")
	var saved: Dictionary = app.game_save.duplicate(true)
	var final_state: Dictionary = app.state.duplicate(true)
	app.apply_upgrade(offer.offer_id,offer.selected_option_id)
	for i in 4: app.advance_frame(0)
	t.check(app.game_save == saved and app.state == final_state and app._autosave_pending.is_empty(),"LOOT CHOICE repeated confirmed input/late polls cannot recommit or rewind reward")
	support.cold_read(t,app,app.state.loot,"reserved chest choice")
	app.free()

func _choice_write_failure(t) -> void:
	var app = support.make(t,"choice_write_failure")
	if app == null: return
	var offer := support.boss_offer(t,app)
	if offer.is_empty(): app.free(); return
	app._save_checkpoint()
	if not await support.drain(t,app,"save open chest before fault"): app.free(); return
	var before: Dictionary = app.state.duplicate(true)
	var authority: Dictionary = app.game_save.duplicate(true)
	var path: String = app.save_store._directory.path_join("game_save.json")
	var source_hash := FileAccess.get_sha256(path)
	app.save_store._fault_injector = func(stage): return ERR_UNAVAILABLE if stage == "write" else OK
	app.apply_upgrade(offer.offer_id,offer.selected_option_id)
	t.check(app.state == before and app.game_save == authority and FileAccess.get_sha256(path) == source_hash,"LOOT CHOICE pre-replace failure leaves live offer, loot and exact durable bytes unchanged")
	t.check(app._failed_growth.get("offer_id") == offer.offer_id and Loot.find_chest(app.state,offer.chest_id).status == "queued","LOOT CHOICE failed selection remains retryable and unclaimed")
	app.save_store._fault_injector = Callable()
	app.apply_upgrade(offer.offer_id,offer.selected_option_id)
	app.apply_upgrade(offer.offer_id,offer.selected_option_id)
	_check_chosen(t,app,offer,int(authority.store_revision)+1,"write failure retry")
	t.check(app._failed_growth.is_empty() and app._pending_transaction.is_empty(),"LOOT CHOICE successful retry clears failed selection")
	support.cold_read(t,app,app.state.loot,"selection after failed write")
	app.free()

func _unknown_autosave_ack(t) -> void:
	var app = support.make(t,"unknown_ack")
	if app == null: return
	var chest := support.field(t,app)
	if chest.is_empty() or chest.status != "placed": app.free(); return
	if not support.collect(t,app,chest.id): app.free(); return
	var expected: Dictionary = app.state.loot.duplicate(true)
	var live: Dictionary = app.state.duplicate(true)
	var core = app.simulation
	var revision: int = app.game_save.store_revision
	app.autosave_test_fault = {"stage":"after_replace_before_return","return_error":true,"persist_read_failure":true}
	app._save_checkpoint()
	if not await support.drain(t,app,"unknown post-replace ACK"): app.free(); return
	t.check(not app._autosave_unknown.is_empty() and app.game_save.store_revision == revision,"LOOT UNKNOWN post-replace failure retains uncertain authority without false ACK")
	t.check(app.simulation == core and app.state == live,"LOOT UNKNOWN uncertainty preserves current loot and Core")
	var observed := support.cold_read(t,app,expected,"already replaced unknown save")
	if not observed.get("ok",false): app.free(); return
	t.check(observed.game_save.store_revision == revision+1,"LOOT UNKNOWN independent read proves exactly one committed revision")
	var path: String = app.save_store._directory.path_join("game_save.json")
	var committed_hash := FileAccess.get_sha256(path)
	app.autosave_test_fault = {}
	app.retry_save_recovery()
	if not await support.drain(t,app,"unknown ACK reread"): app.free(); return
	t.check(app._autosave_unknown.is_empty() and app._autosave_blocker.is_empty() and app.game_save.store_revision == revision+1,"LOOT UNKNOWN readback adopts committed loot exactly once")
	t.check(FileAccess.get_sha256(path) == committed_hash and app.simulation == core and app.state == live,"LOOT UNKNOWN reconciliation neither rewrites disk nor replays live pickup")
	app.retry_save_recovery()
	for i in 4: app.advance_frame(0)
	t.check(app.game_save.store_revision == revision+1 and app.state.loot.gold == 5 and FileAccess.get_sha256(path) == committed_hash,"LOOT UNKNOWN duplicate recovery cannot write or award twice")
	app.free()

func _check_chosen(t, app, offer: Dictionary, revision: int, label: String) -> void:
	var chest := Loot.find_chest(app.state,offer.chest_id)
	t.check(app.game_save.store_revision == revision,"LOOT CHOICE exact durable revision: "+label)
	t.check(chest.get("status") == "claimed" and chest.get("result") == "skill" and app.state.upgrade_offer.is_empty(),"LOOT CHOICE one committed skill claim: "+label)
	var count := 0
	for id in app.state.reward_ids_claimed:
		if id == "offer:"+offer.offer_id: count += 1
	t.check(count == 1 and support.same(app.game_save.checkpoint.loot,app.state.loot),"LOOT CHOICE one offer receipt and matching durable ledger: "+label)
