extends SceneTree
# Dedicated partial runner. Never represents full contracts/full product success.
var failures: Array[String] = []
var checks := 0
func check(value: bool,message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		print("FAIL: "+message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	print("R0 ONLY · NEW fixture contract agreement · Godot "+Engine.get_version_info().string)
	for path in ["res://tests/contracts/test_evolution_supply_fixtures.gd","res://tests/contracts/test_rebuild_content_identity.gd"]:
		var script = load(path)
		check(script != null and script.can_instantiate(),"R0 test script loads: "+path)
		if script != null and script.can_instantiate(): await script.new().run(self)
	check(checks > 2,"nonzero behavioral fixture assertions executed")
	print("R0 RESULT checks=%d failures=%d" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
