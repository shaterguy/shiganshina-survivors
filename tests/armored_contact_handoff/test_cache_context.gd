extends RefCounted
const T = preload("res://tests/armored_contact_handoff/test_contact_handoff.gd")
const S = preload("res://tests/armored_actor/armored_support.gd")
const Pose = preload("res://game/presentation/armored/armored_pose.gd")
func run(t) -> void:
 var c:=T.actual_contact(184.25);var warm:=Pose.new();warm.configure(T.registration())
 var actor:=S.actor(c.snapshot);warm.observe(c.observation,actor);var baseline:=warm.present()
 var moved:=_translated(c.observation,actor,Vector2(48000,0),0,0)
 var fresh:=Pose.new();fresh.configure(T.registration());fresh.observe(moved.observation,moved.actor)
 warm.observe(moved.observation,moved.actor)
 t.check(warm.present()==fresh.present() and warm.present().reason=="contact_speed_precision_unresolved","same epoch root mutation must not reuse old confidence; synthetic representation, not actual Core teleport")
 warm.observe(c.observation,actor)
 t.check(warm.present()==baseline,"repaired current representation recovers after confidence rejection")
 # The existing admitted contact may translate under paired origin/count
 # advance, retaining its original precision rather than re-estimating it.
 var rebased:=_translated(c.observation,actor,Vector2(-768,768),1,1)
 warm.observe(rebased.observation,rebased.actor)
 t.check(warm.present().supported and T._same_commands(warm.present().packet,baseline.packet),"paired uniform rebase preserves original admitted local pose")
 var remembered:=warm.present();warm.observe(rebased.observation,rebased.actor)
 t.check(warm.present()==remembered,"duplicate accepted rebase is idempotent")
 # Going backwards in origin metadata must not transfer its prior admission
 # to a large-magnitude representation with no current proof.
 var reversed:=_translated(rebased.observation,rebased.actor,Vector2(48000,0),0,0)
 fresh.reset();fresh.observe(reversed.observation,reversed.actor);warm.observe(reversed.observation,reversed.actor)
 t.check(warm.present()==fresh.present(),"decreasing origin/count reevaluates confidence like a fresh consumer")
 warm.reset();warm.observe(c.observation,actor)
 var broken:=_translated(c.observation,actor,Vector2(46080,0),1,1)
 broken.observation.contact.center=c.observation.contact.center.duplicate()
 fresh.reset();fresh.observe(broken.observation,broken.actor);warm.observe(broken.observation,broken.actor)
 t.check(warm.present()==fresh.present() and not warm.present().supported,"partial witness translation cannot inherit precision")
 warm.reset();warm.observe(c.observation,actor)
 var unpaired:=_translated(c.observation,actor,Vector2(46080,0),1,0)
 fresh.reset();fresh.observe(unpaired.observation,unpaired.actor);warm.observe(unpaired.observation,unpaired.actor)
 t.check(warm.present()==fresh.present() and not warm.present().supported,"unpaired origin/count advance cannot inherit precision")
 warm.reset();warm.observe(c.observation,actor)
 var impossible:=_translated(c.observation,actor,Vector2(46080,0),1,1)
 fresh.reset();fresh.observe(impossible.observation,impossible.actor);warm.observe(impossible.observation,impossible.actor)
 t.check(warm.present()==fresh.present() and not warm.present().supported,"one tracked rebase cannot exceed the producer's eight-relative-chunk limit")
func _translated(obs: Dictionary,actor: Dictionary,shift: Vector2,revision: int,count: int) -> Dictionary:
 var moved:=obs.duplicate(true);var a:=actor.duplicate(true)
 a.position=[a.position[0]+shift.x,a.position[1]+shift.y];moved.root_position=a.position.duplicate();moved.origin_revision=revision;moved.rebase_count=count
 for field in ["root_position","point","center"]:moved.contact[field]=[moved.contact[field][0]+shift.x,moved.contact[field][1]+shift.y]
 moved.contact.origin_revision=revision
 return {"observation":moved,"actor":a}
