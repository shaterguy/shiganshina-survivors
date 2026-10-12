extends RefCounted
## Pure horizontal charge and actual-witness stop handoff.
## Math packets retain inherited artwork/native HOLD gates.
const Compiler = preload("res://game/presentation/armored/armored_pose_packet.gd")
const Address = preload("res://game/world/world_address.gd")
const Charge = preload("res://game/presentation/armored/armored_charge_curve.gd")
const MAX_COUNTER := 2147483647
# Reviewed Core uses 180..360 world/s at 60 ticks/s. The ratio is an
# observation, not a new Core speed. Tiny fractional witnesses are deliberately
# unresolved because float32 root quantization can dominate the accepted tail.
const MIN_CONTACT_FRACTION := .001
const MIN_REVIEWED_STEP := 3.0
const MAX_REVIEWED_STEP := 6.0
# Candidate visual speed-estimate budget, not a physical accuracy standard.
const MAX_SPEED_ERROR := .001
const MAX_LOCAL_COORDINATE := 49152.0
var _compiler := Compiler.new()
var _charge := Charge.new()
var _handoff: Dictionary = {}
var _stop_key: Array = []
var _stop_plan: Dictionary = {}
var _stop_context: Dictionary = {}
var _seen_attack: Dictionary = {}
var _neck_points: Array = []
var _prepared = null
var _neck: Dictionary = {}
var _present: Dictionary = {"supported":false,"reason":"no_actor"}
func configure(registration: Dictionary) -> Dictionary:
 var meshes = registration.get("meshes")
 if not meshes is Dictionary or not meshes.get("neck") is Dictionary or not meshes.neck.get("points") is Array:
  return {"ok":false,"reason":"neck_mesh_missing"}
 var destinations: Array = []
 for point in meshes.neck.points:
  if not _pair(point): return {"ok":false,"reason":"neck_mesh_source_point"}
  var source := _vec(point)
  var weight := clampf((source.x-553.0)/313.0,0.0,1.0)
  var target := (source-Vector2(866,610)).rotated(.4)+Vector2(645,585)
  var destination := source+(target-source)*weight
  if not destination.is_finite(): return {"ok":false,"reason":"neck_mesh_destination"}
  destinations.append([destination.x,destination.y])
 var neck := {"destinations":destinations,"folded_triangles":[]}
 var row := _row(0.0,0,neck)
 if not row.get("ok",false): return row
 var setup: Dictionary = _compiler.prepare_registration(registration)
 if not setup.ok: return setup
 var packet: Dictionary = setup.session.compile_pose(row.row)
 if not packet.ok: return {"ok":false,"reason":packet.reason}
 _prepared=setup.session; _neck=neck; _neck_points=meshes.neck.points.duplicate(true)
 reset()
 return {"ok":true,"native_gpu_verified":false,"quality_status":"HOLD"}
func reset() -> void:
 _stop_key.clear(); _stop_plan.clear(); _stop_context.clear(); _seen_attack.clear()
 _handoff.clear()
 _present={"supported":false,"reason":"no_actor"}
func observe(observation: Dictionary, actor: Dictionary) -> void:
 _handoff.clear()
 if _prepared==null: _unsupported("not_configured"); return
 if observation.is_empty() or actor.is_empty(): reset(); return
 if not _matches(observation,actor): _unsupported("observation_mismatch"); return
 if not actor.action_state in ["attack","brake","recover"]:
  _handoff.clear(); _seen_attack.clear(); _stop_key.clear(); _stop_plan.clear(); _stop_context.clear(); _unsupported("state_entry_not_reviewed:"+str(actor.action_state)); return
 if not _pair(actor.get("locked_direction")):
  _unsupported("direction_not_reviewed"); return
 var direction := _vec(actor.locked_direction)
 if absf(direction.y)>.000001 or absf(absf(direction.x)-1.0)>.000001:
  _unsupported("direction_not_reviewed"); return
 if actor.action_state in ["brake","recover"]:
  var stopped := _stop_row(observation,actor)
  if not stopped.ok: _unsupported(stopped.reason); return
  _publish(stopped.row,actor,direction); return
 _handoff.clear()
 if not observation.get("charge_distance_known") is bool or not observation.charge_distance_known:
  _unsupported("charge_distance_unknown"); return
 var row := _row(observation.get("charge_distance"),int(observation.tick),_neck)
 if not row.get("ok",false): _unsupported(row.reason); return
 _seen_attack={"actor_id":str(actor.id),"pattern_index":actor.pattern_index,"started":actor.action_started_tick,"ends":actor.action_ends_tick,"tick":observation.tick,"origin_revision":int(observation.origin_revision) if _counter(observation.get("origin_revision")) else -1,"rebase_count":int(observation.rebase_count) if _counter(observation.get("rebase_count")) else -1}
 _publish(row.row,actor,direction)
