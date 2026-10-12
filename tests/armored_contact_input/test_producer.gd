extends RefCounted
const S = preload("res://tests/armored_actor/armored_support.gd")
const F = preload("res://tests/core/core_fixture.gd")
func wall(x: float = 150.0) -> Dictionary:
 var f := S.make({"bounds":[-2000,-2000,4000,4000],"obstacles":[[x,-60,50,120]]},[500,500])
 S.begin(f); S.arrange_windup(f,Vector2.ZERO,Vector2(300,0))
 return f
func before_contact(f: Dictionary) -> Dictionary:
 for i in 150:
  var a := S.actor(f.state)
  if a.action_state == "attack":
   var speed: float = f.core._final_charge_speed(f.state.rules.enemy_catalog.armored_titan.action_profile,int(f.state.active_tick)+1-int(a.action_started_tick))
   var sweep: Dictionary = f.core._final_contact_sweep(f.state,Vector2(a.position[0],a.position[1]),Vector2.RIGHT*speed/60.0,Vector2.RIGHT,f.state.rules.enemy_catalog.armored_titan.action_profile,f.core._streamed)
   if sweep.stopped: return sweep
  S.step(f)
 return {}
func run(t) -> void:
 for wall_x in [150.0,98.0]:
  var f := wall(wall_x)
  var sweep := before_contact(f)
  var original := S.actor(f.state).duplicate(true)
  var events := S.step(f)
  var contacts := F.types(events,"final_charge_contact")
  t.check(contacts.size() == 1,"actual wall contact emits exactly once "+str(wall_x))
  if not contacts.is_empty():
   var e: Dictionary = contacts[0]; var p: Dictionary = e.payload
   t.check(p.attack_started_tick == original.action_started_tick and p.attack_started_tick < e.tick,"original charge epoch is captured before brake overwrite")
   t.check(p.source_id == str(original.id) and p.pattern_index == original.pattern_index and p.origin_revision == 0,"actor pattern and finite origin are precise")
   t.check(p.root_position == S.actor(f.state).position and p.locked_direction == original.locked_direction,"payload carries accepted root and locked direction")
   for k in ["point","center","normal"]: t.check(p[k] is Array and Vector2(p[k][0],p[k][1]) == sweep.contact[k],"finite JSON array matches actual witness "+k)
   t.check(p.shape == "shoulder_circle" and p.shape_id == sweep.contact.shape_id and p.prop_id == sweep.contact.prop_id and p.fraction == sweep.contact.fraction,"actual witness identity and fraction preserved")
   t.check(JSON.parse_string(JSON.stringify(e)) is Dictionary,"entire event roundtrips JSON")
   var saved: Dictionary = f.state.duplicate(true)
   p.root_position[0] += 999; p.locked_direction[0] += 999
   t.check(f.state == saved,"event arrays never alias simulation actor")
  t.check(F.types(S.step(f),"final_charge_contact").is_empty(),"brake tick never repeats contact")
 # Natural public-step endpoint at the final speed6 step. Measure a real open
 # trajectory, then construct an immutable wall at that exact endpoint + front72.
 var probe := wall(1000)
 for i in 150:
  var pa := S.actor(probe.state)
  if pa.action_state == "attack" and int(probe.state.active_tick)-int(pa.action_started_tick) == 58: break
  S.step(probe)
 var wall_at: float = float(S.actor(probe.state).position[0])+6.0+72.0
 var endpoint := wall(wall_at)
 for i in 150:
  var ea := S.actor(endpoint.state)
  if ea.action_state == "attack" and int(endpoint.state.active_tick)-int(ea.action_started_tick) == 58: break
  S.step(endpoint)
 t.check(endpoint.core.restore(endpoint.state).get("ok",false),"natural exact endpoint pre-step snapshot restores")
 var endpoint_events := F.types(S.step(endpoint),"final_charge_contact")
 t.check(endpoint_events.size() == 1 and endpoint_events[0].payload.fraction == 1.0 and endpoint_events[0].payload.root_position[0] == wall_at-72.0,"restore-valid natural public step emits reached endpoint fraction one")
 t.check(endpoint.core.restore(endpoint.state).get("ok",false),"natural exact endpoint accepted brake snapshot restores")
 print("NATURAL_ENDPOINT ",JSON.stringify({"wall":wall_at,"contact":endpoint_events,"restore":endpoint.core.restore(endpoint.state).get("ok",false)}))
 var body := S.make({"bounds":[-2000,-2000,4000,4000],"obstacles":[[20,28,20,12]]},[500,500])
 S.begin(body); S.arrange_windup(body,Vector2(-50,0),Vector2(150,0))
 var body_events: Array = []
 for i in 140:
  body_events.append_array(S.step(body))
  if S.actor(body.state).action_state == "brake": break
 t.check(S.actor(body.state).action_state == "brake" and F.types(body_events,"final_charge_contact").is_empty(),"real body-first stop emits no shoulder contact")
 var open := S.make(); S.begin(open); S.arrange_windup(open,Vector2.ZERO,Vector2(370,0))
 var open_events: Array = []
 for i in 150: open_events.append_array(S.step(open))
 t.check(F.types(open_events,"final_charge_contact").is_empty(),"open expiration emits no contact")
 for mode in ["pause","commands","terminal"]:
  var f := wall(); before_contact(f)
  if mode == "pause": f.state.pause_reasons.append("user")
  if mode == "terminal": f.state.phase = "abandoned"
  var before: Dictionary = f.state.duplicate(true)
  var commands: Array = []
  if mode == "commands": commands.resize(1025); commands.fill({})
  t.check(F.step(f.core,f.state,Vector2.ZERO,commands).is_empty() and f.state == before,"refused "+mode+" emits nothing and changes nothing")
 var refused := wall(64)
 var refused_events: Array = []
 for i in 20: refused_events.append_array(S.step(refused))
 t.check(F.types(refused_events,"final_charge_contact").is_empty() and S.actor(refused.state).action_state == "move","preparation refusal emits no contact")
 for slots in [1,0]:
  var f := wall(); before_contact(f)
  f.state.event_seq = 2147483647-slots
  t.check(f.core.restore(f.state).get("ok",false),"finite near-limit input restores")
  var before: Dictionary = f.state.duplicate(true)
  var events := S.step(f)
  if slots == 1:
   t.check(F.types(events,"final_charge_contact").size() == 1 and f.state.event_seq == 2147483647,"finite exact one-slot capacity publishes contact")
  else:
   t.check(events.is_empty() and f.state == before and f.core._final_sweeps.is_empty(),"finite one slot short rolls back state and witness")
   f.state.event_seq -= 1
   t.check(F.types(S.step(f),"final_charge_contact").size() == 1,"finite counter repaired retry emits once")
