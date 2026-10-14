extends RefCounted
func run(t) -> void:
	var root := "res://tests/corridor_save_integration/"
	var provenance: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(root+"fixtures/provenance.json"))
	t.check(provenance.source_commit == "38b0cb1e70ef7c04a952568597a3ffc983d91945" and provenance.source_ref == "refs/heads/v0.1.0-dev7","migration fixtures pin exact final dev7 source identity")
	t.check(provenance.godot_version == "4.6.3.stable.official.7d41c59c4" and provenance.baseline_final_manifest_matches == 19 and provenance.baseline_final_manifest_mismatches.is_empty(),"legacy capture records checked final baseline manifest and exact engine")
	for name in provenance.fixture_sha256:
		t.check(FileAccess.get_sha256(root+"fixtures/"+name) == provenance.fixture_sha256[name],"legacy fixture digest matches capture evidence: "+name)
	for name in provenance.generation_scripts_sha256:
		t.check(FileAccess.get_sha256(root+name) == provenance.generation_scripts_sha256[name],"capture script digest matches original capture evidence: "+name)
