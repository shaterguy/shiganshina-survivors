extends RefCounted
const Core=preload("res://game/core/run_simulation.gd")
const City=preload("res://game/director/streamed_chapter_provider.gd")
const H=preload("res://game/core/streamed_run_world.gd")
const F=preload("res://tests/core_world/new_streamed_helper_fixture.gd")
const C=preload("res://tests/core/core_fixture.gd")
func run(t) -> void:
 var provider=City.new()
 var chapter:Dictionary=provider.load_chapter("chapter_01_shiganshina").chapter
 var core=Core.new(provider)
 var state=core.new_run(chapter,42,C.run_config())
 state.world.origin_chunk=["52","0"]
 state.player.position=[45.5,384.0]
 state.player.attack_ready_ticks={"blade_slash":1000000}
 var command={"command_id":"blocked-brute","kind":"spawn_enemy","origin_revision":0,"payload":{"entity_id":288,"enemy_id":"brute","position":[129.4290771484375,106.4105224609375],"spawned_tick":1}}
 var hydration=F.hydration(H.requirements(state,[command]))
 t.check(core.prepare_world(state,hydration,[command]).get("ok",false),"exact blocked-route terrain prepares")
 C.step(core,state,Vector2.RIGHT,[command])
 t.check(core.step_status().get("ok",false) and state.active_tick==1,"normal no-route result does not freeze player or fixed tick")
 if state.active_tick!=1:return
 t.check(state.entities[0].position==[135.55201721191406,121.19259643554688] and state.entities[0].velocity==[0.0,0.0],"blocked actor waits at its real collision-valid spawn without teleporting")
 t.check(core.step_status().navigation.get("route_blocked")==1 and core._streamed.query_status().get("ok",false),"normal route-blocked diagnostic is distinct from query failure")
 C.step(core,state,Vector2.ZERO)
 t.check(core.step_status().navigation.get("route_deferred")==1,"brief retry cooldown avoids rebuilding an impossible route every tick")
 for i in 11:C.step(core,state,Vector2.ZERO)
 t.check(core.step_status().navigation.get("route_blocked")==1 and state.active_tick==13,"stationary blocked actor retries after bounded12tick wait")
 var restored=core.restore(JSON.parse_string(JSON.stringify(state,"",true,true)),hydration)
 t.check(restored.get("ok",false),"blocked movement diagnostics create no persistence authority")
