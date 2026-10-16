extends RefCounted
# Unexecuted draft. Uses real Core with explicitly arranged clocks/prerequisites.
# This is not a natural 30-minute run, streamed coverage or disk/ACK test.
const F = preload("res://tests/core/core_fixture.gd")
const Loot = preload("res://game/loot/loot_rules.gd")
const View = preload("res://game/progression/progression_view.gd")
func run(t) -> void:
	var sim = F.simulation(t)
	if sim == null: return
	var config: Dictionary = F.run_config()
	var legacy: Dictionary = sim.new_run(F.v2_chapter(),42,config)
	t.check(not legacy.has("loot") and not legacy.run_config.has("loot_rules_version"),"LOOT legacy constructor remains opt-out")
	config.loot_rules_version = 1
	var state: Dictionary = sim.new_run(F.v2_chapter(),42,config)
	t.check(state.get("loot",{}) == Loot.initial(),"LOOT new opt-in constructor initializes state")
	if not state.has("loot"): return
	t.check(sim.restore(state).get("ok",false),"LOOT initial cold restore accepts new marker")
	var json_state = JSON.parse_string(JSON.stringify(state,"",true,true))
	t.check(sim.restore(json_state).get("ok",false),"LOOT JSON integer-float boundary restores")
	var rng: String = state.progression_rng_state
	var events: Array[Dictionary] = []
	state.active_tick = 10799
	state.survival_tick = 10799
	sim._update_loot(state,events)
	t.check(state.loot.chests.is_empty(),"LOOT no early field chest")
	state.active_tick = 10800
	state.survival_tick = 10800
	sim._update_loot(state,events)
	t.check(state.loot.chests.size() == 1 and state.loot.chests[0].source_id == "10800","LOOT first due field source created once")
	t.check(state.progression_rng_state == rng,"LOOT placement consumes no progression RNG")
	var chest: Dictionary = state.loot.chests[0]
	var identity: String = chest.id
	var retry: int = state.loot.next_retry_tick
	sim._update_loot(state,events)
	t.check(state.loot.chests.size() == 1 and state.loot.next_retry_tick == retry,"LOOT repeated same tick neither duplicates nor retries")
	# Arrange a reachable, already-placed pickup to test exactly-once collection.
	Loot.set_position(state,chest,Vector2(state.player.position[0],state.player.position[1]))
	chest.status = "placed"
	sim._update_loot(state,events)
	t.check(chest.status == "claimed" and state.loot.gold == 5,"LOOT direct gold pickup records five run gold")
	sim._update_loot(state,events)
	t.check(state.loot.gold == 5 and chest.id == identity,"LOOT collected gold cannot repeat")
	t.check(Loot.validate(state),"LOOT collected source evidence validates")
	var before := state.duplicate(true)
	var hostile := state.duplicate(true)
	hostile.loot.gold = 0
	hostile.loot.chests[0].status = "placed"
	hostile.loot.chests[0].result = ""
	t.check(not Loot.transition_valid(before,hostile),"LOOT save transition rejects collection rollback")
	for bad_world in [null,[],"city",{"stage":3}]:
		hostile = state.duplicate(true)
		hostile.world = bad_world
		t.check(not Loot.validate(hostile),"LOOT malformed early world is rejected without member access")
	_boss_and_queue(t,sim,config)
	_dock_transfer(t,sim,config)
	_selection_and_restore(t,sim,config)

func _boss_and_queue(t, sim, config: Dictionary) -> void:
	var state: Dictionary = sim.new_run(F.v2_chapter(),42,config)
	state.active_tick = 18000
	state.survival_tick = 18000
	state.boss_ids_fired.append("ch01_b05")
	state.stats.kills = 1
	state.player.hp = float(state.player.max_hp)*0.5
	var events: Array[Dictionary] = []
	var reward := {"boss_id":"ch01_b05","entity_id":"test:boss","position":state.player.position.duplicate()}
	var rng: String = state.progression_rng_state
	sim._claim_boss_reward(state,reward,events)
	t.check(state.tactical_seals == 1 and state.stats.minibosses_defeated == 1 and state.player.hp == float(state.player.max_hp)*0.75,"LOOT boss seal stats and quarter heal preserved")
	t.check(state.pending_offers.is_empty() and state.offer_seq == 0 and state.progression_rng_state == rng,"LOOT boss death defers only growth offer until collection")
	var boss: Dictionary = Loot.find_chest(state,Loot.chest_id(state.run_id,"boss","ch01_b05"))
	t.check(not boss.is_empty(),"LOOT boss receipt has one stable chest")
	# Fill existing level FIFO; chest must remain available rather than disappear.
	state.player.level = 257
	for i in range(256): sim._queue_offer(state,"level")
	boss.status = "placed"
	sim._update_loot(state,events)
	t.check(boss.status == "placed" and boss.offer_id == "","LOOT full growth FIFO leaves chest uncollected")
	# Arrange already-consumed historical level offers, then collect the chest.
	state.pending_offers.clear()
	sim._update_loot(state,events)
	t.check(boss.status == "queued" and state.pending_offers.size() == 1 and state.pending_offers[0].source == "chest","LOOT pickup connects stable chest ID to FIFO")
	t.check(sim._activate_next_offer(state,events),"LOOT existing materializer accepts chest descriptor")
	t.check(state.upgrade_offer.get("chest_id","") == boss.id,"LOOT activated choice preserves chest identity")
	var view: Dictionary = View.new(sim._catalog).build(state)
	t.check(view.get("active_offer",{}).get("source","") == "chest","LOOT real progression view exposes chest choice")
	var again := state.duplicate(true)
	sim._claim_boss_reward(again,reward,events)
	t.check(again.loot.chests.size() == state.loot.chests.size() and again.tactical_seals == 1,"LOOT duplicate boss receipt cannot add rewards")

