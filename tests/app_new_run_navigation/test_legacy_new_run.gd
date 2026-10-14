extends RefCounted
const F = preload("res://tests/dev5_legacy_compatibility/legacy_fixture.gd")
const S = preload("res://tests/app_city_controller/controller_city_support.gd")
func run(t) -> void:
	var directory := F.install("new_run_menu")
	var arranged := F.enrich(directory)
	var fixture := S.make(t,directory)
	if fixture.is_empty(): return
	var app = fixture.app
	t.check(app._startup_view.is_empty() and not app.pending_checkpoint.is_empty(),"legacy fixture remains a resumable prior run at the common main: "+str(app._startup_view))
	if app.pending_checkpoint.is_empty(): app.free(); return
	var old_id: String = app.pending_checkpoint.run_id
	app.request_new_run(77,true,old_id)
	t.check(app.state.seed == 77 and app.state.rules.content_fingerprint != F.FINGERPRINT and app.simulation._catalog.evolutions._schema_version == 2,"confirmed legacy replacement settles with old rules and starts with current rules")
	for key in ["permanent_upgrades","cleared_chapter_ids","unlocked_character_ids","selected_character_id","owned_doctrine_ids"]:
		t.check(F.same(app.profile[key],arranged.profile[key]),"legacy replacement preserves permanent field "+key)
	t.check(app.state.character_id == "mikasa_01" and app.profile.supply_credits >= arranged.profile.supply_credits,"legacy replacement preserves selected unlocked character and earned currency")
	t.check(app.game_save.settlement_receipts.size() == arranged.settlement_receipts.size()+1,"legacy replacement creates exactly one ordinary settlement receipt")
	app.free()
