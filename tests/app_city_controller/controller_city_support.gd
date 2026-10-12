extends RefCounted
const Controller = preload("res://game/app/run_controller.gd")
const City = preload("res://game/director/streamed_chapter_provider.gd")
const Runtime = preload("res://game/app/prepared_city_runtime.gd")
const Disk = preload("res://game/persistence/world_delta_store.gd")
const Save = preload("res://game/persistence/game_save_store.gd")
static func make(t, directory: String = "") -> Dictionary:
	if directory.is_empty(): directory = "user://city_controller_%d_%d/saves"%[OS.get_process_id(),Time.get_ticks_usec()]
	var app = Controller.new()
	# Existing synchronous fault/authority tests retain their original boundary.
	# Default worker behavior is exercised separately by the integration probes.
	app.autosave_worker_enabled = false
	t.check(app.has_method("configure_city_runtime"),"controller exposes explicit pre-ready city dependency injection")
	if not app.has_method("configure_city_runtime"):
		app.free()
		return {}
	var provider := City.new()
	var disk := Disk.new(directory.path_join("world"))
	var runtime := Runtime.new(provider,disk)
	var configured: Dictionary = app.configure_city_runtime(provider,runtime,disk,directory)
	t.check(configured.get("ok",false),"city dependencies configure before ready")
	if not configured.get("ok",false):
		app.free()
		return {}
	t.root.add_child(app)
	app.set_process(false)
	app.world.set_process(false)
	return {"app":app,"provider":provider,"disk":disk,"runtime":runtime,"directory":directory}
