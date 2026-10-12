extends RefCounted
func run(t) -> void:
	var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://assets/manifest.json"))
	t.check(manifest is Dictionary, "asset manifest parses")
	if not manifest is Dictionary: return
	t.check(manifest.get("palette",[]).size() == 24, "shared palette has 24 colors")
	var required := ["garrison_01","titan_basic","titan_runner","titan_brute","titan_sweeper","titan_grabber","boss_charger","boss_sweeper","boss_leaper","boss_grabber","boss_abnormal","armored_titan","city_tiles","danger_circle","danger_line","danger_sector","xp_pickup","escape_marker","gamepad_a","gamepad_b","combat_loop","boss_loop"]
	for asset_id in required: t.check(manifest.assets.has(asset_id), "required asset exists: " + asset_id)
	for asset_id in manifest.assets:
		var a: Dictionary = manifest.assets[asset_id]
		var path: String = a.path
		t.check(FileAccess.file_exists(path), "asset file exists: " + asset_id)
		t.check(FileAccess.get_sha256(path) == a.sha256, "asset checksum matches: " + asset_id)
		t.check(not str(a.get("source_method","")).is_empty(), "asset has provenance: " + asset_id)
		if a.kind == "audio":
			var sound = AudioStreamWAV.load_from_file(path)
			t.check(sound != null and sound.get_length() > 0, "WAV decodes: " + asset_id)
			continue
		var picture := Image.new()
		var decode_error := picture.load_png_from_buffer(FileAccess.get_file_as_bytes(path))
		t.check(decode_error == OK, "PNG decodes: " + asset_id)
		if decode_error != OK: continue
		t.check(picture.get_format() == Image.FORMAT_RGBA8, "PNG is RGBA8: " + asset_id)
		t.check(picture.get_width() == int(a.width) and picture.get_height() == int(a.height), "atlas dimensions: " + asset_id)
		t.check(int(a.width)%int(a.cell_w) == 0 and int(a.height)%int(a.cell_h) == 0, "atlas divides into cells: " + asset_id)
		var count := int(a.width/a.cell_w)*int(a.height/a.cell_h)
		for animation in a.animations.values():
			t.check(not animation.frames.is_empty(), "animation contains frames: " + asset_id)
			for frame in animation.frames: t.check(int(frame)>=0 and int(frame)<count, "animation frame in bounds: " + asset_id)
		if a.kind == "sprite":
			t.check(a.anchor_px == [a.cell_w/2,a.cell_h], "character anchor at bottom center: " + asset_id)
	t.check(not manifest.assets.armored_titan.animations.has("death"), "Armored Titan has no death animation")
