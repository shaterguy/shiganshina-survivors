extends RefCounted
func run(t) -> void:
	var app = load("res://game/app/run_controller.gd").new()
	t.check(app.has_method("checkpoint_matches_chapter"),"resume checks exact chapter content revision")
	if app.has_method("checkpoint_matches_chapter"):
		var current := {"chapter_id":"chapter_01_shiganshina","content_revision":"ch01.2"}
		t.check(app.checkpoint_matches_chapter(current,current),"same content is resumable")
		t.check(not app.checkpoint_matches_chapter({"chapter_id":"chapter_01_shiganshina","content_revision":"ch01.1"},current),"old unbounded map checkpoint is not silently resumed")
		current.world_geometry = {"bounds":[-640,-300,1280,716],"obstacles":[]}
		var other := {"chapter_id":current.chapter_id,"content_revision":current.content_revision,"rules":{"world_geometry":{"bounds":[-999,-300,1998,716],"obstacles":[]}}}
		t.check(not app.checkpoint_matches_chapter(other,current),"same revision cannot inject different city bounds")
	app.free()
