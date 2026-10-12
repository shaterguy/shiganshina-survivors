extends RefCounted
# Exercises the real WorldView atlas/distance methods with the exact staged
# registration. This injects only an in-memory candidate, never a manifest write.
func run(t) -> void:
	var registration = JSON.parse_string(FileAccess.get_file_as_string("res://docs/art/recovery-armored-v6-registration.json"))
	t.check(registration is Dictionary,"recovered Armored registration parses")
	if not registration is Dictionary: return
	var record: Dictionary = registration.candidate_entry
	var image := Image.new()
	var result := image.load_png_from_buffer(FileAccess.get_file_as_bytes(record.path))
	t.check(result == OK,"recovered Armored PNG decodes through Godot")
	if result != OK: return
	t.check(image.get_size() == Vector2i(1536,2560),"recovered Armored Godot image has exact atlas dimensions")
	t.check(FileAccess.get_sha256(record.path) == "e3b3fe2008cb4db79e8df72bf670dc6c87e37c81c055c85a1546fc47dc7ea427","Godot checks byte-exact recovered Armored identity")
	var fixture = load("res://tests/ui/test_distance_gait.gd").new()
	var view = fixture._view()
	view.load_manifest()
	var baseline: Dictionary = view._assets.armored_titan.duplicate(true)
	view._assets.armored_titan = record.duplicate(true)
	for offset in range(64):
		var frame := 12+offset
		var expected := Rect2((frame%8)*192,(frame/8)*256,192,256)
		t.check(view.frame_rect("armored_titan","move",(float(offset)+0.25)/64.0) == expected,"recovered move selects exact 8-column cell %d"%frame)
	t.check(view.frame_rect("armored_titan","move",1.0) == Rect2(768,256,192,256),"recovered move loops from75 to12 without padding")
	for name in ["idle","hit","windup","attack","entry","retreat"]:
		var animation: Dictionary = record.animations[name]
		for offset in range(animation.frames.size()):
			var frame := int(animation.frames[offset])
			var expected := Rect2((frame%8)*192,(frame/8)*256,192,256)
			t.check(view.frame_rect("armored_titan",name,(float(offset)+0.25)/float(animation.fps)) == expected,"preserved %s uses its original frame meaning in eight columns"%name)
	var snapshot: Dictionary = fixture._snapshot(0,0.0,[fixture._enemy(7,100.0)])
	snapshot.rules.enemy_catalog.basic.art_id = "armored_titan"
	view.present(snapshot)
	for tick in range(1,9):
		snapshot = fixture._snapshot(tick,0.0,[fixture._enemy(7,100.0+float(tick)*7.71)])
		snapshot.rules.enemy_catalog.basic.art_id = "armored_titan"
		view.present(snapshot)
	var seconds: float = view.movement_seconds("armored_titan","entity:7",1.0,99.0)
	t.check(view.frame_rect("armored_titan","move",seconds) == Rect2(768,1280,192,256),"recovered native stride reaches opposite stance from real observed entity displacement")
	var scaled_seconds: float = view.movement_seconds("armored_titan","entity:7",2.0,99.0)
	t.check(view.frame_rect("armored_titan","move",scaled_seconds) == Rect2(768,768,192,256),"recovered native stride is scaled exactly once for displayed size")
	snapshot = fixture._snapshot(9)
	snapshot.phase = "evacuation"
	view.present(snapshot)
	t.check(not view.capture().any(func(sprite): return sprite.asset == "armored_titan"),"final phase cannot fabricate an Armored sprite without the physical actor")
	var final_actor: Dictionary = fixture._enemy(8,100.0,"brake",9)
	final_actor.enemy_id = "armored_titan"
	final_actor.boss_id = "ch01_final_armored"
	final_actor.velocity = [0.0,0.0]
	snapshot.entities = [final_actor]
	snapshot.rules.enemy_catalog.armored_titan = {"art_id":"armored_titan"}
	view.present(snapshot)
	var found_final := false
	for sprite in view.capture():
		if sprite.asset == "armored_titan":
			found_final = true
			t.check(sprite.animation == "idle" and sprite.region == Rect2(0,0,192,256) and sprite.world == Vector2(100,100),"physical final actor brakes at its authoritative position with preserved idle frame")
	t.check(found_final,"physical final actor was actually selected by WorldView draw")
	t.check(not record.animations.has("death") and not record.animations.has("run") and not record.animations.has("charge"),"recovered WALK does not fabricate death or missing run/charge states")
	var disk_manifest = JSON.parse_string(FileAccess.get_file_as_string("res://assets/manifest.json"))
	t.check(disk_manifest.assets.armored_titan == baseline,"candidate injection never mutates the disk manifest")
	view.free()
