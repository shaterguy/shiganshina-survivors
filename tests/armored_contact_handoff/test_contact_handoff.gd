extends RefCounted
const S = preload("res://tests/armored_actor/armored_support.gd")
const Tracker = preload("res://game/presentation/armored_motion_tracker.gd")
const Pose = preload("res://game/presentation/armored/armored_pose.gd")
const Charge = preload("res://game/presentation/armored/armored_charge_curve.gd")
const Compiler = preload("res://game/presentation/armored/armored_pose_packet.gd")
static func registration() -> Dictionary:
 return JSON.parse_string(FileAccess.get_file_as_string("res://assets/art/rig/armored_runtime_v1/registration.json"))
static func actual_contact(distance: float, facing: float = 1.0) -> Dictionary:
 var f := S.make({"bounds":[-2000,-2000,4000,4000],"obstacles":[[-40,-400,80,800]]},[500,500])
 S.begin(f); S.arrange_windup(f,Vector2(-(112.0+distance)*facing,0),Vector2(60*facing,0))
 var tracker := Tracker.new(); tracker.present(f.core.snapshot(f.state))
 for n in 150:
  var before: Dictionary = f.core.snapshot(f.state)
  var before_observation: Dictionary = tracker.debug_observation()
  var events := S.step(f); var snapshot: Dictionary = f.core.snapshot(f.state)
  tracker.consume(events,snapshot)
  if not events.filter(func(e): return e.type=="final_charge_contact").is_empty():
   return {"fixture":f,"tracker":tracker,"before":before,"prior_observation":before_observation,"snapshot":snapshot,"observation":tracker.debug_observation(),"events":events}
 return {}
func run(t) -> void:
 var c := actual_contact(184.25)
 t.check(not c.is_empty(),"real public Core step reaches non-golden contact")
 if c.is_empty(): return
 var pose := Pose.new(); t.check(pose.configure(registration()).ok,"pure pose configures source registration")
 var saved: Dictionary = c.snapshot.duplicate(true); var obs: Dictionary=c.observation.duplicate(true)
 pose.observe(c.observation,S.actor(c.snapshot))
 var output: Dictionary=pose.present()
 print("CONTACT_RED_INPUT ",JSON.stringify(c.observation))
 t.check(output.supported,"actual non-golden known shoulder stop yields exact entry packet")
 t.check(c.snapshot==saved and c.observation==obs,"contact evaluation cannot mutate actor or tracker input")
 if not output.supported: return
 var handoff: Dictionary=pose.debug_handoff()
 t.check(handoff.entry_pose==Charge.new().sample(obs.charge_distance).pose,"entry is sampled from exact whole accepted distance")
 t.check(handoff.prior_pose==Charge.new().sample(obs.charge_distance-obs.last_travel).pose,"prior uses actual partial travel, not nominal speed")
 t.check(_vec(handoff.prior_root).is_equal_approx(_vec(S.actor(c.before).position)),"reconstructed prior root agrees with actual previous Core root")
 t.check(output.packet.source_state=="brake","contact entry packet declares brake, never replays attack")
 var contact_packet: Dictionary=output.packet
 var changed := false; var brake_last: Dictionary={}; var recover_zero: Dictionary={}
 for age in range(1,108):
  var f: Dictionary=c.fixture; var events:=S.step(f); var snapshot: Dictionary=f.core.snapshot(f.state)
  c.tracker.consume(events,snapshot); pose.observe(c.tracker.debug_observation(),S.actor(snapshot))
  var result: Dictionary=pose.present()
  t.check(result.supported,"actual stopped sequence produces packet age "+str(age)+": "+str(result.get("reason")))
  if not result.supported: continue
  t.check(result.root_position==Vector2(-112,0),"Core root is stationary throughout stop/recover "+str(age))
  t.check(result.packet.pose_tick==snapshot.active_tick,"packet consumes real accepted clock "+str(age))
  t.check(result.packet.quality_status=="HOLD" and not result.packet.final_export_allowed,"math cannot waive inherited quality gate")
  if age==4: changed=not _same_commands(contact_packet,result.packet)
  if age==17: brake_last=result.packet
  if age==18: recover_zero=result.packet
 t.check(changed,"brake actually articulates instead of repeating entry")
 t.check(not brake_last.is_empty() and _same_commands(brake_last,recover_zero),"brake17 to recover0 preserves every transform and mesh exactly")
 t.check(not _same_commands(recover_zero,pose.present().get("packet",{})),"recovery changes grounded pose instead of frozen repeat")
static func _vec(a: Array) -> Vector2: return Vector2(a[0],a[1])
static func _same_commands(a: Dictionary,b: Dictionary) -> bool:
 return a.get("commands")==b.get("commands")
