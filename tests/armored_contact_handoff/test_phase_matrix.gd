extends RefCounted
const T = preload("res://tests/armored_contact_handoff/test_contact_handoff.gd")
const S = preload("res://tests/armored_actor/armored_support.gd")
const Pose = preload("res://game/presentation/armored/armored_pose.gd")
const Charge = preload("res://game/presentation/armored/armored_charge_curve.gd")
func run(t) -> void:
 var fixture:=T.actual_contact(184.25); var pose:=Pose.new(); pose.configure(T.registration())
 var phases: Array=[]
 for n in range(48): phases.append(float(n)*5.0)
 phases.append_array([95.999,96.0,96.001,119.999,120.001,215.999,216.0,216.001,239.999])
 var reasons: Dictionary={}; var supported: Dictionary={"right":0,"left":0}; var cases: Array=[]
 # These are labelled pure-input phase/speed probes. They do not claim that
 # Core generated these synthetic distance values at this fixed witness.
 for phase_distance in phases:
  for travel in [0.0,.01,.25,1.0,3.0,6.0]:
   var obs: Dictionary=fixture.observation.duplicate(true); obs.charge_distance=240.0+phase_distance; obs.last_travel=travel; obs.contact.fraction=1.0
   pose.observe(obs,S.actor(fixture.snapshot)); var result:=pose.present(); var handoff:=pose.debug_handoff()
   var label:="phase="+str(phase_distance/240.0)+" travel="+str(travel)
   var record:={"phase":phase_distance/240.0,"last_travel":travel,"supported":result.supported,"reason":result.reason}
   t.check(not result.reason.is_empty() or result.supported,"every rejection has specific diagnosis "+label)
   if result.supported:
    supported[handoff.plan.support_side]+=1
    record.support=handoff.plan.support_side; record.landing_age=handoff.plan.landing_age
    t.check(handoff.entry_pose==Charge.new().sample(obs.charge_distance).pose,"no nearest authored contact selected "+label)
    _check_plan(t,pose,handoff.plan,label)
    _all_packets(t,pose,obs,S.actor(fixture.snapshot),label)
   else:
    reasons[result.reason]=int(reasons.get(result.reason,0))+1
    t.check(not result.has("packet"),"unsupported is not a frozen old packet "+label)
    if handoff.has("plan"): record.diagnostic=handoff.plan
   cases.append(record)
 t.check(supported.right>0 and supported.left>0,"numeric feasible set includes near- and far-support cases")
 t.check(reasons.has("contact_phase_flight") and reasons.has("contact_landing_exceeds_brake") and reasons.has("contact_support_transition") and reasons.has("contact_zero_travel_phase_step"),"flight, touchdown, slow landing and zero step remain separately diagnosed")
 print("CONTACT_PHASE_SWEEP ",JSON.stringify({"scope":"pure_input_not_core_trace","samples":cases.size(),"supported":supported,"reasons":reasons,"cases":cases}))
 # Exact half-cycle boundaries are unsupported; neither arbitrary root shifts
 # nor attachment changes are used to turn flight into planted support.
 for distance in [96.,98.,110.,216.,230.]:
  var obs: Dictionary=fixture.observation.duplicate(true); obs.charge_distance=distance; obs.last_travel=3.0
  pose.observe(obs,S.actor(fixture.snapshot))
  t.check(pose.present().reason=="contact_phase_flight","exact airborne phase rejected "+str(distance))
 var actual: Array=[]; var actual_supported: Dictionary={"right":0,"left":0}
 for distance in [35.25,55.25,75.25,85.25,95.999,96.0,110.25,120.25,145.25,164.25,174.25,184.25,194.25,205.25,216.,230.25]:
  for facing in [1.0,-1.0]:
   var live:=T.actual_contact(distance,facing)
   t.check(not live.is_empty(),"actual horizontal Core contact exists "+str(distance)+"/"+str(facing))
   if live.is_empty(): continue
   pose.reset(); pose.observe(live.observation,S.actor(live.snapshot)); var result:=pose.present(); var handoff:=pose.debug_handoff()
   t.check(live.observation.contact.locked_direction==[facing,0.0],"actual Core left/right direction, not image-only mirror")
   t.check(handoff.entry_pose==Charge.new().sample(live.observation.charge_distance).pose,"real whole distance produces exact incoming pose")
   t.check(T._vec(handoff.prior_root).is_equal_approx(T._vec(S.actor(live.before).position)),"actual prior root from final partial movement")
   if result.supported:
    actual_supported[handoff.plan.support_side]+=1
    _all_packets(t,pose,live.observation,S.actor(live.snapshot),"actual "+str(distance)+"/"+str(facing))
    t.check(result.flip==(facing<0.0) and result.root_position==T._vec(S.actor(live.snapshot).position),"real direction/root paired with output")
   actual.append({"requested_distance":distance,"direction":facing,"actual_distance":live.observation.charge_distance,"last_travel":live.observation.last_travel,"fraction":live.observation.contact.fraction,"supported":result.supported,"reason":result.reason,"phase":handoff.entry_pose.phase})
 t.check(actual_supported.right>0 and actual_supported.left>0,"actual Core contacts include feasible near and far support")
 print("CONTACT_ACTUAL_SWEEP ",JSON.stringify({"scope":"public_Core_steps","supported":actual_supported,"cases":actual}))
