extends SceneTree
# Standalone harness; product runner is unchanged. --mode=counts|guards required.
# counts: instrumented helper copies, both baseline and candidate.
# guards: candidate product copy with no source instrumentation.
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func run() -> void:
	var output := ""
	var mode := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
		if argument.begins_with("--mode="): mode = argument.trim_prefix("--mode=")
	if not output.begins_with("user://") or FileAccess.file_exists(output) or not mode in ["counts","guards"]:
		push_error("READINESS_CONTRACTS requires --mode=counts|guards and fresh --output=user://...")
		quit(2)
		return
	var files: Array[String] = []
	if mode == "counts": files.append("test_readiness_counts.gd")
	else:
		files.append("test_readiness_guards.gd")
		files.append("test_readiness_fallbacks.gd")
	var bodies: Array = []
	for filename in files:
		var path := "res://tests/readiness_reuse/"+filename
		var script = load(path)
		var entry := {"file":filename,"body_returned":false,"checks_before":checks,"failures_before":failures.size(),"sha256":FileAccess.get_sha256(path)}
		if script == null:
			check(false,"READINESS_CONTRACTS failed to load "+filename)
		else:
			var test = script.new()
			await test.run(self)
			entry.body_returned = true
		entry.checks_after = checks
		entry.failures_after = failures.size()
		bodies.append(entry)
	var returned := true
	for body in bodies: returned = returned and body.body_returned
	var result := {"harness":"readiness-reuse-contracts-v1","mode":mode,"ok":returned and failures.is_empty(),"checks":checks,"failures":failures,"files":bodies,"sources":{}}
	for path in ["res://game/core/run_simulation.gd","res://game/core/streamed_run_world.gd","res://game/combat/enemy_world_query.gd","res://tests/readiness_reuse/readiness_support.gd","res://tests/readiness_reuse/qa_readiness_contracts.gd"]:
		result.sources[path] = FileAccess.get_sha256(path)
	var file := FileAccess.open(output,FileAccess.WRITE)
	if file == null: push_error("READINESS_CONTRACTS could not write private result"); quit(2); return
	file.store_string(JSON.stringify(result,"\t",true,true)); file.close()
	print("READINESS_CONTRACTS_RESULT ",JSON.stringify({"ok":result.ok,"mode":mode,"checks":checks,"failures":failures.size(),"bodies_returned":returned,"path":output,"sha256":FileAccess.get_sha256(output)},"",true,true))
	quit(0 if result.ok else 2)
