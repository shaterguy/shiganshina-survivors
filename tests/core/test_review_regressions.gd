extends RefCounted
const Fixture = preload("res://tests/core/new_current_regression_fixture.gd")
func run(t) -> void:
	var sim = Fixture.simulation(t)
	if sim == null: return
	test_queued_offer_rebases_levels(t,sim)
	test_restore_timer_and_pause_relationships(t,sim)
	test_restore_and_choice_reject_invalid_options(t,sim)
	test_queue_identities(t,sim)
func roundtrip(value: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(value,"",true,true))
func test_queued_offer_rebases_levels(t,sim) -> void:
	var state := Fixture.boss_reward_state(sim,2)
	state.passives = {"movement":3}
	# Satisfy the current wing material so the even earned level prioritizes
	# blade growth, preserving the shared-family FIFO/rebase scenario.
	state.equipment.odm_dash = 1
	state.player.attack_ready_ticks.odm_dash = 2147483647
	Fixture.step(sim,state,Vector2.ZERO)
	var queued_id: String = state.pending_offers[0].offer_id
	t.check(state.pending_offers[0].size() == 3 and not state.pending_offers[0].has("options"),"queued offer stores a deferred descriptor rather than stale options")
	var before_checkpoint: Dictionary = roundtrip(sim.snapshot(state))
	var restored: Dictionary = sim.restore(before_checkpoint)
	t.check(restored.ok and sim.snapshot(state) == sim.snapshot(restored.state),"legitimate queued offer checkpoint roundtrip preserved")
	var result: Dictionary = sim.choose_upgrade(state,state.upgrade_offer.offer_id,"equipment:blade_slash")
	t.check(result.ok and state.equipment.blade_slash == 2 and state.upgrade_offer.offer_id == queued_id,"queued offer retains FIFO ID after previous choice")
	var shared: Dictionary = {}
	for option in state.upgrade_offer.options:
		if option.item_id == "blade_slash": shared = option
	t.check(not shared.is_empty(),"queued shared item remains a selectable family")
	if shared.is_empty(): return
	t.check(shared.level == 2 and shared.next_level == 3 and shared.option_id == "equipment:blade_slash","deferred materialization reflects current levels under stable family ID")
	var before: Dictionary = sim.snapshot(state)
	var stale := before.duplicate(true)
	for option in stale.upgrade_offer.options:
		if option.item_id == "blade_slash":
			option.level = 1
			option.next_level = 2
	var unchanged := stale.duplicate(true)
	t.check(not sim.choose_upgrade(stale,queued_id,shared.option_id).ok and stale == unchanged,"stale advertised levels cannot select a different actual level")
	restored = sim.restore(roundtrip(before))
	t.check(restored.ok,"promoted freshly materialized offer checkpoint remains valid")
	t.check(sim.choose_upgrade(state,state.upgrade_offer.offer_id,shared.option_id).ok and state.equipment.blade_slash == 3,"advertised next level is the applied level")
func evacuation(sim) -> Dictionary:
	var state: Dictionary = sim.new_run(Fixture.chapter(),1,Fixture.run_config())
	state.active_tick = 108000
	state.survival_tick = 108000
	Fixture.step(sim,state,Vector2.ZERO,[Fixture.final_command(state)])
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
	Fixture.arrange_final_clock(state,int(state.final_started_tick)+4499)
	Fixture.step(sim,state,Vector2.ZERO,[])
	t.check(state.evacuation_ready and sim.restore(roundtrip(state)).ok,"legitimate ready checkpoint at 4500 ticks accepted")
	state = Fixture.earn_offer(sim,4)
	valid = roundtrip(state)
	t.check(sim.restore(valid).ok,"legitimate earned offer checkpoint accepted")
	valid.pause_reasons.clear()
	var unchanged: Dictionary = valid.duplicate(true)
	t.check(not sim.restore(valid).ok and valid == unchanged,"unanswered offer without upgrade pause rejected unchanged")
	state = sim.new_run(Fixture.chapter(),4,Fixture.run_config())
	sim.set_pause(state,"upgrade",true)
	t.check(not "upgrade" in state.pause_reasons and sim.restore(roundtrip(state)).ok,"standalone upgrade pause cannot invent an unanswered offer")
