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
			var trace_before_checks: int = checks
			var trace_before_failures: int = failures.size()
			var trace_started_usec: int = Time.get_ticks_usec()
			print("TEST_FILE_BEGIN "+JSON.stringify({"path":path.path_join(file),"suite":suite,"checks_before":trace_before_checks,"failures_before":trace_before_failures}))
			var script = load(path.path_join(file))
			check(script != null and script.can_instantiate(), "test script loads: " + file)
			if script != null and script.can_instantiate():
				var test = script.new()
				await test.run(self)
			print("TEST_FILE_END "+JSON.stringify({"path":path.path_join(file),"suite":suite,"phase":"body_returned","script_loaded":script != null,"checks_delta":checks-trace_before_checks,"body_checks":maxi(0,checks-trace_before_checks-1),"failures_delta":failures.size()-trace_before_failures,"elapsed_usec":Time.get_ticks_usec()-trace_started_usec}))
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
	print("TEST_RUN_RESULT "+JSON.stringify({"requested_suites_csv":",".join(OS.get_cmdline_user_args()),"checks":checks,"failures":failures.size(),"phase":"normal_tail_completed"}))
	print("RESULT checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
