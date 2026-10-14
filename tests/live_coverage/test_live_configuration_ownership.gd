extends RefCounted
const F = preload("res://tests/live_coverage/live_fixture.gd")
func run(t) -> void:
	var s := F.make(t)
	if s.is_empty(): return
	var a = s.pair.simulation
	var proof = a._configuration_proof
	t.check(a._has_live_configuration() and proof.owner.get_ref() == a,"cold admitted configuration has exact Core owner")
	t.check(proof.data.is_read_only() and proof.data.chapter.is_read_only() and proof.data.chapter.allowed_equipment_ids.is_read_only(),"constructor configuration is recursively frozen")
	var prior_data: Dictionary = proof.data
	var external: Dictionary = proof.data.duplicate(true)
	external.chapter.content_fingerprint = "f".repeat(64)
	F.Core._freeze_configuration(external)
	proof.data = external
	t.check(proof.data == prior_data,"read-only proof data slot cannot be reassigned to an external record")
	proof.data = prior_data
	var forged = F.Core.LiveConfiguration.new(a,proof.nonce,prior_data)
	a._configuration_proof = forged
	t.check(not a._has_live_configuration() and a._fork_live_configuration() == null,"caller-made typed wrapper with matching fields is not the exact issued proof")
	a._configuration_proof = proof
	var first: String = a._catalog._equipment.keys()[0]
	var original: Dictionary = a._catalog._equipment[first].duplicate(true)
	a._catalog._equipment[first].name = "MUTATED PRIVATE ROW"
	a._capture_constructor_configuration()
	t.check(a._configuration_proof == proof and proof.data.equipment[first] == original,"later cached validate cannot recertify mutated catalog rows")
	var b = a._fork_live_configuration()
	t.check(b != null and b._catalog._equipment[first] == original,"fork consumes the admitted immutable rows rather than mutated donor catalog")
	a._catalog._equipment[first] = original
	var old_template = a._world_template
	a._world_template = F.H.new(s.chapter.world_definitions)
	t.check(not a._has_live_configuration() and a._fork_live_configuration() == null,"replacement helper object cannot inherit another owner's static proof")
	a._world_template = old_template
	var old_provider = a._chapter_provider
	a._chapter_provider = F.City.new()
	t.check(not a._has_live_configuration(),"replacement provider object requires cold admission")
	a._chapter_provider = old_provider
	t.check(a._has_live_configuration(),"restoring unchanged admitted owners restores eligibility")
	b = a._fork_live_configuration()
	t.check(b != null and not b._has_live_configuration(),"configuration fork alone is not a prepared live admission")
	var different_provider := F.City.new()
	var different_runtime := F.Runtime.new(different_provider,s.disk)
	var hits: Dictionary = different_provider._proof_hits.duplicate(true)
	var rebound: Dictionary = different_runtime.refresh_live_coverage(a,s.pair.state)
	t.check(rebound.get("ok",false) and different_provider._proof_hits != hits,"different Runtime provider owner requires fresh cold admission")
	var empty := {}
	for path in F.Core.GAMEPLAY_PATHS: empty[path] = {}
	var failed := F.Core.new(s.provider,null,empty)
	t.check(not failed._has_live_configuration(false) and failed._fork_live_configuration() == null,"failed constructor never issues a static proof")
