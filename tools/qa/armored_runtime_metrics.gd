extends SceneTree
## Headless pure pose/packet CPU only. No GPU/native screen or Android claims.
const T = preload("res://tests/armored_contact_handoff/test_contact_handoff.gd")
const S = preload("res://tests/armored_actor/armored_support.gd")
const Pose = preload("res://game/presentation/armored/armored_pose.gd")
func _initialize() -> void:
 var registration:=T.registration(); var fixture:=T.actual_contact(184.25)
 var samples:={"charge":[],"first_contact":[],"duplicate_contact":[],"subsequent_brake":[],"subsequent_recover":[]}
 for cycle in 40:
  var pose:=Pose.new(); var configured:=pose.configure(registration)
  if not configured.ok: push_error("pose setup failed"); quit(1); return
  _measure(pose,fixture.prior_observation,S.actor(fixture.before),samples.charge)
  _measure(pose,fixture.observation,S.actor(fixture.snapshot),samples.first_contact)
  _measure(pose,fixture.observation,S.actor(fixture.snapshot),samples.duplicate_contact)
  for elapsed in [1,4,9,17,18,42,72,107]:
   var obs: Dictionary=fixture.observation.duplicate(true); var actor: Dictionary=S.actor(fixture.snapshot).duplicate(true)
   var recover: bool=elapsed>=18; var start: int=int(obs.contact.tick)+(18 if recover else 0)
   actor.action_state="recover" if recover else "brake"; actor.action_started_tick=start; actor.action_ends_tick=start+(90 if recover else 18)
   obs.phase=actor.action_state; obs.phase_started_tick=actor.action_started_tick; obs.phase_ends_tick=actor.action_ends_tick; obs.tick=int(obs.contact.tick)+elapsed; obs.phase_age=obs.tick-start
   _measure(pose,obs,actor,samples.subsequent_recover if recover else samples.subsequent_brake)
 var stats:={}
 for key in samples:
  samples[key].sort(); var data: Array=samples[key]
  stats[key]={"count":data.size(),"median_ms":data[data.size()/2],"p95_ms":data[ceili(data.size()*.95)-1],"p99_ms":data[ceili(data.size()*.99)-1],"max_ms":data[-1]}
 print("POSE_CPU_METRICS ",JSON.stringify({"scope":"headless pure observe CPU, no alpha/draw/GPU/device","cycles":40,"host_processors":OS.get_processor_count(),"godot":Engine.get_version_info().string,"costs":stats,"all_samples_ms":samples}))
 quit(0)
func _measure(pose,observation: Dictionary,actor: Dictionary,samples: Array) -> void:
 var start:=Time.get_ticks_usec(); pose.observe(observation,actor); var elapsed:=Time.get_ticks_usec()-start
 if not pose.present().supported: push_error("unsupported metric input: "+str(pose.present().reason)); return
 samples.append(float(elapsed)/1000.0)
