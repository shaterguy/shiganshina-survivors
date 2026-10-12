extends RefCounted
# NEW 2026-10-10 integration tests, not recovered game code.
const PATH := "res://game/app/prepared_city_runtime.gd"
const City = preload("res://game/director/streamed_chapter_provider.gd")
const Core = preload("res://game/core/run_simulation.gd")
const Disk = preload("res://game/persistence/world_delta_store.gd")
const Save = preload("res://game/persistence/game_save_store.gd")
const Helper = preload("res://game/core/streamed_run_world.gd")
const Checkpoint = preload("res://game/app/world_checkpoint_adapter.gd")
const Generator = preload("res://game/world/city_generator.gd")
const Current = preload("res://tests/core/current_combat_provider.gd")
const F = preload("res://tests/core/core_fixture.gd")
class BadHydration:
	extends "res://game/persistence/world_delta_store.gd"
	func hydrate(root: Dictionary, chunks: Array) -> Dictionary:
		var result := super.hydrate(root,chunks)
		if result.ok and not result.deltas.is_empty(): result.deltas[result.deltas.keys()[0]] = [{"slot_id":12,"hp":0,"destroyed":true}]
		return result
func run(t) -> void:
	t.check(FileAccess.file_exists(PATH),"prepared city runtime adapter exists")
	if not FileAccess.file_exists(PATH): return
	var script = load(PATH)
	t.check(script != null and script.can_instantiate(),"prepared city runtime compiles")
	if script == null or not script.can_instantiate(): return
	var setup := _start(t,script)
	if setup.is_empty(): return
	_failure_and_commit(t,setup)
	_closure_and_provider(t,script,setup)
	_refresh(t,setup)
func _start(t,script) -> Dictionary:
	var directory := "/tmp/prepared_city_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()]
	var provider := City.new()
	var chapter: Dictionary = provider.load_chapter("chapter_01_shiganshina").chapter
	var disk := Disk.new(directory.path_join("world"))
	var runtime = script.new(provider,disk)
	var store := Save.new(directory,Callable(runtime,"validate_checkpoint"))
	var initial := store.load_game()
	t.check(initial.ok,"real GameSave initializes career for city adapter fixture")
	if not initial.ok: return {}
	var config := F.run_config()
	config.run_id = initial.game_save.career_id+":1"
	var state: Dictionary = runtime.new_run(chapter,42,config)
	t.check(state.has("world") and state.escape_zone == Helper.CITY_INACTIVE_EXIT,"same provider factory creates city state with inactive exit")
	if not state.has("world"): return {}
	var game: Dictionary = initial.game_save.duplicate(true)
	game.next_run_serial = 2; game.checkpoint = state.duplicate(true)
	var before := game.duplicate(true)
	t.check(not runtime.prepare_commit(game).get("ok",false),"missing durable empty root is not invented by preparation")
	t.check(disk.prepare(state.world.delta_root,[],0).ok,"caller stages initial root through unchanged exact store")
	var prepared: Dictionary = runtime.prepare_commit(game)
	t.check(prepared.get("ok",false) and not prepared.has("simulation") and not prepared.has("state"),"private candidate stays unavailable before authority confirmation")
	t.check(game == before,"preparing candidate does not mutate caller GameSave or world")
	t.check(not runtime.confirm_candidate(store).get("ok",false),"uncommitted candidate cannot be published against earlier authority")
	var committed := store.commit_game(game,int(game.store_revision))
	t.check(committed.ok,"actual Store accepts prepared initial city checkpoint")
	if not committed.ok: return {}
	game.checkpoint.player.hp = 1
	var active: Dictionary = runtime.confirm_candidate(store)
	t.check(active.get("ok",false),"confirmed full authority releases matched prepared Core/state pair")
	if not active.get("ok",false): return {}
	t.check(active.game_save == committed.game_save and active.state == committed.game_save.checkpoint,"adopted state and actual GameSave agree in full; caller aliases cannot change B")
	t.check(active.simulation._streamed.readiness(active.state).ok,"released Core really owns prepared terrain")
	t.check(active.simulation._chapter_provider == provider,"private prepared Core uses exact injected provider")
	var validator := Core.new(provider)
	var hydration := disk.hydrate(state.world.delta_root,Helper.requirements(state).chunks)
	t.check(validator.restore(state,hydration.deltas).ok and not validator.world_status().get("ok",false),"control proves restore alone installs no cache")
	var replay: Dictionary = active.state.duplicate(true)
	var cold = script.new(provider,Disk.new(directory.path_join("world")))
	t.check(cold.prepare_load(active.game_save).ok,"cold load prepares at existing store revision")
	var cold_pair: Dictionary = cold.confirm_candidate(Save.new(directory,Callable(cold,"validate_checkpoint")))
	t.check(cold_pair.get("ok",false),"cold load confirms existing disk authority")
	if not cold_pair.get("ok",false): return {}
	var a := F.step(active.simulation,replay,Vector2.RIGHT)
	var b := F.step(cold_pair.simulation,cold_pair.state,Vector2.RIGHT)
	t.check(replay.active_tick == 1 and replay == cold_pair.state and a == b,"actual prepared next tick and events equal cold reload")
	return {"runtime":runtime,"store":store,"disk":disk,"provider":provider,"chapter":chapter,"directory":directory,"active":active}
