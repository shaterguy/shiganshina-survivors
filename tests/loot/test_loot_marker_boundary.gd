extends RefCounted
const Loot = preload("res://game/loot/loot_rules.gd")
const Growth = preload("res://game/progression/growth_offer_service.gd")
const F = preload("res://tests/core/core_fixture.gd")
func run(t) -> void:
	t.check(not Loot.enabled({}),"LOOT marker missing config is safely disabled")
	for config in [null,[],"bad"]:
		t.check(not Loot.enabled({"run_config":config}),"LOOT marker rejects non-dictionary config without member access")
	for marker in ["1","2",true,[],{},null,0,3,1.5,NAN,INF]:
		t.check(not Loot.enabled({"run_config":{"loot_rules_version":marker}}),"LOOT marker rejects malformed type/value without comparison error")
	for marker in [1,1.0,2,2.0]:
		t.check(Loot.enabled({"run_config":{"loot_rules_version":marker}}),"LOOT marker accepts integer and precise JSON form")
	var sim = F.simulation(t)
	if sim == null: return
	var state: Dictionary = sim.new_run(F.v2_chapter(),42,F.run_config())
	state.offer_seq = 1
	state.run_config.loot_rules_version = "1"
	var before: Dictionary = state.duplicate(true)
	for source in ["level","boss","chest"]:
		var descriptor := {"offer_id":state.run_id+":offer:1","source":source,"level_ordinal":1}
		if source == "chest": descriptor.chest_id = state.run_id+":chest:boss:ch01_b05"
		var result: Dictionary = Growth.new(sim._catalog).materialize(state,descriptor)
		t.check(result.get("ok") == false and not result.get("error_code","").is_empty(),"LOOT Growth refuses malformed marker rather than legacy fallback: "+source)
		t.check(state == before,"LOOT malformed marker leaves state/RNG unchanged: "+source)
	var config: Dictionary = F.run_config()
	config.loot_rules_version = 1
	var valid: Dictionary = sim.new_run(F.v2_chapter(),42,config)
	for field in ["source","offer_id","chest_id"]:
		for value in [1,null,[]]:
			var hostile: Dictionary = valid.duplicate(true)
			hostile.offer_seq = 1
			var descriptor := {"offer_id":hostile.run_id+":offer:1","source":"chest","level_ordinal":1,"chest_id":hostile.run_id+":chest:boss:ch01_b05"}
			descriptor[field] = value
			hostile.pending_offers = [descriptor]
			var saved: Dictionary = hostile.duplicate(true)
			t.check(not Loot.validate(hostile),"LOOT cold validator rejects malformed offer field: "+field)
			t.check(sim.restore(hostile).get("ok") == false and hostile == saved,"LOOT Core rejects malformed descriptor without mutation: "+field)
	for malformed in [null,[],{"chests":null},{"chests":[null,1,{}, {"id":1}]}]:
		var hostile: Dictionary = valid.duplicate(true)
		hostile.offer_seq = 1
		hostile.loot = malformed
		var descriptor := {"offer_id":hostile.run_id+":offer:1","source":"chest","level_ordinal":1,"chest_id":hostile.run_id+":chest:boss:ch01_b05"}
		var saved: Dictionary = hostile.duplicate(true)
		t.check(Growth.new(sim._catalog).materialize(hostile,descriptor).get("ok") == false and hostile == saved,"LOOT Growth safely rejects malformed chest lookup container")
	for field in ["status","reward","offer_id"]:
		for value in [1,null,[]]:
			var hostile: Dictionary = valid.duplicate(true)
			hostile.offer_seq = 1
			var id: String = hostile.run_id+":chest:boss:ch01_b05"
			var chest := {"id":id,"status":"queued","reward":"skill","offer_id":hostile.run_id+":offer:1"}
			chest[field] = value
			hostile.loot.chests = [chest]
			var descriptor := {"offer_id":hostile.run_id+":offer:1","source":"chest","level_ordinal":1,"chest_id":id}
			var saved: Dictionary = hostile.duplicate(true)
			t.check(Growth.new(sim._catalog).materialize(hostile,descriptor).get("ok") == false and hostile == saved,"LOOT Growth rejects malformed chest field: "+field)
	for new_rules in [false,true]:
		var selected_config: Dictionary = F.run_config()
		if new_rules: selected_config.loot_rules_version = 1
		var base: Dictionary = sim.new_run(F.v2_chapter(),42,selected_config)
		base.player.level = 2
		base.offer_seq = 1
		var descriptor := {"offer_id":base.run_id+":offer:1","source":"level","level_ordinal":2}
		var materialized: Dictionary = Growth.new(sim._catalog).materialize(base,descriptor)
		t.check(materialized.get("ok",false),"LOOT boundary fixture materializes normal level offer")
		if not materialized.get("ok",false): continue
		base.upgrade_offer = materialized.offer.duplicate(true)
		base.pause_reasons = ["upgrade"]
		base.progression_rng_state = materialized.next_rng_state
		t.check(sim.restore(base).get("ok",false),"LOOT boundary active-offer base is fully restorable")
		for value in [1,null,[]]:
			var hostile: Dictionary = base.duplicate(true)
			hostile.upgrade_offer.source = value
			var saved: Dictionary = hostile.duplicate(true)
			t.check(sim.restore(hostile).get("ok") == false and hostile == saved,"LOOT Core rejects malformed active offer source in old/new rules")
	var queued: Dictionary = sim.new_run(F.v2_chapter(),42,config)
	queued.active_tick = 18000
	queued.survival_tick = 18000
	queued.boss_ids_fired.append("ch01_b05")
	queued.stats.kills = 1
	var events: Array[Dictionary] = []
	sim._claim_boss_reward(queued,{"boss_id":"ch01_b05","entity_id":"marker-boundary","position":queued.player.position.duplicate()},events)
	sim._update_loot(queued,events)
	t.check(sim._activate_next_offer(queued,events),"LOOT boundary activates actual chest offer")
	var linked_id: String = Loot.chest_id(queued.run_id,"boss","ch01_b05")
	t.check(queued.upgrade_offer.get("source") == "chest" and queued.upgrade_offer.get("chest_id") == linked_id and Loot.find_chest(queued,linked_id).get("status") == "queued","LOOT boundary base contains the actual queued chest link")
	var checked: Dictionary = sim.restore(queued)
	t.check(checked.get("ok",false),"LOOT boundary queued chest base is fully restorable")
	if not checked.get("ok",false): return
	for field in ["source","offer_id","chest_id"]:
		for value in [1,null,[]]:
			var hostile: Dictionary = queued.duplicate(true)
			hostile.upgrade_offer[field] = value
			var saved: Dictionary = hostile.duplicate(true)
			t.check(not Loot.validate(hostile),"LOOT cold linked chest rejects malformed active field: "+field)
			t.check(sim.restore(hostile).get("ok") == false and hostile == saved,"LOOT Core linked chest rejects malformed field without mutation: "+field)
