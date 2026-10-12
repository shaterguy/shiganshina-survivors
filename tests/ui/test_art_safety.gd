extends RefCounted
func run(t) -> void:
	var view = load("res://game/presentation/world_view.gd").new()
	t.check(view.has_method("approved_art_id"),"renderer gates rejected art")
	if view.has_method("approved_art_id"):
		view._assets = {"titan_basic":{"path":"approved.png"},"titan_runner":{"path":"rejected.png","export_blocked":true}}
		t.check(view.approved_art_id("titan_runner") == "titan_basic","rejected clothing never renders even in development")
		t.check(view.approved_art_id("titan_basic") == "titan_basic","approved original sprite remains unchanged")
	view.free()
