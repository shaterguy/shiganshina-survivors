extends RefCounted
func run(t) -> void:
	t.check(ProjectSettings.get_setting("display/window/size/viewport_width") == 450,"both orientations keep450-unit short side")
	t.check(ProjectSettings.get_setting("display/window/size/viewport_height") == 450,"square base prevents portrait world zoom-out")
