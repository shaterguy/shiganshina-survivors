extends RefCounted
static func generator():
	return load("res://game/world/city_generator.gd").new(JSON.parse_string(FileAccess.get_file_as_string("res://chapters/chapter_01/city_templates.json")),JSON.parse_string(FileAccess.get_file_as_string("res://data/world_props.json")))
static func world(chunks: Array = [["0","0"]], origin: Array = ["0","0"]):
	var w = load("res://game/world/streamed_world.gd").new(generator(),42)
	w.prepare(chunks,[],hydration(chunks),origin)
	return w
static func hydration(chunks: Array) -> Dictionary:
	var result := {}
	for chunk in chunks: result[chunk[0]+","+chunk[1]] = []
	return result
static func neighborhood() -> Array:
	var chunks: Array = []
	for y in range(-1,2):
		for x in range(-1,2): chunks.append([str(x),str(y)])
	return chunks
