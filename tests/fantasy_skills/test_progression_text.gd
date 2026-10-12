extends RefCounted
const X = preload("res://tests/fantasy_skills/fantasy_fixture.gd")
const View = preload("res://game/progression/progression_view.gd")
const Supply = preload("res://game/economy/supply_service.gd")
const Fixture = preload("res://tests/fixtures/evolution_supply_fixture.gd")
func run(t) -> void:
	var sim = X.simulation()
	var state: Dictionary = X.state(sim)
	state.equipment = {"chain_lightning":3,"fire_zone":2}
	var view := View.new().build(state)
	t.check(view.owned.equipment[0].attack_summary.contains("5연결"),"owned chain summary exposes actual current link count")
	t.check(view.owned.equipment[1].attack_summary.contains("5회") and view.owned.equipment[1].attack_summary.contains("0.5"),"owned fire summary exposes actual pulse count and rhythm")
	state.equipment = {"chain_lightning":5,"fire_zone":5}
	state.evolutions = {"chain_lightning":"evo_storm_chain","fire_zone":"evo_inferno_zone"}
	view = View.new().build(state)
	t.check(view.owned.equipment[0].attack_summary.contains("12연결"),"ultimate chain summary exposes its actual stronger behavior")
	t.check(view.owned.equipment[1].attack_summary.contains("폭발"),"ultimate fire summary names the final eruption")
	var supply := Supply.new(sim.new_run)
	var options: Dictionary = supply._loadout_options(Fixture.new().game_save().profile,false)
	for target in options.targets:
		if target.id in ["evo_storm_chain","evo_inferno_zone"]:
			t.check(target.requirements.size() == 2 and target.requirements[1].kind == "equipment" and target.requirements[1].required == 3,"pre-run target clearly states its cross-equipment Lv3 requirement")