func _publish(row: Dictionary, actor: Dictionary, direction: Vector2) -> void:
 var packet: Dictionary = _prepared.compile_pose(row)
 if not packet.ok: _unsupported(packet.reason); return
 if not packet.canvas_contained: _unsupported("pose_outside_canvas"); return
 packet.quality_holds.weight_support_readability={"status":"HOLD","reason":"numeric foot lock is not mass/weight or balance acceptance"}
 packet.quality_holds.recovery_readability={"status":"HOLD","reason":"generalized stop/recovery has no raster/native art approval"}
 _present={"supported":true,"reason":"","packet":packet,"actor_id":str(actor.id),"pattern_index":int(actor.pattern_index),"root_position":_vec(actor.position),"flip":direction.x<0.0,"display_scale":1.5,"quality_status":"HOLD","native_gpu_verified":false}
func _stop_row(observation: Dictionary, actor: Dictionary) -> Dictionary:
 _handoff.clear()
 var mode: String = str(observation.get("mode",""))
 if mode=="restored_grounded": return {"ok":false,"reason":"restored_grounded_no_impact"}
 if mode!="impact":
  var stop_tick: int=int(actor.action_started_tick)-(18 if actor.action_state=="recover" else 0)
  if _counter(observation.get("attack_started_tick")) and _seen_attack.get("actor_id")==str(actor.id) and _seen_attack.get("pattern_index")==actor.pattern_index and _seen_attack.get("started")==observation.get("attack_started_tick"):
   if stop_tick<int(_seen_attack.ends): return {"ok":false,"reason":"body_only_stop_no_impact"}
   if stop_tick==int(_seen_attack.ends): return {"ok":false,"reason":"free_brake_no_impact"}
  return {"ok":false,"reason":"stop_without_shoulder_witness"}
 if not observation.get("charge_distance_known") is bool or not observation.charge_distance_known: return {"ok":false,"reason":"contact_phase_unknown"}
 for field in ["origin_revision","attack_started_tick"]:
  if not _counter(observation.get(field)): return {"ok":false,"reason":"observation_counter:"+field}
 if observation.has("rebase_count") and not _counter(observation.rebase_count): return {"ok":false,"reason":"observation_counter:rebase_count"}
 var contact = observation.get("contact")
 if not contact is Dictionary or not contact.get("shape") is String or contact.shape!="shoulder_circle": return {"ok":false,"reason":"live_shoulder_witness_missing"}
 if not contact.get("shape_id") is String or contact.shape_id.is_empty() or not contact.get("prop_id") is String: return {"ok":false,"reason":"contact_shape_identity_invalid"}
 if not _number(contact.get("fraction")) or contact.fraction<0.0 or contact.fraction>1.0: return {"ok":false,"reason":"contact_fraction_invalid"}
 for key in ["point","center","normal","root_position","locked_direction"]:
  if not _pair(contact.get(key)): return {"ok":false,"reason":"contact_vector_invalid:"+key}
 if not is_equal_approx(_vec(contact.normal).length(),1.0): return {"ok":false,"reason":"contact_normal_invalid"}
 for key in ["tick","attack_started_tick","pattern_index","origin_revision"]:
  if not _counter(contact.get(key)): return {"ok":false,"reason":"contact_counter:"+key}
 if not contact.get("source_id") is String or contact.source_id!=str(actor.id) or contact.pattern_index!=actor.pattern_index or contact.get("locked_direction")!=actor.locked_direction or contact.get("root_position")!=actor.position or contact.origin_revision!=observation.get("origin_revision"):
  return {"ok":false,"reason":"contact_identity_mismatch"}
 if not contact.get("event_id") is String or contact.event_id.is_empty() or contact.attack_started_tick!=observation.get("attack_started_tick") or contact.tick<contact.attack_started_tick or contact.tick>observation.tick:
  return {"ok":false,"reason":"contact_epoch_mismatch"}
 var start := int(contact.tick)+(18 if actor.action_state=="recover" else 0)
 var duration := 90 if actor.action_state=="recover" else 18
 if actor.action_started_tick!=start or actor.action_ends_tick!=start+duration: return {"ok":false,"reason":"contact_clock_mismatch"}
 var distance = observation.get("charge_distance")
 var travel = observation.get("last_travel")
 if not _number(distance) or not _number(travel) or travel<0 or travel>distance: return {"ok":false,"reason":"contact_travel_invalid"}
 var incoming: Dictionary = _charge.sample(distance)
 var prior: Dictionary = _charge.sample(distance-travel)
 if not incoming.ok: return incoming
 if not prior.ok: return prior
 var direction := _vec(actor.locked_direction)
 _handoff={"entry_pose":incoming.pose,"prior_pose":prior.pose,"distance":distance,"prior_distance":distance-travel,"last_travel":travel,"root":actor.position.duplicate(),"prior_root":[actor.position[0]-direction.x*travel,actor.position[1]-direction.y*travel],"contact":contact.duplicate(true)}
 var key := [contact.event_id,contact.tick,contact.attack_started_tick,actor.id,actor.pattern_index,distance,travel,contact.fraction,actor.locked_direction.duplicate()]
 if key!=_stop_key or not _same_stop_representation(observation,contact):
  _stop_key=key
  # A previously admitted plan preserves its original uncertainty through
  # rebase. A same-attack observation with unchanged origin/count proves
  # that the cumulative old rebases did not translate this witness. Without
  # that proof, a fresh consumer uses the full Core coordinate domain.
  var root_magnitude:=maxf(absf(float(actor.position[0])),absf(float(_handoff.prior_root[0])))
  var observed_origin: bool=_seen_attack.get("actor_id")==str(actor.id) and _seen_attack.get("pattern_index")==actor.pattern_index and _seen_attack.get("started")==contact.attack_started_tick and _seen_attack.get("tick",MAX_COUNTER)<contact.tick and _seen_attack.get("origin_revision",-1)==observation.origin_revision and _seen_attack.get("rebase_count",-1)==observation.get("rebase_count",0)
  if observation.get("rebase_count",0)!=0 and not observed_origin: root_magnitude=maxf(root_magnitude,MAX_LOCAL_COORDINATE)
  var precision:=_speed_error_budget(root_magnitude,float(travel),float(contact.fraction))
  _stop_plan=_prepare_stop(incoming.pose,prior.pose,float(travel),float(contact.fraction),precision)
  # Confidence may improve on a later valid observation; a rejected budget
  # must not become a replayable cached admission decision.
  if not _stop_plan.ok and _stop_plan.reason=="contact_speed_precision_unresolved": _stop_key.clear()
 _stop_context={"origin":int(observation.origin_revision),"rebases":int(observation.get("rebase_count",0)),"root":contact.root_position.duplicate(),"point":contact.point.duplicate(),"center":contact.center.duplicate(),"normal":contact.normal.duplicate(),"shape_id":contact.shape_id,"prop_id":contact.prop_id}
 _handoff.plan=_stop_plan.duplicate(true)
 if not _stop_plan.ok: return _stop_plan
 var age: int = int(observation.tick)-int(actor.action_started_tick)
 var sampled := _brake(age,_stop_plan) if actor.action_state=="brake" else _recovery(age,_stop_plan)
 if not sampled.ok: return sampled
 _handoff.current_pose=sampled.pose.duplicate(true)
 _handoff.age=age; _handoff.phase=actor.action_state
 return {"ok":true,"row":_pose_row(sampled,int(observation.tick),actor.action_state)}
