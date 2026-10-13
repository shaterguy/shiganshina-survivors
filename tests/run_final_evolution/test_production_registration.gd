extends RefCounted
const Chapters = preload("res://game/director/chapter_catalog.gd")
func run(t) -> void:
	var loaded: Dictionary = Chapters.new().load_chapter(Chapters.CHAPTER_ID)
	t.check(loaded.get("ok",false),"production chapter loads the new evolution definitions")
	if not loaded.get("ok",false): return
	var expected := ["evo_wing_cut","evo_whirlwind","evo_sky_lance","evo_echo_assault","evo_crossfire","evo_wing_squad","evo_storm_chain","evo_inferno_zone"]
	var actual: Array = loaded.chapter.evolution_ids
	t.check(actual.size() == expected.size(),"production chapter registers all eight final evolutions")
	for id in expected: t.check(id in actual,"production chapter exposes final evolution: "+id)