func _check_plan(t,pose,plan: Dictionary,label: String) -> void:
 var base: Dictionary=plan.entry
 for age in [0.,.125,1.,4.,9.,float(plan.landing_age),17.]:
  var sample: Dictionary=pose._brake(age,plan)
  t.check(sample.ok,"brake plan remains reachable "+label+" age="+str(age))
  if not sample.ok: continue
  var support: Dictionary=sample.pose[plan.support_side+"_leg"]
  t.check(support.ankle==base[plan.support_side+"_leg"].ankle and support.foot_angle==base[plan.support_side+"_leg"].foot_angle,"same planted foot stays exact in local/world X "+label)
  for side in ["right","left"]:
   _lengths(t,sample.pose[side+"_leg"],["hip","knee","ankle"],[60.5,60.5],label)
   _lengths(t,sample.pose[side+"_arm"],["shoulder","elbow","wrist"],[39.,35.],label)
 for age in [0.,24.,24.125,54.,71.875,72.,89.]:
  var sample: Dictionary=pose._recovery(age,plan)
  t.check(sample.ok,"recovery plan remains reachable "+label+" age="+str(age))
  if not sample.ok: continue
  t.check(sample.pose[plan.front_side+"_leg"].ankle==plan.settled.pose[plan.front_side+"_leg"].ankle,"recovery supporting foot stays anchored "+label)
  for side in ["right","left"]:
   _lengths(t,sample.pose[side+"_leg"],["hip","knee","ankle"],[60.5,60.5],label)
   _lengths(t,sample.pose[side+"_arm"],["shoulder","elbow","wrist"],[39.,35.],label)
func _lengths(t,limb: Dictionary,joints: Array,lengths: Array,label: String) -> void:
 for i in range(2): t.check(absf(T._vec(limb[joints[i]]).distance_to(T._vec(limb[joints[i+1]]))-lengths[i])<.0001,"fixed length without reach clamp "+label)

func _all_packets(t,pose,entry_observation: Dictionary,entry_actor: Dictionary,label: String) -> void:
 for elapsed in range(108):
  var obs:=entry_observation.duplicate(true); var actor:=entry_actor.duplicate(true)
  var recover:=elapsed>=18; var start: int=int(obs.contact.tick)+(18 if recover else 0)
  actor.action_state="recover" if recover else "brake"; actor.action_started_tick=start; actor.action_ends_tick=start+(90 if recover else 18)
  obs.phase=actor.action_state; obs.phase_started_tick=actor.action_started_tick; obs.phase_ends_tick=actor.action_ends_tick
  obs.tick=int(obs.contact.tick)+elapsed; obs.phase_age=obs.tick-start
  pose.observe(obs,actor); var result: Dictionary=pose.present()
  t.check(result.supported,"whole integer packet sequence cannot silently fall back "+label+" elapsed="+str(elapsed)+" "+result.reason)
  if not result.supported: continue
  t.check(result.packet.canvas_contained and result.packet.commands.size()==17,"complete neck/limb packet stays inside target "+label)
  t.check(result.root_position==T._vec(entry_actor.position),"packet feasibility never moves actual root "+label)
