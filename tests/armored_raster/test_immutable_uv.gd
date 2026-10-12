extends RefCounted
const RASTER = preload("res://game/presentation/armored/armored_raster.gd")
const FIXTURE = preload("res://tests/armored_raster/alpha_fixture.gd")
func run(t) -> void:
	var f = FIXTURE.new()
	var reg = f.registration()
	var valid: Dictionary = f.packet(reg)
	valid.commands[10].modulate = Color.WHITE
	var owner = RASTER.new()
	t.root.add_child(owner)
	t.check(owner.configure(reg).ok and owner.present_packet(valid), "registered mesh UV buffers configure")
	var before = owner._packet.hash()
	var generation = owner._generation
	var bad = valid.duplicate(true)
	bad.commands[10].uvs[0].x += .000001
	t.check(not owner.present_packet(bad), "even subpixel UV mutation cannot diverge cached query from retained mesh buffer")
	t.check(owner._packet.hash() == before and owner._generation == generation, "near-equal forged UV leaves entire previous packet unchanged")
	owner.free()
