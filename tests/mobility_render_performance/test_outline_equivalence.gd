extends RefCounted
const Mask = preload("res://game/presentation/raster_alpha_mask.gd")
const View = preload("res://game/presentation/world_view.gd")
func _reference(image: Image) -> Image:
	var outline := Image.create(image.get_width(),image.get_height(),false,Image.FORMAT_RGBA8)
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x,y).a > 0.1: continue
			var edge := false
			for dy in range(-2,3):
				for dx in range(-2,3):
					if x+dx >= 0 and x+dx < image.get_width() and y+dy >= 0 and y+dy < image.get_height() and image.get_pixel(x+dx,y+dy).a > 0.1: edge = true
			if edge: outline.set_pixel(x,y,Color(0.24,0.94,1.0,0.95))
	return outline
func run(t) -> void:
	var image := Image.load_from_file("res://assets/art/characters/garrison_01_v2.png")
	for frame in 16:
		var region := Rect2i((frame%4)*64,(frame/4)*64,64,64)
		t.check(Mask.build(image,region).get_data() == _reference(image.get_region(region)).get_data(),"outline pixels identical for player frame "+str(frame))
	for size in [Vector2i(1,1),Vector2i(2,3),Vector2i(7,9)]:
		var sample := Image.create(size.x,size.y,false,Image.FORMAT_RGBA8)
		for y in size.y:
			for x in size.x:
				var alpha: float = [0.0,25.0/255.0,26.0/255.0,1.0][(x*3+y*5)%4]
				sample.set_pixel(x,y,Color(1,1,1,alpha))
		t.check(Mask.build(sample,Rect2i(Vector2i.ZERO,size)).get_data() == _reference(sample).get_data(),"outline preserves threshold and image-edge clipping "+str(size))
	var view := View.new()
	view.load_manifest()
	t.check(view._outline_textures.size() == 16,"all fixed player frames prepared before first airborne draw")
	var count: int = view._outline_textures.size()
	for frame in 16:
		var region := Rect2((frame%4)*64,(frame/4)*64,64,64)
		var first: Texture2D = view._player_outline_texture(region)
		t.check(is_same(first,view._player_outline_texture(region)),"repeated frame reuses same texture")
	t.check(count == view._outline_textures.size(),"airborne frame use does not create new outline entries")
	view.free()