func test_restore_and_choice_reject_invalid_options(t,sim) -> void:
	for corruption in ["missing_next_level","negative_level","zero_next_level","next_level_type","kind_type","level_type","fractional_level","wrong_semantic_id","wrong_item_id"]:
		var state: Dictionary = Fixture.earn_offer(sim,2)
		var offer_id: String = state.upgrade_offer.offer_id
		match corruption:
			"missing_next_level": state.upgrade_offer.options[0].erase("next_level")
			"negative_level": state.upgrade_offer.options[0].level = -1
			"zero_next_level": state.upgrade_offer.options[0].next_level = 0
			"next_level_type": state.upgrade_offer.options[0].next_level = "bad"
			"kind_type": state.upgrade_offer.options[0].kind = []
			"level_type": state.upgrade_offer.options[0].level = "bad"
			"fractional_level": state.upgrade_offer.options[0].level = 0.5
			"wrong_semantic_id": state.upgrade_offer.options[0].option_id = "equipment:unknown"
			"wrong_item_id": state.upgrade_offer.options[0].item_id = "not_authored"
		var before: Dictionary = sim.snapshot(state)
		t.check(not sim.restore(roundtrip(state)).ok,"malformed offer checkpoint rejected: "+corruption)
		var choice: Dictionary = sim.choose_upgrade(state,offer_id,str(state.upgrade_offer.options[0].option_id))
		t.check(choice.has("ok") and not choice.ok and choice.has("error_code") and state == before,"public choose rejects malformed option explicitly without mutation: "+corruption)
	var chapter: Dictionary = Fixture.chapter()
	chapter.allowed_equipment_ids = ["blade_slash"]
	t.check(sim.new_run(chapter,2,Fixture.run_config()).get("error_code") == "invalid_chapter","caller cannot replace pinned chapter equipment permissions")
	var state := Fixture.earn_offer(sim,2)
	state.rules.allowed_equipment_ids = ["blade_slash"]
	var before: Dictionary = sim.snapshot(state)
	t.check(not sim.restore(roundtrip(state)).ok,"tampered chapter equipment permissions rejected on restore")
	var choice: Dictionary = sim.choose_upgrade(state,state.upgrade_offer.offer_id,state.upgrade_offer.options[0].option_id)
	t.check(not choice.ok and state == before,"public choice cannot use altered chapter permissions")
func test_queue_identities(t,sim) -> void:
	var state := Fixture.earn_offer(sim,1,56)
	t.check(state.pending_offers.size() == 1 and sim.restore(state).ok,"two real level thresholds create a valid FIFO queue")
	# Current contract rejects materialized future choices atomically, including
	# duplicate item families; it does not redraw malformed caller authority.
	state.pending_offers[0].options = [state.upgrade_offer.options[0].duplicate(true),state.upgrade_offer.options[0].duplicate(true)]
	var checkpoint: Dictionary = roundtrip(state)
	var unchanged: Dictionary = checkpoint.duplicate(true)
	t.check(not sim.restore(checkpoint).ok and checkpoint == unchanged,"materialized duplicate pending family rejected without mutation")
	var before := state.duplicate(true)
	var chosen: Dictionary = sim.choose_upgrade(state,state.upgrade_offer.offer_id,state.upgrade_offer.options[0].option_id)
	t.check(not chosen.ok and state == before,"public choice rejects malformed future family without consuming reward")
	state = Fixture.earn_offer(sim,1,56)
	chosen = sim.choose_upgrade(state,state.upgrade_offer.offer_id,state.upgrade_offer.options[0].option_id)
	t.check(chosen.ok,"valid current choice promotes a valid deferred queue")
	var ids: Array = []
	for option in state.upgrade_offer.options:
		t.check(not option.option_id in ids,"defensive promotion never exposes duplicate IDs")
		ids.append(option.option_id)
	var selected: Dictionary = sim.choose_upgrade(state,state.upgrade_offer.offer_id,state.upgrade_offer.options[0].option_id)
	t.check(selected.ok,"defensive promotion remains selectable")
	for corruption in ["current_pending","pending_pending","claimed_current","claimed_pending"]:
		state = Fixture.earn_offer(sim,1,56)
		match corruption:
			"current_pending": state.pending_offers[0].offer_id = state.upgrade_offer.offer_id
			"pending_pending": state.pending_offers.append(state.pending_offers[0].duplicate(true))
			"claimed_current": state.reward_ids_claimed = ["offer:"+state.upgrade_offer.offer_id]
			"claimed_pending": state.reward_ids_claimed = ["offer:"+state.pending_offers[0].offer_id]
		checkpoint = roundtrip(state)
		unchanged = checkpoint.duplicate(true)
		t.check(not sim.restore(checkpoint).ok and checkpoint == unchanged,"duplicate or claimed queue offer rejected unchanged: "+corruption)
	state = Fixture.earn_offer(sim,1)
	state.reward_ids_claimed = ["offer:"+state.upgrade_offer.offer_id]
	before = sim.snapshot(state)
	selected = sim.choose_upgrade(state,state.upgrade_offer.offer_id,state.upgrade_offer.options[0].option_id)
	t.check(not selected.ok and state == before,"public choice rejects already claimed offer without mutation")
	state = Fixture.earn_offer(sim,1,56)
	state.player.hp = 1.0
	state.pending_offers[0].offer_id = state.upgrade_offer.offer_id
	before = sim.snapshot(state)
	chosen = sim.choose_upgrade(state,state.upgrade_offer.offer_id,state.upgrade_offer.options[0].option_id)
	selected = sim.choose_upgrade(state,state.upgrade_offer.offer_id,state.upgrade_offer.options[0].option_id)
	t.check(not chosen.ok and not selected.ok and state == before,"repeated malformed duplicate queue requests never pay or consume authority")
