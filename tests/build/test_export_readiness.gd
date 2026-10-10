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