func _dock_transfer(t, sim, config: Dictionary) -> void:
	var state: Dictionary = sim.new_run(F.v2_chapter(),42,config)
	state.active_tick = 18000
	state.survival_tick = 18000
	var events: Array[Dictionary] = []
	sim._add_loot(state,Loot.field_spec(0),Vector2.ZERO)
	sim._add_loot(state,Loot.boss_spec("ch01_b05"),Vector2.ZERO)
	var id: String = state.loot.chests[1].id
	state.loot.next_retry_tick = 18059
	# Narrow unit arrangement of already-constructed dock transition state.
	state.world = {"stage":"dock"}
	sim.transfer_loot_to_dock(state)
	t.check(state.loot.chests[0].status == "expired","LOOT dock expires unclaimed field chest")
	t.check(state.loot.chests[1].status == "pending" and state.loot.chests[1].stage == "dock" and state.loot.chests[1].id == id,"LOOT dock preserves boss chest identity as pending")
	t.check(state.loot.next_retry_tick == 18059,"LOOT dock cannot reset global placement budget")

func _selection_and_restore(t, sim, config: Dictionary) -> void:
	var state: Dictionary = sim.new_run(F.v2_chapter(),42,config)
	state.active_tick = 32400
	state.survival_tick = 32400
	var events: Array[Dictionary] = []
	for i in range(2): sim._add_loot(state,Loot.field_spec(i),Vector2(state.player.position[0],state.player.position[1]))
	state.loot.chests[0].status = "placed"
	state.loot.chests[1].status = "placed"
	sim._update_loot(state,events)
	t.check(sim._activate_next_offer(state,events),"LOOT field skill activates real candidate")
	var offer: Dictionary = state.upgrade_offer.duplicate(true)
	var decoded = JSON.parse_string(JSON.stringify(state,"",true,true))
	var restored: Dictionary = sim.restore(decoded)
	t.check(restored.get("ok",false),"LOOT active chest offer cold restore succeeds")
	if not restored.get("ok",false): return
	state = restored.state
	t.check(state.upgrade_offer == offer,"LOOT restored options/focus are not rerolled")
	var chosen: Dictionary = sim.choose_upgrade(state,offer.offer_id,offer.selected_option_id)
	t.check(chosen.get("ok",false),"LOOT real selection commits chest skill")
	t.check(state.loot.chests[1].status == "claimed" and state.loot.chests[1].result == "skill" and "offer:"+offer.offer_id in state.reward_ids_claimed,"LOOT successful choice records one receipt")
	var fingerprint := JSON.stringify(state,"",true,true)
	t.check(not sim.choose_upgrade(state,offer.offer_id,offer.selected_option_id).get("ok",false) and JSON.stringify(state,"",true,true) == fingerprint,"LOOT repeated choice fails without mutating live state")
	# Existing slots are full/maxed and their available evolutions already applied.
	state = sim.new_run(F.v2_chapter(),42,config)
	state.active_tick = 32400
	state.survival_tick = 32400
	state.equipment = {"blade_slash":5,"spin_slash":5,"odm_dash":5,"reentry_combo":5}
	state.passives = {"damage":5,"fire_interval":5,"movement":5,"recovery":5}
	state.evolutions = {"blade_slash":"evo_wing_cut","spin_slash":"evo_whirlwind","odm_dash":"evo_sky_lance","reentry_combo":"evo_echo_assault"}
	t.check(sim._catalog.candidates(state).is_empty(),"LOOT saturation fixture has no basic candidates")
	for id in sim._catalog.evolutions.ids():
		t.check(not sim._catalog.evolutions.evaluate(state,id).get("can_evolve",false),"LOOT saturation fixture has no remaining evolution: "+id)
	for i in range(2): sim._add_loot(state,Loot.field_spec(i),Vector2(state.player.position[0],state.player.position[1]))
	state.loot.chests[0].status = "placed"
	state.loot.chests[1].status = "placed"
	sim._update_loot(state,events)
	var rng: String = state.progression_rng_state
	t.check(sim._activate_next_offer(state,events),"LOOT saturated chest uses existing empty candidate path")
	t.check(state.upgrade_offer.is_empty() and state.loot.gold == 10 and state.loot.chests[1].result == "gold","LOOT saturated skill adds exactly five gold")
	t.check(state.progression_rng_state == rng,"LOOT no-candidate fallback consumes no RNG")
	t.check(Loot.validate(state),"LOOT fallback receipt matches source and gold")
	t.check(sim.restore(JSON.parse_string(JSON.stringify(state,"",true,true))).get("ok",false),"LOOT saturated fallback cold restore preserves claimed source")
