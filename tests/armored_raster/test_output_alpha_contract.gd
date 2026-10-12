extends RefCounted
const RASTER = preload("res://game/presentation/armored/armored_raster.gd")
const FIXTURE = preload("res://tests/armored_raster/alpha_fixture.gd")
func run(t) -> void:
	var fixture = FIXTURE.new()
	var reg = fixture.registration()
	var owner = RASTER.new()
	t.root.add_child(owner)
	t.check(owner.configure(reg).ok and owner.present_packet(fixture.packet(reg)), "transparent target output contract configured")
	t.check(owner.packet_status().get("output_alpha_mode") == "premultiplied", "output consumer is told target RGB is premultiplied")
	owner.free()
