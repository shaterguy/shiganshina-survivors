extends RefCounted
const Recovery = preload("res://tests/app_rebuild/test_save_recovery_ui.gd")
const Controller = preload("res://game/app/run_controller.gd")
const Core = preload("res://game/core/run_simulation.gd")
class DisappearingLegacyStore:
	extends "res://game/persistence/game_save_store.gd"
	func inspect_known_locations(root: Variant) -> Dictionary:
		var observed: Dictionary = super.inspect_known_locations(root)
		if observed.get("ok",false) and observed.locations[0].status == "supported_legacy":
			for name in ["profile.json","checkpoint.json"]:
				var path: String = _directory.path_join(name)
				if FileAccess.file_exists(path): assert(DirAccess.rename_absolute(path,path+".review-retained") == OK)
		return observed
func run(t) -> void:
	_test_legacy_read_retry(t)
	_test_legacy_disappears_after_inspection(t)
func _fixture() -> String:
	var directory: String = Recovery.new()._unique_directory("legacy_edge")
	var legacy := {"schema_version":1,"settings":{"deadzone":0.25,"audio_master":0.4,"screen_shake":0.2,"reduce_effects":true},"cleared_chapter_ids":["chapter_01_shiganshina"],"unlocked_character_ids":["garrison_01"],"best_runs":{}}
	Recovery.new()._write(directory.path_join("profile.json"),JSON.stringify(legacy))
	Recovery.new()._write(directory.path_join("checkpoint.json"),"old checkpoint retained")
	return directory
func _test_legacy_read_retry(t) -> void:
	var directory := _fixture()
	var fault := func(stage): return ERR_CANT_OPEN if stage == "read_file" else OK
	var app = Recovery.new()._restart_observed(t,directory,fault)
	t.check(app._startup_view.get("kind") == "retry","setup: initial legacy profile read failure offers retry")
	app.save_store._fault_injector = Callable()
	app.retry_save_recovery()
	print("REVIEW legacy_read_retry ",JSON.stringify({"kind":app._startup_view.get("kind"),"code":app._startup_view.get("error_code"),"adopted":not app.game_save.is_empty(),"migration_allowed":app._allow_legacy_migration}))
	t.check(not app.game_save.is_empty() and app._startup_view.is_empty(),"transient initial dev1 read error must permit explicit validated legacy migration retry")
	app.free()
func _test_legacy_disappears_after_inspection(t) -> void:
	var directory := _fixture()
	var app = Controller.new()
	var validator = Core.new()
	app.set_meta("review_validator",validator)
	app.save_store = DisappearingLegacyStore.new(directory,Callable(validator,"restore"))
	t.root.add_child(app)
	app.set_process(false)
	app.world.set_process(false)
	print("REVIEW legacy_disappears_after_inspection ",JSON.stringify({"kind":app._startup_view.get("kind"),"adopted":not app.game_save.is_empty(),"settings":app.profile.get("settings",{}),"primary_created":FileAccess.file_exists(directory.path_join("game_save.json"))}))
	t.check(not FileAccess.file_exists(directory.path_join("game_save.json")) and app.game_save.is_empty(),"observed dev1 source disappearing after inspection must not initialize default career")
	app.free()
