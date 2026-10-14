class_name RasterAlphaMask
extends RefCounted
# Exact 5x5 alpha dilation, computed as two bounded linear passes.
# Source alpha threshold and RGBA8 truncation match the former pixel renderer.
static func build(source: Image, region: Rect2i) -> Image:
	var image := source.get_region(region)
	if image.get_format() != Image.FORMAT_RGBA8: image.convert(Image.FORMAT_RGBA8)
	var width := image.get_width()
	var height := image.get_height()
	var pixels := image.get_data()
	var horizontal := PackedByteArray()
	horizontal.resize(width*height)
	for y in height:
		var row := y*width
		var count := 0
		for x in mini(2,width):
			if pixels[(row+x)*4+3] > 25: count += 1
		for x in width:
			if x+2 < width and pixels[(row+x+2)*4+3] > 25: count += 1
			horizontal[row+x] = 1 if count > 0 else 0
			if x-2 >= 0 and pixels[(row+x-2)*4+3] > 25: count -= 1
	var output := PackedByteArray()
	output.resize(width*height*4)
	var tint := Color(0.24,0.94,1.0,0.95)
	for x in width:
		var count := 0
		for y in mini(2,height): count += horizontal[y*width+x]
		for y in height:
			if y+2 < height: count += horizontal[(y+2)*width+x]
			var offset := (y*width+x)*4
			if count > 0 and pixels[offset+3] <= 25:
				output[offset] = int(tint.r*255.0)
				output[offset+1] = int(tint.g*255.0)
				output[offset+2] = int(tint.b*255.0)
				output[offset+3] = int(tint.a*255.0)
			if y-2 >= 0: count -= horizontal[(y-2)*width+x]
	return Image.create_from_data(width,height,false,Image.FORMAT_RGBA8,output)

static func opaque_bounds(source: Image, region: Rect2i) -> Rect2i:
	var image := source.get_region(region)
	if image.get_format() != Image.FORMAT_RGBA8: image.convert(Image.FORMAT_RGBA8)
	var pixels := image.get_data()
	var width := image.get_width()
	var low := Vector2i(width,image.get_height())
	var high := Vector2i.ZERO
	for y in image.get_height():
		for x in width:
			if pixels[(y*width+x)*4+3] <= 25: continue
			low = low.min(Vector2i(x,y))
			high = high.max(Vector2i(x+1,y+1))
	return Rect2i() if high.x <= low.x or high.y <= low.y else Rect2i(low,high-low)
