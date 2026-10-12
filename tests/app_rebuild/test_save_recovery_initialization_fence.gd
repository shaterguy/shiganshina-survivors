extends RefCounted
const Probe = preload("res://tests/app_rebuild/test_save_recovery_guarded_initialization.gd")
const Core = preload("res://game/core/run_simulation.gd")
const Recovery = preload("res://tests/app_rebuild/test_save_recovery_ui.gd")
func run(t) -> void:
	_test_late_authority(t,"game_save.json")
	_test_late_authority(t,"game_save.json.bak")
func _test_late_authority(t,authority_name: String) -> void:
	var validator = Core.new()
	var target: Dictionary = Probe.new()._legacy(validator)
	var foreign: Dictionary = Probe.new()._legacy(validator)
	var seeded: Dictionary = foreign.store.initialize_game(foreign.observed,"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
	t.check(seeded.get("ok",false),"final-source race uses a real valid competing authority")
	var foreign_source: String = FileAccess.get_file_as_string(foreign.directory.path_join("game_save.json"))
	var flags := {"armed":false,"inserted":false}
	target.store._fault_injector = func(stage):
		if stage == "replace": flags.armed = true
		if stage == "read_file" and flags.armed and not flags.inserted:
			flags.inserted = true
			Recovery.new()._write(target.directory.path_join(authority_name),foreign_source)
		return OK
	var result: Dictionary = target.store.initialize_game(target.observed,Probe.CAREER)
	if authority_name.ends_with(".bak"):
		t.check(not FileAccess.file_exists(target.directory.path_join("game_save.json")),"late competing backup cannot authorize creation of a new primary")
	target.store._fault_injector = Callable()
	var after: String = FileAccess.get_file_as_string(target.directory.path_join(authority_name))
	print("REVIEW final_initialization_fence ",JSON.stringify({"authority_name":authority_name,"inserted":flags.inserted,"ok":result.get("ok"),"error_code":result.get("error_code"),"foreign_retained":after==foreign_source,"adopted_career":result.get("game_save",{}).get("career_id")}))
	t.check(flags.inserted,"probe inserts authority during final legacy-source verification")
	t.check(not result.get("ok",false) and after == foreign_source,"final initial source guard must not reopen primary-authority overwrite after writer's last primary fence")

	if authority_name.ends_with(".bak"):
		t.check(not FileAccess.file_exists(target.directory.path_join("game_save.json")),"late competing backup cannot authorize creation of a new primary")
	target.store._fault_injector = Callable()