func _same_stop_representation(observation: Dictionary,contact: Dictionary) -> bool:
 if _stop_context.is_empty(): return false
 if contact.shape_id!=_stop_context.shape_id or contact.prop_id!=_stop_context.prop_id or contact.normal!=_stop_context.normal: return false
 var origin_delta: int=int(observation.origin_revision)-int(_stop_context.origin)
 var rebase_delta: int=int(observation.get("rebase_count",0))-int(_stop_context.rebases)
 if origin_delta==0 and rebase_delta==0:
  return contact.root_position==_stop_context.root and contact.point==_stop_context.point and contact.center==_stop_context.center
 # Tracker advances its count for each consumed origin change and translates
 # the complete retained witness through WorldAddress.relative. A context
 # change is not a license to reuse confidence for arbitrary movement.
 if origin_delta<=0 or rebase_delta!=origin_delta: return false
 var shift: Array=[float(contact.root_position[0])-float(_stop_context.root[0]),float(contact.root_position[1])-float(_stop_context.root[1])]
 if rebase_delta==1 and shift==[0.0,0.0]: return false
 for axis in 2:
  if not is_finite(shift[axis]) or fmod(shift[axis],float(Address.CHUNK_SIZE))!=0.: return false
  if absf(shift[axis])>float(Address.CHUNK_SIZE*Address.MAX_RELATIVE_CHUNKS)*rebase_delta: return false
  for field in ["point","center"]:
   # Use the tracker's double array arithmetic, not a rounded Vector2 diff.
   if float(contact[field][axis])!=float(_stop_context[field][axis])+shift[axis]: return false
 return true
