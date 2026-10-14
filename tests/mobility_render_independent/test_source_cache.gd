extends RefCounted
const View = preload("res://game/presentation/world_view.gd")
func run(t):
	var view := View.new()
	view.load_manifest()
	var results := []
	for asset in ["garrison_01","house_narrow","house_warehouse","house_bakery","house_ruined","titan_basic","titan_runner","titan_brute","titan_sweeper","titan_grabber","armored_titan","titan_quadruped","titan_stone_thrower","wall_segment","wall_breach"]:
		var texture: Texture2D = view._texture(asset)
		t.check(texture != null,"current imported raster source exists "+asset)
		if texture == null: continue
		var source: Image = texture.get_image()
		t.check(not source.is_compressed(),"current lossless import returns uncompressed Image "+asset)
		t.check(source.get_format()==Image.FORMAT_RGBA8,"current source alpha is exact RGBA8 "+asset)
		var started := Time.get_ticks_usec()
		var bytes: Dictionary = view._raster_data(asset)
		var cold := Time.get_ticks_usec()-started
		t.check(bytes.pixels == source.get_data(),"cached bytes preserve imported source "+asset)
		started = Time.get_ticks_usec()
		for i in 100: view._raster_data(asset)
		var warm := Time.get_ticks_usec()-started
		results.append({"asset":asset,"source_bytes":bytes.pixels.size(),"uncached_bytes_us":cold,"warm_100_us":warm})
	print("INDEPENDENT_SOURCE_CACHE "+JSON.stringify(results))
	view.free()
