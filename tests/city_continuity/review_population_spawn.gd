extends SceneTree
var failures := 0
var checks := 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: "+message)
func _initialize() -> void:
	create_timer(30).timeout.connect(func(): quit(99))
	load("res://tests/city_continuity/test_population_spawn.gd").new().run(self)
	print("SPAWN_RESULT checks=%d failures=%d"%[checks,failures])
	quit(0 if failures == 0 else 1)
