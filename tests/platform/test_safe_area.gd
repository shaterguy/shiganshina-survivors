extends RefCounted
func run(t) -> void:
	var path := "res://game/input/lifecycle_guard.gd"
	t.check(FileAccess.file_exists(path),"lifecycle geometry guard exists")
	if not FileAccess.file_exists(path): return
	var guard = load(path).new()
	var mapped: Rect2i = guard.map_safe_area(Vector2i(800,450),Vector2i(2400,1350),Rect2i(90,0,2220,1350),Vector2i.ZERO)
	t.check(mapped == Rect2i(30,0,740,450),"physical notch inset maps to logical viewport")
	mapped = guard.map_safe_area(Vector2i(450,800),Vector2i(1080,1920),Rect2i(0,72,1080,1800),Vector2i.ZERO)
	t.check(mapped == Rect2i(0,30,450,750),"portrait inset maps without resetting world")
