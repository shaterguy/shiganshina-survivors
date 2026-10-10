extends RefCounted
func run(t) -> void:
	var ui = load("res://game/ui/game_ui.gd").new()
	t.root.add_child(ui)
	t.check(ui.has_method("objective_text"),"objective guidance exists for offscreen exit")
	if ui.has_method("objective_text"):
		var sample := {"phase":"evacuation","player":{"position":[0,0]},"escape_zone":[-56,320,112,80],"survival_tick":108000}
		t.check("↓" in ui.objective_text(sample) and "선착장" in ui.objective_text(sample),"exit arrow points to actual fixed zone")
		sample.phase = "survival"
		sample.survival_tick = 17940
		t.check("00:01" in ui.objective_text(sample),"next boss countdown uses survival ticks")
	ui.free()
