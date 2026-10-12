extends RefCounted
const T = preload("res://tests/armored_contact_handoff/test_contact_handoff.gd")
const S = preload("res://tests/armored_actor/armored_support.gd")
const Pose = preload("res://game/presentation/armored/armored_pose.gd")
const Matrix = preload("res://tests/armored_contact_handoff/test_phase_matrix.gd")
const Tracker = preload("res://game/presentation/armored_motion_tracker.gd")
func run(t) -> void:
 var seed:=T.actual_contact(184.25); var pose:=Pose.new(); pose.configure(T.registration())
 var profile: Dictionary=seed.fixture.state.rules.enemy_catalog.armored_titan.action_profile
 var nominal: float=seed.fixture.core._final_charge_speed(profile,int(seed.observation.contact.tick)-int(seed.observation.attack_started_tick))/60.0
 var shifts: Array=[]
 for fraction in [.01,.1,.5,.9]:
  var c:=T.actual_contact(float(seed.prior_observation.charge_distance)+nominal*fraction)
  pose.observe(c.observation,S.actor(c.snapshot)); var result:=pose.present(); var h:=pose.debug_handoff()
  t.check(result.supported,"known incoming speed supports ordinary fraction "+str(fraction)+": "+result.reason)
  if not result.supported: continue
  t.check(h.plan.has("incoming_step_world") and h.plan.has("accepted_partial_world"),"incoming speed and accepted travel have separate meanings")
  if not h.plan.has("incoming_step_world"): continue
  t.check(absf(h.plan.incoming_step_world-nominal)<.0001 and h.plan.accepted_partial_world==c.observation.last_travel,"speed estimate agrees with Core while entry keeps exact partial")
  t.check(h.prior_distance==c.prior_observation.charge_distance and h.entry_pose==T.Charge.new().sample(c.observation.charge_distance).pose,"speed correction never changes actual incoming phase")
  var load: Dictionary=pose._brake(4,h.plan)
  shifts.append(float(load.pose.pelvis[0])-float(h.entry_pose.pelvis[0]))
  Matrix.new()._all_packets(t,pose,c.observation,S.actor(c.snapshot),"actual fraction "+str(fraction))
 t.check(shifts.size()==4,"all ordinary fractions generate comparable load response")
 if shifts.size()==4:
  t.check(absf(shifts.max()-shifts.min())<.0001,"same Core incoming speed gives same recoil scale independent of accepted fraction")
 for fraction in [0.0,.00001,NAN,INF,-1.,1.1]:
  var obs: Dictionary=seed.observation.duplicate(true); obs.contact.fraction=fraction
  pose.observe(obs,S.actor(seed.snapshot))
  t.check(not pose.present().supported,"zero tiny nonfinite/outside fraction cannot be divided blindly "+str(fraction))
 var forged: Dictionary=seed.observation.duplicate(true); forged.contact.fraction=.01
 pose.observe(forged,S.actor(seed.snapshot))
 t.check(not pose.present().supported and pose.present().reason=="contact_speed_not_reviewed","implausible accepted/fraction ratio is rejected")
 var corner:=S.make({"bounds":[-2000,-2000,4000,4000],"obstacles":[[-40,8,80,800]]},[500,500])
 S.begin(corner); S.arrange_windup(corner,Vector2(-296.25,0),Vector2(60,0))
 var tracker:=Tracker.new(); tracker.present(corner.core.snapshot(corner.state)); var reached:=false
 for n in 150:
  var events:=S.step(corner); var snapshot: Dictionary=corner.core.snapshot(corner.state); tracker.consume(events,snapshot)
  if events.filter(func(e):return e.type=="final_charge_contact").is_empty(): continue
  reached=true; var obs:=tracker.debug_observation(); pose.observe(obs,S.actor(snapshot))
  t.check(absf(obs.contact.normal[1])>.1,"actual Core circle reaches rounded corner, not a face strip")
  var expected: float=corner.core._final_charge_speed(profile,int(obs.contact.tick)-int(obs.attack_started_tick))/60.0
  t.check(absf(obs.last_travel/obs.contact.fraction-expected)<.0001,"same fraction recovery also agrees at real rounded corner")
  t.check(pose.present().supported,"resolved horizontal corner supplies valid pure handoff")
  if pose.present().supported: Matrix.new()._all_packets(t,pose,obs,S.actor(snapshot),"actual rounded corner")
  break
 t.check(reached,"real corner shoulder witness exists")
