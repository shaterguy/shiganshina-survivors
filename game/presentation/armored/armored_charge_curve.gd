extends RefCounted
## Continuous distance sampler ported from the reviewed registered charge recipe.
## No Core clock/root mutation, image loading, fixed-frame lookup or stop synthesis.
const WORLD_CYCLE := 240.0 # Native160 at the final actor's existing display scale1.5.
const PELVIS_X := 127.10240975982227
const GROUND_ANKLE := 262.875
const TORSO_ANGLE := 0.1
func sample(distance_world: Variant) -> Dictionary:
 if not (distance_world is int or distance_world is float) or not is_finite(float(distance_world)) or float(distance_world)<0.0:
  return {"ok":false,"reason":"invalid_charge_distance"}
 var p := fposmod(float(distance_world),WORLD_CYCLE)/WORLD_CYCLE
 var half := fposmod(p,.5)
 var flight := 6.0*pow(sin(PI*(half-.4)/.1),2.0) if half>.4 else 0.0
 var pelvis := Vector2(PELVIS_X,_body_height(half))
 var pelvis_angle := .018*sin(TAU*p)
 var result := {"phase":p,"pelvis":_array(pelvis),"torso":_array(pelvis),"torso_angle":TORSO_ANGLE,"pelvis_angle":pelvis_angle,"flight_height":flight}
 for side in ["right","left"]:
  var phase := p if side=="right" else fposmod(p+.5,1.0)
  var hip := pelvis if side=="right" else pelvis+Vector2(5,-2).rotated(pelvis_angle)
  var leg := _leg(phase,hip,flight)
  if not leg.ok: return leg
  result[side+"_leg"] = leg.limb
  var source_root := Vector2(670,800) if side=="right" else Vector2(735,735)
  var shoulder := pelvis+((source_root-Vector2(210,1175)+Vector2(120,-50))*.085).rotated(TORSO_ANGLE)
  var folded_offset := Vector2(-6,24) if side=="right" else Vector2(-12,20)
  var wrist := shoulder+folded_offset.rotated(TORSO_ANGLE)
  var arm := _joint(shoulder,wrist,39.0,35.0,1.0)
  if not arm.ok: return arm
  result[side+"_arm"] = {"phase_swing":-cos(TAU*(phase+.05)),"shoulder":_array(shoulder),"elbow":_array(arm.joint),"wrist":_array(wrist),"clamped":false}
 return {"ok":true,"reason":"","pose":result}
func _body_height(half: float) -> float:
 var knots := [[0.0,164.0,100.0],[.055,169.0,0.0],[.2,168.0,-12.0],[.4,166.0,-20.0],[.5,164.0,100.0]]
 for i in range(knots.size()-1):
  var a: Array = knots[i]; var b: Array = knots[i+1]
  if half<=float(b[0]):
   var span := float(b[0])-float(a[0])
   return _hermite(float(a[1]),float(b[1]),float(a[2])*span,float(b[2])*span,(half-float(a[0]))/span)
 return 164.0
func _leg(phase: float, hip: Vector2, flight: float) -> Dictionary:
 var contact := phase<.4
 var x := 137.0-160.0*phase
 var lift := 0.0
 var pitch := 0.0
 if not contact:
  var u := (phase-.4)/.6
  x = _hermite(73.0,137.0,-96.0,-96.0,u)
  lift = 45.0*u*u*pow(1.0-u,3.0)/(.4*.4*.6*.6*.6)
  pitch = .7*pow(sin(PI*u),2.0)*(.45-u)
 var ankle := Vector2(x,GROUND_ANKLE-lift-flight)
 var knee := _joint(hip,ankle,60.5,60.5,-1.0)
 if not knee.ok: return knee
 return {"ok":true,"limb":{"phase":phase,"hip":_array(hip),"knee":_array(knee.joint),"ankle":_array(ankle),"contact":contact,"foot_angle":pitch,"clamped":false}}
func _joint(root: Vector2, target: Vector2, upper: float, lower: float, bend: float) -> Dictionary:
 var delta := target-root
 var distance := delta.length()
 if not root.is_finite() or not target.is_finite() or not is_finite(distance) or distance<=absf(upper-lower) or distance>=upper+lower:
  return {"ok":false,"reason":"unreachable_fixed_bone"}
 var along := (upper*upper-lower*lower+distance*distance)/(2.0*distance)
 var height_squared := upper*upper-along*along
 if height_squared<0.0: return {"ok":false,"reason":"unreachable_fixed_bone"}
 var direction := delta/distance
 var joint := root+direction*along+Vector2(-direction.y,direction.x)*sqrt(height_squared)*bend
 if not joint.is_finite(): return {"ok":false,"reason":"nonfinite_joint"}
 return {"ok":true,"joint":joint}
func _hermite(a: float,b: float,ta: float,tb: float,u: float) -> float:
 var u2 := u*u; var u3 := u2*u
 return (2.0*u3-3.0*u2+1.0)*a+(u3-2.0*u2+u)*ta+(-2.0*u3+3.0*u2)*b+(u3-u2)*tb
func _array(v: Vector2) -> Array: return [v.x,v.y]
