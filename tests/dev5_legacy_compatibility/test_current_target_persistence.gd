extends RefCounted
const S = preload("res://tests/app_city_controller/controller_city_support.gd")
const F = preload("res://tests/dev5_legacy_compatibility/legacy_fixture.gd")
const CURRENT_TARGETS := ["evo_wing_cut","evo_crossfire","evo_storm_chain","evo_inferno_zone","evo_whirlwind","evo_sky_lance","evo_echo_assault","evo_wing_squad"]
func run(t) -> void:
	for id in CURRENT_TARGETS: _roundtrip_target(t,id)
	_unknown_target(t)
func _roundtrip_target(t, id: String) -> void:
	var fixture := S.make(t)
	if fixture.is_empty(): return
	var app = fixture.app
	var selection := {"doctrine_id":"doctrine_standard","target_evolution_id":id,"supply_item_id":""}
	var revision: int = app.game_save.store_revision
	app.apply_loadout(selection,int(app.supply_view().view_revision))
	t.check(app.game_save.store_revision == revision+1 and app.profile.loadout == selection,"real Controller persists selected current target: "+id)
	var saved: Dictionary = app.save_store.read_game()
	t.check(saved.get("ok",false) and saved.game_save.profile.loadout == selection,"real Store reads selected target without profile rejection: "+id)
	var accepted: bool = saved.get("ok",false) and saved.game_save.profile.loadout == selection
	app.free()
	if not accepted: return
	var cold := S.make(t,fixture.directory)
	if cold.is_empty(): return
	app = cold.app
	t.check(app._startup_view.is_empty() and app.profile.loadout == selection,"cold Controller retains selected target: "+id)
	app.start_run(77)
	t.check(not app.state.is_empty() and app.state.run_config.target_evolution_id == id,"real new-run Core receives selected target: "+id)
	if not app.state.is_empty():
		var checkpoint: Dictionary = app.save_store.read_game()
		t.check(checkpoint.get("ok",false) and checkpoint.game_save.checkpoint.run_config.target_evolution_id == id,"target remains valid in committed active checkpoint: "+id)
	app.free()
func _unknown_target(t) -> void:
	var fixture := S.make(t)
	if fixture.is_empty(): return
	var app = fixture.app
	var before := F.bytes(fixture.directory)
	var authority: Dictionary = app.game_save.duplicate(true)
	app.apply_loadout({"doctrine_id":"doctrine_standard","target_evolution_id":"evo_unknown","supply_item_id":""},int(app.supply_view().view_revision))
	t.check(app.game_save == authority and F.bytes(fixture.directory) == before,"unknown target cannot mutate Controller authority or save bytes")
	var poison := authority.duplicate(true)
	poison.profile.loadout.target_evolution_id = "evo_unknown"
	t.check(not app.save_store._contracts.validate_and_normalize(poison).get("ok",false),"current profile catalog rejects arbitrary future target IDs")
	app.free()
