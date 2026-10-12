extends RefCounted
const T = preload("res://tests/armored_contact_handoff/test_contact_handoff.gd")
const S = preload("res://tests/armored_actor/armored_support.gd")
const Pose = preload("res://game/presentation/armored/armored_pose.gd")
const Tracker = preload("res://game/presentation/armored_motion_tracker.gd")
const Support = preload("res://tests/app/controller_test_support.gd")
const C = preload("res://tests/armored_contact_input/city_fixture.gd")
const Address = preload("res://game/world/world_address.gd")
func run(t) -> void:
 _duplicates_and_restore(t); await _catchup(t); _rebase(t); _malformed(t)
func _duplicates_and_restore(t) -> void:
 var c:=T.actual_contact(184.25); var pose:=Pose.new(); pose.configure(T.registration())
 pose.observe(c.observation,S.actor(c.snapshot)); var baseline:=pose.present(); var handoff:=pose.debug_handoff()
 for n in 3:
  c.tracker.consume(c.events,c.snapshot); pose.observe(c.tracker.debug_observation(),S.actor(c.snapshot))
  t.check(pose.present()==baseline and pose.debug_handoff()==handoff,"same accepted contact is idempotent "+str(n))
 # A fresh pose consumer only sees a tracker at the final catch-up frame.
 for n in 7:
  var events:=S.step(c.fixture); var snapshot: Dictionary=c.fixture.core.snapshot(c.fixture.state)
  c.tracker.consume(events,snapshot); pose.observe(c.tracker.debug_observation(),S.actor(snapshot))
 var fresh:=Pose.new(); fresh.configure(T.registration())
 fresh.observe(c.tracker.debug_observation(),S.actor(c.fixture.state))
 t.check(fresh.present()==pose.present(),"late presentation reconstructs the same entry and current brake7 packet")
 c.fixture.state.pause_reasons.append("user"); var saved: Dictionary=c.fixture.state.duplicate(true)
 var old:=pose.present(); var events:=S.step(c.fixture)
 c.tracker.consume(events,c.fixture.core.snapshot(c.fixture.state)); pose.observe(c.tracker.debug_observation(),S.actor(c.fixture.state))
 t.check(c.fixture.state==saved and pose.present()==old,"real paused Core does not age handoff")
 c.fixture.state.pause_reasons.clear()
 var restored: Dictionary=c.fixture.core.restore(c.fixture.state)
 t.check(restored.ok,"stopped snapshot passes unchanged Core restore")
 var cold:=Tracker.new(); cold.present(c.fixture.core.snapshot(restored.state)); pose.observe(cold.debug_observation(),S.actor(restored.state))
 t.check(pose.present().reason=="restored_grounded_no_impact" and pose.debug_handoff().is_empty(),"restore clears live stop, without replaying accepted old event")
 # The old valid event cannot override a same-tick adoption floor.
 cold.consume(c.events,c.snapshot); pose.observe(cold.debug_observation(),S.actor(c.snapshot))
 t.check(not pose.present().supported,"historical contact cannot restart on rewind")
 # Restored attack has authoritative whole distance and does support a future
 # new live stop, even though its observed window distance begins at zero.
 var before: Dictionary=c.fixture.core.restore(c.before)
 t.check(before.ok,"actual prior attack can be restored")
 c.fixture.state=before.state; cold.reset(); cold.present(c.fixture.core.snapshot(c.fixture.state)); pose.reset()
 pose.observe(cold.debug_observation(),S.actor(c.fixture.state))
 var resumed_events:=S.step(c.fixture); var snapshot: Dictionary=c.fixture.core.snapshot(c.fixture.state)
 cold.consume(resumed_events,snapshot); pose.observe(cold.debug_observation(),S.actor(snapshot))
 t.check(T._same_commands(pose.present().packet,baseline.packet),"restored charge joins the same actual incoming pose")
 t.check(pose.debug_handoff().distance==handoff.distance,"restored prefix is not confused with observed-window tail")
 var absent: Dictionary=snapshot.duplicate(true); absent.entities=[]
 cold.consume([],absent); pose.observe(cold.debug_observation(),{})
 t.check(pose.present().reason=="no_actor" and pose.debug_handoff().is_empty(),"actor removal/dock output cannot retain old impact")
