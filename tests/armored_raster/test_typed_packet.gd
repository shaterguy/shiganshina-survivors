extends RefCounted
const RASTER = preload("res://game/presentation/armored/armored_raster.gd")
const FIXTURE = preload("res://tests/armored_raster/alpha_fixture.gd")
func run(t) -> void:
	var fixture = FIXTURE.new()
	var registration = fixture.registration()
	var valid: Dictionary = fixture.packet(registration)
	valid.commands[0].modulate = Color.WHITE
	var names = ["minimal_ok_int", "ok_int", "canvas_int", "anchor_string", "ground_bool", "contained_int", "part_bool", "layer_bool", "offset_int", "texture_string", "source_array", "transform_string", "modulate_vector", "vertices_array", "uvs_array", "indices_array", "command_bounds_int", "packet_bounds_string"]
	for name in names:
		var owner = RASTER.new()
		t.root.add_child(owner)
		t.check(owner.configure(registration).ok and owner.present_packet(valid), "valid full previous packet before malformed type: " + name)
		var stored_hash = owner._packet.hash()
		var generation: int = owner._generation
		var updates: int = owner._update_requests
		var alpha: float = owner.alpha_local(Vector2(21.5, 21.5))
		var bad: Dictionary = valid.duplicate(true)
		match name:
			"minimal_ok_int": bad = {"ok": 1}
			"ok_int": bad.ok = 1
			"canvas_int": bad.canvas = 1
			"anchor_string": bad.anchor_px = "144,280"
			"ground_bool": bad.anatomical_ground_y = true
			"contained_int": bad.canvas_contained = 1
			"part_bool": bad.commands[0].part_id = true
			"layer_bool": bad.commands[0].layer = false
			"offset_int": bad.commands[0].source_offset = 1
			"texture_string": bad.commands[0].texture_size = "6,6"
			"source_array": bad.commands[0].source_size = [1, 1]
			"transform_string": bad.commands[0].transform = "identity"
			"modulate_vector": bad.commands[0].modulate = Vector2.ONE
			"vertices_array": bad.commands[0].vertices = []
			"uvs_array": bad.commands[0].uvs = []
			"indices_array": bad.commands[0].indices = []
			"command_bounds_int": bad.commands[0].bounds = 1
			"packet_bounds_string": bad.bounds = "rect"
		t.check(not owner.present_packet(bad), "malformed type rejected: " + name)
		t.check(not owner.last_error.is_empty(), "rejection has diagnostic string: " + name)
		t.check(owner._generation == generation and owner._update_requests == updates, "malformed type leaves generation/update unchanged: " + name)
		t.check(owner._packet.hash() == stored_hash and owner._packet.get("commands", []).size() == 17, "malformed type leaves whole commands/metadata unchanged: " + name)
		t.check(owner.alpha_local(Vector2(21.5, 21.5)) == alpha, "malformed type preserves prior alpha: " + name)
		owner.free()
