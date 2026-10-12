extends SceneTree
## Run against the staged project, not the complete source checkout.
var checks := 0
var failures := 0
func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL " + label)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var path := "res://assets/art/rig/armored_runtime_v1/registration.json"
	check(FileAccess.file_exists(path), "registration exists in exact staged closure")
	if not FileAccess.file_exists(path): finish(); return
	var registration = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(registration is Dictionary, "registration parses")
	if not registration is Dictionary: finish(); return
	if FileAccess.file_exists("res://tools/build/production_export_filter.gd"):
		var filter = load("res://tools/build/production_export_filter.gd")
		check(filter.has_method("validate_armored_bundle"), "export filter owns exact runtime bundle gate")
		if filter.has_method("validate_armored_bundle"):
			var gate: Dictionary = filter.validate_armored_bundle(registration, "development-validation")
			check(gate.ok and gate.paths.size() == 18, "exact registration and 17 runtime texture paths")
			check(not filter.validate_armored_bundle(registration, "final").ok, "pending armored final export remains denied")
			check(not filter.validate_armored_bundle(registration, "unknown").ok, "unknown mode denied")
			for bad_path in ["res://assets/art/rig/armored_runtime_v1/parts/../head.png", "res://assets/art/rig/armored_runtime_v1/parts/left_foot.png", "res://recovery/head.png"]:
				var bad: Dictionary = registration.duplicate(true)
				bad.parts.head.texture_path = bad_path
				check(not filter.validate_armored_bundle(bad, "development-validation").ok, "nonexact part path denied")
			var bad: Dictionary = registration.duplicate(true)
			bad.parts.head.packed_png_sha256 = "0".repeat(64)
			check(not filter.validate_armored_bundle(bad, "development-validation").ok, "corrupt digest denied")
			bad = registration.duplicate(true)
			bad.parts.erase("head")
			check(not filter.validate_armored_bundle(bad, "development-validation").ok, "missing registered part denied")
	else:
		check(OS.get_cmdline_user_args().has("--exported"), "filter omission is permitted only in the exported-resource check")
	check(registration.final_export_allowed == false and registration.native_gpu_verified == false, "pending review is unchanged")
	var pose = load("res://game/presentation/armored/armored_pose.gd").new()
	var prepared: Dictionary = pose.configure(registration)
	check(prepared.ok, "staged ArmoredPose.configure succeeds")
	var raster = load("res://game/presentation/armored/armored_raster.gd").new()
	root.add_child(raster)
	var configured: Dictionary = raster.configure(registration)
	check(configured.ok, "staged ArmoredRaster.configure succeeds: " + str(configured))
	if configured.ok:
		check(raster.debug_stats().source_decodes == 17, "all 17 imported textures actually decoded")
	raster.free()
	finish()
func finish() -> void:
	print("ARMORED_PACKAGE_PROBE checks=%d failures=%d native_gpu_verified=false" % [checks, failures])
	quit(0 if failures == 0 else 1)
