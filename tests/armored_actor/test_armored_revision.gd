extends RefCounted
const S = preload("res://tests/armored_actor/armored_support.gd")
const Recovery = preload("res://tests/app_rebuild/test_save_recovery_ui.gd")
const CitySupport = preload("res://tests/app_city_controller/controller_city_support.gd")
func run(t) -> void:
	for revision in ["ch01.3-rebuild.2","ch01.3-rebuild.3-contact-candidate","ch01.3-rebuild.4-contact72-candidate","ch01.3-rebuild.5-preparation97"]:
		_revision(t,revision)
func _revision(t,revision: String) -> void:
	var f := S.make()
	t.check(f.state.content_revision == "ch01.3-rebuild.7-grabber-hand","A1 actual final actor semantics require deliberate candidate content revision")
	var old: Dictionary = f.state.duplicate(true)
	old.content_revision = revision
	t.check(f.core.restore(old).get("error_code") == "content_mismatch","A1 prior checkpoint "+revision+" is never silently reinterpreted as physical final")
	var fixture: Dictionary = Recovery.new()._incompatible_fixture(t,true)
	var source: Dictionary = fixture.save.duplicate(true)
	source.checkpoint.content_revision = revision
	var bytes := JSON.stringify(source,"",true,true)
	var file := FileAccess.open(fixture.directory.path_join("game_save.json"),FileAccess.WRITE)
	file.store_string(bytes); file.close()
	var current := CitySupport.make(t,fixture.directory)
	if current.is_empty(): return
	var app = current.app
	t.check(app.state.is_empty() and app._startup_view.get("kind") == "checkpoint" and app.ui.focused_semantic_id() == "recovery_keep","A1 prior authority defaults to explicit keep/new-run UI")
	t.check(FileAccess.get_file_as_string(fixture.directory.path_join("game_save.json")) == bytes,"A1 incompatible revision startup preserves exact source bytes")
	app.confirm_preserved_run_start(146)
	t.check(not app.state.is_empty() and app.state.content_revision == "ch01.3-rebuild.7-grabber-hand","A1 explicitly chosen preserved replacement starts current Core")
	if not app.state.is_empty():
		t.check(app.game_save.career_id == source.career_id and app.game_save.profile.settings == source.profile.settings and app.game_save.purchase_receipts == source.purchase_receipts and app.game_save.profile.supply_credits == source.profile.supply_credits,"A1 revision replacement preserves career/settings/purchases/credits")
		t.check(FileAccess.get_file_as_string(fixture.directory.path_join("archives").path_join(bytes.sha256_text()+".json")) == bytes,"A1 prior source checkpoint remains exact archived bytes")
	app.free()
