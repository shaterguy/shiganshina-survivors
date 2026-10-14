extends RefCounted
const View = preload("res://game/presentation/world_view.gd")
const Mask = preload("res://game/presentation/raster_alpha_mask.gd")
const Armored = preload("res://game/presentation/armored/armored_raster.gd")
const Outline = preload("res://tests/mobility_render_performance/test_outline_equivalence.gd")
func _opaque(image: Image, region: Rect2, bounds: Rect2, flip: bool, point: Vector2) -> bool:
	if not bounds.has_point(point) or not region.has_area(): return false
	var local := Vector2i(((point-bounds.position)/bounds.size*region.size).floor())
	if flip: local.x = int(region.size.x)-1-local.x
	return image.get_pixelv(Vector2i(region.position)+local).a > 0.1
func _reference(view, player, occluder):
	var other: Dictionary = view._city_draw_data[occluder.id.get_slice(":",0)][occluder.source_id] if occluder.has("source_id") else {}
	var pr: Rect2 = view.frame_rect(player.asset_id,player.pose,player.seconds)
	var other_region: Rect2 = view.frame_rect(occluder.asset_id,occluder.pose,float(other.get("seconds",view._clock)))
	var overlap: Rect2 = player.render_bounds.intersection(occluder.render_bounds)
	var image: Image = view._raster_images[player.asset_id]
	for y in range(int(floor(overlap.position.y)),int(ceil(overlap.end.y))):
		for x in range(int(floor(overlap.position.x)),int(ceil(overlap.end.x))):
			var pixel := Vector2(x+0.5,y+0.5)
			if _opaque(image,pr,player.render_bounds,player.flip,pixel) and (view._armored_opaque(pixel) if other.get("armored_raster",false) else _opaque(view._raster_images[occluder.asset_id],other_region,occluder.render_bounds,other.get("flip",false),pixel)): return true
	return false
func _sample(rng: RandomNumberGenerator, width: int, height: int) -> Image:
	var image := Image.create(width,height,false,Image.FORMAT_RGBA8)
	for y in height:
		for x in width:
			var alpha: float = [0.0,25.0/255.0,26.0/255.0,1.0][rng.randi_range(0,3)] if x >= width/4 and y >= height/4 and x < width*3/4 and y < height*3/4 else 0.0
			image.set_pixel(x,y,Color(1,0.3,0.6,alpha))
	return image
func run(t):
	var rng := RandomNumberGenerator.new()
	rng.seed = 329783133
	var outline_reference = Outline.new()
	for width in range(1,13):
		for height in range(1,13):
			var sample := _sample(rng,width,height)
			t.check(Mask.build(sample,Rect2i(0,0,width,height)).get_data() == outline_reference._reference(sample).get_data(),"random small image dilation "+str([width,height]))
	for format in [Image.FORMAT_L8,Image.FORMAT_LA8,Image.FORMAT_R8,Image.FORMAT_RG8,Image.FORMAT_RGB8,Image.FORMAT_RGBA8,Image.FORMAT_RGBA4444,Image.FORMAT_RGB565]:
		var sample := _sample(rng,9,11)
		sample.convert(format)
		t.check(Mask.build(sample,Rect2i(0,0,9,11)).get_data() == outline_reference._reference(sample).get_data(),"integer image format "+str(format))
	var view := View.new()
	var sample := _sample(rng,32,32)
	var occluder_image := _sample(rng,24,24)
	view._assets = {"garrison_01":{"cell_w":16,"cell_h":16,"columns":2,"animations":{"idle":{"frames":[0,1,2,3],"fps":1,"loop":true}}},"other":{"cell_w":12,"cell_h":12,"columns":2,"animations":{"idle":{"frames":[0,1,2,3],"fps":1,"loop":true}}}}
	view._raster_images = {"garrison_01":sample,"other":occluder_image}
	for frame in 4: view._player_outline_texture(Rect2((frame%2)*16,(frame/2)*16,16,16))
	var armored_owner = Armored.new()
	var armored_bounds := Rect2(138.2,270.2,11.2,12.4)
	var armored_alpha := Image.create(20,20,false,Image.FORMAT_LA8)
	armored_alpha.fill(Color.WHITE)
	armored_owner._packet = {"bounds":armored_bounds}
	armored_owner._query_commands = [{"modulate_alpha":1.0,"bounds":armored_bounds,"inverse":Transform2D(0,-armored_bounds.position),"alpha":{"size":Vector2i(20,20),"data":armored_alpha.get_data()},"vertices":[]}]
	view._armored_raster = armored_owner
	view._armored_display = {"supported":true,"root_position":Vector2(0.5,0.5),"flip":false,"display_scale":1.7}
	view._city_draw_data = {"actor":{"x":{}}}
	var positives := 0
	var armored_positives := 0
	for i in 16000:
		var pscale := Vector2(rng.randf_range(.03,4.0),rng.randf_range(.03,4.0))
		var oscale := Vector2(rng.randf_range(.03,4.0),rng.randf_range(.03,4.0))
		var start := Vector2(rng.randf_range(-36,36),rng.randf_range(-36,36))
		if i%5 == 0: start = start.floor()+Vector2(.5,.5)
		var player := {"asset_id":"garrison_01","pose":"idle","seconds":float(i%4),"render_bounds":Rect2(start,Vector2(16,16)*pscale),"flip":bool(i%2)}
		var other := {"id":"actor:x","source_id":"x","asset_id":"other","pose":"idle","render_bounds":Rect2(Vector2(rng.randf_range(-36,36),rng.randf_range(-36,36)),Vector2(12,12)*oscale)}
		var armored: bool = i%3==0
		view._city_draw_data.actor.x = {"flip":bool((i/2)%2),"seconds":float((i/4)%4),"armored_raster":armored}
		view._armored_display.flip = bool((i/8)%2)
		if armored: other.render_bounds = view._armored_world_transform() * armored_owner.local_bounds()
		var expected: bool = _reference(view,player,other)
		var actual: bool = view._city_rasters_overlap(player,other)
		if expected: positives += 1
		if expected and armored: armored_positives += 1
		t.check(expected==actual,"fuzzed raster overlap "+str([i,pscale,oscale,start,armored,expected,actual]))
	print("INDEPENDENT_RASTER_FUZZ "+JSON.stringify({"cases":16000,"positives":positives,"armored_positives":armored_positives,"seed":rng.seed}))
	view._armored_raster = null
	armored_owner.free()
	view.free()
	var live := View.new()
	var started := Time.get_ticks_usec()
	live.load_manifest()
	var cold := Time.get_ticks_usec()-started
	live._raster_data("garrison_01")
	var first_player: Texture2D = live._outline_textures.values()[0]
	live.load_manifest()
	t.check(not is_same(first_player,live._outline_textures.values()[0]),"manifest reload invalidates player outlines")
	t.check(live._raster_bytes.is_empty(),"manifest reload clears raster bytes")
	t.check(live._player_alpha_bounds.size()==16,"manifest reload replaces complete alpha bounds")
	var first_bounds := live._player_alpha_bounds.duplicate(true)
	live.reset_presentation()
	t.check(first_bounds==live._player_alpha_bounds,"presentation reset retains source-dependent bounds")
	print("INDEPENDENT_PREWARM "+JSON.stringify({"load_manifest_cold_us":cold,"outline_frames":live._outline_textures.size()}))
	live.free()
