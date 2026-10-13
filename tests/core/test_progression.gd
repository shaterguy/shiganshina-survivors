extends RefCounted
const Fixture = preload("res://tests/core/new_current_regression_fixture.gd")
const Catalog = preload("res://game/progression/upgrade_catalog.gd")
func run(t) -> void:
	var sim = Fixture.simulation(t)
	if sim == null: return
	test_upgrade_offer(t, sim)
	test_simultaneous_rewards(t, sim)
	test_max_items_fallback(t, sim)
	test_data_driven_xp_curve(t, sim)
	test_passive_effects(t, sim)
func earn_offer(sim, seed := 21) -> Dictionary:
	return Fixture.earn_offer(sim,seed)
func test_upgrade_offer(t, sim) -> void:
	var state: Dictionary = earn_offer(sim)
	t.check(state.player.level == 2 and state.upgrade_offer.options.size() == 3, "test_upgrade_offer 3 options on first level")
	t.check("upgrade" in state.pause_reasons, "upgrade pauses simulation")
	var ids: Array = []
	for option in state.upgrade_offer.options:
		ids.append(option.option_id)
		t.check(option.next_level > option.level and not option.item_id.is_empty(), "valid meaningful upgrade option")
	t.check(ids[0] != ids[1] and ids[1] != ids[2] and ids[0] != ids[2], "offer choices distinct")
	var original_offer: String = state.upgrade_offer.offer_id
	var option_id: String = state.upgrade_offer.options[1].option_id
	sim.set_offer_focus(state, option_id)
	t.check(state.upgrade_offer.selected_option_id == option_id, "semantic focus set")
	sim.set_offer_focus(state, "invalid")
	t.check(state.upgrade_offer.selected_option_id == option_id, "invalid focus ignored")
	var before: Dictionary = sim.snapshot(state)
	t.check(not sim.choose_upgrade(state,"invalid",option_id).ok and state == before, "invalid offer rejected without mutation")
	t.check(sim.choose_upgrade(state,original_offer,option_id).ok, "valid upgrade applied")
	before = sim.snapshot(state)
	t.check(not sim.choose_upgrade(state,original_offer,option_id).ok and state == before, "duplicate selected offer rejected")
	state = sim.new_run(Fixture.chapter(),21,Fixture.run_config())
	state.equipment = {"blade_slash":1,"spin_slash":1,"odm_dash":1,"reentry_combo":1}
	Fixture.drop_xp(sim,state,24)
	for option in state.upgrade_offer.options:
		t.check(option.kind != "equipment" or state.equipment.has(option.item_id), "equipment slot cap 4 filters new families")
	var equipment: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/equipment.json"))
	var passives: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/passives.json"))
	var current_families: Array = equipment.items.keys()
	var allowed_families: Array = Fixture.chapter().allowed_equipment_ids.duplicate()
	current_families.sort()
	allowed_families.sort()
	t.check(current_families == allowed_families and "chain_lightning" in current_families and "fire_zone" in current_families and passives.items.size() == 8, "current chapter exposes every authored equipment family and eight passive axes")
func test_simultaneous_rewards(t, sim) -> void:
	var state := Fixture.boss_reward_state(sim)
	t.check(sim.restore(state).ok,"arranged authored boss remaining health is a valid checkpoint")
	var events: Array = Fixture.step(sim,state,Vector2.ZERO)
	t.check(state.stats.minibosses_defeated == 1 and state.player.hp > 50.0, "boss death records kill and heals")
	t.check(Fixture.types(events,"boss_defeated").size() == 1, "boss reward emitted once")
	t.check(state.upgrade_offer.source == "level" and state.pending_offers.size() == 1 and state.pending_offers[0].source == "boss", "test_simultaneous_rewards level then boss FIFO")
	var queued_id: String = state.pending_offers[0].offer_id
	var result: Dictionary = sim.choose_upgrade(state,state.upgrade_offer.offer_id,state.upgrade_offer.options[0].option_id)
	t.check(result.ok and state.upgrade_offer.offer_id == queued_id and "upgrade" in state.pause_reasons, "queued boss offer survives first choice")
	sim.choose_upgrade(state,state.upgrade_offer.offer_id,state.upgrade_offer.options[0].option_id)
	t.check(state.upgrade_offer.is_empty() and not "upgrade" in state.pause_reasons, "last offer releases upgrade reason")
	events = Fixture.step(sim,state,Vector2.ZERO,[Fixture.boss("ch01_b05",[10.0,0.0])])
	t.check(Fixture.types(events,"boss_defeated").is_empty() and state.reward_ids_claimed.count("boss:ch01_b05") == 1, "boss reward idempotent")
