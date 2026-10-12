extends SceneTree
var checks := 0
var failures := 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	load("res://tests/city_continuity_review/test_rebase_precision.gd").new().run(self)
	load("res://tests/world/test_new_city_definitions.gd").new().run(self)
	print("NUMERIC_DEFINITION_RESULT checks=%d failures=%d"%[checks,failures])
	quit(0 if failures == 0 else 1)
