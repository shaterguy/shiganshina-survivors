extends RefCounted
const T = preload("res://tests/armored_contact_handoff/test_contact_handoff.gd")
const S = preload("res://tests/armored_actor/armored_support.gd")
const Pose = preload("res://game/presentation/armored/armored_pose.gd")
const Tracker = preload("res://game/presentation/armored_motion_tracker.gd")
const C = preload("res://tests/armored_contact_input/city_fixture.gd")
var _t
var failures: Array=[]
var checks:=0
func run(t) -> void:
 _t=t
 var city:=C.new().make(self);city.state=city.previous_states[0].duplicate(true)
 check(city.core.prepare_world(city.state,C.HF.hydration(C.H.requirements(city.state))).ok,"streamed fixture prepares")
 var tracker:=Tracker.new();tracker.present(city.core.snapshot(city.state));var pose:=Pose.new();pose.configure(T.registration())
 city.state.player.position=[766.,384.]
 check(city.core.prepare_world(city.state,C.HF.hydration(C.H.requirements(city.state))).ok,"rebase shift prepares")
 for n in 8:
  var events:=S.step(city,Vector2.RIGHT);var snapshot: Dictionary=city.core.snapshot(city.state);tracker.consume(events,snapshot);pose.observe(tracker.debug_observation(),S.actor(snapshot))
 check(tracker.debug_observation().rebase_count>0,"real prior rebase was consumed")
 var chosen:={}
 for prop in city.core._streamed.props_query(Rect2(T._vec(S.actor(city.state).position)-Vector2(160,160),Vector2(640,640))).props:
  if not prop.destructible or prop.collision_mask==0:continue
  var box: Rect2=prop.ground_footprint
  var start:=Vector2(box.position.x-72.-55.25,box.get_center().y)
  var player:=Vector2(box.end.x+40.,box.get_center().y)
  if not city.core._streamed.walkable(start,32).get("walkable",false) or not city.core._streamed.walkable(player,8).get("walkable",false):continue
  if not city.core._final_contact_ready(city.state,start,Vector2.RIGHT,city.state.rules.enemy_catalog.armored_titan.action_profile,city.core._streamed).get("clear",false):continue
  chosen={"start":start,"player":player};break
 check(not chosen.is_empty(),"new attack approach found after real rebase")
 if chosen.is_empty():return
 var actor:=S.actor(city.state);actor.position=[chosen.start.x,chosen.start.y];city.state.player.position=[chosen.player.x,chosen.player.y];city.state.telegraphs.clear()
 city.core._set_action(actor,"move",int(city.state.active_tick),0);actor.next_action_tick=city.state.active_tick
 check(city.core.prepare_world(city.state,C.HF.hydration(C.H.requirements(city.state))).ok,"new attack arrangement is restore-valid")
 tracker.present(city.core.snapshot(city.state));pose.observe(tracker.debug_observation(),S.actor(city.state))
 var reached:=false
 for n in 140:
  var events:=S.step(city);var snapshot: Dictionary=city.core.snapshot(city.state);tracker.consume(events,snapshot);var obs:=tracker.debug_observation();pose.observe(obs,S.actor(snapshot))
  if events.filter(func(e):return e.type=="final_charge_contact").is_empty():continue
  reached=true
  print("REBASE_NEW_ATTACK ",JSON.stringify({"observation":obs,"supported":pose.present().supported,"reason":pose.present().reason}))
  check(obs.rebase_count>0 and pose.present().supported,"old cumulative rebase cannot reject newly observed current-origin attack contact")
  if pose.present().supported:
   load("res://tests/armored_contact_handoff/test_phase_matrix.gd").new()._all_packets(t,pose,obs,S.actor(snapshot),"actual city rebase then new attack")
   pose.observe(obs,S.actor(snapshot));var admitted: Dictionary=pose.debug_handoff().plan
   city.state.player.position=[766.,384.]
   check(city.core.prepare_world(city.state,C.HF.hydration(C.H.requirements(city.state))).ok,"post-contact rebase setup is restore-valid")
   var shifted: Dictionary={}
   for rebase_step in 8:
    var shifted_events:=S.step(city,Vector2.RIGHT);var shifted_snapshot: Dictionary=city.core.snapshot(city.state)
    tracker.consume(shifted_events,shifted_snapshot);shifted=tracker.debug_observation();pose.observe(shifted,S.actor(shifted_snapshot))
    if shifted.origin_revision>obs.origin_revision: break
   check(shifted.origin_revision==obs.origin_revision+1 and shifted.rebase_count==obs.rebase_count+1,"actual Core and tracker advance both rebase counters after contact")
   check(pose.present().supported and pose.debug_handoff().plan==admitted,"actual post-contact rebase preserves original plan and precision admission")
   check(shifted.contact.event_id==obs.contact.event_id and shifted.contact.root_position!=obs.contact.root_position,"actual post-contact rebase translates the retained same witness")
   print("ACTUAL_CACHED_REBASE ",JSON.stringify({"origin_before":obs.origin_revision,"origin_after":shifted.origin_revision,"rebases_before":obs.rebase_count,"rebases_after":shifted.rebase_count,"root_before":obs.root_position,"root_after":shifted.root_position,"supported":pose.present().supported,"reason":pose.present().reason}))
  break
 check(reached,"new actual Core attack reaches live shoulder witness")
 print("REBASE_NEW_ATTACK_RESULT checks=",checks," failures=",failures.size())
func check(value: bool,message: String) -> void:
 checks+=1
 _t.check(value,message)
 if not value:failures.append(message);push_error("FAIL: "+message)