func _prepare_stop(entry: Dictionary, prior: Dictionary, travel: float, fraction: float, precision: float = 0.0) -> Dictionary:
 # Define the authored flight intervals before side-phase modulo arithmetic:
 # fposmod(.9+.5,1) may round just below .4 and falsely claim support.
 var phase: float=entry.phase
 if (phase>=.4 and phase<.5) or phase>=.9: return {"ok":false,"reason":"contact_phase_flight","phase":phase}
 var near: bool=entry.right_leg.contact; var far: bool=entry.left_leg.contact
 if not near and not far: return {"ok":false,"reason":"contact_phase_flight","phase":entry.phase}
 if near and far: return {"ok":false,"reason":"contact_support_ambiguous"}
 if travel<=0.0: return {"ok":false,"reason":"contact_zero_travel_phase_step"}
 if fraction<MIN_CONTACT_FRACTION: return {"ok":false,"reason":"contact_fraction_unresolved","fraction":fraction}
 var incoming_step:=travel/fraction
 if not is_finite(incoming_step) or incoming_step<MIN_REVIEWED_STEP-.0001 or incoming_step>MAX_REVIEWED_STEP+.0001:
  return {"ok":false,"reason":"contact_speed_not_reviewed","incoming_step_world":incoming_step}
 if not is_finite(precision) or precision>MAX_SPEED_ERROR: return {"ok":false,"reason":"contact_speed_precision_unresolved","speed_error_budget":precision}
 var support := "right" if near else "left"
 var swing := "left" if near else "right"
 if not prior[support+"_leg"].contact: return {"ok":false,"reason":"contact_support_transition","phase":entry.phase}
 var limb: Dictionary=entry[swing+"_leg"]
 var earlier: Dictionary=prior[swing+"_leg"]
 var landing := ceili((1.0-float(limb.phase))/(incoming_step/Charge.WORLD_CYCLE))
 if landing<1 or landing>17: return {"ok":false,"reason":"contact_landing_exceeds_brake","landing_age":landing,"phase":entry.phase}
 # Actual entry/prior poses are unchanged. Their displacement spans only
 # fraction of the attempted tick; scale the tangent, never the pose/root.
 var velocity := (_vec(limb.ankle)-_vec(earlier.ankle)+Vector2(travel/1.5,0))/fraction
 var plan := {"ok":true,"entry":entry.duplicate(true),"support_side":support,"swing_side":swing,"landing_age":landing,"incoming_step_world":incoming_step,"accepted_partial_world":travel,"incoming_native":incoming_step/1.5,"swing_velocity":velocity,"pitch_velocity":(float(limb.foot_angle)-float(earlier.foot_angle))/fraction,"swing_end":Vector2(float(limb.ankle[0])+velocity.x*landing*.5,Charge.GROUND_ANKLE)}
 # Validate the entire planned stop before publishing any part of it. This
 # bounded 1/8-tick numeric sweep is not a continuous proof or art approval.
 for index in range(137):
  var age := float(index)/8.0
  var tested := _brake(age,plan,true)
  if not tested.ok: return {"ok":false,"reason":tested.reason,"failed_phase":"brake","failed_age":age,"phase":entry.phase}
 var settled: Dictionary=_brake(17.0,plan)
 plan.settled=settled
 var q: Dictionary=settled.pose
 var rear := "right" if q.right_leg.ankle[0]<q.left_leg.ankle[0] else "left"
 var front := "left" if rear=="right" else "right"
 plan.rear_side=rear; plan.front_side=front
 plan.retrieve_end=Vector2(float(q[front+"_leg"].ankle[0])-32.0,Charge.GROUND_ANKLE)
 plan.ready_pelvis=Vector2(float(q[front+"_leg"].ankle[0])-24.0,164.0)
 for index in range(357):
  var age := float(index)/4.0
  var tested := _recovery(age,plan,true)
  if not tested.ok: return {"ok":false,"reason":tested.reason,"failed_phase":"recover","failed_age":age,"phase":entry.phase}
 return plan
