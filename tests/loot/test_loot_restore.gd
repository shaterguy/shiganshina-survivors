extends RefCounted
# Real finite Core cold boundaries with deliberately arranged authored clocks.
# No claim of natural spawn cadence, city geometry or actual disk persistence.
const Core = preload("res://game/core/run_simulation.gd")
const F = preload("res://tests/core/core_fixture.gd")
const Loot = preload("res://game/loot/loot_rules.gd")
class BlockedPlacement:
	extends "res://game/core/run_simulation.gd"
	var attempts := 0
	func _loot_path_clear(_state: Dictionary, _origin: Vector2, _target: Vector2) -> bool:
		attempts += 1
		return false
func run(t) -> void:
	_field_boundaries(t)
	_all_sources(t)
	_pending_and_claimed(t)
	_queued_chain(t)
	_replay_new(t)
	_retry_budget(t)
func _new(sim) -> Dictionary:
	var config: Dictionary = F.run_config()
	config.loot_rules_version = 1
	return sim.new_run(F.v2_chapter(),42,config)
func _all_sources(t) -> void:
	var sim = Core.new()
	var state := _new(sim)
	var events: Array[Dictionary] = []
	var bosses := ["boss_charger","boss_sweeper","boss_leaper","boss_grabber","boss_abnormal"]
	for i in range(5):
		state.active_tick = (i+1)*18000
		state.survival_tick = state.active_tick
		var id: String = Loot.BOSS_IDS[i]
		var command := {"command_id":"loot-test:boss:"+id,"kind":"spawn_boss","payload":{"entity_id":"loot-test:"+id,"boss_id":id,"enemy_id":bosses[i],"position":[45.0,0.0],"scheduled_tick":state.active_tick}}
		sim._apply_command(state,command,events)
		t.check(state.entities.size() == 1,"LOOT authored boss is admitted: "+id)
		if state.entities.is_empty(): return
		var entity: Dictionary = state.entities[0]
		var rewards: Array[Dictionary] = []
		var hp: float = entity.hp
		sim._hit_entity(state,entity,hp,"blade_slash",events,rewards)
		sim._hit_entity(state,entity,hp,"blade_slash",events,rewards)
		t.check(rewards.size() == 1,"LOOT duplicate lethal hit produces one boss reward: "+id)
		sim._remove_dead(state)
		for reward in rewards: sim._claim_boss_reward(state,reward,events)
		sim._update_loot(state,events)
		if not _drain_offers(t,sim,state,events): return
		var chest: Dictionary = Loot.find_chest(state,Loot.chest_id(state.run_id,"boss",id))
		t.check(not chest.is_empty() and state.stats.minibosses_defeated == i+1 and state.tactical_seals == i+1,"LOOT one source/stat/seal per authored boss: "+id)
	state.active_tick = 97200
	state.survival_tick = 97200
	sim._update_loot(state,events)
	if not _drain_offers(t,sim,state,events): return
	t.check(state.loot.chests.size() == 10,"LOOT all five field plus five actual boss sources exist once")
	for i in range(5):
		var field: Dictionary = Loot.find_chest(state,Loot.chest_id(state.run_id,"field",str(Loot.FIELD_TICKS[i])))
		t.check(not field.is_empty() and field.reward == ("gold" if i%2 == 0 else "skill"),"LOOT exact field source/reward: "+str(i))
	t.check(Loot.validate(state),"LOOT complete ten-source evidence validates")
	var restored: Dictionary = sim.restore(JSON.parse_string(JSON.stringify(state,"",true,true)))
	t.check(restored.get("ok",false),"LOOT all-source cold restore accepts arranged valid state")
	if restored.get("ok",false):
		var saved: String = JSON.stringify(restored.state.loot,"",true,true)
		sim._update_loot(restored.state,events)
		t.check(restored.state.loot.chests.size() == 10 and JSON.stringify(restored.state.loot,"",true,true) == saved,"LOOT same tick after restore cannot regenerate sources")
