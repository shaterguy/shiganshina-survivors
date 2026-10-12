extends SceneTree
const T = preload("res://tests/armored_contact_handoff/test_contact_handoff.gd")
const S = preload("res://tests/armored_actor/armored_support.gd")
const Pose = preload("res://game/presentation/armored/armored_pose.gd")
func _initialize() -> void:
 var fixture:=T.actual_contact(184.25); var pose:=Pose.new(); pose.configure(T.registration())
 var phases: Array=[]; var results: Array=[]
 for n in range(48): phases.append(float(n)*5.0)
 phases.append_array([95.999,96.,96.001,119.999,120.001,215.999,216.,216.001,239.999])
 for phase in phases:
  for travel in [0.,.01,.25,1.,3.,6.]:
   var base: Dictionary=fixture.observation.duplicate(true); base.charge_distance=240.+phase; base.last_travel=travel; base.contact.fraction=1.0
   pose.observe(base,S.actor(fixture.snapshot)); var initial: Dictionary=pose.present()
   var item:={"phase":phase,"travel":travel,"supported":initial.supported,"reason":initial.reason,"samples":[]}
   if initial.supported:
    for elapsed in [0,1,4,9,17,18,42,72,90,107]:
     var obs:=base.duplicate(true); var actor: Dictionary=S.actor(fixture.snapshot).duplicate(true)
     var recover: bool=elapsed>=18; var start: int=int(obs.contact.tick)+(18 if recover else 0)
     actor.action_state="recover" if recover else "brake"; actor.action_started_tick=start; actor.action_ends_tick=start+(90 if recover else 18)
     obs.phase=actor.action_state; obs.phase_started_tick=actor.action_started_tick; obs.phase_ends_tick=actor.action_ends_tick; obs.tick=int(obs.contact.tick)+elapsed; obs.phase_age=obs.tick-start
     pose.observe(obs,actor)
     var hash:=HashingContext.new(); hash.start(HashingContext.HASH_SHA256); hash.update(var_to_bytes([pose.present(),pose.debug_handoff()]))
     item.samples.append({"elapsed":elapsed,"sha256":hash.finish().hex_encode()})
   results.append(item)
 print("POSE_FINGERPRINT ",JSON.stringify(results))
 quit(0)
