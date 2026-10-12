extends RefCounted
const RASTER_PATH = "res://game/presentation/armored/armored_raster.gd"
const FIXTURE = preload("res://tests/armored_raster/alpha_fixture.gd")
func run(t) -> void:
	var script = load(RASTER_PATH)
	if script == null or not script.can_instantiate(): return
	var path = FIXTURE.PATH
	var parked = path + ".test-preserved"
	var owner = script.new()
	t.root.add_child(owner)
	var reg = FIXTURE.new().registration()
	# Only our new test PNG is moved reversibly; its normal .import remap and
	# imported .ctex remain. This is not an export or native scene execution.
	var moved = DirAccess.rename_absolute(path, parked)
	t.check(moved == OK, "remap fixture raw PNG safely parked")
	if moved != OK: owner.free(); return
	var raw_missing = not FileAccess.file_exists(path)
	var imported_available = ResourceLoader.exists(path, "Texture2D")
	var result: Dictionary = owner.configure(reg)
	var restored = DirAccess.rename_absolute(parked, path)
	t.check(restored == OK, "remap fixture original PNG restored")
	t.check(raw_missing and imported_available, "normal imported resource available without raw PNG")
	t.check(result.ok, "configure follows normal imported remap without raw PNG dependency")
	if result.ok:
		var packet = FIXTURE.new().packet(reg)
		packet.commands[0].modulate = Color.WHITE
		t.check(owner.present_packet(packet) and absf(owner.alpha_local(Vector2(21.5, 21.5)) - 128.0 / 255.0) < .000001, "alpha cache reads the retained imported texture's exact source alpha")
	owner.free()