func _failure_and_commit(t,s: Dictionary) -> void:
	var active: Dictionary = s.active
	var state_a: Dictionary = active.state.duplicate(true)
	var view_a: Dictionary = active.simulation._streamed.render_view(active.state)
	var helper_a = active.simulation._streamed
	var game_b: Dictionary = active.game_save.duplicate(true)
	game_b.checkpoint.player.hp = 73.0
	var generated := Generator.new(s.chapter.world_definitions.templates,s.chapter.world_definitions.props).generate(42,["0","0"])
	var selected := {}
	for prop in generated.props:
		if prop.destructible: selected = prop; break
	t.check(not selected.is_empty(),"B terrain fixture uses a real generated destructible slot")
	if selected.is_empty(): return
	game_b.checkpoint.world.world_revision = 1
	game_b.checkpoint.world.dirty_chunks = [{"chunk":["0","0"],"props":[{"slot_id":selected.slot_id,"hp":0,"destroyed":true}]}]
	t.check(not s.runtime.prepare_commit(game_b).get("ok",false),"unaccepted dirty world is not a durable checkpoint")
	var pages: Dictionary = s.disk.prepare(game_b.checkpoint.world.delta_root,game_b.checkpoint.world.dirty_chunks,1)
	var receipt := Checkpoint.accept_receipt(game_b.checkpoint.world,pages.receipt)
	game_b.checkpoint.world = receipt.world
	t.check(s.runtime.prepare_commit(game_b).ok,"B prepares its changed durable geometry privately")
	for stage in ["write","flush","verify","backup","replace"]:
		var fault := func(value): return ERR_CANT_CREATE if value == stage else OK
		var result := Save.new(s.directory,Callable(s.runtime,"validate_checkpoint"),fault).commit_game(game_b,int(game_b.store_revision))
		t.check(not result.ok and not s.runtime.confirm_candidate(s.store).get("ok",false),"failed Store stage cannot release B: "+stage)
		t.check(active.state == state_a and active.simulation._streamed == helper_a and helper_a.render_view(active.state) == view_a,"failed B preserves live A state, cache object and geometry: "+stage)
	var unknown := func(stage): return ERR_CANT_CREATE if stage == "after_replace_before_return" else OK
	var result := Save.new(s.directory,Callable(s.runtime,"validate_checkpoint"),unknown).commit_game(game_b,int(game_b.store_revision))
	t.check(result.get("error_code") == "commit_outcome_unknown","real after-rename fault returns uncertain outcome")
	var transient := func(stage): return ERR_CANT_OPEN if stage == "read_primary" else OK
	t.check(not s.runtime.confirm_candidate(Save.new(s.directory,Callable(s.runtime,"validate_checkpoint"),transient)).get("ok",false),"transient read failure retains pending pair")
	var adopted: Dictionary = s.runtime.confirm_candidate(s.store)
	t.check(adopted.get("ok",false),"same candidate resolves uncertain commit by actual readback")
	if not adopted.get("ok",false): return
	t.check(adopted.game_save.store_revision == game_b.store_revision+1 and adopted.state.player.hp == 73.0,"Store-assigned revision is matched exactly")
	t.check(adopted.simulation != active.simulation and adopted.simulation._streamed.readiness(adopted.state).ok,"B state is paired with B Core")
	t.check(active.state == state_a and active.simulation._streamed == helper_a and helper_a.render_view(active.state) == view_a,"successful B output never mutates live A")
	t.check(adopted.simulation._streamed.render_view(adopted.state) != view_a,"B cache has actual changed prop geometry")
	var next_candidate: Dictionary = adopted.game_save.duplicate(true)
	next_candidate.checkpoint.player.hp = 61.0
	t.check(s.runtime.prepare_commit(next_candidate).ok,"next candidate prepares without permanent pending lock")
	var different := next_candidate.duplicate(true)
	different.checkpoint.player.hp = 62.0
	t.check(s.store.commit_game(different,int(different.store_revision)).ok,"different valid authority has same next revision and run identity")
	t.check(s.runtime.confirm_candidate(s.store).get("error_code") == "authority_mismatch","same revision/run ID cannot authorize different full candidate")
	var observed: Dictionary = s.store.read_game().game_save
	t.check(s.runtime.prepare_load(observed).ok,"different authority can explicitly prepare a fresh pair")
	var reloaded: Dictionary = s.runtime.confirm_candidate(s.store)
	t.check(reloaded.get("ok",false) and reloaded.state.player.hp == 62.0,"explicit replacement adopts only its own prepared pair")
	s.latest = observed
