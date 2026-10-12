extends RefCounted
const Support = preload("res://tests/app/controller_test_support.gd")
func run(t) -> void:
	t.check(ResourceLoader.exists("res://tools/qa/recovery_ui_visual.tscn"),"disposable visual QA scene is available without changing main startup")
	if not ResourceLoader.exists("res://tools/qa/recovery_ui_visual.tscn"): return
	var scene = load("res://tools/qa/recovery_ui_visual.tscn")
	t.check(scene is PackedScene,"visual QA is an actual Godot scene")
	if not scene is PackedScene: return
	var fixture := Support.new().make(t)
	fixture.app.start_run(157)
	var source: Dictionary = fixture.app.game_save.duplicate(true)
	fixture.app.free()
	source.checkpoint.content_revision = "old-visual-qa"
	var file := FileAccess.open(fixture.directory.path_join("game_save.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(source,"",true,true))
	file.close()
	var app = scene.instantiate()
	# Automated test uses its own fresh fixture, never the editor QA fixture.
	app.qa_save_directory = fixture.directory
	t.root.add_child(app)
	app.set_process(false)
	app.world.set_process(false)
	t.check(app.save_store._directory == ProjectSettings.globalize_path(fixture.directory),"QA scene uses only its explicitly configured disposable save directory")
	t.check(app.ui._mode == "save_recovery" and app._startup_view.get("kind") == "checkpoint","QA scene reaches actual controller and validated recovery UI")
	t.check(app.ui._dev_notice.text.begins_with("QA 전용") and app.ui._notice.text.begins_with("QA 전용"),"QA fixture has a visible sentinel notice")
	t.check(app.game_save.is_empty() and app.state.is_empty(),"QA scene does not adopt its old checkpoint before explicit choice")
	t.check(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/main.tscn","QA leaves production main scene selection unchanged")
	app.free()