func test_max_items_fallback(t, sim) -> void:
	var state: Dictionary = sim.new_run(Fixture.chapter(),7,Fixture.run_config())
	state.equipment = {"blade_slash":5,"spin_slash":5,"odm_dash":5,"reentry_combo":5}
	state.passives = {"damage":5,"fire_interval":5,"movement":5,"armor":5}
	# Internal base5 still has a legal final6 choice. A genuinely exhausted
	# four-slot build must have completed every owned attack's final stage.
	for id in sim._catalog.evolutions.ids():
		var recipe: Dictionary = sim._catalog.evolutions.definition(id)
		if state.equipment.has(recipe.base_item_id) and sim._catalog.evolutions.evaluate(state,id).get("can_evolve",false):
			state.evolutions[recipe.base_item_id] = id
	t.check(state.evolutions.size() == 4 and sim._catalog.candidates(state).is_empty(),"fallback fixture exhausts four final attack stages and every legal base/passive growth")
	state.player.hp = 1.0
	t.check(sim.restore(state).ok,"four-slot maxed arrangement is valid")
	Fixture.drop_xp(sim,state,24)
	# Current growth contract: no fabricated recovery choices. An empty legal
	# pool atomically claims the earned descriptor and heals ten percent.
	t.check(state.upgrade_offer.is_empty() and state.pending_offers.is_empty(), "maxed build consumes the empty-pool offer without a stuck choice")
	t.check(state.reward_ids_claimed == ["offer:"+state.run_id+":offer:1"] and not "upgrade" in state.pause_reasons, "maxed equipment/passives excluded and earned fallback claimed once")
	t.check(state.player.hp == 11.0 and sim.restore(state).ok, "fallback recovery heals ten percent and remains restorable")
func test_data_driven_xp_curve(t, sim) -> void:
	var state: Dictionary = sim.new_run(Fixture.chapter(),5,Fixture.run_config())
	t.check(state.rules.progression.base_xp == Catalog.new().progression.base_xp and state.rules.progression.xp_per_level == Catalog.new().progression.xp_per_level,"run pins the authored progression catalog")
	Fixture.drop_xp(sim,state,6,"small")
	t.check(state.player.level == 1 and state.upgrade_offer.is_empty(),"default first XP threshold avoids premature offer")
	Fixture.drop_xp(sim,state,12,"enough")
	t.check(state.player.level == 1 and state.upgrade_offer.is_empty(),"18 XP still below default first threshold")
	Fixture.drop_xp(sim,state,6,"threshold")
	t.check(state.player.level == 2 and not state.upgrade_offer.is_empty(),"default first threshold 24 XP opens offer")
func test_passive_effects(t, sim) -> void:
	var state: Dictionary = sim.new_run(Fixture.chapter(),18,Fixture.run_config())
	state.passives = {"movement":1,"recovery":1,"armor":1,"pickup_radius":1}
	state.equipment.clear()
	state.player.hp = 50.0
	state.drops = [{"id":"passive_drop","position":[40.0,0.0],"xp":2}]
	Fixture.step(sim,state,Vector2.RIGHT,[])
	t.check(is_equal_approx(state.player.velocity[0],165.0),"movement passive scales standard doctrine speed")
	t.check(state.player.hp > 50.0 and state.player.xp == 2,"recovery and pickup passives act")
	state.player.position = [0.0,0.0]
	var before_hp: float = state.player.hp
	Fixture.step(sim,state,Vector2.ZERO,[Fixture.spawn("armor_target",[0,0])])
	t.check(is_equal_approx(state.player.hp,before_hp-7.0+0.5/60.0),"armor reduces authored walker damage")
	state = sim.new_run(Fixture.chapter(),18,Fixture.run_config())
	state.passives = {"damage":1,"fire_interval":1,"attack_range":1}
	Fixture.step(sim,state,Vector2.ZERO,[Fixture.spawn("buff_target",[68,0])])
	t.check(is_equal_approx(state.stats.damage_dealt,13.8) and state.player.attack_ready_ticks.blade_slash == 45,"damage interval and range passives alter attack")
	# This tests an actually earned first health choice, not a seed21 RNG oracle.
	# The changed target material shifts the current random pool. Search only a
	# fixed small seed range using real XP/materialization; never insert an offer.
	var selected := ""
	for seed in range(1,65):
		state = sim.new_run(Fixture.chapter(),seed,Fixture.run_config())
		state.player.hp = 50.0
		Fixture.drop_xp(sim,state,24)
		for option in state.upgrade_offer.options:
			if option.item_id == "max_health": selected = option.option_id
		if not selected.is_empty():
			print("CURRENT_EARNED_HEALTH_SEED ",seed)
			break
	t.check(not selected.is_empty(),"real earned offer exposes max-health option")
	if selected.is_empty(): return
	t.check(state.player.level == 2 and state.player.xp == 0 and state.upgrade_offer.source == "level" and not state.passives.has("max_health") and sim.restore(state).get("ok",false),"bounded health search returns a valid first actually earned level offer")
	t.check(sim.choose_upgrade(state,state.upgrade_offer.offer_id,selected).ok,"earned max-health choice applies")
	t.check(state.player.max_hp == 120.0 and state.player.hp == 70.0,"max health upgrade raises cap and heals")
