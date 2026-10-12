extends SceneTree
var checks := 0
var failures: Array[String] = []
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		print("FAIL: "+message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	for path in ["res://tests/core/test_live_grabber.gd","res://tests/core/test_live_grabber_lifecycle.gd","res://tests/core/test_live_grabber_admission.gd","res://tests/core_world/test_live_grabber_transaction.gd"]:
		if not FileAccess.file_exists(path): continue
		var script = load(path)
		check(script != null and script.can_instantiate(),"loads "+path)
		if script != null and script.can_instantiate(): script.new().run(self)
	print("RESULT checks=%d failures=%d" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
