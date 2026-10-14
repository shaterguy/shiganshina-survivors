extends RefCounted
const View = preload("res://game/presentation/world_view.gd")
func _opaque(image: Image, region: Rect2, bounds: Rect2, flip: bool, point: Vector2) -> bool:
	if not bounds.has_point(point) or not region.has_area(): return false
	var local := Vector2i(((point-bounds.position)/bounds.size*region.size).floor())
	if flip: local.x = int(region.size.x)-1-local.x
	return image.get_pixelv(Vector2i(region.position)+local).a > 0.1
func _reference(view, player, other, image, house):
	var pr: Rect2 = view.frame_rect(player.asset_id,player.pose,player.seconds)
	var orr: Rect2 = view.frame_rect(other.asset_id,other.pose,0.0)
	var overlap: Rect2 = player.render_bounds.intersection(other.render_bounds)
	for y in range(int(floor(overlap.position.y)),int(ceil(overlap.end.y))):
		for x in range(int(floor(overlap.position.x)),int(ceil(overlap.end.x))):
			var pixel := Vector2(x+0.5,y+0.5)
			if _opaque(image,pr,player.render_bounds,player.flip,pixel) and _opaque(house,orr,other.render_bounds,false,pixel): return true
	return false
func run(t):
	var view := View.new()
	view.load_manifest()
	var image: Image = view._texture("garrison_01").get_image()
	var house: Image = view._texture("house_narrow").get_image()
	var old_times=[]
	var new_times=[]
	for pose in ["idle","move","windup","attack","hit","death"]:
		for flipped in [false,true]:
			for scale_value in [0.75,1.0,1.5]:
				for offset in [Vector2(-159,-190),Vector2(-130,-170),Vector2(-96,-128),Vector2(-64,-96),Vector2(-48,-64),Vector2(-16,-32),Vector2(0,0),Vector2(32,32),Vector2(63,63),Vector2(-64.4,-95.6)]:
					var player := {"asset_id":"garrison_01","pose":pose,"seconds":0.3,"render_bounds":Rect2(Vector2(0.25,0.75),Vector2(64,64)*scale_value),"flip":flipped}
					var other := {"id":"prop:test","asset_id":"house_narrow","pose":"idle","render_bounds":Rect2(offset,Vector2(160,192))}
					var started := Time.get_ticks_usec()
					var expected: bool = _reference(view,player,other,image,house)
					old_times.append(Time.get_ticks_usec()-started)
					started=Time.get_ticks_usec()
					var actual: bool = view._city_rasters_overlap(player,other)
					new_times.append(Time.get_ticks_usec()-started)
					t.check(expected==actual,"same exact occlusion "+str([pose,flipped,scale_value,offset]))
	old_times.sort();new_times.sort()
	print("RASTER_AB "+JSON.stringify({"samples":old_times.size(),"old_p50_us":old_times[old_times.size()/2],"old_p95_us":old_times[int(old_times.size()*.95)],"old_max_us":old_times[-1],"new_p50_us":new_times[new_times.size()/2],"new_p95_us":new_times[int(new_times.size()*.95)],"new_max_us":new_times[-1],"limits":"cloud headless CPU, exact alpha comparison on synthetic layout matrix"}))
	view.free()
