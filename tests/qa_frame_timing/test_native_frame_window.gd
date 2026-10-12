extends RefCounted
const Scene = preload("res://tools/qa/city_play_validation.gd")

func run(t) -> void:
	var scene = Scene.new()
	t.check(scene.has_method("_record_frame_delta"),"native city QA records actual frame intervals")
	if not scene.has_method("_record_frame_delta"):
		scene.free()
		return
	scene._record_frame_delta(0.016,false)
	scene._record_frame_delta(0.020,true)
	scene._record_frame_delta(0.060,true)
	var first: Dictionary = scene._take_frame_metrics()
	t.check(first.frames == 3 and first.playing_frames == 2,"pause and playing samples are distinguished")
	t.check(is_equal_approx(first.max_ms,60.0) and is_equal_approx(first.playing_max_ms,60.0),"long real frame is retained")
	t.check(first.over_50_ms == 1 and first.playing_over_50_ms == 1,"visible stall count is explicit")
	t.check(is_equal_approx(first.mean_ms,32.0) and is_equal_approx(first.playing_mean_ms,40.0),"means use measured deltas")
	var empty: Dictionary = scene._take_frame_metrics()
	t.check(empty.frames == 0 and empty.max_ms == 0.0 and empty.playing_mean_ms == 0.0,"drained window resets without division by zero")
	scene._record_frame_delta(0.5,false)
	var paused: Dictionary = scene._take_frame_metrics()
	t.check(paused.over_50_ms == 1 and paused.playing_over_50_ms == 0,"menu stalls do not count as active gameplay stalls")
	scene.free()
