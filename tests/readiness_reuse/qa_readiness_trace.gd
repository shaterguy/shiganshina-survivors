extends SceneTree
# Standalone uninstrumented baseline/candidate oracle. No performance claim.
# Mount under tests/readiness_reuse. --output=user://<fresh name>.json is required.
# Use exact same fixture bytes/engine/seed for both trees and compare trace only.
const Support = preload("res://tests/readiness_reuse/readiness_support.gd")
const FIXED_TICKS := 24
var support := Support.new()
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
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
	if not output.begins_with("user://") or FileAccess.file_exists(output):
		push_error("READINESS_TRACE requires fresh private user:// output")
		quit(2)
		return
	var cases: Array = []
	for scenario in [{"label":"no_role","roles":[]},{"label":"one_role","roles":["grabber"]},{"label":"three_roles","roles":["grabber","quadruped","stone_thrower"]}]:
		var app = support.make(self,scenario.label,scenario.roles)
		if app == null: continue
		check(not support.has_property(app.simulation._streamed,"qa_readiness_calls"),"READINESS_TRACE rejects QA counter copy")
		var trace: Array = []
		var initial: String = support.digest(app.state)
		for index in FIXED_TICKS:
			var before: int = int(app.state.active_tick)
			var commands: Array[Dictionary] = []
			# Deterministic held input with movement reversals; Director is deliberately
			# not invoked. This is a bounded Core trace, not a natural encounter.
			var move := Vector2.RIGHT if index < 8 else (Vector2.LEFT if index < 16 else Vector2.ZERO)
			var events: Array[Dictionary] = app.simulation.step(app.state,move,commands)
			trace.append(support.row(app.simulation,app.state,events,index))
			check(app.simulation.step_status().get("ok",false) and int(app.state.active_tick) == before+1,"READINESS_TRACE each arranged ordinary Core tick commits")
			if not app.simulation.step_status().get("ok",false) or int(app.state.active_tick) != before+1: break
		check(trace.size() == FIXED_TICKS,"READINESS_TRACE complete fixed tick budget")
		cases.append({"scenario":scenario.label,"initial_state_sha256":initial,"trace":trace,"final_state_sha256":support.digest(app.state),"trace_sha256":support.digest(trace)})
		await support.dispose(self,app)
	var result := {"harness":"readiness-reuse-core-trace-v1","scope":"arranged 24-tick Core state/events/RNG equivalence; no timing, device or natural-duration claim","ok":failures.is_empty() and cases.size() == 3,"checks":checks,"failures":failures,"cases":cases,"cases_sha256":support.digest(cases),"sources":{}}
	for path in ["res://game/core/run_simulation.gd","res://game/core/streamed_run_world.gd","res://game/combat/enemy_world_query.gd","res://tests/readiness_reuse/readiness_support.gd","res://tests/readiness_reuse/qa_readiness_trace.gd"]:
		result.sources[path] = FileAccess.get_sha256(path)
	var file := FileAccess.open(output,FileAccess.WRITE)
	if file == null: push_error("READINESS_TRACE could not write private result"); quit(2); return
	file.store_string(JSON.stringify(result,"\t",true,true)); file.close()
	print("READINESS_TRACE_RESULT ",JSON.stringify({"ok":result.ok,"checks":checks,"failures":failures.size(),"cases_sha256":result.cases_sha256,"path":output,"sha256":FileAccess.get_sha256(output)},"",true,true))
	quit(0 if result.ok else 2)
