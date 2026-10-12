extends RefCounted
const Runtime = preload("res://game/app/prepared_city_runtime.gd")
const City = preload("res://game/director/streamed_chapter_provider.gd")
const Disk = preload("res://game/persistence/world_delta_store.gd")
const Save = preload("res://game/persistence/game_save_store.gd")
const F = preload("res://tests/core/core_fixture.gd")
func run(t) -> void:
 var directory := "/tmp/static_los_cold_%s" % Crypto.new().generate_random_bytes(12).hex_encode()
 var provider := City.new()
 var chapter: Dictionary = provider.load_chapter("chapter_01_shiganshina").chapter
 var disk := Disk.new(directory.path_join("world"))
 var runtime := Runtime.new(provider,disk)
 var store := Save.new(directory,Callable(runtime,"validate_checkpoint"))
 var initial := store.load_game()
 t.check(initial.ok,"static LOS cold fixture initializes actual save authority")
 if not initial.ok: return
 var config := F.run_config()
 config.run_id = initial.game_save.career_id+":1"
 var state: Dictionary = runtime.new_run(chapter,42,config)
 t.check(disk.prepare(state.world.delta_root,[],0).ok,"static LOS fixture stages durable empty root")
 var pair := runtime.refresh_coverage(state)
 t.check(pair.ok,"static LOS fixture prepares actual Core and world")
 if not pair.ok: return
 var before: String = JSON.stringify(pair.state,"",true,true)
 var nav = pair.simulation._streamed._navigation
 var start := Vector2(384,384); var target := Vector2(640,384)
 t.check(nav.direction(start,target,8,0).ok and not nav._tick_los.is_empty(),"live simulation owns a warmed LOS memo")
 t.check(JSON.stringify(pair.state,"",true,true) == before,"warming LOS cannot change saved authority bytes")
 var game: Dictionary = initial.game_save.duplicate(true)
 game.next_run_serial = 2; game.checkpoint = pair.state.duplicate(true)
 var committed := store.commit_game(game,int(game.store_revision))
 t.check(committed.ok,"warmed simulation checkpoint commits through actual save contract")
 if not committed.ok: return
 var cold := Runtime.new(provider,Disk.new(directory.path_join("world")))
 t.check(cold.prepare_load(committed.game_save).ok,"cold runtime reload validates and prepares actual persisted checkpoint")
 var loaded := cold.confirm_candidate(Save.new(directory,Callable(cold,"validate_checkpoint")))
 t.check(loaded.ok,"cold runtime confirms same disk authority")
 if not loaded.ok: return
 t.check(loaded.simulation._streamed._navigation._tick_los.is_empty(),"cold persisted restore never imports a prior LOS memo")
 var warm_events := F.step(pair.simulation,pair.state,Vector2.RIGHT)
 var cold_events := F.step(loaded.simulation,loaded.state,Vector2.RIGHT)
 t.check(pair.state == loaded.state and warm_events == cold_events,"actual next Core state and events match warm versus cold navigation")
 t.check(pair.simulation.step_status() == loaded.simulation.step_status(),"warm versus cold restore retains exact step status")
