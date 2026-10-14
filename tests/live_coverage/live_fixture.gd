extends RefCounted
const Core = preload("res://game/core/run_simulation.gd")
const City = preload("res://game/director/streamed_chapter_provider.gd")
const Runtime = preload("res://game/app/prepared_city_runtime.gd")
const Disk = preload("res://game/persistence/world_delta_store.gd")
const H = preload("res://game/core/streamed_run_world.gd")
const F = preload("res://tests/core/core_fixture.gd")
static func make(t) -> Dictionary:
	var provider := City.new()
	var chapter: Dictionary = provider.load_chapter("chapter_01_shiganshina").chapter
	var directory := "user://live_coverage_%d_%d" % [OS.get_process_id(),Time.get_ticks_usec()]
	var disk := Disk.new(directory.path_join("world"))
	var runtime := Runtime.new(provider,disk)
	var state := runtime.new_run(chapter,42,F.run_config())
	t.check(disk.prepare(state.world.delta_root,[],0).get("ok",false),"live fixture stages real exact Disk root")
	state.player.position = [0.0,192.0]
	var pair := runtime.refresh_coverage(state)
	t.check(pair.get("ok",false),"live fixture starts through original full cold admission")
	if not pair.get("ok",false): return {}
	return {"provider":provider,"chapter":chapter,"disk":disk,"runtime":runtime,"pair":pair,"directory":directory}
