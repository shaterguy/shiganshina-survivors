extends RefCounted
const T = preload("res://tests/armored_contact_handoff/test_contact_handoff.gd")
const S = preload("res://tests/armored_actor/armored_support.gd")
const Pose = preload("res://game/presentation/armored/armored_pose.gd")
const Tracker = preload("res://game/presentation/armored_motion_tracker.gd")
func run(t) -> void:
 var live:=T.actual_contact(184.25)
 var pose:=Pose.new(); pose.configure(T.registration())
 var unknown:=Tracker.new(); unknown.consume(live.events,live.snapshot)
 pose.observe(unknown.debug_observation(),S.actor(live.snapshot))
 t.check(pose.present().get("reason")=="contact_phase_unknown" and pose.debug_handoff().is_empty(),"first live unknown-distance contact cannot invent historical phase")
 var cold:=Tracker.new(); cold.present(live.snapshot); cold.consume(live.events,live.snapshot)
 pose.observe(cold.debug_observation(),S.actor(live.snapshot))
 t.check(pose.present().get("reason")=="restored_grounded_no_impact" and pose.debug_handoff().is_empty(),"cold brake suppresses old shoulder impact")
 for body in [false,true]:
  var geometry:={"bounds":[-2000,-2000,4000,4000],"obstacles":[[20,28,20,12]] if body else []}
  var f:=S.make(geometry,[500,500]); S.begin(f); S.arrange_windup(f,Vector2(-50,0),Vector2(150,0))
  var tracker:=Tracker.new(); tracker.present(f.core.snapshot(f.state)); pose.reset()
  for n in 150:
   var events:=S.step(f); var snapshot: Dictionary=f.core.snapshot(f.state)
   tracker.consume(events,snapshot); pose.observe(tracker.debug_observation(),S.actor(snapshot))
   if S.actor(snapshot).action_state=="brake": break
  t.check(pose.present().get("reason")==("body_only_stop_no_impact" if body else "free_brake_no_impact"),"body-only/free expiry distinguished without shoulder replay "+str(body))
  t.check(pose.debug_handoff().is_empty(),"no witness means no stop handoff")
 # A pure output must retain all quality failures, rather than converting a
 # numerically valid packet into visual acceptance.
 pose.observe(live.observation,S.actor(live.snapshot)); var result:=pose.present()
 t.check(result.packet.quality_holds.has("weight_support_readability") and result.packet.quality_holds.has("recovery_readability"),"weight/recovery readability remains explicitly unapproved")
 var face: Dictionary=result.packet.quality_holds.face_source_corner_reach
 t.check(face.reach>face.shoulder_limit and face.status=="HOLD" and not face.strict_gate_failure_waived,"72.657>72 source-space failure remains held")
