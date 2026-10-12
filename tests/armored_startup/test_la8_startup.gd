extends RefCounted
const RASTER = preload("res://game/presentation/armored/armored_raster.gd")
const BASELINE = preload("res://tests/armored_startup/reference/baseline_raster.gd")
const COMPILER = preload("res://game/presentation/armored/armored_pose_packet.gd")
const FIXTURE = preload("res://tests/armored_raster/alpha_fixture.gd")

func digest(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	assert(ctx.start(HashingContext.HASH_SHA256) == OK)
	assert(ctx.update(bytes) == OK)
	return ctx.finish().hex_encode()

func run(t) -> void:
	var reg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/art/rig/armored_runtime_v1/registration.json"))
	var before: Dictionary = {}
	for name in COMPILER.ORDER:
		before[name] = digest((load(reg.parts[name].texture_path) as CompressedTexture2D).get_image().get_data())
	var owner = RASTER.new()
	t.root.add_child(owner)
	var result: Dictionary = owner.configure(reg)
	t.check(result.ok, "exact registered sources configure")
	if not result.ok: owner.free(); return
	t.check(result.cached_alpha_bytes == 4591880, "LA8 reports exact 2-byte query storage")
	t.check(owner.debug_stats().alpha_bytes == 4591880, "LA8 retained storage accounting agrees")
	var pixels := 0
	var alpha_one := 0
	var mismatch := 0
	for name in COMPILER.ORDER:
		var image: Image = (load(reg.parts[name].texture_path) as CompressedTexture2D).get_image()
		t.check(image.get_format() == Image.FORMAT_RGBA8 and digest(image.get_data()) == before[name], "retained draw texture RGBA remains unmodified: " + name)
		var rgba := image.get_data()
		var data: PackedByteArray = owner._alpha[name].data
		var count: int = image.get_width() * image.get_height()
		t.check(data.size() == count * 2, "each query buffer uses exact LA8 stride: " + name)
		if data.size() != count * 2: continue
		for i in range(count):
			if data[i * 2 + 1] != rgba[i * 4 + 3]: mismatch += 1
			if data[i * 2 + 1] == 1: alpha_one += 1
		pixels += count
	t.check(mismatch == 0 and pixels == 2295940 and alpha_one == 3337, "all packed alpha bytes including alpha=1 exactly preserved")
	# Compare the actual owners, including affine and neck-mesh query paths.
	var old = BASELINE.new()
	t.root.add_child(old)
	t.check(old.configure(reg).ok, "baseline reference configures")
	var compiler = COMPILER.new()
	var rows: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/armored_raster/golden_rows.json")).rows
	var queries := 0
	var unequal := 0
	for row in [rows[0], rows[rows.size()/2], rows[-1]]:
		var packet: Dictionary = compiler.compile_pose(row.row,reg)
		t.check(owner.present_packet(packet) and old.present_packet(packet), "same complete golden pose accepted")
		for y in range(0,288,4):
			for x in range(0,288,4):
				var point := Vector2(x+.5,y+.5)
				if owner.alpha_local(point) != old.alpha_local(point): unequal += 1
				if owner.is_opaque_local(point) != old.is_opaque_local(point): unequal += 1
				queries += 2
	t.check(unequal == 0, "full and threshold query values exactly match baseline")
	var packet_before = owner.packet_status()
	var bad = reg.duplicate(true)
	bad.parts.left_upper_arm.packed_png_sha256 = "0".repeat(64)
	t.check(not owner.configure(bad).ok and owner.last_error == "source_digest:left_upper_arm", "initial source SHA mismatch fails closed")
	var fresh = RASTER.new()
	t.root.add_child(fresh)
	t.check(not fresh.configure(bad).ok and fresh.get_child_count() == 0 and fresh.debug_stats().alpha_bytes == 0, "damaged initial source creates no partial actor or query storage")
	fresh.free()
	t.check(owner.packet_status() == packet_before, "failed initial validation preserves existing actor")
	var constructed: Dictionary = FIXTURE.new().registration()
	for variant in ["border_rgb","border_alpha"]:
		bad=constructed.duplicate(true)
		bad.parts.left_upper_arm.texture_path="res://tests/armored_startup/fixtures/"+variant+".png"
		bad.parts.left_upper_arm.packed_png_sha256=FileAccess.get_sha256(bad.parts.left_upper_arm.texture_path)
		t.check(not owner.configure(bad).ok and owner.last_error=="source_clear_border:left_upper_arm", "exact border RGBA failure rejected: "+variant)
		t.check(owner.packet_status()==packet_before,"border rejection preserves existing actor")
	owner.clear_actor()
	t.check(owner.debug_stats().alpha_bytes == 0, "clear releases LA8 query buffer")
	owner.free()
	old.free()
	print("LA8_OWNER_PROOF pixels=%d alpha_one=%d pixel_mismatches=%d queries=%d query_mismatches=%d native_gpu_verified=false" % [pixels,alpha_one,mismatch,queries,unequal])
