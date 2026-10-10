extends RefCounted
func run(t) -> void:
	var path := "res://game/presentation/world_view.gd"
	t.check(FileAccess.file_exists(path),"WorldView exists")
	if not FileAccess.file_exists(path): return
	var script = load(path)
	t.check(script != null and script.can_instantiate(),"WorldView compiles")
	if script == null or not script.can_instantiate(): return
	var view = script.new()
	view.load_manifest()
	var rect: Rect2 = view.frame_rect("garrison_01","move",0.0)
	t.check(rect == Rect2(128,0,64,64),"renderer consumes row-major64px manifest")
	t.check(view.frame_rect("missing","move",0) == Rect2(),"unknown asset never fabricates sprite")
	t.check(view.has_method("telegraph_pieces"),"danger geometry renderer available")
	if view.has_method("telegraph_pieces"):
		var line: Array = view.telegraph_pieces({"shape":"line","length":240.0,"width":40.0})
		t.check(line.size() == 3,"line uses three-slice capsule")
		t.check(line[0].rect == Rect2(-20,-20,20,40) and line[1].rect == Rect2(0,-20,240,40) and line[2].rect == Rect2(240,-20,20,40),"capsule footprint matches core length and radius")
		var circle: Array = view.telegraph_pieces({"shape":"circle","radius":56.0})
		t.check(circle[0].rect == Rect2(-56,-56,112,112),"circle danger radius exact")
		var sector: Array = view.telegraph_pieces({"shape":"sector","radius":180.0,"arc_degrees":150.0})
		t.check(sector.size() == 2 and is_equal_approx(sector[0].rotation,-PI/6) and is_equal_approx(sector[1].rotation,PI/6),"broad sector union has exact150-degree footprint")
	view.free()
