extends RefCounted
const Fixture = preload("res://tests/core/core_fixture.gd")
func run(t) -> void:
	var sim = Fixture.simulation(t)
	if sim == null: return
	test_normalized_move(t, sim)
	test_first_thirty_seconds(t, sim)
	test_contact_invulnerability_and_death(t, sim)
	test_hazard_geometry(t, sim)
	test_equipment_attacks(t, sim)
	test_drop_merge_and_spatial_query(t, sim)
	test_drop_attraction(t, sim)
func test_normalized_move(t, sim) -> void:
	var straight: Dictionary = sim.new_run(Fixture.chapter(), 7)
	var diagonal: Dictionary = sim.new_run(Fixture.chapter(), 7)
	for index in 60:
		Fixture.step(sim,straight, Vector2.RIGHT, [])
		Fixture.step(sim,diagonal, Vector2(1,1), [])
	var straight_distance := Vector2(straight.player.position[0],straight.player.position[1]).length()
	var diagonal_distance := Vector2(diagonal.player.position[0],diagonal.player.position[1]).length()
	t.check(is_equal_approx(straight_distance, 100.0), "move is 100 world units per second")
	t.check(is_equal_approx(straight_distance, diagonal_distance), "test_normalized_move diagonal equals straight")
func test_first_thirty_seconds(t, sim) -> void:
	var state: Dictionary = sim.new_run(Fixture.chapter(), 9)
	var gained := 0
	var offers := 0
	for tick in 1800:
		var commands: Array[Dictionary] = []
		if tick % 90 == 0:
			commands.append(Fixture.spawn("first:%d" % tick, [state.player.position[0]+16.0,state.player.position[1]]))
		var events: Array = Fixture.step(sim,state, Vector2.RIGHT, commands)
		gained += Fixture.types(events, "xp_gained").size()
		offers += Fixture.types(events, "upgrade_opened").size()
		if not state.upgrade_offer.is_empty():
			var result: Dictionary = sim.choose_upgrade(state, state.upgrade_offer.offer_id, state.upgrade_offer.options[0].option_id)
			t.check(result.ok, "first loop upgrade accepted")
	t.check(state.active_tick == 1800 and state.player.position[0] > 2900.0, "first 30 seconds moves and advances")
	t.check(state.stats.kills > 0 and gained > 0 and offers > 0 and state.player.level > 1, "first 30 seconds autoattacks kills collects XP upgrades")
func test_contact_invulnerability_and_death(t, sim) -> void:
	var state: Dictionary = sim.new_run(Fixture.chapter(), 12)
	state.equipment.clear()
	var events: Array = Fixture.step(sim,state, Vector2.ZERO, [Fixture.spawn("contact", [0.0,0.0])])
	t.check(state.player.hp == 90.0 and Fixture.types(events,"damage").size() == 1, "contact causes one hit")
	for tick in 29: Fixture.step(sim,state, Vector2.ZERO, [])
	t.check(state.player.hp == 90.0, "invulnerability prevents repeated contact hits")
	Fixture.step(sim,state, Vector2.ZERO, [])
	t.check(state.player.hp == 80.0, "contact resumes at invulnerability deadline")
	state.player.hp = 1.0
	state.player.invulnerable_until = 0
	events = Fixture.step(sim,state, Vector2.ZERO, [])
	t.check(state.phase == "dead" and Fixture.types(events,"run_ended").size() == 1, "lethal damage ends run once")
	var frozen: Dictionary = sim.snapshot(state)
	t.check(Fixture.step(sim,state, Vector2.RIGHT, []).is_empty() and state == frozen, "dead run is immutable on step")
	var fresh: Dictionary = sim.new_run(Fixture.chapter(), 12)
	t.check(fresh.phase == "survival" and fresh.player.hp == 100.0 and fresh.stats.kills == 0, "restart creates clean run")
func test_hazard_geometry(t, sim) -> void:
	for shape in ["circle","sector","line"]:
		var state: Dictionary = sim.new_run(Fixture.chapter(), 1)
		state.player.position = [10.0,0.0]
		Fixture.step(sim,state, Vector2.ZERO, [Fixture.hazard("inside:"+shape, shape)])
		t.check(state.phase == "dead", "hazard hits inside " + shape)
		state = sim.new_run(Fixture.chapter(), 1)
		state.player.position = [-80.0,80.0]
		Fixture.step(sim,state, Vector2.ZERO, [Fixture.hazard("outside:"+shape, shape)])
		t.check(state.player.hp == 100.0, "hazard misses outside " + shape)
	var warned: Dictionary = sim.new_run(Fixture.chapter(), 1)
	var warning: Dictionary = Fixture.hazard("warning", "circle", {"warning_ticks":45})
	for tick in 45:
		Fixture.step(sim,warned, Vector2.ZERO, [warning] if tick == 0 else [])
	t.check(warned.player.hp == 100.0, "45 tick warning never damages early")
	Fixture.step(sim,warned, Vector2.ZERO, [])
	t.check(warned.phase == "dead", "warning resolves to damage at exact deadline")
func test_equipment_attacks(t, sim) -> void:
	for item_id in Fixture.EQUIPMENT_IDS:
		var state: Dictionary = sim.new_run(Fixture.chapter(), 15)
		state.equipment = {item_id:1}
		for tick in 100:
			Fixture.step(sim,state, Vector2.ZERO, [Fixture.spawn("target", [20.0,0.0])] if tick == 0 else [])
			if not state.upgrade_offer.is_empty(): sim.choose_upgrade(state,state.upgrade_offer.offer_id,state.upgrade_offer.options[0].option_id)
		t.check(state.stats.kills == 1 and state.stats.damage_dealt >= 8.0, "equipment attacks: " + item_id)
func test_drop_merge_and_spatial_query(t, sim) -> void:
	var state: Dictionary = sim.new_run(Fixture.chapter(), 4)
	state.player.position = [-100.0,0.0]
	var commands: Array[Dictionary] = []
	for index in 30: commands.append(Fixture.spawn("crowd:%d"%index,[0.0,0.0]))
	state.equipment = {"spin_slash":5}
	state.player.position = [-45.0,0.0]
	Fixture.step(sim,state, Vector2.ZERO, commands)
	t.check(state.stats.kills == 30 and state.drops.size() == 1 and state.drops[0].xp == 60, "same cell XP drops merge without lost value")
	state.player.position = [0.0,0.0]
	Fixture.step(sim,state, Vector2.ZERO, [])
	t.check(state.drops.is_empty() and state.player.level > 1, "merged drops collected using spatial query")
func test_drop_attraction(t, sim) -> void:
	var state: Dictionary = sim.new_run(Fixture.chapter(),77)
	state.drops = [{"id":"near","position":[70.0,0.0],"xp":2},{"id":"far","position":[300.0,0.0],"xp":2}]
	Fixture.step(sim,state,Vector2.ZERO,[])
	t.check(state.drops[0].position[0] < 70.0 and state.drops[1].position[0] == 300.0, "near XP attracts while distant drop stays")
	for tick in 20: Fixture.step(sim,state,Vector2.ZERO,[])
	t.check(state.drops.size() == 1 and state.player.xp == 2, "attracted XP reaches pickup radius")
