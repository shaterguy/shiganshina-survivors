class_name ChapterCatalog
extends RefCounted
func load_chapter(chapter_id: String) -> Dictionary:
	if chapter_id != "chapter_01_shiganshina":
		return {"ok":false, "error_code":"unknown_chapter"}
	var file := FileAccess.open("res://chapters/chapter_01/manifest.json", FileAccess.READ)
	if file == null: return {"ok":false, "error_code":"chapter_missing"}
	var chapter = JSON.parse_string(file.get_as_text())
	if not chapter is Dictionary or chapter.get("chapter_id") != chapter_id:
		return {"ok":false, "error_code":"invalid_chapter"}
	var map = JSON.parse_string(FileAccess.get_file_as_string("res://chapters/chapter_01/map.json"))
	if not map is Dictionary or map.get("map_id") != chapter.get("map_id") or not map.has("geometry") or not load("res://game/combat/world_geometry.gd").valid(map.geometry) or map.geometry.is_empty():
		return {"ok":false,"error_code":"invalid_world_geometry"}
	chapter.world_geometry = map.geometry.duplicate(true)
	return {"ok":true,"chapter":chapter}
