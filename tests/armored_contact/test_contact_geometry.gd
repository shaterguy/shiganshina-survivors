extends RefCounted
const S = preload("res://tests/armored_actor/armored_support.gd")
const Contact = preload("res://game/combat/armored_contact.gd")
func run(t) -> void:
	var old := S.make({"bounds":[-2000,-2000,4000,4000],"obstacles":[[64,-100,40,200]]},[500,500])
	S.begin(old)
	S.arrange_windup(old,Vector2.ZERO,Vector2(200,0))
	var start_tick: int = old.state.active_tick
	for i in 20:
		S.step(old)
		t.check(S.actor(old.state).action_state == "move" and old.state.telegraphs.is_empty() and old.core._final_sweeps.is_empty(),"old64 gap defers overlapping probe instead of starting charge "+str(i))
	t.check(old.state.active_tick == start_tick+20 and old.state.final_started_tick == 108000,"old64 activation refusal keeps final clock advancing")
	for separation in [0.000000001,0.00000001,0.0000001,0.000001,0.00001]:
		var body := {"position":Vector2(0.5,0),"fraction":0.5-separation}
		var shoulder := {"fraction":0.5,"contact":{"shape":"shoulder_circle","prop_id":"not_reached","fraction":0.5}}
		var combined := Contact.combine(Vector2.ZERO,Vector2.RIGHT,body,shoulder)
		t.check(combined.contact.is_empty() and combined.fraction < shoulder.fraction,"float near-tie never promotes earlier body stop "+str(separation))
	for gap in [0.00001,0.0001,0.001]:
		var near := S.make({"bounds":[-2000,-2000,4000,4000],"obstacles":[[20,28,20,12],[60+gap,-20,10,40]]},[500,500])
		var profile: Dictionary = near.state.rules.enemy_catalog.armored_titan.action_profile
		var measured: Dictionary = near.core._final_contact_sweep(near.state,Vector2(-50,0),Vector2(100,0),Vector2.RIGHT,profile,null)
		t.check(measured.stopped and measured.contact.is_empty() and measured.body_fraction < measured.shoulder_fraction,"actual finite two-shape near-tie preserves earlier body stop "+str(gap))
	var f := S.make({"bounds":[-2000,-2000,4000,4000],"obstacles":[[20,28,20,12]]},[500,500])
	S.begin(f)
	S.arrange_windup(f,Vector2(-50,0),Vector2(150,0))
	t.check(S.actor(f.state).action_state == "windup","side obstacle does not overlap initial root/probe connector")
	var seen := false
	for i in 130:
		S.step(f)
		for sweep in f.core._final_sweeps: t.check(sweep.contact.is_empty(),"body-side stop never publishes shoulder witness")
		if S.actor(f.state).action_state == "brake": seen = true; break
	t.check(seen and absf(S.actor(f.state).position[0]+12) < 0.002,"real body-first side collision stops at conservative body32 boundary")
	var p: Dictionary = f.state.rules.enemy_catalog.armored_titan.action_profile
	var aligned := S.make({"bounds":[-500,-500,1000,1000],"obstacles":[[-400,32.1,800,100],[-400,-132.1,800,100]]},[0,0])
	t.check(aligned.core._final_contact_ready(aligned.state,Vector2.ZERO,Vector2.RIGHT,p,null).clear,"64.2 corridor accepts aligned probe without body inflation")
	t.check(not aligned.core._final_contact_ready(aligned.state,Vector2.ZERO,Vector2(1,1).normalized(),p,null).clear,"same corridor rejects diagonal activation")
	var shapes := [{"id":"tiny","prop_id":"tiny","rect":Rect2(0,0,1,1)}]
	var rounded := Contact.trace(Vector2(-100,-100),Vector2(200,200),16,shapes)
	var center: Vector2 = rounded.contact.center
	t.check(absf(center.length()-16) < 0.001 and rounded.contact.point == Vector2.ZERO,"thin corner produces true circle TOI rather than slab-square contact")
	var body := {"position":Vector2(-32,-32),"fraction":0.34}
	var result := Contact.combine(Vector2(-100,-100),Vector2(200,200),body,rounded)
	t.check(result.contact.is_empty(),"existing conservative body corner cannot claim later actual shoulder contact")
