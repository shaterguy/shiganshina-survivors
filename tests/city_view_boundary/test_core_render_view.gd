extends RefCounted
# NEW read-only presentation boundary; no application activation or save writes.
const Core = preload("res://game/core/run_simulation.gd")
const City = preload("res://game/director/streamed_chapter_provider.gd")
const F = preload("res://tests/core/core_fixture.gd")
const Helper = preload("res://game/core/streamed_run_world.gd")
const Disk = preload("res://game/persistence/world_delta_store.gd")
func run(t) -> void:
	var provider = City.new()
	var core = Core.new(provider)
	t.check(core.has_method("world_render_view"),"Core exposes prepared-only terrain render view")
	if not core.has_method("world_render_view"): return
	var chapter: Dictionary = provider.load_chapter("chapter_01_shiganshina").chapter
	var state: Dictionary = core.new_run(chapter,17,F.run_config())
	t.check(not core.world_render_view(state).ok,"unprepared Core cannot expose fabricated city terrain")
	var disk = Disk.new("/tmp/city_render_boundary_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()])
	t.check(disk.prepare(state.world.delta_root,[],0).ok,"actual empty root is durable before hydration")
	var hydration: Dictionary = disk.hydrate(state.world.delta_root,Helper.requirements(state).chunks)
	var prepared: Dictionary = core.prepare_world(state,hydration.get("deltas",{}))
	t.check(hydration.get("ok",false) and prepared.get("ok",false),"real generated terrain is prepared from verified hydration")
	if not prepared.get("ok",false): return
	var before := state.duplicate(true)
	var view: Dictionary = core.world_render_view(state)
	t.check(view.get("ok",false) and view.stage == "city" and not view.chunks.is_empty(),"prepared render view contains real generated chunks")
	if not view.get("ok",false): return
	t.check(view.origin_chunk == state.world.origin_chunk and view.origin_revision == state.world.origin_revision,"view carries current authoritative local origin")
	t.check(state == before,"render extraction cannot change RunState")
	var saved := view.duplicate(true)
	view.chunks.clear()
	t.check(core.world_render_view(state) == saved,"returned render data cannot corrupt prepared geometry")
	var stale := state.duplicate(true)
	stale.world.origin_revision += 1
	t.check(not core.world_render_view(stale).ok,"stale origin cannot observe mismatched terrain")
	t.check(core.world_render_view(state) == saved,"failed stale query preserves prepared view")
	var finite = Core.new()
	t.check(not finite.world_render_view({}).ok,"finite/unprepared Core never synthesizes a city view")
