extends SceneTree
var checks := 0
var failures: Array[String] = []
var cases: Array[Dictionary] = []
var completed: Array[String] = []
var mode := ""
func _initialize() -> void:
	call_deferred("run")
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)
func run() -> void:
	var output := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
		if argument.begins_with("--mode="): mode = argument.trim_prefix("--mode=")
	if not output.begins_with("user://") or FileAccess.file_exists(output) or mode not in ["contracts","candidate","proof","scope-baseline","scope-candidate"]:
		push_error("VISIBILITY_DOMAIN requires --mode=contracts|candidate|proof|scope-baseline|scope-candidate and fresh --output=user://...")
		quit(2)
		return
	var files: Array[String] = []
	if mode in ["scope-baseline","scope-candidate"]: files.assign(["test_scope.gd"])
	elif mode == "proof": files.assign(["test_proof.gd"])
	else: files.assign(["test_geometry.gd","test_domains.gd","test_guards.gd","test_helper.gd"])
	var bodies: Array = []
	for filename in files:
		var path := "res://tests/visibility_domain/"+filename
		var script = load(path)
		var entry := {"file":filename,"body_returned":false,"checks_before":checks,"cases_before":cases.size(),"failures_before":failures.size(),"sha256":FileAccess.get_sha256(path)}
		if script == null or not script.can_instantiate(): check(false,"VISIBILITY_DOMAIN load/instantiate "+filename)
		else:
			var test = script.new()
			test.run(self)
			entry.body_returned = filename in completed
			check(entry.body_returned,"VISIBILITY_DOMAIN final completion sentinel: "+filename)
		entry.checks_after = checks
		entry.cases_after = cases.size()
		entry.failures_after = failures.size()
		bodies.append(entry)
	var expected_cases: int = 120 if mode == "scope-candidate" else (80 if mode == "scope-baseline" else (18 if mode == "proof" else 1934))
	check(cases.size() == expected_cases,"VISIBILITY_DOMAIN complete expected comparison matrix")
	check(completed == files,"VISIBILITY_DOMAIN all selected bodies return in exact order")
	var returned := true
	for body in bodies: returned = returned and body.body_returned
	var result := {"harness":"native-visibility-domain-focused-v1","source_commit":"ffd8bc90ced00e58d94547b55c52e4e18ded0eee","mode":mode,"ok":returned and failures.is_empty(),"checks":checks,"failures":failures,"files":bodies,"cases":cases,"completed":completed,"sources":{}}
	for path in ["res://game/world/streamed_navigation_view.gd","res://game/world/streamed_world.gd","res://game/world/cached_streamed_world.gd","res://game/world/city_navigation.gd","res://game/world/precise_city_navigation.gd","res://game/core/streamed_run_world.gd","res://game/world/world_address.gd","res://tests/world/fixtures/city_fixture.gd","res://tests/visibility_domain/qa_visibility_domain.gd","res://tests/visibility_domain/support.gd","res://tests/visibility_domain/oracle_old_view.gd","res://tests/visibility_domain/fixture_generator.gd","res://tests/visibility_domain/custom_stream.gd","res://tests/visibility_domain/custom_cached.gd","res://tests/visibility_domain/custom_view.gd","res://tests/visibility_domain/full_navigation.gd","res://tests/visibility_domain/test_proof.gd","res://tests/visibility_domain/test_scope.gd","res://tests/visibility_domain/oracle_city_navigation.gd","res://tests/visibility_domain/oracle_precise_city_navigation.gd","res://tests/visibility_domain/scope_custom_navigation.gd","res://tests/visibility_domain/scope_custom_oracle_navigation.gd"]:
		result.sources[path] = FileAccess.get_sha256(path)
	var file := FileAccess.open(output,FileAccess.WRITE)
	if file == null: push_error("VISIBILITY_DOMAIN could not write private result"); quit(2); return
	file.store_string(JSON.stringify(result,"\t",true,true))
	file.close()
	print("VISIBILITY_DOMAIN_RESULT ",JSON.stringify({"ok":result.ok,"mode":mode,"checks":checks,"cases":cases.size(),"failures":failures.size(),"bodies_returned":returned,"path":output,"sha256":FileAccess.get_sha256(output)},"",true,true))
	quit(0 if result.ok else 2)
