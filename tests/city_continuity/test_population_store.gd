extends RefCounted
# NEW exact Store/PreparedRuntime compatibility exercise for world-v2 only.
const Runtime=preload("res://game/app/prepared_city_runtime.gd")
const Store=preload("res://game/persistence/game_save_store.gd")
const Disk=preload("res://game/persistence/world_delta_store.gd")
const City=preload("res://game/director/streamed_chapter_provider.gd")
const H=preload("res://game/core/streamed_run_world.gd")
const C=preload("res://tests/core/core_fixture.gd")
func run(t) -> void:
 var directory="/tmp/city_population_store_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()]
 var provider=City.new()
 var chapter:Dictionary=provider.load_chapter("chapter_01_shiganshina").chapter
 var disk=Disk.new(directory.path_join("world"))
 var runtime=Runtime.new(provider,disk)
 var store=Store.new(directory,Callable(runtime,"validate_checkpoint"))
 var initial=store.load_game()
 t.check(initial.get("ok",false),"world-v2 Store fixture initializes a real career")
 if not initial.get("ok",false):return
 var config=C.run_config()
 config.run_id=initial.game_save.career_id+":1"
 var state:Dictionary=runtime.new_run(chapter,42,config)
 t.check(disk.prepare(state.world.delta_root,[],0).get("ok",false),"world-v2 Store fixture stages its real empty terrain root")
 var game:Dictionary=initial.game_save.duplicate(true)
 game.next_run_serial=2
 game.checkpoint=state
 var prepared=runtime.prepare_commit(game)
 var started=store.commit_game(game,game.store_revision)
 print("POPULATION_STORE_INITIAL ",prepared," commit=",started.get("error_code", "ok")," errors=",started.get("errors",[]))
 t.check(prepared.get("ok",false) and started.get("ok",false),"world-v1 initial run commits before population transition")
 var active:Dictionary=runtime.confirm_candidate(store)
 t.check(active.get("ok",false),"world-v1 authority confirms its prepared Core")
 if not active.get("ok",false):return
 state=active.state
 state.player.position=[384.0,384.0]
 state.player.attack_ready_ticks={"blade_slash":1000000}
 state.active_tick=17999
 state.survival_tick=17999
 state.drops=[{"id":100,"position":[-1152.0,384.0],"xp":7}]
 state.next_entity_id=101
 var command={"command_id":"persisted-far-boss","kind":"spawn_boss","origin_revision":0,"payload":{"entity_id":"persisted-far-boss","enemy_id":"boss_charger","boss_id":"ch01_b05","position":[-1154.0,384.0],"scheduled_tick":18000}}
 var hydrated=disk.hydrate(state.world.delta_root,H.requirements(state,[command]).chunks)
 t.check(active.simulation.prepare_world(state,hydrated.deltas,[command]).get("ok",false),"parked Store fixture prepares real geometry")
 C.step(active.simulation,state,Vector2.ZERO,[command])
 C.step(active.simulation,state,Vector2.ZERO)
 t.check(state.world.schema_version==2 and state.world.dormant.entities.size()==1 and state.world.dormant.drops.size()==1,"real successful parking creates the world-v2 checkpoint")
 game=active.game_save.duplicate(true)
 game.checkpoint=state.duplicate(true)
 t.check(runtime.prepare_commit(game).get("ok",false),"PreparedRuntime accepts world-v2 dormant authority")
 var committed=store.commit_game(game,game.store_revision)
 t.check(committed.get("ok",false),"actual GameSaveStore commits world-v2 without top-level schema migration")
 if not committed.get("ok",false):return
 var adopted=runtime.confirm_candidate(store)
 t.check(adopted.get("ok",false) and adopted.state==state,"confirmed world-v2 prepared pair matches full persisted authority")
 var cold=Runtime.new(City.new(),Disk.new(directory.path_join("world")))
 var cold_store=Store.new(directory,Callable(cold,"validate_checkpoint"))
 var loaded=cold_store.load_game()
 t.check(loaded.get("ok",false) and loaded.game_save.profile==initial.game_save.profile and loaded.game_save.career_id==initial.game_save.career_id,"cold world-v2 load preserves career/profile authority")
 if not loaded.get("ok",false):return
 t.check(cold.prepare_load(loaded.game_save).get("ok",false),"cold runtime prepares persisted dormant boss and XP")
 var resumed=cold.confirm_candidate(cold_store)
 t.check(resumed.get("ok",false) and resumed.state==state,"cold world-v2 confirmation retains exact dormant identities and absolute addresses")
 if not resumed.get("ok",false):return
 var a=C.step(adopted.simulation,adopted.state,Vector2.LEFT)
 var b=C.step(resumed.simulation,resumed.state,Vector2.LEFT)
 t.check(adopted.state==resumed.state and a==b and adopted.state.active_tick==18002,"live and real Store-resumed next tick/events match")
 # A newer world authority must not silently fall back to the older v1 backup.
 var future:Dictionary=loaded.game_save.duplicate(true)
 future.checkpoint.world.schema_version=3
 var path=directory.path_join("game_save.json")
 var bytes=JSON.stringify(future,"",true,true)
 var file=FileAccess.open(path,FileAccess.WRITE)
 file.store_string(bytes)
 file.close()
 var refused=cold_store.load_game()
 t.check(refused.get("error_code")=="unsupported_schema" and not refused.get("ok",false),"future world schema is a real Store compatibility barrier, never backup recovery")
 t.check(FileAccess.get_file_as_string(path)==bytes,"unknown future world bytes remain intact")
