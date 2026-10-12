extends RefCounted
const PATH = "res://game/presentation/armored/armored_raster.gd"
const FIXTURE = preload("res://tests/armored_raster/alpha_fixture.gd")
func run(t) -> void:
	t.check(FileAccess.file_exists(PATH), "cached same-composition alpha query exists")
	if not FileAccess.file_exists(PATH): return
	var script = load(PATH)
	if script == null or not script.can_instantiate(): return
	var owner = script.new()
	t.root.add_child(owner)
	t.check(owner.has_method("alpha_local") and owner.has_method("is_opaque_local"), "native-grid cached alpha API exists")
	if not owner.has_method("alpha_local") or not owner.has_method("is_opaque_local"): owner.free(); return
	var fixture = FIXTURE.new()
	var reg = fixture.registration()
	t.check(owner.configure(reg).ok, "constructed RGBA sources configure")
	var packet = fixture.packet(reg)
	packet.commands[0].modulate = Color.WHITE
	t.check(owner.present_packet(packet), "constructed affine packet accepted")
	for y in range(6):
		for x in range(6):
			var expected = fixture.scalar_at(x, y)
			for offset in [Vector2(.01, .99), Vector2(.5, .5), Vector2(.99, .01)]:
				var point = Vector2(20 + x, 20 + y) + offset
				t.check(absf(owner.alpha_local(point) - expected) < .000001, "native pixel center and nearest sample")
				t.check(owner.is_opaque_local(point) == (expected > .1), "same atlas alpha >0.1 overlap threshold")
	packet.commands[1].modulate = Color(1, 1, 1, .5)
	t.check(owner.present_packet(packet), "overlapping semi-transparent layer accepted")
	var a = 128.0 / 255.0
	var composed = a * .5 + a * (1 - a * .5)
	t.check(absf(owner.alpha_local(Vector2(21.5, 21.5)) - composed) < .000001, "source-over composition in fixed layer order")
	# Final native image mirror: map the world/display point through x144 first.
	var mirrored_display_point = Vector2(288 - 21.5, 21.5)
	t.check(owner.is_opaque_local(Vector2(288 - mirrored_display_point.x, mirrored_display_point.y)), "mirror about anchor retains exact native column")
	for c in packet.commands: c.modulate.a = 0
	packet.commands[10].modulate.a = 1
	t.check(owner.present_packet(packet), "two UV triangles accepted with out-of-range UVs")
	for y in range(12):
		for x in range(12):
			# Interpolation maps destination center to source x-3+0.5, y-3+0.5.
			var expected = fixture.scalar_at(clampi(x - 3, 0, 5), clampi(y - 3, 0, 5))
			var point = Vector2(100.5 + x, 100.5 + y)
			t.check(absf(owner.alpha_local(point) - expected) < .000001, "two-triangle nearest UV and edge-clamp agree")
	t.check(absf(owner.alpha_local(Vector2(104.5, 104.5)) - a) < .000001, "shared triangle edge covered once, no doubled alpha")
	for point in [Vector2(99.99, 104), Vector2(112, 104), Vector2(-1, 104), Vector2(288, 104), Vector2(INF, 0)]:
		t.check(owner.alpha_local(point) == 0 and not owner.is_opaque_local(point), "outside target/geometry or nonfinite point is transparent")
	var before = owner.debug_stats()
	for i in range(10000): owner.is_opaque_local(Vector2(104.5, 104.5))
	t.check(owner.debug_stats().source_decodes == before.source_decodes and owner.debug_stats().resource_ids == before.resource_ids, "queries never decode images or allocate render resources")
	owner.clear_actor()
	t.check(owner.alpha_local(Vector2(104.5, 104.5)) == 0, "clear releases alpha coverage")
	owner.free()
