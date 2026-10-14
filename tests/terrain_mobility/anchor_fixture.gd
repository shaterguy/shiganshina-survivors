extends RefCounted
const H = preload("res://game/core/streamed_run_world.gd")
const F = preload("res://tests/core_world/new_streamed_helper_fixture.gd")
const Address = preload("res://game/world/world_address.gd")
static func make(slots: Array = [], origin: Array = ["0","0"]) -> Dictionary:
	var definitions := F.definitions()
	var authored := [{"slot_id":"roof_a","definition_id":"house_narrow","position":[144,224],"rotation_degrees":0}]
	if not slots.is_empty(): authored = slots.duplicate(true)
	for template in definitions.templates.templates: template.slots = authored.duplicate(true)
	var helper := H.new(definitions)
	var state := F.state(helper)
	state.player.position = [144.0,256.0]
	state.world.origin_chunk = origin.duplicate()
	var hydration := F.hydration(H.requirements(state))
	return {"helper":helper,"state":state,"hydration":hydration,"prepared":helper.prepare(state,hydration),"definitions":definitions}
static func slot(id: String, definition: String, position: Array) -> Dictionary:
	return {"slot_id":id,"definition_id":definition,"position":position,"rotation_degrees":0}
static func point(value: Dictionary, origin: Array) -> Vector2:
	return Address.relative(value.chunk,Vector2(value.local[0],value.local[1]),origin).local
static func changed(s: Dictionary, slots: Array) -> Dictionary:
	var next: Dictionary = s.state.duplicate(true)
	next.world.world_revision = int(next.world.world_revision)+1
	next.world.dirty_chunks = [{"chunk":next.world.origin_chunk.duplicate(),"props":slots}]
	return next

# Live v2 tests use the shared paired-anchor Core fixture. Keep make() unchanged
# because captured v1 checkpoints depend on its exact one-roof fingerprint.
static func corridor(t, slots: Array = [], origin: Array = ["0","0"]) -> Dictionary:
	var fixture = load("res://tests/corridor_mobility/corridor_fixture.gd")
	var s: Dictionary = fixture.make(t,slots,[180.0,256.0],origin)
	t.check(not s.is_empty(),"paired geometry fixture constructs genuine Core state")
	if s.is_empty(): return s
	s.helper = s.core._streamed
	s.definitions = F.definitions()
	for template in s.definitions.templates.templates: template.slots = (fixture.slots() if slots.is_empty() else slots).duplicate(true)
	s.prepared = {"ok":true}
	return s
static func legacy(phase := "over") -> Dictionary:
	var packet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/corridor_mobility/fixtures/legacy_"+phase+".json"))
	var s := make()
	s.state = packet.state
	s.hydration = packet.hydration
	s.prepared = s.helper.prepare(s.state,s.hydration)
	return s
