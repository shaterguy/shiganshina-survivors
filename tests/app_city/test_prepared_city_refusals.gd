extends RefCounted
const Runtime = preload("res://game/app/prepared_city_runtime.gd")
const City = preload("res://game/director/streamed_chapter_provider.gd")
const Disk = preload("res://game/persistence/world_delta_store.gd")
const Save = preload("res://game/persistence/game_save_store.gd")
const Contracts = preload("res://game/contracts/game_save_contracts.gd")
const F = preload("res://tests/core/core_fixture.gd")
class RejectCore:
	extends "res://game/core/run_simulation.gd"
	func prepare_world(_state: Dictionary, _hydration: Dictionary, _commands: Array = []) -> Dictionary:
		return {"ok":false,"error_code":"world_not_ready"}
class RejectRuntime:
	extends "res://game/app/prepared_city_runtime.gd"
	func _new_core(_snapshot: Dictionary = {}): return RejectCore.new(_provider)
class FixedProvider:
	extends RefCounted
	var chapter: Dictionary
	func _init(value: Dictionary) -> void: chapter = value.duplicate(true)
	func load_chapter(_id: String) -> Dictionary: return {"ok":true,"chapter":chapter.duplicate(true)}
func run(t) -> void:
	var directory := "/tmp/prepared_city_refusal_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()]
	var chapter: Dictionary = City.new().load_chapter("chapter_01_shiganshina").chapter
	var provider := FixedProvider.new(chapter)
	var disk := Disk.new(directory.path_join("world"))
	var runtime := Runtime.new(provider,disk)
	var store := Save.new(directory,Callable(runtime,"validate_checkpoint"))
	var initial := store.load_game()
	t.check(initial.ok,"refusal fixture creates actual authority")
	if not initial.ok: return
	var config := F.run_config(); config.run_id = initial.game_save.career_id+":1"
	var state := runtime.new_run(chapter,42,config)
	t.check(disk.prepare(state.world.delta_root,[],0).ok,"refusal fixture publishes exact empty root")
	var game: Dictionary = initial.game_save.duplicate(true)
	game.next_run_serial = 2; game.checkpoint = state
	var rejected := RejectRuntime.new(provider,disk)
	t.check(rejected.validate_checkpoint(state).get("ok",false),"late-failure fixture still passes real checkpoint restore")
	t.check(rejected.prepare_commit(game).get("error_code") == "world_not_ready","false Core.prepare_world cannot be treated as restore success")
	t.check(rejected.confirm_candidate(store).get("error_code") == "no_prepared_candidate","false prepare publishes no pending B")
	t.check(rejected.refresh_coverage(state).get("error_code") == "world_not_ready","false prepare cannot release coverage replacement")
	var high := game.duplicate(true); high.store_revision = Contracts.MAX_COUNTER
	t.check(runtime.prepare_commit(high).get("error_code") == "counter_exhausted","intended commit increment respects actual Store maximum")
	t.check(runtime.prepare_commit(game).ok,"good preparation after refusal is retryable")
	t.check(store.commit_game(game,int(game.store_revision)).ok,"good fixture commits")
	# Changing a provider after private preparation must not bypass current scope.
	provider.chapter.world_definitions.templates.generator_revision = "wrong"
	t.check(not runtime.confirm_candidate(store).get("ok",false),"provider content drift blocks confirmation of old prepared pair")
	provider.chapter = chapter.duplicate(true)
	var pair := runtime.confirm_candidate(store)
	t.check(pair.get("ok",false),"same candidate confirms after original provider scope is restored")
	if not pair.get("ok",false): return
	var tick: int = pair.state.active_tick
	F.step(pair.simulation,pair.state,Vector2.RIGHT)
	t.check(pair.state.active_tick == tick+1,"released retry pair is actually ready for next tick")
	t.check(pair.game_save.checkpoint.active_tick == 0,"stepping returned state cannot mutate returned saved authority by alias")
	# A new preparation is explicit replacement; invalid requests do not poison it.
	var saved: Dictionary = store.read_game().game_save
	t.check(runtime.prepare_load(saved).ok,"existing authority prepares for load")
	var bad := saved.duplicate(true); bad.checkpoint.player.radius = 9.0
	t.check(not runtime.prepare_load(bad).get("ok",false),"invalid B fails preparation")
	t.check(runtime.confirm_candidate(store).get("ok",false),"failed preparation preserves prior valid private pair")
