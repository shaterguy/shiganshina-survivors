extends SceneTree
var checks := 0
var failures: Array[String] = []
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error("FAIL: "+label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	for name in OS.get_cmdline_user_args():
		await load(name if name.begins_with("res://") else "res://tests/app_city_controller/"+name+".gd").new().run(self)
	await process_frame
	await process_frame
	await create_timer(0.25).timeout
	print("RESULT checks=%d failures=%d"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
