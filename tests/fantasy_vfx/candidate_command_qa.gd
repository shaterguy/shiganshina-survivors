extends RefCounted
# ISOLATED CANDIDATE QA ONLY. This helper cannot be reached by product code.
# It validates real unapproved PNG bytes and metadata, then calls _command
# directly for geometry/frame inspection. It NEVER changes approval flags or
# claims production rendering, native visibility, frame rate or acceptance.
const Catalog = preload("res://game/presentation/combat_vfx_catalog.gd")
const Renderer = preload("res://game/presentation/combat_vfx_renderer.gd")
var metadata: Dictionary = {}
var problems: Array[String] = []
func _init() -> void:
	var catalog := Catalog.new()
	for path in ["res://docs/art/vfx/fantasy-runtime-candidate.json","res://docs/art/vfx/evolution-runtime-candidate.json"]:
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not parsed is Dictionary or not parsed.get("assets") is Dictionary:
			problems.append("candidate_metadata_missing:"+path)
			continue
		for id in parsed.assets:
			var asset: Dictionary = parsed.assets[id]
			var errors := catalog.validate_art_metadata(id,asset)
			if asset.get("vfx_approved",true) != false: errors.append("candidate_must_remain_unapproved")
			if not FileAccess.file_exists(asset.path) or FileAccess.get_sha256(asset.path) != asset.sha256: errors.append("candidate_png_hash_mismatch")
			var image := Image.new()
			if FileAccess.file_exists(asset.path):
				if image.load_png_from_buffer(FileAccess.get_file_as_bytes(asset.path)) != OK or image.get_width() != int(asset.width) or image.get_height() != int(asset.height): errors.append("candidate_png_dimensions_mismatch")
			for error in errors: problems.append(id+":"+error)
			if errors.is_empty(): metadata[id] = asset.duplicate(true)
func commands(effects: Array[Dictionary], snapshot: Dictionary, reduce := false) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var renderer := Renderer.new()
	var tick := int(snapshot.active_tick)
	var context := {"tick":tick,"origin_revision":int(snapshot.get("world",{}).get("origin_revision",snapshot.get("origin_revision",0))),"reduce_effects":reduce}
	for effect in effects:
		if not effect.get("base_item_id","") in ["chain_lightning","fire_zone"] or tick < int(effect.start_tick) or tick >= int(effect.end_tick): continue
		for index in effect.layers.size():
			var layer: Dictionary = effect.layers[index]
			if not metadata.has(layer.art_id): continue
			if (reduce or effect.get("omit_optional",false)) and layer.get("reduce_mode","preserve") == "omit": continue
			output.append(renderer._command(effect,layer,layer.get("component","main"),metadata[layer.art_id],tick,context,index))
	return output
