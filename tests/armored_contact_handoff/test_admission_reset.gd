extends RefCounted
const T = preload("res://tests/armored_contact_handoff/test_contact_handoff.gd")
const S = preload("res://tests/armored_actor/armored_support.gd")
const Pose = preload("res://game/presentation/armored/armored_pose.gd")
const Tracker = preload("res://game/presentation/armored_motion_tracker.gd")
func run(t) -> void:
 var c:=T.actual_contact(184.25); var pose:=Pose.new(); pose.configure(T.registration())
 pose.observe(c.observation,S.actor(c.snapshot)); var valid:=pose.present()
 for value in [1,1.0,"true",[],null]:
  var bad: Dictionary=c.observation.duplicate(true); bad.charge_distance_known=value
  pose.observe(bad,S.actor(c.snapshot))
  t.check(not pose.present().supported and pose.debug_handoff().is_empty(),"stop whole-distance authority must be boolean true: "+str(value))
  pose.observe(c.observation,S.actor(c.snapshot))
  t.check(pose.present()==valid,"repaired current input remains admissible after malformed type")
 for key in ["shape","source_id"]:
  for value in [42,[],{},null,true]:
   var bad: Dictionary=c.observation.duplicate(true); bad.contact[key]=value
   pose.observe(bad,S.actor(c.snapshot))
   t.check(not pose.present().supported and pose.debug_handoff().is_empty(),"typed witness rejection clears old output: "+key+"/"+str(value))
   pose.observe(c.observation,S.actor(c.snapshot));t.check(pose.present()==valid,"valid current witness recovers after malformed "+key)
 for key in ["origin_revision","attack_started_tick","rebase_count"]:
  for value in [42.5,[],{},null,true]:
   var bad: Dictionary=c.observation.duplicate(true); bad[key]=value
   pose.observe(bad,S.actor(c.snapshot))
   t.check(not pose.present().supported and pose.debug_handoff().is_empty(),"typed observation counter fails closed: "+key+"/"+str(value))
   pose.observe(c.observation,S.actor(c.snapshot));t.check(pose.present()==valid,"valid current input recovers after bad observation counter "+key)
 var mismatched: Dictionary=c.observation.duplicate(true); mismatched.actor_id="not_current"
 pose.observe(mismatched,S.actor(c.snapshot))
 t.check(not pose.present().supported and pose.debug_handoff().is_empty(),"mismatched observation cannot expose previous handoff")
 pose.observe(c.observation,S.actor(c.snapshot)); var detached:=pose.debug_handoff(); detached.plan.entry.pelvis[0]=9999
 t.check(pose.present()==valid and pose.debug_handoff().plan.entry.pelvis[0]!=9999,"caller cannot mutate the retained contact plan")
 pose.reset()
 t.check(pose.present().reason=="no_actor" and pose.debug_handoff().is_empty() and pose._stop_key.is_empty() and pose._stop_plan.is_empty(),"explicit reset clears bounded handoff and plan")
 var cold:=Tracker.new(); cold.present(c.snapshot); pose.observe(cold.debug_observation(),S.actor(c.snapshot))
 t.check(pose.present().reason=="restored_grounded_no_impact","reset then cold adoption cannot replay old impact")
 pose.observe(c.observation,S.actor(c.snapshot))
 var changed:=T.registration(); changed.quality_holds.registration_probe={"status":"HOLD","id":"new_registration"}
 t.check(pose.configure(changed).ok and pose.present().reason=="no_actor" and pose._stop_plan.is_empty(),"successful registration replaces and clears the previous handoff")
 pose.observe(c.observation,S.actor(c.snapshot))
 t.check(pose.present().packet.quality_holds.has("registration_probe"),"first packet after registration uses new owned metadata")
 changed.quality_holds.registration_probe.id="caller_mutation"
 t.check(pose.present().packet.quality_holds.registration_probe.id=="new_registration","registration ownership is detached")
 # A reused pose receiving a new run's first contact must honor the tracker's
 # unknown historical phase instead of retaining the old same actor ID.
 var next: Dictionary=c.snapshot.duplicate(true); next.run_id="new-run"
 var events: Array[Dictionary]=c.events.duplicate(true)
 for event in events: event.event_id="new-run:"+str(event.event_id).get_slice(":",str(event.event_id).get_slice_count(":")-1)
 var tracker:=Tracker.new(); tracker.consume(events,next); pose.observe(tracker.debug_observation(),S.actor(next))
 t.check(pose.present().reason=="contact_phase_unknown" and pose.debug_handoff().is_empty(),"new run first witness cannot reuse old phase")