func _speed_error_budget(root_magnitude: float,travel: float,fraction: float) -> float:
 if fraction<=0.: return INF
 # Horizontal-only: half an ULP for the final root addition, four travel
 # ULPs cover product, subtraction, square and sqrt rounding, plus float32
 # narrowing of fraction and the reviewed 3..6 delta. This is a deliberately
 # conservative candidate arithmetic budget, not a full engine error proof.
 return (.5*_float32_ulp(root_magnitude)+4.*_float32_ulp(travel)+.5*MAX_REVIEWED_STEP*_float32_ulp(fraction))/fraction+.000001
func _float32_ulp(value: float) -> float:
 var bits:=PackedByteArray(); bits.resize(4); bits.encode_float(0,absf(value))
 var exponent: int=(bits.decode_u32(0)>>23)&255
 return pow(2.,float(maxi(-126,exponent-127)-23))
func _brake(age: float, plan: Dictionary, validation_only: bool = false) -> Dictionary:
 var entry: Dictionary=plan.entry
 if age==0:
  if validation_only: return {"ok":true}
  return {"ok":true,"pose":entry.duplicate(true),"head_angle":.4,"head":[645.,585.],"plate":[120.,-50.]}
 var load := Vector2(-float(plan.incoming_native),4.5)
 var end := Vector2(load.x,2.5)
 var shift := Vector2.ZERO.lerp(load,_smooth(age/4.0)) if age<=4 else load.lerp(end,_smooth((age-4.0)/13.0))
 var torso_angle := _angle_keys(age,[0.,4.,9.,17.],[.1,.025,.04,.065])
 var head_angle := _angle_keys(age,[0.,4.,9.,17.],[.4,.4,.37,.382])
 var pose: Dictionary={} if validation_only else entry.duplicate(true)
 var pelvis := _vec(entry.pelvis)+shift
 if not validation_only:
  pose.pelvis=_array(pelvis); pose.torso=_array(pelvis); pose.torso_angle=torso_angle
 for side in ["right","left"]:
  var old: Dictionary=entry[side+"_leg"]
  var hip := pelvis+(_vec(old.hip)-_vec(entry.pelvis)).rotated(torso_angle-float(entry.torso_angle))
  var ankle := _vec(old.ankle)
  var pitch: float=old.foot_angle
  var contact: bool=old.contact
  if side==plan.swing_side:
   contact=age>=float(plan.landing_age)
   if contact: ankle=plan.swing_end; pitch=0.0
   else:
    var duration: float=plan.landing_age; var u:=age/duration
    ankle=Vector2(_charge._hermite(ankle.x,plan.swing_end.x,plan.swing_velocity.x*duration,0.0,u),_charge._hermite(ankle.y,plan.swing_end.y,plan.swing_velocity.y*duration,0.0,u))
    pitch=_charge._hermite(pitch,0.0,float(plan.pitch_velocity)*duration,0.0,u)
  if ankle.y>Charge.GROUND_ANKLE+.0001: return {"ok":false,"reason":"contact_swing_below_ground:"+side}
  if validation_only:
   if not _reachable(hip,ankle,60.5,60.5): return {"ok":false,"reason":"contact_leg_unreachable"}
  else:
   var leg := _leg_pose(old,hip,ankle,contact,pitch)
   if not leg.ok: return leg
   pose[side+"_leg"]=leg.limb
   # Brake arms are a rigid rotation/translation of fixed entry bones.
   for joint in ["shoulder","elbow","wrist"]:
    pose[side+"_arm"][joint]=_array(pelvis+(_vec(entry[side+"_arm"][joint])-_vec(entry.pelvis)).rotated(torso_angle-float(entry.torso_angle)))
 if validation_only: return {"ok":true}
 return {"ok":true,"pose":pose,"head_angle":head_angle,"head":[645.,585.],"plate":[120.,-50.]}
