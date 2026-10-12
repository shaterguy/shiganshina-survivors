extends SceneTree
var failures: Array[String] = []
var checks := 0
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures.append(label); print("FAIL: "+label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	load("res://tests/world/test_new_city_definitions.gd").new().run(self)
	print("WORLD_IDENTITY_RESULT checks=%d failures=%d" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
