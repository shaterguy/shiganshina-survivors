extends RefCounted
const Fixture = preload("res://tests/core/core_fixture.gd")
func run(t) -> void:
	var sim = Fixture.simulation(t)
	if sim == null: return
	test_queued_offer_rebases_levels(t,sim)
	test_restore_timer_and_pause_relationships(t,sim)
	test_restore_and_choice_reject_invalid_options(t,sim)
	test_queue_identities(t,sim)
func recovery_options() -> Array:
	return [{"option_id":"recovery:25","item_id":"field_recovery_25","kind":"recovery","level":0,"next_level":1,"amount":25.0},{"option_id":"recovery:40","item_id":"field_recovery_40","kind":"recovery","level":0,"next_level":1,"amount":40.0},{"option_id":"recovery:60","item_id":"field_recovery_60","kind":"recovery","level":0,"next_level":1,"amount":60.0}]
func install_offer(state: Dictionary) -> void:
	state.upgrade_offer = {"offer_id":"levelup:2","source":"levelup","selected_option_id":"recovery:25","options":recovery_options()}
	state.pause_reasons = ["upgrade"]
func roundtrip(value: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(value))
func test_queued_offer_rebases_levels(t,sim) -> void:
	var state: Dictionary = sim.new_run(Fixture.chapter(),1)
	state.active_tick = 17999
	state.survival_tick = 17999
	Fixture.step(sim,state,Vector2.ZERO,[Fixture.boss("ch01_b05",[10,0])])
	var queued_id: String = state.pending_offers[0].offer_id
	var before_checkpoint: Dictionary = roundtrip(sim.snapshot(state))
	var restored: Dictionary = sim.restore(before_checkpoint)
	t.check(restored.ok and sim.snapshot(state) == sim.snapshot(restored.state),"legitimate queued offer checkpoint roundtrip preserved")
	var result: Dictionary = sim.choose_upgrade(state,state.upgrade_offer.offer_id,"equipment:blade_slash:2")
	t.check(result.ok and state.equipment.blade_slash == 2 and state.upgrade_offer.offer_id == queued_id,"queued offer retains FIFO ID after previous choice")
	var shared: Dictionary = {}
	for option in state.upgrade_offer.options:
		if option.item_id == "blade_slash": shared = option
	t.check(not shared.is_empty(),"queued shared item remains a selectable family")
	if shared.is_empty(): return
	t.check(shared.level == 2 and shared.next_level == 3 and shared.option_id == "equipment:blade_slash:3","queued option rebases displayed levels and semantic ID")
	var before: Dictionary = sim.snapshot(state)
	t.check(not sim.choose_upgrade(state,state.upgrade_offer.offer_id,"equipment:blade_slash:2").ok and state == before,"obsolete semantic option cannot select a different actual level")
	restored = sim.restore(roundtrip(before))
	t.check(restored.ok,"promoted rebased offer checkpoint remains valid")
	t.check(sim.choose_upgrade(state,state.upgrade_offer.offer_id,shared.option_id).ok and state.equipment.blade_slash == 3,"advertised next level is the applied level")
func evacuation(sim) -> Dictionary:
	var state: Dictionary = sim.new_run(Fixture.chapter(),1)
	state.active_tick = 108000
	state.survival_tick = 108000
	Fixture.step(sim,state,Vector2.ZERO,[{"command_id":"final","kind":"begin_evacuation","payload":{"boss_id":"ch01_final_armored","escape_zone":[-20,-20,40,40],"evacuation_ticks":4500}}])
	return state
func test_restore_timer_and_pause_relationships(t,sim) -> void:
	var state: Dictionary = evacuation(sim)
	var valid: Dictionary = roundtrip(state)
	t.check(sim.restore(valid).ok,"legitimate evacuation checkpoint accepted")
	for corruption in ["premature_ready","missing_start","future_start","unfrozen_survival","short_rule"]:
		var broken: Dictionary = valid.duplicate(true)
		match corruption:
			"premature_ready": broken.evacuation_ready = true
			"missing_start": broken.final_started_tick = -1
			"future_start": broken.final_started_tick = broken.active_tick+1
			"unfrozen_survival": broken.survival_tick = 107999
			"short_rule": broken.rules.evacuation_ticks = 1
		var unchanged: Dictionary = broken.duplicate(true)
		t.check(not sim.restore(broken).ok and broken == unchanged,"inconsistent evacuation checkpoint rejected without mutation: "+corruption)
	state.player.position = [100.0,100.0]
	state.active_tick = state.final_started_tick+4499
	Fixture.step(sim,state,Vector2.ZERO,[])
	t.check(state.evacuation_ready and sim.restore(roundtrip(state)).ok,"legitimate ready checkpoint at 4500 ticks accepted")
	state = sim.new_run(Fixture.chapter(),4)
	install_offer(state)
	valid = roundtrip(state)
	t.check(sim.restore(valid).ok,"legitimate recovery offer checkpoint accepted")
	valid.pause_reasons.clear()
	var unchanged: Dictionary = valid.duplicate(true)
	t.check(not sim.restore(valid).ok and valid == unchanged,"unanswered offer without upgrade pause rejected unchanged")
	state = sim.new_run(Fixture.chapter(),4)
	sim.set_pause(state,"upgrade",true)
	t.check(sim.restore(roundtrip(state)).ok,"standalone upgrade pause remains valid")
