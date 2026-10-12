extends RefCounted
func run(t) -> void:
	var path := "res://game/presentation/audio_director.gd"
	t.check(FileAccess.file_exists(path),"audio director exists")
	if not FileAccess.file_exists(path): return
	var a = load(path).new()
	t.check(a.sound_for_event({"type":"damage","payload":{"target_id":"player","source_id":"enemy"}}) == "hurt","player damage sound")
	t.check(a.sound_for_event({"type":"damage","payload":{"target_id":1,"source_id":"wall_cannon"}}) == "cannon","cannon uses own sound")
	t.check(a.sound_for_event({"type":"run_ended","payload":{"result":"won"}}) == "victory","victory sound")
	t.check(a.sound_for_event({"type":"unknown","payload":{}}) == "","unknown event silent")
	a.free()