func _recovery(age: float, plan: Dictionary, validation_only: bool = false) -> Dictionary:
 var base: Dictionary=plan.settled
 if age==0: return {"ok":true} if validation_only else base.duplicate(true)
 var entry: Dictionary=base.pose
 var ready: Vector2=plan.ready_pelvis
 var pelvis := _vector_keys(age,[0.,24.,54.,89.],[_vec(entry.pelvis),Vector2(ready.x,169.5),Vector2(ready.x+1.0,165.0),ready])
 var angle := _angle_keys(age,[0.,24.,54.,89.],[float(entry.torso_angle),.06,.052,.04])
 var head_angle := _angle_keys(age,[0.,24.,54.,89.],[float(base.head_angle),.375,.285,.25])
 var plate := _vector_keys(age,[0.,24.,54.,89.],[_vec(base.plate),Vector2(99,-39.5),Vector2(78,-29),Vector2(70,-25)])
 var head := _vector_keys(age,[0.,24.,54.,89.],[_vec(base.head),Vector2(636,610),Vector2(638,596),Vector2(650,598)])
 var release := _angle_keys(age,[0.,24.,54.,89.],[0.,.12,.7,1.])
 var pose: Dictionary={} if validation_only else entry.duplicate(true)
 if not validation_only:
  pose.pelvis=_array(pelvis); pose.torso=_array(pelvis); pose.torso_angle=angle; pose.flight_height=0.0
 for side in ["right","left"]:
  var old: Dictionary=entry[side+"_leg"]
  var hip := pelvis+(_vec(old.hip)-_vec(entry.pelvis)).rotated(angle-float(entry.torso_angle))
  var ankle := _vec(old.ankle); var contact:=true; var pitch:=0.0
  if side==plan.rear_side and age>24:
   if age>=72: ankle=plan.retrieve_end
   else:
    var u:=(age-24.0)/48.0; var lift:=pow(sin(PI*u),2.0)
    ankle=ankle.lerp(plan.retrieve_end,_smooth(u))-Vector2(0,12.0*lift)
    contact=false; pitch=-.1*lift
  if validation_only:
   if not _reachable(hip,ankle,60.5,60.5): return {"ok":false,"reason":"contact_leg_unreachable"}
  else:
   var leg:=_leg_pose(old,hip,ankle,contact,pitch)
   if not leg.ok: return leg
   pose[side+"_leg"]=leg.limb
  var arm: Dictionary=entry[side+"_arm"]
  var shoulder_local:=(_vec(arm.shoulder)-_vec(entry.pelvis)).rotated(-float(entry.torso_angle))
  var shoulder:=pelvis+(shoulder_local+(plate-_vec(base.plate))*.085).rotated(angle)
  var wrist_local:=(_vec(arm.wrist)-_vec(arm.shoulder)).rotated(-float(entry.torso_angle))
  var target:=Vector2(-5,43) if side=="right" else Vector2(-13,37)
  var wrist:=shoulder+wrist_local.lerp(target,release).rotated(angle)
  if validation_only:
   if not _reachable(shoulder,wrist,39.0,35.0): return {"ok":false,"reason":"recovery_arm_unreachable:"+side}
  else:
   var elbow: Dictionary=_charge._joint(shoulder,wrist,39.0,35.0,1.0)
   if not elbow.ok: return {"ok":false,"reason":"recovery_arm_unreachable:"+side}
   pose[side+"_arm"].merge({"shoulder":_array(shoulder),"elbow":_array(elbow.joint),"wrist":_array(wrist),"clamped":false},true)
 if validation_only: return {"ok":true}
 return {"ok":true,"pose":pose,"head_angle":head_angle,"head":_array(head),"plate":_array(plate)}
func _reachable(root: Vector2,target: Vector2,upper: float,lower: float) -> bool:
 # Same strict interval as Charge._joint. No knee/elbow or dictionary is
 # needed for admission; the eventual packet still runs the original IK.
 var distance: float=(target-root).length()
 return root.is_finite() and target.is_finite() and is_finite(distance) and distance>absf(upper-lower) and distance<upper+lower
