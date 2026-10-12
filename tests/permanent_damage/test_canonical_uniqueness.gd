extends RefCounted
const Core = preload("res://game/core/run_simulation.gd")
const Current = preload("res://tests/core/current_combat_provider.gd")
const F = preload("res://tests/core/new_current_regression_fixture.gd")
const A = preload("res://tests/core/test_rebuild_attack_events.gd")
const Catalog = preload("res://game/progression/upgrade_catalog.gd")
const Resolver = preload("res://game/combat/evolved_attack_resolver.gd")
func run(t) -> void:
	# A legal custom tuning with near-adjacent modifier values proves that
	# normalization rejects ambiguity instead of picking its first match.
	var passives: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/passives.json"))
	passives.items.damage.increment = 0.000000001
	var catalog := Catalog.new(null,passives)
	t.check(catalog.validate().is_empty(),"tiny positive modifier is legal authored catalog tuning")
	var sim := Core.new(Current.new())
	var state := A.evolved_state(sim,F.chapter(),"evo_crossfire")
	state.rules.permanent_damage_bonus = 0.05
	state.passives.damage = 1
	var resolver := Resolver.new(catalog)
	var proposal := resolver.reserve(state,"wall_cannon",Vector2(60,0),Vector2.RIGHT,state.run_id+":attack:1")
	t.check(proposal.get("ok",false),"ambiguous-tuning fixture uses an actual reserved cast")
	if not proposal.get("ok",false): return
	state.attack_seq = 1
	state.player_attack_instances = proposal.records
	t.check(resolver.validate_records(state),"valid cast retains existing tolerance-based validation")
	var before := state.duplicate(true)
	t.check(not resolver.canonicalize_damage(state) and state == before,"distinct near-matches cannot mutate pending stages or pick an arbitrary damage")
	var config: Dictionary = F.run_config()
	config.permanent_upgrades = {"permanent_might":1}
	state = sim.new_run(F.chapter(),42,config)
	state.equipment = {"wall_cannon":1}
	state.passives = {"damage":1}
	sim._catalog = catalog
	sim._evolved = resolver
	F.step(sim,state,Vector2.ZERO,[F.spawn("ambiguous-projectile",[120,0],"brute")])
	t.check(state.projectiles.size() == 1,"ambiguous-tuning projectile is actually launched")
	if state.projectiles.is_empty(): return
	var canonical: Array[float] = []
	t.check(sim._projectile_valid(state,state.projectiles[0]),"ordinary shape and past-modifier validator accepts the known valid projectile")
	t.check(not sim._projectile_valid(state,state.projectiles[0],canonical) and canonical.size() > 1,"projectile normalization refuses multiple distinct historical near-matches")
