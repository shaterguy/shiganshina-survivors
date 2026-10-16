extends RefCounted
# Actual disk and Core A/B boundary; prop damage is an arranged storage fixture,
# not a claim of implemented Core structural combat or streamed tick execution.
const Core = preload("res://game/core/run_simulation.gd")
const City = preload("res://game/director/streamed_chapter_provider.gd")
const Helper = preload("res://game/core/streamed_run_world.gd")
const Generator = preload("res://game/world/city_generator.gd")
const Disk = preload("res://game/persistence/world_delta_store.gd")
const Save = preload("res://game/persistence/game_save_store.gd")
const Adapter = preload("res://game/app/world_checkpoint_adapter.gd")
const F = preload("res://tests/core/core_fixture.gd")
func run(t) -> void:
	var directory := "/tmp/c4_commit_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()]
	var world_dir := directory.path_join("world")
	var provider := City.new()
	var chapter: Dictionary = provider.load_chapter("chapter_01_shiganshina").chapter
	var validator := Core.new(provider)
	var disk := Disk.new(world_dir)
	var adapter := Adapter.new(disk,Callable(Helper,"requirements"),Callable(validator,"restore"))
	var store := Save.new(directory,Callable(adapter,"validate_checkpoint"))
	var initial: Dictionary = store.load_game()
	t.check(initial.get("ok",false),"actual GameSave creates its initial career authority")
	if not initial.get("ok",false): return
	var config := F.run_config()
	config.run_id = initial.game_save.career_id+":1"
	config.loot_rules_version = 1 # Newly committed departures require the current optional rule marker.
	var core_a := Core.new(provider)
	var state_a := core_a.new_run(chapter,42,config)
	var staged: Dictionary = disk.prepare(state_a.world.delta_root,[],0)
	t.check(staged.ok,"real initial root is durably staged before player authority")
	var needed := Helper.requirements(state_a)
	var hydration: Dictionary = disk.hydrate(state_a.world.delta_root,needed.chunks)
	t.check(hydration.ok and core_a.prepare_world(state_a,hydration.deltas).ok,"live A installs only verified initial terrain")
	var game: Dictionary = initial.game_save.duplicate(true)
	game.next_run_serial = 2
	game.checkpoint = state_a.duplicate(true)
	var committed: Dictionary = store.commit_game(game,int(game.store_revision))
	t.check(committed.get("ok",false),"real GameSave commits full world-bearing initial Core checkpoint")
	if not committed.get("ok",false): return
	var view_a: Dictionary = core_a._streamed.render_view(state_a)
	var status_a: Dictionary = core_a.world_status()
	var authority_a := state_a.duplicate(true)
	# Choose an actually generated destructible slot, never a synthetic unknown ID.
	var generated := Generator.new(chapter.world_definitions.templates,chapter.world_definitions.props).generate(42,["0","0"])
	var selected := {}
	for prop in generated.props:
		if prop.destructible:
			selected = prop
			break
	t.check(not selected.is_empty(),"storage fixture uses an actual generated destructible prop")
	if selected.is_empty(): return
	var state_b := state_a.duplicate(true)
	state_b.player.hp = 73.0
	state_b.world.world_revision = 1
	state_b.world.dirty_chunks = [{"chunk":["0","0"],"props":[{"slot_id":selected.slot_id,"hp":0,"destroyed":true}]}]
	var prepared_pages: Dictionary = disk.prepare(state_a.world.delta_root,state_b.world.dirty_chunks,1)
	t.check(prepared_pages.ok,"real world pages stage the arranged ruined-prop candidate")
	if not prepared_pages.ok: return
	var accepted := Adapter.accept_receipt(state_b.world,prepared_pages.receipt)
	t.check(accepted.ok,"exact receipt binds base root, dirty digest and world revision")
	state_b.world = accepted.world
	var hydrated_b: Dictionary = Disk.new(world_dir).hydrate(state_b.world.delta_root,Helper.requirements(state_b).chunks)
	var core_b := Core.new(provider)
	t.check(hydrated_b.ok and core_b.prepare_world(state_b,hydrated_b.deltas).ok,"private B independently prepares the committed-root candidate")
	t.check(core_a.world_status() == status_a and core_a._streamed.render_view(state_a) == view_a and state_a == authority_a,"preparing different B terrain preserves all A authority/cache content")
	var candidate: Dictionary = committed.game_save.duplicate(true)
	candidate.checkpoint = state_b.duplicate(true)
	for stage in ["write","flush","verify","backup","replace"]:
		var reached := [false]
		var fault := func(value):
			if value == stage:
				reached[0] = true
				return ERR_CANT_CREATE
			return OK
		var failing := Save.new(directory,Callable(adapter,"validate_checkpoint"),fault)
		var failure: Dictionary = failing.commit_game(candidate,int(candidate.store_revision))
		t.check(reached[0] and not failure.get("ok",false),"actual GameSave reaches and rejects fault stage: "+stage)
		t.check(store.load_game().game_save == committed.game_save,"failed commit preserves durable player/world A pair: "+stage)
		t.check(core_a.world_status() == status_a and core_a._streamed.render_view(state_a) == view_a and state_a == authority_a,"failed commit does not adopt B or poison A cache: "+stage)
	var next: Dictionary = store.commit_game(candidate,int(candidate.store_revision))
	t.check(next.get("ok",false),"verified B commits after all failed attempts")
	if not next.get("ok",false): return
	# Application assignment is explicit, and must swap the matched Core + state.
	var active_core = core_b
	var active_state: Dictionary = next.game_save.checkpoint
	t.check(active_core._streamed.readiness(active_state).ok and active_state == state_b,"confirmed B authority is adopted with its own matching cache")
	var fresh_core := Core.new(provider)
	var cold_adapter := Adapter.new(Disk.new(world_dir),Callable(Helper,"requirements"),Callable(fresh_core,"restore"))
	var cold_store := Save.new(directory,Callable(cold_adapter,"validate_checkpoint"))
	var reloaded: Dictionary = cold_store.load_game()
	t.check(reloaded.get("ok",false) and reloaded.game_save == next.game_save,"fresh process-style disk validator restores complete B player/world pair")
	var root_hash: String = state_b.world.delta_root.root_hash
	var page_path: String = world_dir.path_join("pages").path_join(root_hash.substr(0,2)).path_join(root_hash+".json")
	var original := FileAccess.get_file_as_bytes(page_path)
	var file := FileAccess.open(page_path,FileAccess.WRITE)
	file.store_string("{}"); file.close()
	var bad_adapter := Adapter.new(Disk.new(world_dir),Callable(Helper,"requirements"),Callable(fresh_core,"restore"))
	var corrupt: Dictionary = bad_adapter.validate_checkpoint(state_b)
	t.check(not corrupt.get("ok",false) and not corrupt.get("error_code","").is_empty(),"fresh adapter rejects corrupt nonempty-root page before Core restore")
	t.check(core_a._streamed.render_view(state_a) == view_a and state_a == authority_a,"corrupt B disk closure still cannot mutate live A cache")
	file = FileAccess.open(page_path,FileAccess.WRITE)
	file.store_buffer(original); file.close()
	var missing_dir := directory.path_join("missing-world")
	var missing_adapter := Adapter.new(Disk.new(missing_dir),Callable(Helper,"requirements"),Callable(fresh_core,"restore"))
	var missing: Dictionary = missing_adapter.validate_checkpoint(state_b)
	t.check(not missing.get("ok",false) and not missing.get("error_code","").is_empty(),"missing root file is not reinterpreted as empty generated terrain")
