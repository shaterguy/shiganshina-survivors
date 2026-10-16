extends RefCounted
const F = preload("res://tests/core/core_fixture.gd")
const Loot = preload("res://game/loot/loot_rules.gd")
func _make(t,supply: String = "") -> Dictionary:
	var sim = F.simulation(t)
	var config: Dictionary = F.run_config(1,"doctrine_standard","evo_wing_cut",supply)
	config.loot_rules_version = 2
	var state: Dictionary = sim.new_run(F.v2_chapter(),42,config)
	state.active_tick = 10800;state.survival_tick = 10800
	var events: Array[Dictionary] = []
	sim._update_loot(state,events)
	var chest: Dictionary = state.loot.chests[0]
	chest.status = "placed"
	Loot.set_position(state,chest,Vector2(state.player.position[0],state.player.position[1]))
	sim._update_loot(state,events)
	t.check(state.loot.potions.size() == 1 and sim.restore(state).get("ok",false),"POTION order arranged placed fixture is cold admissible")
	return {"sim":sim,"state":state}
func run(t) -> void:
	var f := _make(t)
	var sim = f.sim
	var state: Dictionary = f.state
	state.player.hp -= 7.0
	sim.set_pause(state,"user",true)
	var paused: Dictionary = state.duplicate(true)
	F.step(sim,state,Vector2.ZERO)
	t.check(state == paused,"POTION actual paused step does not age or consume bottle")
	sim.set_pause(state,"user",false)
	F.step(sim,state,Vector2.ZERO)
	t.check(state.loot.potions[0].status == "claimed" and state.player.hp == state.player.max_hp,"POTION actual resumed step collects immediately")
	f = _make(t,"field_bandage");sim = f.sim;state = f.state
	state.player.hp = 1.0
	var events: Array[Dictionary] = F.step(sim,state,Vector2.ZERO)
	t.check(state.player.hp == 46.0 and state.supply_used,"POTION real tick heals20 then existing threshold bandage25")
	var kinds: Array = events.map(func(e): return e.type)
	t.check(kinds.has("potion_collected") and kinds.has("supply_used") and kinds.find("potion_collected") < kinds.find("supply_used"),"POTION actual event order precedes existing supply")
	f = _make(t,"field_bandage");sim = f.sim;state = f.state
	state.player.hp = 1.0
	var hazard: Dictionary = F.hazard("potion:lethal","circle",{"origin":state.player.position.duplicate(),"damage":40.0})
	events = F.step(sim,state,Vector2.ZERO,[hazard])
	t.check(state.phase == "dead" and not state.supply_used and state.loot.potions[0].healed_amount == 20.0,"POTION heal-before-lethal-damage does not revive or consume bandage after death")
	f = _make(t);sim = f.sim;state = f.state
	state.passives.recovery = 1
	state.player.hp -= 30.0
	events = F.step(sim,state,Vector2.ZERO)
	t.check(is_equal_approx(float(state.player.hp),float(state.player.max_hp)-10.0+0.5/60.0),"POTION tick preserves existing natural recovery after collection")
	f = _make(t);sim = f.sim;state = f.state
	state.passives.max_health = 1
	state.player.max_hp = sim._catalog.stat(state,"max_hp",float(state.rules.base_hp))
	state.player.hp = float(state.player.max_hp)-7.0
	t.check(sim.restore(state).get("ok",false),"POTION changed max-health fixture uses authored passive calculation")
	events = F.step(sim,state,Vector2.ZERO)
	t.check(state.player.hp == state.player.max_hp and state.loot.potions[0].healed_amount == 7.0,"POTION clamps against current authored maximum health")
	f = _make(t);sim = f.sim;state = f.state
	state.player.hp -= 7.0
	state.player_mobility = {"phase":"airborne"}
	var before: Dictionary = state.duplicate(true)
	events.clear();sim._collect_potions(state,events)
	t.check(state == before and events.is_empty(),"POTION private airborne guard leaves bottle and HP unchanged")
