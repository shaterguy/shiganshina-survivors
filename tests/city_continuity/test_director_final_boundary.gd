extends RefCounted
# NEW actual Director -> Core -> passage/dock -> exact 75-second regression.
# Only the survival clock precondition and per-tick HP refill are arranged.
const Core=preload("res://game/core/run_simulation.gd")
const City=preload("res://game/director/streamed_chapter_provider.gd")
const H=preload("res://game/core/streamed_run_world.gd")
const D=preload("res://game/director/spawn_director.gd")
const F=preload("res://tests/core/core_fixture.gd")
const Disk=preload("res://game/persistence/world_delta_store.gd")
func run(t)->void:
 _mode(t,false)
 _mode(t,true)
func _mode(t,city:bool)->void:
 var label="city" if city else "finite"
 var provider=City.new() if city else null
 var chapter:Dictionary=provider.load_chapter("chapter_01_shiganshina").chapter if city else F.v2_chapter()
 var core=Core.new(provider) if city else Core.new()
 var state:Dictionary=core.new_run(chapter,42,F.run_config())
 state.active_tick=107999
 state.survival_tick=107999
 if city:state.player.position=[384.0,384.0]
 var disk=Disk.new("/tmp/city_director_final_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()])
 if city:disk.prepare(state.world.delta_root,[],0)
 var director=D.new()
 var before=state.duplicate(true)
 var commands:Array[Dictionary]=director.plan(state,chapter)
 t.check(state==before,label+" Director planning leaves live authority unchanged")
 t.check(commands.size()==1 and commands[0].kind=="begin_evacuation",label+" actual Director schedules final boundary command")
 t.check(commands[0].payload.escape_zone==state.escape_zone,label+" final command uses current validated escape zone")
 var alias_state=state.duplicate(true)
 var alias_test:Array[Dictionary]=director.plan(alias_state,chapter.duplicate(true))
 alias_test[0].payload.escape_zone[0]+=1
 t.check(alias_state==before,label+" planned final command does not alias authority escape array")
 var events=_step(core,state,director,chapter,disk,Vector2.ZERO)
 var began=state.phase=="evacuation" and state.final_started_tick==108000
 t.check(began,label+" actual Director advances Core into evacuation exactly at108000")
 if not began:return
 t.check(F.types(events,"boss_spawned").size()==1 and F.types(events,"phase_changed").size()==1 and state.boss_ids_fired==["ch01_final_armored"],label+" final threat and phase event occur once")
 if city:
  t.check(state.escape_zone==[0.0,0.0,0.0,0.0] and not state.evacuation_ready,"city final keeps inactive escape sentinel")
  var passage=core._streamed.passage_proposal(state)
  t.check(passage.get("ok",false),"real prepared Helper selects final passage")
  if not passage.get("ok",false):return
  state.world=passage.world
  var passage_hydration=disk.hydrate(state.world.delta_root,H.requirements(state).chunks)
  t.check(core.prepare_world(state,passage_hydration.deltas).get("ok",false),"selected passage candidate prepares against actual geometry")
  var command={"command_id":"final-boundary-dock","kind":"dock_transition","origin_revision":state.world.origin_revision,"payload":{"passage_id":state.world.evacuation.passage_id}}
  var proposal=core._streamed.dock_transition_proposal(state,command,chapter.authored_dock)
  t.check(proposal.get("ok",false) and not proposal.get("idempotent",true),"physical passage overlap yields real dock handoff")
  if not proposal.get("ok",false):return
  var final_actor=core.final_actor_handoff(state,chapter.authored_dock)
  t.check(final_actor.get("ok",false),"safe boundary prepares exact physical final actor handoff")
  if not final_actor.get("ok",false):return
  state.world=proposal.candidate_world
  state.player.position=[proposal.player_position.x,proposal.player_position.y]
  state.escape_zone=chapter.authored_dock.escape_rect.duplicate()
  for collection in proposal.retire_ids:
   if state.has(collection):state[collection].clear()
  state.entities.append(final_actor.entity)
  state.telegraphs.append_array(final_actor.telegraphs)
  var prepared=core.prepare_world(state,{})
  t.check(prepared.get("ok",false),"actual dock candidate prepares with retained physical final actor")
  if not prepared.get("ok",false):return
  t.check(state.final_started_tick==108000 and state.active_tick==108000,"dock handoff preserves final clock")
  var duplicate=core._streamed.dock_transition_proposal(state,command,chapter.authored_dock)
  t.check(duplicate.get("ok",false) and duplicate.get("idempotent",false) and duplicate.event.is_empty(),"same dock command is an idempotent no-event retry")
 var final_events=1
 var phase_events=1
 for age in 4500:
  state.player.hp=state.player.max_hp
  var move=Vector2.DOWN if state.player.position[1]<350.0 else Vector2.ZERO
  events=_step(core,state,director,chapter,disk,move)
  final_events+=F.types(events,"boss_spawned").size()
  phase_events+=F.types(events,"phase_changed").size()
  if age==4498:t.check(state.active_tick==112499 and state.phase=="evacuation" and not state.evacuation_ready,label+" physical exit cannot win before75seconds")
 t.check(state.active_tick==112500 and state.phase=="won" and state.evacuation_ready,label+" actual movement and Director final hazards reach exact75second win")
 t.check(F.types(events,"run_ended").size()==1 and final_events==1 and phase_events==1,label+" win final threat and phase events occur once")
 var restored=core.restore(JSON.parse_string(JSON.stringify(state,"",true,true)))
 t.check(restored.get("ok",false) and core._same_json(restored.state,state),label+" completed final path cold-restores with exact JSON numeric semantics")
func _step(core,state:Dictionary,director,chapter:Dictionary,disk,move:Vector2)->Array:
 var commands:Array[Dictionary]=director.plan(state,chapter)
 if state.has("world"):
  for command in commands:
   if H.spatial_command(command):command.origin_revision=state.world.origin_revision
 var events=core.step(state,move,commands)
 if not state.has("world") or core.step_status().get("error_code")!="world_not_ready":return events
 var needed=H.requirements(state,commands)
 if not needed.get("ok",false):return []
 var hydration=disk.hydrate(state.world.delta_root,needed.chunks)
 if not hydration.get("ok",false):return []
 if not core.prepare_world(state,hydration.deltas,commands).get("ok",false):return []
 return core.step(state,move,commands)
