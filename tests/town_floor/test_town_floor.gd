extends RefCounted
class Capture extends "res://game/presentation/world_view.gd":
	var calls: Array = []
	var builds := 0
	func _prepare_town_floor() -> void:
		builds += 1
		super._prepare_town_floor()
	func _world_region(texture: Texture2D,rect: Rect2,region: Rect2,color:=Color.WHITE) -> void:
		calls.append({"texture":texture.get_instance_id(),"rect":rect,"region":region,"color":color})
	func ground(command: Dictionary) -> Array:
		calls.clear()
		_draw_city_ground(command)
		return calls.duplicate(true)
func run(t) -> void:
	var view := Capture.new()
	var manifest := FileAccess.get_file_as_bytes("res://assets/manifest.json")
	var raster := FileAccess.get_file_as_bytes("res://assets/art/environment/city_tiles.png")
	view.load_manifest()
	t.check(view._town_floor_texture != null and view.builds == 1,"town atlas created once at manifest initialization")
	if view._town_floor_texture == null: view.free(); return
	var texture: Texture2D = view._town_floor_texture
	var image := texture.get_image()
	t.check(image.get_size() == Vector2i(128,160),"one bounded twenty-frame atlas")
	var source: Image = view._texture("city_tiles").get_image()
	if source.is_compressed(): source.decompress()
	source.convert(Image.FORMAT_RGBA8)
	var converted: bool = true
	var max_color_error: float = 0.0
	var quantized_oracle: Image = Image.create(1,1,false,Image.FORMAT_RGBA8)
	var rgba8_exact: bool = true
	for y in range(128):
		for x in range(128):
			var original_color: Color = source.get_pixel(x,y)
			var luminance: float = 0.06+0.94*(0.2126*original_color.r+0.7152*original_color.g+0.0722*original_color.b)
			var expected := Color(clampf(luminance*1.04,0.0,1.0),luminance,clampf(luminance*0.94,0.0,1.0),original_color.a)
			quantized_oracle.set_pixel(0,0,expected)
			var observed: Color = image.get_pixel(x,y)
			rgba8_exact = rgba8_exact and observed.to_rgba32() == quantized_oracle.get_pixel(0,0).to_rgba32()
			max_color_error = maxf(max_color_error,maxf(absf(observed.r-expected.r),maxf(absf(observed.g-expected.g),absf(observed.b-expected.b))))
			converted = converted and observed.a == original_color.a
	print("TOWN_COLOR_QUANTIZATION ",JSON.stringify({"max_channel_error":max_color_error,"one_rgba8_step":1.0/255.0,"alpha_preserved":converted,"rgba8_exact":rgba8_exact}))
	t.check(converted and rgba8_exact and max_color_error <= 1.0/255.0+0.000001,"derived RGBA8 stone stays within one quantization step of warm neutral transform and preserves alpha")
	var base := Color("#896345").to_rgba32()
	var sums := []
	var opaque := true
	var borders := true
	for variant in range(4):
		var sum := Vector3i.ZERO
		for y in range(32):
			for x in range(32):
				var c := image.get_pixel(variant*32+x,128+y)
				opaque = opaque and c.a == 1.0
				if x < 2 or x >= 30 or y < 2 or y >= 30: borders = borders and c.to_rgba32() == base
				sum += Vector3i(roundi(c.r*255),roundi(c.g*255),roundi(c.b*255))
		sums.append(sum)
	t.check(opaque and borders,"dirt opaque with common two-pixel border")
	t.check(sums.all(func(s): return s == sums[0]),"all four dirt variants have equal average color")
	view._camera = Vector2(384,384);view._viewport_size = Vector2(768,768)
	view.screen_shake = 0
	var command := {"position":Vector2.ZERO,"bounds":Rect2(0,0,768,768),"ground_variant":0}
	var before := command.duplicate(true)
	var reference := []
	for variant in range(4):
		command.ground_variant = variant
		var calls: Array = view.ground(command)
		t.check(calls.size() == 576,"same one draw submission per full-chunk tile")
		var stone := 0;var dirt := 0
		for y in range(24):
			for x in range(24):
				var call: Dictionary = calls[y*24+x]
				var paved: bool = (x >= 9 and x < 15) or (y >= 9 and y < 15)
				var index: int = posmod(variant*4+posmod(x*7+y*11,4),16) if paved else 16+posmod(variant+x*7+y*11,4)
				t.check(call.region == Rect2(Vector2(index%4,index/4)*32,Vector2(32,32)) and call.color == Color.WHITE,"actual tile region and tint match paving/dirt boundary")
				t.check(call.texture == texture.get_instance_id(),"one cached texture for both materials")
				if paved: stone += 1
				else: dirt += 1
		t.check(stone == 252 and dirt == 324,"six-cell crossing roads cover exactly252 stone324 dirt cells")
		if variant == 0: reference = calls
	command.ground_variant = 0
	t.check(command == before,"ground draw leaves command untouched")
	var offset := Vector2(-768,768)
	var shifted := command.duplicate(true)
	shifted.position += offset;shifted.bounds.position += offset
	view._camera += offset
	t.check(view.ground(shifted) == reference,"negative-origin translation preserves screen rectangles texture and pattern")
	view._camera = Vector2(304,304);view._viewport_size = Vector2(64,64)
	t.check(view.ground(command).size() == 9,"partial visible boundary keeps existing culling loop")
	view.reset_presentation()
	t.check(view._town_floor_texture == texture and view.builds == 1,"presentation reset does not rebuild atlas")
	view._camera = Vector2(384,384);view._viewport_size = Vector2(768,768)
	for frame in range(12):
		view._clock = frame*0.1
		view.ground(command)
	t.check(view._town_floor_texture == texture and view.builds == 1,"warm drawing never prepares texture")
	view._assets.city_tiles.width = 129
	view._prepare_town_floor()
	t.check(view._town_floor_texture == null,"invalid metadata discards stale atlas")
	var attempts: int = view.builds
	view.ground(command);view.ground(command)
	t.check(view.builds == attempts,"fallback draw never retries atlas initialization")
	view._assets.erase("city_tiles");view._textures.clear()
	view._prepare_town_floor()
	t.check(view._town_floor_texture == null and view.ground(command).is_empty(),"missing source fails cleanly without stale floor")
	view.load_manifest()
	t.check(view._town_floor_texture != null and view._town_floor_texture != texture,"explicit reload creates fresh atlas only")
	t.check(FileAccess.get_file_as_bytes("res://assets/manifest.json") == manifest and FileAccess.get_file_as_bytes("res://assets/art/environment/city_tiles.png") == raster,"source asset and manifest bytes preserved")
	view.free()