func test_restore_and_choice_reject_invalid_options(t,sim) -> void:
	for corruption in ["missing_amount","negative_amount","zero_amount","amount_type","kind_type","level_type","fractional_level","wrong_semantic_id","wrong_item_id"]:
		var state: Dictionary = sim.new_run(Fixture.chapter(),2)
		install_offer(state)
		match corruption:
			"missing_amount": state.upgrade_offer.options[0].erase("amount")
			"negative_amount": state.upgrade_offer.options[0].amount = -1
			"zero_amount": state.upgrade_offer.options[0].amount = 0
			"amount_type": state.upgrade_offer.options[0].amount = "bad"
			"kind_type": state.upgrade_offer.options[0].kind = []
			"level_type": state.upgrade_offer.options[0].level = "bad"
			"fractional_level": state.upgrade_offer.options[0].level = 0.5
			"wrong_semantic_id": state.upgrade_offer.options[0].option_id = "recovery:999"
			"wrong_item_id": state.upgrade_offer.options[0].item_id = "wall_cannon"
		var before: Dictionary = sim.snapshot(state)
		t.check(not sim.restore(roundtrip(state)).ok,"malformed offer checkpoint rejected: "+corruption)
		var choice: Dictionary = sim.choose_upgrade(state,"levelup:2",str(state.upgrade_offer.options[0].option_id))
		t.check(choice.has("ok") and not choice.ok and choice.has("error_code") and state == before,"public choose rejects malformed option explicitly without mutation: "+corruption)
	var chapter: Dictionary = Fixture.chapter()
	chapter.allowed_equipment_ids = ["blade_slash"]
	var state: Dictionary = sim.new_run(chapter,2)
	install_offer(state)
	state.upgrade_offer.options[0] = {"option_id":"equipment:wall_cannon:1","item_id":"wall_cannon","kind":"equipment","level":0,"next_level":1}
	state.upgrade_offer.selected_option_id = "equipment:wall_cannon:1"
	var before: Dictionary = sim.snapshot(state)
	t.check(not sim.restore(roundtrip(state)).ok,"chapter-disallowed equipment offer rejected on restore")
	var choice: Dictionary = sim.choose_upgrade(state,"levelup:2","equipment:wall_cannon:1")
	t.check(not choice.ok and state == before,"chapter-disallowed equipment rejected by public choice")
func queued_offer(id: String, choices: Array) -> Dictionary:
	return {"offer_id":id,"source":"levelup","selected_option_id":choices[0].option_id,"options":choices}
func item_option(level: int) -> Dictionary:
	return {"option_id":"equipment:blade_slash:%d"%(level+1),"item_id":"blade_slash","kind":"equipment","level":level,"next_level":level+1}
func test_queue_identities(t,sim) -> void:
	var state: Dictionary = sim.new_run(Fixture.chapter(),1)
	install_offer(state)
	state.pending_offers = [queued_offer("levelup:3",[item_option(0),item_option(1),recovery_options()[0]])]
	var checkpoint: Dictionary = roundtrip(state)
	var unchanged: Dictionary = checkpoint.duplicate(true)
	t.check(not sim.restore(checkpoint).ok and checkpoint == unchanged,"duplicate pending item family rejected without mutation")
	# Defense in depth for an invalid caller bypassing restore: promotion
	# must never expose colliding IDs even when stale levels differ.
	var chosen: Dictionary = sim.choose_upgrade(state,"levelup:2","recovery:25")
	t.check(chosen.ok,"valid current choice survives malformed future family via redraw")
	var ids: Array = []
	for option in state.upgrade_offer.options:
		t.check(not option.option_id in ids,"defensive promotion never exposes duplicate IDs")
		ids.append(option.option_id)
	var selected: Dictionary = sim.choose_upgrade(state,state.upgrade_offer.offer_id,state.upgrade_offer.options[0].option_id)
	t.check(selected.ok,"defensive promotion remains selectable")
	for corruption in ["current_pending","pending_pending","claimed_current","claimed_pending"]:
		state = sim.new_run(Fixture.chapter(),1)
		install_offer(state)
		state.pending_offers = [queued_offer("levelup:3",recovery_options())]
		match corruption:
			"current_pending": state.pending_offers[0].offer_id = "levelup:2"
			"pending_pending": state.pending_offers.append(queued_offer("levelup:3",recovery_options()))
			"claimed_current": state.reward_ids_claimed = ["offer:levelup:2"]
			"claimed_pending": state.reward_ids_claimed = ["offer:levelup:3"]
		checkpoint = roundtrip(state)
		unchanged = checkpoint.duplicate(true)
		t.check(not sim.restore(checkpoint).ok and checkpoint == unchanged,"duplicate or claimed queue offer rejected unchanged: "+corruption)
	state = sim.new_run(Fixture.chapter(),1)
	install_offer(state)
	state.reward_ids_claimed = ["offer:levelup:2"]
	var before: Dictionary = sim.snapshot(state)
	selected = sim.choose_upgrade(state,"levelup:2","recovery:25")
	t.check(not selected.ok and state == before,"public choice rejects already claimed offer without mutation")
	state = sim.new_run(Fixture.chapter(),1)
	install_offer(state)
	state.player.hp = 1.0
	state.pending_offers = [queued_offer("levelup:2",recovery_options())]
	chosen = sim.choose_upgrade(state,"levelup:2","recovery:25")
	selected = sim.choose_upgrade(state,"levelup:2","recovery:25")
	t.check(chosen.ok and not selected.ok and state.player.hp == 26.0 and state.upgrade_offer.is_empty() and not "upgrade" in state.pause_reasons,"defensive duplicate reward queue pays once and releases pause")
