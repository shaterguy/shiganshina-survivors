extends RefCounted
## Import-data verification only. No viewport, draw, GPU capture, or live loop.
func run(t) -> void:
	var registration = JSON.parse_string(FileAccess.get_file_as_string("res://assets/art/rig/armored_runtime_v1/registration.json"))
	for name in registration.parts:
		var path: String = registration.parts[name].texture_path
		var config = ConfigFile.new()
		t.check(config.load(path + ".import") == OK, "explicit texture import settings: " + name)
		t.check(config.get_value("params", "compress/mode") == 0, "lossless imported texture: " + name)
		t.check(config.get_value("params", "mipmaps/generate") == false, "no imported mipmaps: " + name)
		t.check(config.get_value("params", "process/fix_alpha_border") == false, "import does not rewrite border RGBA: " + name)
		var packed := Image.new()
		t.check(packed.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) == OK, "packed PNG decodes: " + name)
		var texture = load(path)
		t.check(texture is CompressedTexture2D, "packed texture resource imports: " + name)
		if not texture is CompressedTexture2D: continue
		# One-time headless imported-source read, never a render-target/live-frame read.
		var imported: Image = texture.get_image()
		t.check(imported != null and imported.get_size() == packed.get_size(), "import-data dimensions agree: " + name)
		if imported != null: t.check(imported.get_data() == packed.get_data(), "exact imported RGBA bytes: " + name)
