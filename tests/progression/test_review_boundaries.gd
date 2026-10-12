extends RefCounted
# Independent review reproductions, fixed at the public C1 boundary.
const Fixture = preload("res://tests/progression/progression_test_fixture.gd")
const Upgrades = preload("res://game/progression/upgrade_catalog.gd")
const Offers = preload("res://game/progression/growth_offer_service.gd")
const Views = preload("res://game/progression/progression_view.gd")
func run(t) -> void:
	var equipment := Fixture.read("res://data/equipment.json")
	var passives := Fixture.read("res://data/passives.json")
	var bad := equipment.duplicate(true)
	bad.items.blade_slash.damage = -1
	var invalid = Upgrades.new(bad,passives)
	t.check(not invalid.validate().is_empty() and invalid.weapon_stats(Fixture.state(),"blade_slash",1).is_empty(),"invalid base catalog cannot produce a weapon stat record")
	bad = passives.duplicate(true)
	bad.items.damage.increment = -1
	invalid = Upgrades.new(equipment,bad)
	var state := Fixture.state()
	state.passives = {"damage":2}
	t.check(not invalid.validate().is_empty() and invalid.stat(state,"damage_multiplier",1.0) == 1.0,"invalid passive catalog returns neutral caller base rather than forged multiplier")
	t.check(invalid.stat(state,"damage_multiplier",NAN) == 0.0,"invalid nonfinite neutral base cannot escape stat boundary")
	var catalog = Upgrades.new()
	var builder := Views.new(catalog)
	state = _offered(catalog)
	var foreign := RefCounted.new()
	foreign.set_meta("amount",1)
	state.upgrade_offer.foreign = foreign
	var view := builder.build(state)
	t.check(view.is_empty(),"unsafe Object offer metadata is rejected, never aliased through view")
	t.check(foreign.get_meta("amount") == 1,"unsafe metadata rejection leaves original object unchanged")
	state = _offered(catalog)
	state.upgrade_offer.options[0].extra = NAN
	t.check(builder.build(state).is_empty(),"nonfinite option metadata is rejected before projection")
	state = _offered(catalog)
	state.run_config.target_evolution_id = {"bad":true}
	t.check(builder.build(state).is_empty(),"malformed target type returns empty without script errors")
	state = _offered(catalog)
	state.run_config = []
	t.check(builder.build(state).is_empty(),"nonobject run_config returns empty")
	state = _offered(catalog)
	state.rules.base_hp = {"bad":true}
	t.check(builder.build(state).is_empty(),"invalid stat base field cannot enter card calculation")
	state = _offered(catalog)
	state.upgrade_offer.foreign = "untrusted_safe_metadata"
	state.upgrade_offer.options[0].foreign = [1,2,3]
	view = builder.build(state)
	t.check(not view.is_empty() and not view.active_offer.has("foreign") and not view.active_offer.options[0].has("foreign"),"view explicitly projects allowed fields instead of carrying arbitrary metadata")
	state = _offered(catalog)
	state.entities = []
	state.drops = []
	for index in range(1000):
		state.entities.append({"id":str(index)})
		state.drops.append({"id":str(index)})
	t.check(not builder.build(state).is_empty(),"fragment validation never imposes catalog64 array cap on full RunState")
	var option: Dictionary = state.upgrade_offer.options[0]
	var malformed := option.duplicate(true)
	malformed.foreign = foreign
	t.check(catalog.decorate_option(state,malformed).is_empty(),"direct decoration rejects an Object before copying")
	state.run_config.target_evolution_id = false
	t.check(catalog.decorate_option(state,option).is_empty(),"direct decoration validates target type without relying on view caller")
	var offers := Offers.new(catalog)
	state = Fixture.state()
	state.rules.base_hp = {"bad":true}
	var rejected: Dictionary = offers.materialize(state,Fixture.descriptor())
	t.check(rejected.get("ok",true) == false and rejected.get("error_code") == "invalid_core_state","materializer rejects invalid presentation stat base before adding empty choices")
	state = Fixture.state()
	state.run_config.foreign = foreign
	rejected = offers.materialize(state,Fixture.descriptor())
	t.check(rejected.get("ok",true) == false and rejected.get("error_code") == "invalid_core_state","materializer rejects unsafe config before choice decoration")
func _offered(catalog) -> Dictionary:
	var state := Fixture.state()
	state.upgrade_offer = Offers.new(catalog).materialize(state,Fixture.descriptor()).offer
	return state
