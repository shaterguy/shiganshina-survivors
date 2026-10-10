extends RefCounted
const Fixture = preload("res://tests/progression/progression_test_fixture.gd")
const Upgrades = preload("res://game/progression/upgrade_catalog.gd")
func run(t) -> void:
	var catalog = Upgrades.new()
	var state := Fixture.maxed()
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var options: Array = catalog.options(state,rng)
	t.check(options.is_empty(),"maxed four-slot build has no legal upgrades and no fake healing cards")
	state.passives.armor = 4
	options = catalog.options(state,rng)
	t.check(options.size() == 1 and options[0].get("option_id") == "passive:armor","one legal upgrade stays one semantic option")
	state.equipment.blade_slash = 4
	options = catalog.options(state,rng)
	t.check(options.size() == 2,"two legal upgrades stay two without filler")
	t.check(catalog.has_method("candidates"),"single legal candidate authority exists")
	if not catalog.has_method("candidates"): return
	_slot_limits(t,catalog)
	var path := "res://game/progression/growth_offer_service.gd"
	t.check(ResourceLoader.exists(path),"growth materializer is present")
	if not ResourceLoader.exists(path): return
	var service = load(path).new(catalog)
	_priority(t,service)
	_replay_and_invalid(t,service)
func _slot_limits(t,catalog) -> void:
	var state := Fixture.maxed()
	state.equipment.blade_slash = 4
	state.passives.armor = 4
	var before := state.duplicate(true)
	var candidates: Array = catalog.candidates(state)
	t.check(Fixture.ids(candidates) == ["equipment:blade_slash","passive:armor"],"full slots allow owned upgrades only in sorted order")
	t.check(state == before,"candidate read does not mutate state")
	for bad in [0,6,1.5,NAN,INF,2147483648]:
		state = Fixture.state()
		state.equipment.blade_slash = bad
		t.check(catalog.candidates(state).is_empty(),"invalid owned level rejects candidate input: "+str(bad))
	state = Fixture.state()
	state.equipment.thunder_spear = 1
	t.check(catalog.candidates(state).is_empty(),"unknown equipment cannot enter candidate state")
	state = Fixture.state()
	state.rules.allowed_equipment_ids = ["blade_slash"]
	for option in catalog.candidates(state):
		t.check(option.kind != "equipment" or option.item_id == "blade_slash","candidate obeys allowed equipment IDs")
	state = Fixture.state()
	var normal: Dictionary = catalog.candidates(state)[0]
	normal.level = 1.5
	t.check(not catalog.option_valid(state,normal),"fractional option levels rejected")
	normal = {"option_id":"recovery:60","item_id":"field_recovery_60","kind":"recovery","level":0,"next_level":1,"amount":60}
	t.check(not catalog.option_valid(state,normal),"legacy healing option is not a legal new option")
func _priority(t,service) -> void:
	var state := Fixture.state()
	var result: Dictionary = service.materialize(state,Fixture.descriptor())
	t.check(result.get("ok",false),"valid growth descriptor materializes")
	if not result.get("ok",false): return
	t.check(result.offer.options[0].option_id == "passive:movement","even level prioritizes missing passive")
	state.equipment = {"wall_cannon":1}
	state.passives = {"movement":1}
	result = service.materialize(state,Fixture.descriptor())
	t.check(result.offer.options[0].option_id == "equipment:blade_slash","target missing weapon follows missing passive")
	state.equipment = {"blade_slash":4}
	result = service.materialize(state,Fixture.descriptor())
	t.check(result.offer.options[0].option_id == "equipment:blade_slash","target weapon reaches Lv5 before passive reaches Lv3")
	state.equipment.blade_slash = 5
	result = service.materialize(state,Fixture.descriptor())
	t.check(result.offer.options[0].option_id == "passive:movement","target passive reaches Lv3 after weapon max")
	state.equipment.wall_cannon = 5
	state.passives = {"movement":3,"fire_interval":3}
	state.tactical_seals = 2
	for source in ["level","boss"]:
		result = service.materialize(state,Fixture.descriptor(2,source))
		t.check(Fixture.ids(result.offer.options).slice(0,2) == ["evolution:evo_crossfire","evolution:evo_wing_cut"],"both ready evolutions precede ordinary growth for "+source)
		t.check(result.offer.options.size() == 3,"ready evolution offer fills remaining legal option")
	state = Fixture.maxed()
	result = service.materialize(state,Fixture.descriptor())
	t.check(result.ok and result.offer.is_empty() and result.next_rng_state == state.progression_rng_state,"zero legal choices returns empty without random draw")
	state.passives.armor = 4
	result = service.materialize(state,Fixture.descriptor())
	t.check(result.ok and result.offer.options.size() == 1,"one materialized option remains one")
	state.equipment.blade_slash = 4
	result = service.materialize(state,Fixture.descriptor())
	t.check(result.ok and result.offer.options.size() == 2,"two materialized options remain two")
func _replay_and_invalid(t,service) -> void:
	var state := Fixture.state()
	var before := state.duplicate(true)
	var descriptor := Fixture.descriptor()
	var descriptor_before := descriptor.duplicate(true)
	var first: Dictionary = service.materialize(state,descriptor)
	t.check(first.get("ok",false),"repeatable materialization returns an offer")
	if not first.get("ok",false): return
	for count in range(20):
		t.check(service.materialize(state,descriptor) == first,"same input and RNG reproduce exact offer and successor state")
	t.check(state == before and descriptor == descriptor_before,"materialization never mutates inputs or combat RNG")
	var identities: Array = Fixture.ids(first.offer.options)
	var unique := {}
	for id in identities: unique[id] = true
	t.check(identities.size() == unique.size(),"offer identities are unique")
	var reverse := state.duplicate(true)
	reverse.rules.allowed_equipment_ids.reverse()
	t.check(service.materialize(reverse,descriptor) == first,"allow-list insertion order never changes random results")
	for source in ["levelup","",1]:
		var bad := descriptor.duplicate(true)
		bad.source = source
		t.check(not service.materialize(state,bad).get("ok",false),"invalid source rejected: "+str(source))
	for bad_id in ["other:offer:1",Fixture.RUN_ID+":offer:0",Fixture.RUN_ID+":offer:2",Fixture.RUN_ID+":offer:01"]:
		var bad := descriptor.duplicate(true)
		bad.offer_id = bad_id
		t.check(not service.materialize(state,bad).get("ok",false),"foreign/future/noncanonical offer identity rejected")
	var bad := descriptor.duplicate(true)
	bad.options = []
	t.check(not service.materialize(state,bad).get("ok",false),"pending descriptor must not store materialized options")
	for level in [0,1.5,NAN,2147483648]:
		bad = descriptor.duplicate(true)
		bad.level_ordinal = level
		t.check(not service.materialize(state,bad).get("ok",false),"descriptor level counter bounded and integral")
	for text in ["","01","-0","+1","1.2"," 1","9223372036854775808"]:
		var invalid := state.duplicate(true)
		invalid.progression_rng_state = text
		t.check(not service.materialize(invalid,descriptor).get("ok",false),"invalid decimal RNG state rejected: "+text)
	for phase in ["dead","won","abandoned"]:
		var terminal := state.duplicate(true)
		terminal.phase = phase
		t.check(not service.materialize(terminal,descriptor).get("ok",false),"terminal phase cannot materialize choices: "+phase)
	var active := state.duplicate(true)
	active.upgrade_offer = first.offer.duplicate(true)
	t.check(not service.materialize(active,descriptor).get("ok",false),"active offer cannot be rerolled through materializer")
