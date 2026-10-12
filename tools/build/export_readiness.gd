extends RefCounted
const VfxCatalog = preload("res://game/presentation/combat_vfx_catalog.gd")
# Final approval stays closed. Only exact development placeholder metadata permits validation export.
func validate(manifest: Dictionary, mode: String = "final") -> Dictionary:
	if mode == "development-validation": return validate_development(manifest)
	if mode != "final" or manifest.has("development_validation"): return _denied("invalid_export_mode")
	var blocked: Array[String] = []
	if not manifest.get("assets") is Dictionary or manifest.assets.is_empty():
		return {"ok":false,"blocked_ids":blocked,"reason":"missing_manifest"}
	for id in manifest.assets:
		var record = manifest.assets[id]
		if not record is Dictionary or not record.get("export_blocked",false) is bool:
			return {"ok":false,"blocked_ids":blocked,"reason":"invalid_manifest"}
		if record.get("export_blocked",false): blocked.append(str(id))
	blocked.sort()
	var status = manifest.get("art_revision_status",{})
	if not status is Dictionary or not status.get("final_export_allowed",true) is bool:
		return {"ok":false,"blocked_ids":blocked,"reason":"invalid_manifest"}
	var approved: bool = status.get("final_export_allowed",true)
	return {"ok":blocked.is_empty() and approved,"blocked_ids":blocked,"reason":"" if blocked.is_empty() and approved else "art_review_pending"}

func _denied(reason: String) -> Dictionary:
	return {"ok":false,"blocked_ids":[],"reason":reason}

func validate_development(manifest: Dictionary) -> Dictionary:
	var ids := ["boss_abnormal","boss_charger","boss_leaper","titan_runner","titan_sweeper"]
	var rejected := {
		"titan_runner":"b4979340dd3339dfd062143e027d453b7e01c0a1f0b2b83ddfa93b09e690e722",
		"titan_sweeper":"eb640f8a8c8617db7da4599554152d41162e7716f513335ed6ba56f002274f0f",
		"boss_charger":"7ee769802a176e95474e9ce9f88d22aab3aff6e967165cf82c06181c5c617bcb",
		"boss_leaper":"2da095171c0e6c8bff217837ab86f04120ff1aaebd3da7368ac34ca512e51efa",
		"boss_abnormal":"9de54f758a3ad0e2370c1d8f469272d4f68f3ab196dd7ee8a65d747ed1ec787a"}
	if not manifest.get("assets") is Dictionary or manifest.assets.is_empty(): return _denied("missing_manifest")
	var status = manifest.get("art_revision_status",{})
	if not status is Dictionary or status.get("final_export_allowed") != false: return _denied("development_final_gate")
	var blocked_ids = status.get("blocked_character_ids",[])
	if not blocked_ids is Array: return _denied("development_ids")
	blocked_ids = blocked_ids.duplicate()
	blocked_ids.sort()
	if blocked_ids != ids: return _denied("development_ids")
	var meta = manifest.get("development_validation",{})
	if not meta is Dictionary or meta.get("mode") != "development-validation" or meta.get("development_only") != true: return _denied("development_metadata")
	if meta.get("notice") != "DEV VALIDATION | INCOMPLETE | 5 titan_basic art placeholders" or meta.get("replacement_ids") != ids or meta.get("fallback_asset_id") != "titan_basic": return _denied("development_metadata")
	var sha_pattern := RegEx.create_from_string("^[0-9a-f]{64}$")
	if sha_pattern.search(str(meta.get("source_manifest_sha256",""))) == null: return _denied("development_provenance")
	var basic = manifest.assets.get("titan_basic",{})
	if not basic is Dictionary or basic.get("path") != "res://assets/art/characters/titan_basic_v2.png" or basic.get("sha256") != "e7debeea18672d55cd938f213a7738eb93c2a89c9783a201b30421e4e466a62c": return _denied("development_fallback")
	if basic.get("export_blocked") != false or basic.get("review_status") != "visual_reviewed_revision_2" or not "titan_basic" in status.get("approved_character_ids",[]): return _denied("development_fallback")
	var actual_blocked: Array = []
	for id in manifest.assets:
		var record = manifest.assets[id]
		if not record is Dictionary or not record.get("export_blocked",false) is bool: return _denied("invalid_manifest")
		if record.get("export_blocked",false): actual_blocked.append(id)
		if not is_runtime_asset_path(record) or sha_pattern.search(str(record.get("sha256",""))) == null: return _denied("development_runtime_asset")
		if record.sha256 in rejected.values(): return _denied("development_rejected_bytes")
		for rejected_id in ids:
			if record.path == "res://assets/art/characters/%s.png" % rejected_id: return _denied("development_rejected_path")
		if not id in ids:
			if record.get("development_only",false) or record.has("development_placeholder"): return _denied("unexpected_development_placeholder")
			continue
		if record.get("development_only") != true or record.get("export_blocked") != true or record.get("review_status") != "development_placeholder_not_final_approval": return _denied("development_status")
		for key in ["path","sha256","width","height","columns","cell_w","cell_h","anchor_px","animations"]:
			if not basic.has(key) or record.get(key) != basic[key]: return _denied("development_fallback_mismatch")
		var provenance = record.get("development_placeholder",{})
		var expected := {"fallback_asset_id":"titan_basic","original_path":"res://assets/art/characters/%s.png" % id,
			"original_sha256":rejected[id],"original_export_blocked":true,"original_review_status":"rejected_incorrect_clothing"}
		if provenance != expected: return _denied("development_placeholder_provenance")
	actual_blocked.sort()
	if actual_blocked != ids: return _denied("development_ids")
	return {"ok":true,"blocked_ids":actual_blocked,"reason":"development_validation_only","final_export_allowed":false}

# Runtime paths are manifest-selected. Candidate sources/previews are never exported.
func is_runtime_asset_path(record: Dictionary) -> bool:
	var path := str(record.get("path",""))
	var flat := RegEx.create_from_string("^res://assets/(art/(characters|environment|effects|ui)/[^/]+\\.png|audio/[^/]+\\.wav)$")
	if flat.search(path) != null: return true
	var enemy_records := {
		"res://assets/art/characters/enemy_diversity_v1/titan_quadruped.png":["sprite","nearest_palette_alpha128"],
		"res://assets/art/characters/enemy_diversity_v1/titan_stone_thrower.png":["sprite","nearest_palette_alpha128_exclude_20252c"],
		"res://assets/art/characters/enemy_diversity_v1/enemy_stone_projectile.png":["projectile","nearest_palette_alpha128"]}
	if enemy_records.has(path):
		return record.get("enemy_art_development_ready") is bool and record.enemy_art_development_ready and record.get("export_blocked") is bool and not record.export_blocked and [record.get("kind"),record.get("packing_profile")] == enemy_records[path]
	if record.get("kind") != "effect" or not VfxCatalog.render_enabled(record): return false
	if path.begins_with("res://assets/art/effects/vfx_remaining_v1/"):
		var remaining := RegEx.create_from_string("^res://assets/art/effects/vfx_remaining_v1/vfx_(dash_compressed_gas|dash_cross_tip|reentry_triple|ally_gas_swoop|ally_arrival_cut)\\.png$")
		return remaining.search(path) != null
	var nested := RegEx.create_from_string("^res://assets/art/effects/vfx_(rebuild|evolution|fantasy)_v1/vfx_[A-Za-z0-9_-]+\\.png$")
	return nested.search(path) != null
