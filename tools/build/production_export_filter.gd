@tool
extends EditorExportPlugin
var _allowed_assets: Dictionary = {}
func _get_name() -> String:
	return "ChapterOneProductionFiles"
func _export_begin(_features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
	_allowed_assets.clear()
	var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://assets/manifest.json"))
	if manifest is Dictionary:
		var mode := OS.get_environment("SHIGAN_EXPORT_MODE")
		if mode.is_empty(): mode = "final"
		var gate: Dictionary = load("res://tools/build/export_readiness.gd").new().validate(manifest,mode)
		if not gate.ok: return
		var runtime := RegEx.create_from_string("^res://assets/(art/(characters|environment|effects|ui)/[^/]+\\.png|audio/[^/]+\\.wav)$")
		for record in manifest.assets.values():
			if runtime.search(str(record.path)) != null: _allowed_assets[str(record.path)] = true
	_add_json("res://data")
	_add_json("res://chapters")
	add_file("res://assets/manifest.json",FileAccess.get_file_as_bytes("res://assets/manifest.json"),false)
func _add_json(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null: return
	for file in dir.get_files():
		if file.ends_with(".json"):
			var full := path.path_join(file)
			add_file(full,FileAccess.get_file_as_bytes(full),false)
	for folder in dir.get_directories(): _add_json(path.path_join(folder))
func _export_file(path: String, _type: String, _features: PackedStringArray) -> void:
	if path.begins_with("res://game/") or path.begins_with("res://scenes/"): return
	if _allowed_assets.has(path): return
	skip()
