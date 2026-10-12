extends RefCounted
const Core = preload("res://game/core/run_simulation.gd")
const City = preload("res://game/director/streamed_chapter_provider.gd")
const H = preload("res://game/core/streamed_run_world.gd")
const Director = preload("res://game/director/spawn_director.gd")
const F = preload("res://tests/core/core_fixture.gd")
const HF = preload("res://tests/core_world/new_streamed_helper_fixture.gd")
class ObservedCore:
 extends "res://game/core/run_simulation.gd"
 var audit: Dictionary = {}
 func _emit(state: Dictionary, events: Array[Dictionary], type: String, payload: Dictionary) -> void:
  super._emit(state,events,type,payload)
  if type == "final_charge_contact": audit.tentative = events.back().duplicate(true)
 func _auto_attack(state: Dictionary, events: Array[Dictionary], rewards: Array[Dictionary]) -> void:
  audit.phase = "auto_attack"
  super._auto_attack(state,events,rewards)
  audit.phase = "after_auto_attack"
 func _player_damage(state: Dictionary, events: Array[Dictionary]) -> void:
  audit.phase = "player_damage"
  super._player_damage(state,events)
class FaultCoverHelper:
 extends "res://game/core/streamed_run_world.gd"
 var audit: Dictionary
 func _init(definitions = null, record: Dictionary = {}):
  super._init(definitions)
  audit = record
 func fresh(): return FaultCoverHelper.new(_definitions,audit)
 func prepare(state: Dictionary, hydration: Dictionary, commands: Array = []) -> Dictionary:
  if audit.get("rebase_fault",false) and int(state.world.origin_revision) > int(audit.base_revision): return failure("world_not_ready")
  return super.prepare(state,hydration,commands)
 func cover_query(origin: Vector2, target: Vector2, radius: float, mask: int) -> Dictionary:
  if audit.get("armed",false):
   audit.injected = true
   audit.saw_tentative = audit.has("tentative")
   audit.fault_phase = audit.get("phase","")
   return _query_result(failure("invalid_query"))
  return super.cover_query(origin,target,radius,mask)
func make(t) -> Dictionary:
 var audit := {}
 var provider := City.new()
 var chapter: Dictionary = provider.load_chapter("chapter_01_shiganshina").chapter
 var core := ObservedCore.new(provider,FaultCoverHelper.new(chapter.world_definitions,audit))
 var state := core.new_run(chapter,42,F.run_config())
 state.player.position = [384.0,384.0]
 state.player.attack_ready_ticks.blade_slash = 200000
 state.active_tick = 107999; state.survival_tick = 107999
 var commands := Director.new().plan(state,chapter)
 for command in commands:
  if H.spatial_command(command): command.origin_revision = state.world.origin_revision
 t.check(core.prepare_world(state,HF.hydration(H.requirements(state,commands)),commands).get("ok",false),"real city final fixture prepares")
 F.step(core,state,Vector2.ZERO,commands)
 t.check(state.entities.size() == 1,"real final actor spawned")
 var actor: Dictionary = state.entities[0]
 var target := {}
 var origin := Vector2.ZERO
 var player := Vector2.ZERO
 for prop in core._streamed.props_query(Rect2(-512,-512,1792,1792)).props:
  if not prop.destructible or prop.collision_mask == 0: continue
  var box: Rect2 = prop.ground_footprint
  var start := box.get_center()-Vector2.RIGHT*(box.size.x/2+110)
  var finish := box.get_center()+Vector2.RIGHT*(box.size.x/2+40)
  if not Rect2(-448,-448,1664,1664).has_point(start) or not Rect2(-448,-448,1664,1664).has_point(finish): continue
  if start.distance_to(finish) <= 420 and core._streamed.walkable(start,32).get("walkable",false) and core._streamed.walkable(finish,8).get("walkable",false) and core._final_contact_ready(state,start,Vector2.RIGHT,state.rules.enemy_catalog.armored_titan.action_profile,core._streamed).get("clear",false):
   target = prop; origin = start; player = finish; break
 t.check(not target.is_empty(),"authored destructible has legal opposite approaches")
 if target.is_empty(): return {}
 actor.position = [origin.x,origin.y]
 state.player.position = [player.x,player.y]
 state.telegraphs.clear()
 core._set_action(actor,"move",int(state.active_tick),0)
 actor.next_action_tick = state.active_tick
 t.check(core.prepare_world(state,HF.hydration(H.requirements(state))).get("ok",false),"arranged real actor is accepted by full restore")
 var reached := false
 var previous_states: Array = []
 for tick in 140:
  previous_states.append(state.duplicate(true))
  if previous_states.size() > 4: previous_states.pop_front()
  actor = state.entities[0]
  if actor.action_state == "attack":
   var profile: Dictionary = state.rules.enemy_catalog.armored_titan.action_profile
   var speed: float = core._final_charge_speed(profile,int(state.active_tick)+1-int(actor.action_started_tick))
   var contact: Dictionary = core._final_contact_sweep(state,Vector2(actor.position[0],actor.position[1]),Vector2.RIGHT*speed/60.0,Vector2.RIGHT,profile,core._streamed)
   if contact.get("ok",false) and contact.get("contact",{}).get("prop_id","") == target.prop_id and contact.fraction < 1:
    reached = true; break
  F.step(core,state,Vector2.ZERO,Director.new().plan(state,chapter))
 t.check(reached,"next real tick reaches selected destructible")
 if not reached: return {}
 var root := SVector(state.entities[0].position)
 for prop in core._streamed.props_query(Rect2(root-Vector2(160,160),Vector2(640,640))).props:
  if prop.prop_id == target.prop_id: target = prop; break
 core.audit = audit
 return {"core":core,"state":state,"chapter":chapter,"provider":provider,"target":target,"audit":audit,"previous_states":previous_states}
func SVector(value: Array) -> Vector2: return Vector2(value[0],value[1])