func _pending_and_claimed(t) -> void:
	var sim = Core.new()
	var state := _new(sim)
	state.active_tick = 10800
	state.survival_tick = 10800
	sim._add_loot(state,Loot.field_spec(0),Vector2.ZERO)
	state.loot.next_retry_tick = 10860
	var pending: Dictionary = sim.restore(JSON.parse_string(JSON.stringify(state,"",true,true)))
	t.check(pending.get("ok",false),"LOOT pending chest and retry deadline cold restore")
	if not pending.get("ok",false): return
	state = pending.state
	var events: Array[Dictionary] = []
	sim._update_loot(state,events)
	t.check(state.loot.chests[0].status == "pending" and state.loot.next_retry_tick == 10860,"LOOT restore cannot bypass retry deadline")
	state.loot.chests[0].status = "placed"
	Loot.set_position(state,state.loot.chests[0],Vector2(state.player.position[0],state.player.position[1]))
	var placed: Dictionary = sim.restore(JSON.parse_string(JSON.stringify(state,"",true,true)))
	t.check(placed.get("ok",false),"LOOT placed before-pickup cold restore")
	if not placed.get("ok",false): return
	state = placed.state
	sim._update_loot(state,events)
	var claimed: Dictionary = sim.restore(JSON.parse_string(JSON.stringify(state,"",true,true)))
	t.check(claimed.get("ok",false),"LOOT claimed after-pickup cold restore")
	if not claimed.get("ok",false): return
	state = claimed.state
	sim._update_loot(state,events)
	t.check(state.loot.gold == 5 and state.loot.chests[0].status == "claimed","LOOT cold resume never repays claimed chest")
	var forged := state.duplicate(true)
	forged.loot.chests.append(forged.loot.chests[0].duplicate(true))
	t.check(not sim.restore(forged).get("ok",false),"LOOT duplicate source rejected by real restore")
	forged = state.duplicate(true)
	forged.loot.gold = 10
	t.check(not sim.restore(forged).get("ok",false),"LOOT gold without matching source rejected by real restore")
func _replay_new(t) -> void:
	var a = Core.new()
	var b = Core.new()
	var first := _new(a)
	var second := _new(b)
	first.active_tick = 10798
	first.survival_tick = 10798
	second.active_tick = 10798
	second.survival_tick = 10798
	for i in range(5):
		var ea: Array[Dictionary] = F.step(a,first,Vector2.RIGHT)
		var eb: Array[Dictionary] = F.step(b,second,Vector2.RIGHT)
		t.check(ea == eb and first == second,"LOOT same seed/input exact repeat at field boundary "+str(i))
		if i == 2:
			var restored: Dictionary = b.restore(JSON.parse_string(JSON.stringify(second,"",true,true)))
			t.check(restored.get("ok",false),"LOOT replay midway cold restore")
			if restored.get("ok",false): second = restored.state

func _retry_budget(t) -> void:
	# Controlled geometry rejection tests scheduling bounds, not real walkability.
	var sim = BlockedPlacement.new()
	var state := _new(sim)
	state.active_tick = 97200
	state.survival_tick = 97200
	for boss in Loot.BOSS_IDS: sim._add_loot(state,Loot.boss_spec(boss),Vector2.ZERO)
	var events: Array[Dictionary] = []
	sim._update_loot(state,events)
	t.check(state.loot.chests.size() == 10 and sim.attempts == 16,"LOOT ten pending sources share sixteen placement candidates")
	var ids: Array = state.loot.chests.map(func(chest): return chest.id)
	state.active_tick += 59
	sim._update_loot(state,events)
	t.check(sim.attempts == 16,"LOOT fifty-nine active ticks cannot retry")
	state.active_tick += 1
	sim._update_loot(state,events)
	t.check(sim.attempts == 32 and state.loot.chests.map(func(chest): return chest.id) == ids,"LOOT sixtieth tick retries bounded candidates without replacing IDs")
	for chest in state.loot.chests: t.check(chest.status == "pending","LOOT failed placement preserves each pending source")

