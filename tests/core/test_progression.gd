extends RefCounted
const Fixture = preload("res://tests/core/core_fixture.gd")
func run(t) -> void:
	var sim = Fixture.simulation(t)
	if sim == null: return
	test_upgrade_offer(t, sim)
	test_simultaneous_rewards(t, sim)
	test_max_items_fallback(t, sim)
	test_data_driven_xp_curve(t, sim)
	test_passive_effects(t, sim)
func earn_offer(sim, seed := 21) -> Dictionary:
	var state: Dictionary = sim.new_run(Fixture.chapter(), seed)
	Fixture.step(sim,state, Vector2.ZERO, [Fixture.spawn("xp1",[8.0,0.0]),Fixture.spawn("xp2",[9.0,0.0]),Fixture.spawn("xp3",[10.0,0.0])])
	return state
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
	state = sim.new_run(Fixture.chapter(), 21)
	state.equipment = {"blade_slash":1,"spin_slash":1,"odm_dash":1,"reentry_combo":1}
	state.drops = [{"id":"drop","position":[0.0,0.0],"xp":6}]
	Fixture.step(sim,state,Vector2.ZERO,[])
	for option in state.upgrade_offer.options:
		t.check(option.kind != "equipment" or state.equipment.has(option.item_id), "equipment slot cap 4 filters new families")
	var equipment: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/equipment.json"))
	var passives: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/passives.json"))
	t.check(equipment.items.size() == 6 and passives.items.size() == 8, "six equipment families and eight passive axes")
func test_simultaneous_rewards(t, sim) -> void:
	var state: Dictionary = sim.new_run(Fixture.chapter(), 11)
	state.player.hp = 50.0
	var events: Array = Fixture.step(sim,state,Vector2.ZERO,[Fixture.boss("ch01_b05",[10.0,0.0])])
	t.check(state.stats.minibosses_defeated == 1 and state.player.hp > 50.0, "boss death records kill and heals")
	t.check(Fixture.types(events,"boss_defeated").size() == 1, "boss reward emitted once")
	t.check(state.upgrade_offer.source == "levelup" and state.pending_offers.size() == 1 and state.pending_offers[0].source == "boss", "test_simultaneous_rewards levelup then boss FIFO")
	var queued_id: String = state.pending_offers[0].offer_id
	var result: Dictionary = sim.choose_upgrade(state,state.upgrade_offer.offer_id,state.upgrade_offer.options[0].option_id)
	t.check(result.ok and state.upgrade_offer.offer_id == queued_id and "upgrade" in state.pause_reasons, "queued boss offer survives first choice")
	sim.choose_upgrade(state,state.upgrade_offer.offer_id,state.upgrade_offer.options[0].option_id)
	t.check(state.upgrade_offer.is_empty() and not "upgrade" in state.pause_reasons, "last offer releases upgrade reason")
	events = Fixture.step(sim,state,Vector2.ZERO,[Fixture.boss("ch01_b05",[10.0,0.0])])
	t.check(Fixture.types(events,"boss_defeated").is_empty() and state.reward_ids_claimed.count("boss:ch01_b05") == 1, "boss reward idempotent")
func test_max_items_fallback(t, sim) -> void:
	var state: Dictionary = sim.new_run(Fixture.chapter(), 7)
	state.equipment = {"blade_slash":5,"spin_slash":5,"odm_dash":5,"reentry_combo":5}
	state.passives = {"damage":5,"fire_interval":5,"movement":5,"max_health":5,"recovery":5,"pickup_radius":5,"attack_range":5,"armor":5}
	state.player.hp = 1.0
	state.drops = [{"id":"drop","position":[0.0,0.0],"xp":6}]
	Fixture.step(sim,state,Vector2.ZERO,[])
	t.check(state.upgrade_offer.options.size() == 3, "maxed items still provide 3 meaningful alternatives")
	for option in state.upgrade_offer.options: t.check(option.kind == "recovery", "maxed equipment/passives excluded")
	sim.choose_upgrade(state,state.upgrade_offer.offer_id,state.upgrade_offer.options[0].option_id)
	t.check(state.player.hp > 1.0, "fallback recovery applies")

func test_data_driven_xp_curve(t, sim) -> void:
	var chapter: Dictionary = Fixture.chapter()
	chapter.erase("progression")
	var state: Dictionary = sim.new_run(chapter,5)
	state.drops = [{"id":"small","position":[0,0],"xp":6}]
	Fixture.step(sim,state,Vector2.ZERO,[])
	t.check(state.player.level == 1 and state.upgrade_offer.is_empty(),"default first XP threshold avoids premature offer")
	state.drops = [{"id":"enough","position":[0,0],"xp":12}]
	Fixture.step(sim,state,Vector2.ZERO,[])
	t.check(state.player.level == 1 and state.upgrade_offer.is_empty(),"18 XP still below default first threshold")
	state.drops = [{"id":"threshold","position":[0,0],"xp":6}]
	Fixture.step(sim,state,Vector2.ZERO,[])
	t.check(state.player.level == 2 and not state.upgrade_offer.is_empty(),"default first threshold 24 XP opens offer")
func test_passive_effects(t, sim) -> void:
	var state: Dictionary = sim.new_run(Fixture.chapter(),18)
	state.passives = {"movement":1,"recovery":1,"armor":1,"pickup_radius":1}
	state.equipment.clear()
	state.player.hp = 50.0
	state.drops = [{"id":"passive_drop","position":[40.0,0.0],"xp":2}]
	Fixture.step(sim,state,Vector2.RIGHT,[])
	t.check(is_equal_approx(state.player.velocity[0],110.0),"movement passive changes speed")
	t.check(state.player.hp > 50.0 and state.player.xp == 2,"recovery and pickup passives act")
	state.player.position = [0.0,0.0]
	var before_hp: float = state.player.hp
	Fixture.step(sim,state,Vector2.ZERO,[Fixture.spawn("armor_target",[0,0])])
	t.check(is_equal_approx(state.player.hp,before_hp-8.0+0.5/60.0),"armor reduces incoming damage")
	state = sim.new_run(Fixture.chapter(),18)
	state.passives = {"damage":1,"fire_interval":1,"attack_range":1}
	state.rules.enemy_catalog.slow_titan.hp = 1000.0
	Fixture.step(sim,state,Vector2.ZERO,[Fixture.spawn("buff_target",[68,0])])
	t.check(is_equal_approx(state.stats.damage_dealt,13.8) and state.player.attack_ready_ticks.blade_slash == 45,"damage interval and range passives alter attack")
	state = sim.new_run(Fixture.chapter(),18)
	state.upgrade_offer = {"offer_id":"hp_test","selected_option_id":"passive:max_health:1","options":[{"option_id":"passive:max_health:1","item_id":"max_health","kind":"passive","level":0,"next_level":1},{"option_id":"passive:damage:1","item_id":"damage","kind":"passive","level":0,"next_level":1},{"option_id":"passive:movement:1","item_id":"movement","kind":"passive","level":0,"next_level":1}]}
	state.player.hp = 50.0
	sim.choose_upgrade(state,"hp_test","passive:max_health:1")
	t.check(state.player.max_hp == 120.0 and state.player.hp == 70.0,"max health upgrade raises cap and heals")
