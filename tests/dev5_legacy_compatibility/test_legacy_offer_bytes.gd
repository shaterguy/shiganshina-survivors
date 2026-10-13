extends RefCounted
# Historical finite fixture tests the persisted offer contract only. It does not
# stand in for the separate production dev4 world/fingerprint routing tests.
const Frozen = preload("res://tests/core/frozen_gameplay_fixture.gd")
const F = preload("res://tests/dev5_legacy_compatibility/legacy_fixture.gd")
const Current = preload("res://tests/core/new_current_regression_fixture.gd")
const ROOT := "res://tests/fixtures/evolution_supply_grabber/"
func run(t) -> void:
	_current_hostile_decoration(t)
	t.check(FileAccess.get_sha256(ROOT+"actual_evolution_ready.json") == "dbe95b3b085ee1fa3ba6a7ea24e6bab36d4d3217dfeff7a99c40e27852a1ef36","historical pending-offer fixture bytes remain unchanged")
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT+"actual_evolution_ready.json"))
	var before := source.duplicate(true)
	var sim = Frozen.simulation()
	var restored: Dictionary = sim.restore(source)
	t.check(restored.get("ok",false),"schema1 historical ready offer restores without rewriting decoration")
	t.check(source == before,"legacy offer restore does not edit the caller snapshot")
	if not restored.get("ok",false): return
	var raw: Dictionary = sim.snapshot(restored.state)
	t.check(F.same(raw.upgrade_offer,source.upgrade_offer),"legacy raw snapshot keeps the exact old persisted offer keys and values")
	var cold = Frozen.simulation()
	var json_restored: Dictionary = cold.restore(JSON.parse_string(JSON.stringify(raw,"",true,true)))
	t.check(json_restored.get("ok",false) and F.same(json_restored.state,raw),"legacy ready offer raw/JSON roundtrip stays at the same authority")
	if not json_restored.get("ok",false): return
	_store_roundtrip(t,source)
	var offer: String = raw.upgrade_offer.offer_id
	var selected: Dictionary = sim.choose_upgrade(raw,offer,"evolution:evo_wing_cut")
	var repeated: Dictionary = cold.choose_upgrade(json_restored.state,offer,"evolution:evo_wing_cut")
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT+"actual_evolution_chosen.json"))
	var expected_events: Array = JSON.parse_string(FileAccess.get_file_as_string(ROOT+"actual_evolution_events.json"))
	t.check(selected.get("ok",false) and repeated == selected and F.same(raw,json_restored.state),"warm and cold legacy pending offers choose identically")
	t.check(F.same(raw,expected) and F.same(selected.get("events",[]),expected_events),"legacy chosen state and events match the original frozen Core output")
	for kind in ["unexpected_key","changed_requirement","new_display_key","changed_effect","missing_old_key","missing_requirement_key"]:
		var poison := source.duplicate(true)
		var option: Dictionary = poison.upgrade_offer.options[0]
		match kind:
			"unexpected_key": option.grant_gold = 100
			"changed_requirement": option.requirements[0].required += 1
			"new_display_key": option.display_max_level = 999
			"changed_effect": option.effect_delta.unapproved_damage = 100
			"missing_old_key": option.erase("can_select")
			"missing_requirement_key": option.requirements[0].erase("required")
		var poison_before := poison.duplicate(true)
		t.check(not Frozen.simulation().restore(poison).get("ok",false) and poison == poison_before,"legacy strict decoration refuses "+kind+" without repairing bytes")
func _store_roundtrip(t, ready: Dictionary) -> void:
	var directory := "user://dev5_legacy_offer_%d_%d/saves" % [OS.get_process_id(),Time.get_ticks_usec()]
	var envelope: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT+"game_save_v2.json")).started
	envelope.checkpoint = ready.duplicate(true)
	F.write(directory.path_join("game_save.json"),JSON.stringify(envelope,"",true,true))
	var sim = Frozen.simulation()
	var store := F.Save.new(directory,Callable(sim,"restore"))
	var loaded: Dictionary = store.read_game()
	t.check(loaded.get("ok",false),"real Store opens the historical evolution selection window")
	if not loaded.get("ok",false): return
	var selected: Dictionary = loaded.game_save.duplicate(true)
	var result: Dictionary = sim.choose_upgrade(selected.checkpoint,selected.checkpoint.upgrade_offer.offer_id,"evolution:evo_wing_cut")
	t.check(result.get("ok",false),"restored historical window confirms the actual evolution choice")
	if not result.get("ok",false): return
	var committed: Dictionary = store.commit_game(selected,int(loaded.game_save.store_revision))
	t.check(committed.get("ok",false),"confirmed historical evolution is persisted by the real Store")
	if not committed.get("ok",false): return
	var cold = Frozen.simulation()
	var reloaded: Dictionary = F.Save.new(directory,Callable(cold,"restore")).read_game()
	t.check(reloaded.get("ok",false) and F.same(reloaded.game_save,committed.game_save) and reloaded.game_save.checkpoint.upgrade_offer.is_empty(),"restart preserves confirmed legacy evolution and never resurrects its old selection window")
func _current_hostile_decoration(t) -> void:
	var sim = Current.simulation(t)
	var state: Dictionary = Current.earn_offer(sim)
	t.check(not state.upgrade_offer.is_empty() and sim.restore(state).get("ok",false),"current schema2 comparison offer comes from real Core and restores")
	if state.upgrade_offer.is_empty(): return
	for kind in ["unexpected_key","changed_requirement","missing_display","changed_display"]:
		var poison := state.duplicate(true)
		var option: Dictionary = poison.upgrade_offer.options[0]
		match kind:
			"unexpected_key": option.grant_gold = 100
			"changed_requirement": option.requirements[0].required += 1
			"missing_display": option.erase("display_max_level")
			"changed_display": option.display_max_level = 999
		t.check(not sim.restore(poison).get("ok",false),"schema2 strict decoration still refuses "+kind)
