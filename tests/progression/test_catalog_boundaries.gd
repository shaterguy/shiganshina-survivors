extends RefCounted
const Fixture = preload("res://tests/progression/progression_test_fixture.gd")
const Upgrades = preload("res://game/progression/upgrade_catalog.gd")
const Evolution = preload("res://game/progression/evolution_catalog.gd")
const Offers = preload("res://game/progression/growth_offer_service.gd")
func run(t) -> void:
	var catalog = Upgrades.new()
	t.check(catalog.validate().is_empty(),"whole progression catalog validates")
	var state := Fixture.state()
	state.passives = {"damage":2,"fire_interval":3,"attack_range":2,"movement":1}
	var blade: Dictionary = catalog.weapon_stats(state,"blade_slash",5)
	t.check(is_equal_approx(blade.damage,46.8) and is_equal_approx(blade.range,96.72) and blade.cooldown_ticks == 27,"blade5 effective values:36*1.3,78*1.24,round36*.76")
	var dash: Dictionary = catalog.weapon_stats(state,"odm_dash",1)
	t.check(dash.has("width") and is_equal_approx(dash.get("width",0),34.72),"linear width scales once with attack range")
	t.check(blade.get("arc_degrees") == 150,"range never expands sector angle")
	var cannon: Dictionary = catalog.weapon_stats(state,"wall_cannon",5)
	t.check(cannon.get("projectile_speed") == 480 and is_equal_approx(cannon.get("splash_radius",0),49.6),"projectile splash scales once; velocity does not scale")
	t.check(is_equal_approx(catalog.stat(state,"move_multiplier",1.0),1.1),"movement1 yields independent1.1 multiplier")
	state.passives = {"max_health":1}
	state.rules.base_hp = 85
	t.check(catalog.stat(state,"max_hp",85) == 105,"mobile base85 plus health1 remains105")
	state.passives = {"fire_interval":5}
	t.check(catalog.weapon_stats(state,"blade_slash",5).cooldown_ticks == 22,"maximum fire interval levels use round21.6=22")
	var returned: Dictionary = catalog.equipment
	returned.blade_slash.damage = 999
	var returned_passives: Dictionary = catalog.passives
	returned_passives.movement.increment = 999
	var returned_curve: Dictionary = catalog.progression
	returned_curve.base_xp = 999
	t.check(catalog.equipment.blade_slash.damage == 12 and catalog.passives.movement.increment == 0.1 and catalog.progression.base_xp == 24,"public catalog/curve properties cannot mutate authority")
	t.check(Upgrades.xp_to_next(5,catalog.progression) == 56,"preserved progression curve24+4*8")
	var equipment := Fixture.read("res://data/equipment.json")
	var passives := Fixture.read("res://data/passives.json")
	for bad in [-1,NAN,INF,1.5,2147483648,"48"]:
		var data := equipment.duplicate(true)
		data.items.blade_slash.cooldown_ticks = bad
		t.check(not Upgrades.new(data,passives).validate().is_empty(),"invalid cooldown definition rejected: "+str(bad))
	for bad in [0,4,6,true,1.5]:
		var data := equipment.duplicate(true)
		data.items.blade_slash.max_level = bad
		t.check(not Upgrades.new(data,passives).validate().is_empty(),"weapon max level must remain5")
	var data := passives.duplicate(true)
	data.items.fire_interval.increment = -0.2
	t.check(not Upgrades.new(equipment,data).validate().is_empty(),"cooldown multiplier cannot reach zero at legal max level")
	data = passives.duplicate(true)
	data.progression.base_xp = 2147483648
	t.check(not Upgrades.new(equipment,data).validate().is_empty(),"progression counters reject overflow")
	data = equipment.duplicate(true)
	data.items.thunder_spear = data.items.blade_slash.duplicate(true)
	var invalid = Upgrades.new(data,passives)
	t.check(not invalid.validate().is_empty() and invalid.candidates(Fixture.state()).is_empty(),"unapproved era equipment fails closed")
	t.check(invalid.equipment.is_empty() and invalid.passives.is_empty() and invalid.progression.is_empty() and invalid.evolutions.ids().is_empty(),"invalid base catalog cannot expose plausible valid public rows or recipes")
	var deep := equipment.duplicate(true)
	deep.extra = {"a":{"b":{"c":{"d":{"e":{"f":{"g":{"h":{"i":0}}}}}}}}}
	t.check(not Upgrades.new(deep,passives).validate().is_empty(),"excessive definition nesting rejected before copy")
	data = equipment.duplicate(true)
	data.items.blade_slash.cooldown_ticks = 1
	data.items.blade_slash.cooldown_per_level = 0
	var passive_tuning := passives.duplicate(true)
	passive_tuning.items.fire_interval.increment = -0.19
	var tiny_cooldown = Upgrades.new(data,passive_tuning)
	state.passives = {"fire_interval":5}
	t.check(tiny_cooldown.validate().is_empty() and tiny_cooldown.weapon_stats(state,"blade_slash",5).cooldown_ticks == 1,"fractional effective cooldown rounds then clamps to minimum1")
	var held_evolution = catalog.evolutions
	var owner_id: int = catalog.get_instance_id()
	catalog = null
	t.check(not is_instance_id_valid(owner_id),"catalog can free while evolution handle survives (no strong cycle)")
	t.check(held_evolution.evaluate(Fixture.state(),"evo_wing_cut").is_empty(),"expired owner evaluation fails closed")
	for index in range(100):
		var temporary = Upgrades.new()
		var id: int = temporary.get_instance_id()
		temporary = null
		t.check(not is_instance_id_valid(id),"repeated catalog construction/free does not leak owners")
	_rng_draws(t)
func _rng_draws(t) -> void:
	var catalog = Fixture.legacy_catalog()
	var offers := Offers.new(catalog)
	var state := Fixture.state()
	var pool: Array = catalog.candidates(state)
	# Independent draw oracle: explicitly remove guaranteed movement, then PCG draw2.
	var expected := ["passive:movement"]
	for index in range(pool.size()):
		if pool[index].option_id == "passive:movement":
			pool.remove_at(index)
			break
	var rng := RandomNumberGenerator.new()
	rng.state = state.progression_rng_state.to_int()
	for index in range(2):
		var draw := rng.randi_range(0,pool.size()-1)
		expected.append(pool[draw].option_id)
		pool.remove_at(draw)
	var result: Dictionary = offers.materialize(state,Fixture.descriptor())
	t.check(Fixture.ids(result.offer.options) == expected and result.next_rng_state == str(rng.state),"even target is not a random draw; remaining choices advance exact RNG twice")
	for source in ["boss","level"]:
		var level := 2 if source == "boss" else 3
		state.player.level = level
		pool = catalog.candidates(state)
		expected = []
		rng.state = state.progression_rng_state.to_int()
		for index in range(3):
			var draw := rng.randi_range(0,pool.size()-1)
			expected.append(pool[draw].option_id)
			pool.remove_at(draw)
		result = offers.materialize(state,Fixture.descriptor(level,source))
		t.check(Fixture.ids(result.offer.options) == expected and result.next_rng_state == str(rng.state),"boss or odd level has no target-priority draw: "+source)
	state = Fixture.state()
	state.run_id = "unbound"
	var descriptor := Fixture.descriptor()
	descriptor.offer_id = "unbound:offer:1"
	t.check(not offers.materialize(state,descriptor).get("ok",false),"offer namespace must bind canonical career:serial run identity")