func _closure_and_provider(t,script,s: Dictionary) -> void:
	var game: Dictionary = s.get("latest",s.active.game_save)
	var bad_hydration = script.new(s.provider,BadHydration.new(s.directory.path_join("world")))
	t.check(not bad_hydration.prepare_load(game).get("ok",false),"malformed hydrated props fail closed")
	var missing = script.new(s.provider,Disk.new(s.directory.path_join("missing")))
	t.check(not missing.prepare_load(game).get("ok",false),"missing world closure rejects valid GameSave")
	var finite = script.new(Current.new(),s.disk)
	t.check(not finite.prepare_load(game).get("ok",false),"finite provider cannot claim city authority")
	var wrong := game.duplicate(true)
	wrong.checkpoint.world.content_fingerprint = "0".repeat(64)
	t.check(not s.runtime.prepare_load(wrong).get("ok",false),"mismatched world fingerprint cannot prepare")
	for origin in [2147483648,9007199254740991]:
		var numeric := game.duplicate(true)
		numeric.checkpoint.world = JSON.parse_string(JSON.stringify(numeric.checkpoint.world,"",true,true))
		numeric.checkpoint.world.origin_revision = float(origin)
		var refreshed: Dictionary = s.runtime.refresh_coverage(numeric.checkpoint)
		t.check(refreshed.get("ok",false),"integral-float world and wide origin prepare: "+str(origin))
		if refreshed.get("ok",false):
			t.check(refreshed.simulation._streamed.readiness(refreshed.state).ok and refreshed.state.world.origin_revision == origin,"wide origin cache matches immediately")
			var tick: int = int(refreshed.state.active_tick)
			F.step(refreshed.simulation,refreshed.state,Vector2.RIGHT)
			t.check(refreshed.state.active_tick == tick+1,"wide origin pair executes actual next tick")
	var hash: String = game.checkpoint.world.delta_root.root_hash
	var path: String = s.directory.path_join("world/pages").path_join(hash.substr(0,2)).path_join(hash+".json")
	var bytes := FileAccess.get_file_as_bytes(path)
	var file := FileAccess.open(path,FileAccess.WRITE); file.store_string("{}"); file.close()
	var corrupt = script.new(s.provider,Disk.new(s.directory.path_join("world")))
	t.check(not corrupt.prepare_load(game).get("ok",false),"fresh closure check rejects corrupted root bytes")
	file = FileAccess.open(path,FileAccess.WRITE); file.store_buffer(bytes); file.close()
func _refresh(t,s: Dictionary) -> void:
	var state: Dictionary = s.active.state.duplicate(true)
	state.player.position = [1920.0,384.0]
	var before := state.duplicate(true)
	var disk_before := FileAccess.get_file_as_bytes(s.directory.path_join("game_save.json"))
	var active = s.active.simulation
	var helper = active._streamed
	var view: Dictionary = helper.render_view(s.active.state)
	F.step(active,state,Vector2.RIGHT)
	t.check(active.step_status().get("error_code") == "world_not_ready" and state == before,"A refuses missing coverage without consuming fixed tick/input state")
	var refreshed: Dictionary = s.runtime.refresh_coverage(state)
	t.check(refreshed.get("ok",false),"same-state refresh prepares private replacement")
	if not refreshed.get("ok",false): return
	t.check(refreshed.state == before and state == before and not refreshed.has("game_save"),"refresh preserves state and fabricates no GameSave authority")
	t.check(FileAccess.get_file_as_bytes(s.directory.path_join("game_save.json")) == disk_before,"refresh writes no economic checkpoint or revision")
	t.check(active._streamed == helper and helper.render_view(s.active.state) == view,"refresh never installs terrain on live A")
	var tick: int = int(refreshed.state.active_tick)
	F.step(refreshed.simulation,refreshed.state,Vector2.RIGHT)
	t.check(refreshed.state.active_tick == tick+1,"same input succeeds once on refreshed terrain")
	var command := {"command_id":"stale","kind":"spawn_enemy","origin_revision":1,"payload":{"entity_id":1,"enemy_id":"walker","position":[1920,384],"spawned_tick":0}}
	t.check(not s.runtime.refresh_coverage(before,[command]).get("ok",false),"stale-origin command coverage is rejected")
	command.origin_revision = before.world.origin_revision
	var ready: Dictionary = s.runtime.refresh_coverage(before,[command])
	t.check(ready.get("ok",false),"current-stamp spatial command contributes valid coverage")
	if ready.get("ok",false):
		F.step(ready.simulation,ready.state,Vector2.ZERO,[command])
		t.check(ready.state.active_tick == before.active_tick+1 and ready.state.entities.size() == 1,"current-stamp command actually executes once on prepared coverage")
