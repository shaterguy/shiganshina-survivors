extends RefCounted
# New real initial/evolution fixture provenance; copied rendering DTOs stay illustrative.
const ROOT := "res://tests/fixtures/evolution_supply_grabber/"
func run(t) -> void:
	var provenance = JSON.parse_string(FileAccess.get_file_as_string(ROOT+"provenance.json"))
	t.check(provenance is Dictionary,"NEW fixture provenance present")
	if not provenance is Dictionary: return
	t.check(provenance.origin_class == "NEW" and provenance.content_revision == "ch01.3-rebuild.7-grabber-hand","new identity never masquerades as recovered ch01.3")
	t.check(str(provenance.claim).contains("Not recovered originals") and str(provenance.claim).contains("not real Core"),"claim excludes original recovery and real validator acceptance")
	for name in provenance.files:
		t.check(FileAccess.get_sha256(ROOT+name) == provenance.files[name],"provenance hash matches authored bytes: "+name)
	var basis: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT+provenance.fingerprint_basis_file))
	var basis_hash: String = load("res://game/director/chapter_catalog.gd").new().definition_digest(basis)
	t.check(basis_hash == provenance.fixture_content_fingerprint,"fixture fingerprint binds actual exported catalog under finite_test identity")
	var packet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT+"run_v2.json"))
	var state: Dictionary = packet.initial
	t.check(state.content_revision == provenance.content_revision and state.rules.content_fingerprint == basis_hash,"initial reference binds NEW revision and fixture identity")
	t.check(not state.has("world"),"R0 never invents a streamed world from missing template content")
	var saves: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT+"game_save_v2.json"))
	t.check(saves.started.checkpoint == state,"started fixture binds exact reference checkpoint")
	var changed := state.duplicate(true)
	changed.content_revision = "ch01.3"
	t.check(not _matches_fixture_identity(changed,provenance),"old lost ch01.3 cannot equal NEW fixture identity")
	changed = state.duplicate(true)
	changed.rules.content_fingerprint = "0".repeat(64)
	t.check(not _matches_fixture_identity(changed,provenance),"unknown fixture fingerprint rejected as identity mismatch")
	var doc := FileAccess.get_file_as_string("res://docs/design/rebuild-contracts-v1.md")
	for boundary in ["restore(snapshot,hydrated_deltas={})","state.upgrade_offer","view.active_offer","WHOLE authority","same ID","checkpoint null is legal ONLY","latest current lifecycle generation","CONTRACT-ONLY"]:
		t.check(doc.contains(boundary),"review contract retains explicit boundary: "+boundary)
func _matches_fixture_identity(state: Dictionary,provenance: Dictionary) -> bool:
	return state.get("content_revision") == provenance.content_revision and state.get("rules",{}).get("content_fingerprint") == provenance.fixture_content_fingerprint