func _field_boundaries(t) -> void:
	for index in range(5):
		var sim = BlockedPlacement.new()
		var state := _new(sim)
		state.active_tick = Loot.FIELD_TICKS[index]-1
		state.survival_tick = state.active_tick
		var events: Array[Dictionary] = []
		sim._update_loot(state,events)
		t.check(state.loot.chests.size() == index,"LOOT field not created before exact boundary "+str(index))
		state.active_tick += 1
		state.survival_tick += 1
		sim._update_loot(state,events)
		t.check(state.loot.chests.size() == index+1,"LOOT field created on exact boundary "+str(index))
		var state_before := JSON.stringify(state,"",true,true)
		sim.set_pause(state,"user",true)
		var paused := JSON.stringify(state,"",true,true)
		F.step(sim,state,Vector2.RIGHT)
		t.check(JSON.stringify(state,"",true,true) == paused,"LOOT pause cannot advance source schedule "+str(index))
		sim.set_pause(state,"user",false)
		t.check(JSON.stringify(state,"",true,true) == state_before,"LOOT pause/unpause preserves source ledger "+str(index))

func _drain_offers(t, sim, state: Dictionary, events: Array[Dictionary]) -> bool:
	# Mirror the normal tick's activation boundary after direct unit calls.
	if not sim._activate_next_offer(state,events):
		t.check(false,"LOOT all-source fixture activates pending offers")
		return false
	for i in range(10):
		if state.upgrade_offer.is_empty(): return true
		var offer: Dictionary = state.upgrade_offer.duplicate(true)
		var selected: Dictionary = sim.choose_upgrade(state,offer.offer_id,offer.selected_option_id)
		t.check(selected.get("ok",false),"LOOT all-source fixture resolves incidental reachable chest")
		if not selected.get("ok",false): return false
	t.check(state.upgrade_offer.is_empty(),"LOOT all-source fixture remains bounded")
	return state.upgrade_offer.is_empty()

func _queued_chain(t) -> void:
	var sim = Core.new()
	var state := _new(sim)
	state.active_tick = 75600
	state.survival_tick = 75600
	for i in range(4):
		sim._add_loot(state,Loot.field_spec(i),Vector2(state.player.position[0],state.player.position[1]))
		if i%2 == 1: state.loot.chests[i].status = "placed"
	state.loot.next_retry_tick = 75660
	var events: Array[Dictionary] = []
	sim._update_loot(state,events)
	t.check(state.pending_offers.size() == 2,"LOOT two simultaneous skill pickups enter stable FIFO")
	t.check(sim._activate_next_offer(state,events),"LOOT first queued chest materializes")
	var first: Dictionary = state.upgrade_offer.duplicate(true)
	var waiting: Dictionary = state.pending_offers[0].duplicate(true) if not state.pending_offers.is_empty() else {}
	t.check(not first.is_empty() and not waiting.is_empty(),"LOOT active and pending chest descriptors coexist")
	if first.is_empty() or waiting.is_empty(): return
	var restored: Dictionary = sim.restore(JSON.parse_string(JSON.stringify(state,"",true,true)))
	t.check(restored.get("ok",false),"LOOT active plus queued chest cold restore")
	if not restored.get("ok",false): return
	state = restored.state
	t.check(state.upgrade_offer == first and state.pending_offers[0] == waiting,"LOOT cold restore preserves active options and pending descriptor")
	var result: Dictionary = sim.choose_upgrade(state,first.offer_id,first.selected_option_id)
	t.check(result.get("ok",false) and state.upgrade_offer.get("offer_id","") == waiting.offer_id,"LOOT first ACK promotes the exact next chest")
	if not result.get("ok",false): return
	t.check(state.loot.chests[1].status == "claimed" and state.loot.chests[3].status == "queued","LOOT FIFO promotion preserves each source status")
	var after: Dictionary = sim.restore(JSON.parse_string(JSON.stringify(state,"",true,true)))
	t.check(after.get("ok",false),"LOOT claimed plus active source cold restore")
