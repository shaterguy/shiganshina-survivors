@tool
extends EditorExportPlugin
const UI_FONT_FILES := ["res://assets/fonts/NotoSansKR-wght.ttf","res://assets/fonts/NotoSansKR-OFL.txt"]
var _allowed_assets: Dictionary = {}
func _get_name() -> String:
	return "ChapterOneProductionFiles"
func _export_begin(_features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
	_allowed_assets.clear()
	var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://assets/manifest.json"))
	if manifest is Dictionary:
		var mode := OS.get_environment("SHIGAN_EXPORT_MODE")
		if mode.is_empty(): mode = "final"
		var readiness = load("res://tools/build/export_readiness.gd").new()
		var gate: Dictionary = readiness.validate(manifest,mode)
		if not gate.ok: return
		for record in manifest.assets.values():
			if readiness.is_runtime_asset_path(record):
				_allowed_assets[str(record.path)] = true
				# VFX validates/decodes original PNG bytes at runtime, not only .ctex.
				if record.get("vfx_approved",false) == true:
					add_file(str(record.path),FileAccess.get_file_as_bytes(str(record.path)),false)
	# Keep unmodified font bytes and its license together; no directory wildcard.
	for font_file in UI_FONT_FILES:
		_allowed_assets[font_file] = true
		# Godot exports the font through its normal imported-resource remap.
		if font_file.ends_with(".txt"):
			add_file(font_file,FileAccess.get_file_as_bytes(font_file),false)
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