func _catchup(t) -> void:
 var c:=T.actual_contact(184.25)
 var restored: Dictionary=c.fixture.core.restore(c.before); t.check(restored.ok,"Controller starts from actual restore-valid precontact")
 var fixture:=Support.new().make(t); var app=fixture.app; app.start_run(42)
 app.simulation=c.fixture.core; app.state=restored.state; app.chapter=c.fixture.chapter
 app._last_phase=app.state.phase; app._last_save_tick=app.state.active_tick
 app.world.present(app.simulation.snapshot(app.state)); var tick: int=app.state.active_tick
 app.advance_frame(8.0/60.0)
 var status: Dictionary=app.world.armored_raster_status(); var obs: Dictionary=app.world.armored_motion_observation()
 t.check(app.state.active_tick==tick+8 and obs.phase_age==7 and obs.contact_count==1,"Controller eight successes retain contact and brake7")
 t.check(status.supported and status.pose_tick==tick+8,"existing WorldView final presentation receives current contact packet")
 var independent:=Pose.new(); independent.configure(T.registration()); independent.observe(obs,S.actor(app.state))
 t.check(T._same_commands(independent.present().packet,app.world._armored_pose.present().packet),"single final frame equals pure reconstructed packet")
 t.check(status.root_position==T._vec(S.actor(app.state).position),"eight-tick root/packet generation agrees")
 app.free()
 await t.process_frame
func _rebase(t) -> void:
 # Same local pose under a translated witness is a pure translation contract.
 var c:=T.actual_contact(184.25); var pose:=Pose.new(); pose.configure(T.registration()); pose.observe(c.observation,S.actor(c.snapshot))
 var before:=pose.present(); var obs: Dictionary=c.observation.duplicate(true); var actor: Dictionary=S.actor(c.snapshot).duplicate(true)
 var shift:=Vector2(-768,768)
 actor.position=[actor.position[0]+shift.x,actor.position[1]+shift.y]; obs.root_position=actor.position.duplicate(); obs.origin_revision+=1
 for key in ["root_position","point","center"]: obs.contact[key]=[obs.contact[key][0]+shift.x,obs.contact[key][1]+shift.y]
 obs.contact.origin_revision=obs.origin_revision
 pose.observe(obs,actor); var after:=pose.present()
 t.check(after.supported and T._same_commands(before.packet,after.packet),"rebase does not alter local entry or restart impact")
 t.check(after.root_position==before.root_position+shift,"root shifts exactly once")
 pose.observe(obs,actor); t.check(pose.present()==after,"duplicate rebase cannot shift a second time")
 # Actual streamed Core rebase feeds the existing tracker. A phase can remain
 # unsupported; the precise prior pose/root must still use the accepted travel.
 var city:=C.new().make(t); city.state=city.previous_states[0].duplicate(true)
 t.check(city.core.prepare_world(city.state,C.HF.hydration(C.H.requirements(city.state))).ok,"actual rebase fixture prepares")
 var tracker:=Tracker.new(); tracker.present(city.core.snapshot(city.state)); pose.reset()
 city.state.player.position=[766.,384.]
 t.check(city.core.prepare_world(city.state,C.HF.hydration(C.H.requirements(city.state))).ok,"actual road-boundary shift prepares")
 var previous: Dictionary=city.core.snapshot(city.state); var rebases:=0; var contact_seen:=false
 for n in 8:
  var events:=S.step(city,Vector2.RIGHT); var snapshot: Dictionary=city.core.snapshot(city.state)
  var prior_root: Array=S.actor(previous).position.duplicate()
  if snapshot.world.origin_revision!=previous.world.origin_revision:
   var translated:=Address.relative(previous.world.origin_chunk,Vector2.ZERO,snapshot.world.origin_chunk)
   prior_root=[prior_root[0]+translated.local.x,prior_root[1]+translated.local.y]; rebases+=1
  tracker.consume(events,snapshot); pose.observe(tracker.debug_observation(),S.actor(snapshot))
  if not events.filter(func(e):return e.type=="final_charge_contact").is_empty():
   contact_seen=true; var entry:=pose.debug_handoff()
   t.check(not entry.is_empty() and T._vec(entry.prior_root).is_equal_approx(T._vec(prior_root)),"actual rebase+contact retains exact translated previous root")
   var repeated:=pose.present(); tracker.consume(events,snapshot); pose.observe(tracker.debug_observation(),S.actor(snapshot))
   t.check(pose.present()==repeated,"actual rebased contact duplicate is stable")
  previous=snapshot
 t.check(rebases==1 and contact_seen,"actual streamed trace contains exactly one rebase and one shoulder witness")
func _malformed(t) -> void:
 var c:=T.actual_contact(184.25); var pose:=Pose.new(); pose.configure(T.registration())
 for field in ["fraction","normal","point","shape_id","prop_id"]:
  var obs: Dictionary=c.observation.duplicate(true)
  obs.contact[field]={"fraction":NAN,"normal":[0.,0.],"point":[INF,0.],"shape_id":"","prop_id":42}[field]
  pose.observe(obs,S.actor(c.snapshot))
  t.check(not pose.present().supported and not pose.present().has("packet"),"pure packet boundary rejects malformed witness "+field)
