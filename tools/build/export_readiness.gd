extends RefCounted
# This guard is shared by every EditorPlugin export; never bypass pending art.
func validate(manifest: Dictionary) -> Dictionary:
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
