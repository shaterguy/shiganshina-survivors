extends RefCounted
const T = preload("res://tests/armored_contact_handoff/test_contact_handoff.gd")
const S = preload("res://tests/armored_actor/armored_support.gd")
const Pose = preload("res://game/presentation/armored/armored_pose.gd")
const Matrix = preload("res://tests/armored_contact_handoff/test_phase_matrix.gd")
const Tracker = preload("res://game/presentation/armored_motion_tracker.gd")
var _t
func contact_at(start: float,shift: float) -> Dictionary:
 var f:=S.make({"bounds":[-49152,-2000,98304,4000],"obstacles":[[-40.+shift,8,80,800]]},[500,500])
 S.begin(f);S.arrange_windup(f,Vector2(start+shift,0),Vector2(60.+shift,0))
 check(f.core.restore(f.state).ok,"corner fixture restore valid")
 var tracker:=Tracker.new();tracker.present(f.core.snapshot(f.state))
 for n in 150:
  var prior:=tracker.debug_observation(); var events:=S.step(f);var snapshot: Dictionary=f.core.snapshot(f.state);tracker.consume(events,snapshot)
  if events.filter(func(e):return e.type=="final_charge_contact").is_empty():continue
  var obs:=tracker.debug_observation();var profile: Dictionary=f.state.rules.enemy_catalog.armored_titan.action_profile
  var expected: float=f.core._final_charge_speed(profile,int(obs.contact.tick)-int(obs.attack_started_tick))/60.
  return {"observation":obs,"actor":S.actor(snapshot),"prior":prior,"expected":expected}
 return {}
func run(t) -> void:
 _t=t
 var seed:=contact_at(-296.25,0.); var rows: Array=[];var pose:=Pose.new();pose.configure(T.registration())
 for shift in [-48700.125,0.,48750.375]:
  for fraction in [.001,.002,.01,.1,.5,.9]:
   var c:=contact_at(float(seed.observation.root_position[0])-float(seed.prior.charge_distance)-float(seed.expected)*fraction,shift)
   check(not c.is_empty(),"corner actual contact exists")
   if c.is_empty():continue
   var obs: Dictionary=c.observation
   var estimate: float=obs.last_travel/obs.contact.fraction if obs.contact.fraction>0. else -1.
   pose.observe(obs,c.actor);var result:=pose.present();var plan: Dictionary=pose.debug_handoff().get("plan",{})
   rows.append({"shift":shift,"intended_fraction":fraction,"actual_fraction":obs.contact.fraction,"root":obs.root_position,"last_travel":obs.last_travel,"expected_step":c.expected,"inferred_step":estimate,"abs_error":absf(estimate-float(c.expected)),"supported":result.supported,"reason":result.reason,"landing_age":plan.get("landing_age"),"recoil_native":plan.get("incoming_native")})
   if result.supported:
    check(absf(estimate-float(c.expected))<.0001,"supported corner precision agrees with Core")
    Matrix.new()._all_packets(t,pose,obs,c.actor,"precision-reviewed actual corner "+str(fraction))
   if shift!=0.:check(not result.supported and result.reason=="contact_speed_precision_unresolved","large-coordinate actual corner fails closed with arithmetic precision reason")
 _rebase_confidence(t)
 print("CONTACT_PRECISION_CORNERS ",JSON.stringify({"scope":"actual_Core_near_and_49152_domain_edges","rows":rows}))
func check(value: bool,message: String) -> void:
 _t.check(value,message)
func _rebase_confidence(t) -> void:
 var c:=T.actual_contact(184.25); var pose:=Pose.new();pose.configure(T.registration())
 pose.observe(c.observation,S.actor(c.snapshot));var before:=pose.present()
 var obs: Dictionary=c.observation.duplicate(true);var actor: Dictionary=S.actor(c.snapshot).duplicate(true)
 var shift:=Vector2(-768,768)
 actor.position=[actor.position[0]+shift.x,actor.position[1]+shift.y];obs.root_position=actor.position.duplicate();obs.origin_revision+=1;obs.rebase_count=1
 for key in ["root_position","point","center"]:obs.contact[key]=[obs.contact[key][0]+shift.x,obs.contact[key][1]+shift.y]
 obs.contact.origin_revision=obs.origin_revision
 pose.observe(obs,actor)
 t.check(pose.present().supported and T._same_commands(before.packet,pose.present().packet),"known contact keeps original precision admission and local output across rebase")
 var fresh:=Pose.new();fresh.configure(T.registration());fresh.observe(obs,actor)
 t.check(not fresh.present().supported and fresh.present().reason=="contact_speed_precision_unresolved","fresh observer after rebase cannot infer original witness magnitude")
 t.check(fresh.debug_handoff().entry_pose==pose.debug_handoff().entry_pose,"precision refusal never substitutes an entry or moves root")
 fresh.observe(c.observation,S.actor(c.snapshot))
 t.check(fresh.present()==before,"resolved next current input recovers after conservative rebase refusal")
