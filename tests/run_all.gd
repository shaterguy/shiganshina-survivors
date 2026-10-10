extends SceneTree
var failures: Array[String] = []
var checks := 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error("FAIL: " + message)
func _initialize() -> void:
	call_deferred("run")
func scan(path: String, requested: PackedStringArray) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	for file in directory.get_files():
		if file.begins_with("test_") and file.ends_with(".gd"):
			var suite := path.get_file()
			if not requested.is_empty() and not suite in requested:
				continue
			var script = load(path.path_join(file))
			check(script != null and script.can_instantiate(), "test script loads: " + file)
			if script != null and script.can_instantiate():
				var test = script.new()
				await test.run(self)
	for folder in directory.get_directories():
		await scan(path.path_join(folder), requested)
func run() -> void:
	if "__runtime_error_fixture" in OS.get_cmdline_user_args():
		push_error("intentional runtime error fixture")
		quit(0)
		return
	await scan("res://tests", OS.get_cmdline_user_args())
	await process_frame
	await process_frame
	# Headless AudioServer releases stopped WAV playbacks on its mixer thread.
	# Allow a full fade/reap cycle after freeing scenes, before engine teardown.
	await create_timer(0.25).timeout
	check(checks > 0, "at least one test assertion ran")
	print("RESULT checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