func _leg_pose(old: Dictionary, hip: Vector2, ankle: Vector2, contact: bool, pitch: float) -> Dictionary:
 var joint: Dictionary=_charge._joint(hip,ankle,60.5,60.5,-1.0)
 if not joint.ok: return {"ok":false,"reason":"contact_leg_unreachable"}
 var limb: Dictionary=old.duplicate(true)
 limb.merge({"hip":_array(hip),"knee":_array(joint.joint),"ankle":_array(ankle),"contact":contact,"foot_angle":pitch,"clamped":false},true)
 return {"ok":true,"limb":limb}
func _pose_row(sampled: Dictionary,tick: int,phase: String) -> Dictionary:
 var destinations: Array=[]
 for point in _neck_points:
  var source:=_vec(point); var weight:=clampf((source.x-553.0)/313.0,0.0,1.0)
  var target: Vector2=(source-Vector2(866,610)).rotated(float(sampled.head_angle))+_vec(sampled.head)
  destinations.append(_array(source+(target-source)*weight))
 return {"id":"runtime_"+phase+"_"+str(tick),"core_tick":tick,"sequence_phase":phase,"pose":sampled.pose,"source_scale":.085,"source_hip":[210,1175],"head_relative_angle":sampled.head_angle,"head_control_source":sampled.head,"near_plate_offset_source":sampled.plate,"mesh":{"neck":{"destinations":destinations,"folded_triangles":[]}}}
func _smooth(u: float) -> float: return u*u*(3.0-2.0*u)
func _angle_keys(age: float,times: Array,values: Array) -> float:
 for i in range(times.size()-1):
  if age<=times[i+1]: return lerpf(values[i],values[i+1],_smooth((age-times[i])/(times[i+1]-times[i])))
 return values[-1]
func _vector_keys(age: float,times: Array,values: Array) -> Vector2:
 for i in range(times.size()-1):
  if age<=times[i+1]: return values[i].lerp(values[i+1],_smooth((age-times[i])/(times[i+1]-times[i])))
 return values[-1]
func _array(v: Vector2) -> Array: return [v.x,v.y]
func debug_handoff() -> Dictionary: return _handoff.duplicate(true)
func present() -> Dictionary: return _present.duplicate(true)
func _unsupported(reason: String) -> void:
 _present={"supported":false,"reason":reason}
func _row(distance: Variant,tick: int,neck: Dictionary) -> Dictionary:
 var sampled: Dictionary = _charge.sample(distance)
 if not sampled.ok: return sampled
 return {"ok":true,"row":{"id":"runtime_charge_"+str(tick),"core_tick":tick,"sequence_phase":"charge","pose":sampled.pose,"source_scale":.085,"source_hip":[210,1175],"head_relative_angle":.4,"head_control_source":[645,585],"near_plate_offset_source":[120,-50],"mesh":{"neck":neck}}}
func _matches(observation: Dictionary,actor: Dictionary) -> bool:
 if not actor.get("enemy_id") is String or actor.enemy_id!="armored_titan" or not actor.get("action_state") is String: return false
 if not observation.get("actor_id") is String or not observation.get("phase") is String: return false
 for key in ["id","pattern_index","action_started_tick","action_ends_tick"]:
  if not _counter(actor.get(key)): return false
 for key in ["tick","pattern_index","phase_started_tick","phase_ends_tick"]:
  if not _counter(observation.get(key)): return false
 if not _pair(actor.get("position")) or not _pair(observation.get("root_position")): return false
 if observation.get("actor_id")!=str(actor.id) or observation.pattern_index!=actor.pattern_index or observation.get("phase")!=actor.get("action_state"): return false
 if observation.get("phase_started_tick")!=actor.action_started_tick or observation.get("phase_ends_tick")!=actor.action_ends_tick: return false
 if actor.action_started_tick>observation.tick or actor.action_ends_tick<=observation.tick: return false
 return observation.root_position==actor.position
func _counter(value: Variant) -> bool: return _number(value) and value>=0 and value<=MAX_COUNTER and value==floor(float(value))
func _number(value: Variant) -> bool: return (value is int or value is float) and is_finite(float(value))
func _pair(value: Variant) -> bool:
 return value is Array and value.size()==2 and _number(value[0]) and _number(value[1]) and _vec(value).is_finite()
func _vec(value: Array) -> Vector2: return Vector2(value[0],value[1])
