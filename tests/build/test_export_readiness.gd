extends RefCounted
func run(t) -> void:
	var path := "res://tools/build/export_readiness.gd"
	t.check(FileAccess.file_exists(path),"export readiness guard exists")
	if not FileAccess.file_exists(path): return
	var gate = load(path).new()
	t.check(gate.validate({"schema_version":1,"assets":{"soldier":{"path":"res://a.png"}}}).ok,"approved manifest permits export")
	var blocked: Dictionary = gate.validate({"schema_version":1,"assets":{"titan":{"path":"res://b.png","export_blocked":true,"reason":"canon_revision_pending"}}})
	t.check(not blocked.ok and blocked.blocked_ids == ["titan"],"unapproved art prevents every export")
	t.check(not gate.validate({}).ok,"missing art manifest fails closed")

	t.check(not gate.validate({"assets":{"x": {"path":"res://assets/x.png"}},"art_revision_status":{"final_export_allowed":false}}).ok,"explicit final art veto prevents export")
	t.check(not gate.validate({"assets":{"x": "broken"}}).ok,"malformed asset record fails closed")
	t.check(not gate.validate({"assets":{"x":{"export_blocked":"false"}}}).ok,"non-boolean block flag fails closed")
	t.check(not gate.validate({"assets":{"x":{}},"art_revision_status":{"final_export_allowed":"true"}}).ok,"non-boolean approval fails closed")
	t.check(gate.has_method("validate_development"),"explicit development-validation export gate exists")
	if not gate.has_method("validate_development"): return
	var dev := _dev_fixture()
	t.check(gate.validate(dev,"development-validation").ok,"explicit development mode accepts exact approved basic replacements")
	t.check(not gate.validate(dev).ok,"development placeholders cannot pass final gate")
	var raw = JSON.parse_string(FileAccess.get_file_as_string("res://assets/manifest.json"))
	t.check(not gate.validate(raw,"development-validation").ok,"raw rejected art cannot use development flag")
	for mutation in ["wrong_path","wrong_hash","approved_final","missing_placeholder","wrong_count","missing_notice","unsafe_runtime"]:
		var changed := dev.duplicate(true)
		if mutation == "wrong_path": changed.assets.titan_runner.path = "res://assets/art/characters/titan_runner.png"
		if mutation == "wrong_hash": changed.assets.titan_runner.sha256 = "f".repeat(64)
		if mutation == "approved_final": changed.art_revision_status.final_export_allowed = true
		if mutation == "missing_placeholder": changed.assets.titan_runner.erase("development_placeholder")
		if mutation == "wrong_count": changed.development_validation.replacement_ids.pop_back()
		if mutation == "missing_notice": changed.development_validation.notice = ""
		if mutation == "unsafe_runtime": changed.assets.game_icon.path = "res://assets/art/source/unreviewed.png"
		t.check(not gate.validate(changed,"development-validation").ok,"development gate rejects " + mutation)
	t.check(not gate.validate(dev,"typo-mode").ok,"unknown export mode fails closed")

func _dev_fixture() -> Dictionary:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/manifest.json"))
	var ids := ["boss_abnormal","boss_charger","boss_leaper","titan_runner","titan_sweeper"]
	manifest.development_validation = {"mode":"development-validation","development_only":true,
		"notice":"DEV VALIDATION | INCOMPLETE | 5 titan_basic art placeholders", "replacement_ids":ids,
		"fallback_asset_id":"titan_basic","source_manifest_sha256":"a".repeat(64)}
	for id in ids:
		var old: Dictionary = manifest.assets[id]
		var record: Dictionary = manifest.assets.titan_basic.duplicate(true)
		record.export_blocked = true
		record.development_only = true
		record.reason = "canon_revision_pending"
		record.review_status = "development_placeholder_not_final_approval"
		record.development_placeholder = {"fallback_asset_id":"titan_basic", "original_path":old.path,
			"original_sha256":old.sha256,"original_export_blocked":true,"original_review_status":old.review_status}
		manifest.assets[id] = record
	return manifest
