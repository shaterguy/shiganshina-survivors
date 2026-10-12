@tool
extends EditorPlugin
## Template-free resource ZIP probe. This is not an Android APK or visual review.
func _enter_tree() -> void:
	call_deferred("run")
func run() -> void:
	while EditorInterface.get_resource_filesystem().is_scanning():
		await get_tree().create_timer(0.1).timeout
	var args := OS.get_cmdline_user_args()
	if args.size() != 1: get_tree().quit(2); return
	var registration = JSON.parse_string(FileAccess.get_file_as_string("res://assets/art/rig/armored_runtime_v1/registration.json"))
	var filter = load("res://tools/build/production_export_filter.gd").new()
	var gate: Dictionary = filter.validate_armored_bundle(registration, "development-validation")
	if not gate.ok: printerr(gate); get_tree().quit(3); return
	var plugin := EditorPlugin.new()
	plugin.add_export_plugin(filter)
	var platform := EditorExportPlatformLinuxBSD.new()
	var preset := platform.create_preset()
	var result := platform.export_zip(preset, true, args[0])
	plugin.remove_export_plugin(filter)
	plugin.free()
	print("ARMORED_RESOURCE_ZIP code=%d" % result)
	await get_tree().create_timer(1.0).timeout
	get_tree().quit(0 if result == OK else 1)
