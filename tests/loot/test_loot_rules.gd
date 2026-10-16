extends RefCounted
const Loot = preload("res://game/loot/loot_rules.gd")
func run(t) -> void:
	for row in [[4,0,1.0],[9,0,1.0],[10,1,1.25],[79,1,1.25],[80,2,1.5],[180,2,1.5]]:
		t.check(Loot.xp_tier(row[0]) == row[1] and Loot.xp_scale(row[0]) == row[2],"XP boundary "+str(row[0]))
	t.check(Loot.xp_tier(9+1) == 1 and Loot.xp_tier(79+1) == 2,"merged XP derives its new tier from the sum")
	var ids := {}
	for i in range(5):
		var spec := Loot.field_spec(i)
		t.check(spec.due_tick == [10800,32400,54000,75600,97200][i],"field schedule "+str(i))
		t.check(spec.reward == ("gold" if i%2 == 0 else "skill"),"field reward "+str(i))
		var id := Loot.chest_id("run:1","field",spec.source_id)
		ids[id] = true
		spec.reward = "invalid"
		t.check(Loot.field_spec(i).reward != "invalid","spec reads do not expose mutable global state")
	for boss_id in Loot.BOSS_IDS:
		t.check(Loot.boss_spec(boss_id).reward == "skill","boss skill specification")
		ids[Loot.chest_id("run:1","boss",boss_id)] = true
	t.check(ids.size() == 10 and not ids.has(""),"ten distinct stable chest IDs")
	t.check(Loot.field_spec(-1).is_empty() and Loot.field_spec(5).is_empty(),"out-of-range field rejected")
	t.check(Loot.boss_spec("armored_titan").is_empty(),"final boss has no chest")
	t.check(Loot.chest_id("run:1","field","010800").is_empty(),"noncanonical field ID rejected")
	t.check(Loot.chest_id("run:1","boss","armored_titan").is_empty(),"unknown boss ID rejected")
	t.check(not Loot.retry_due(159,160) and Loot.retry_due(160,160),"retry boundary is 60 active ticks after attempt at 100")
	for value in [0,5,15,50,5.0]: t.check(Loot.gold_amount_valid(value),"legal bounded gold "+str(value))
	for value in [-5,1,4.5,55,NAN,INF,true,"5",null]: t.check(not Loot.gold_amount_valid(value),"invalid gold "+str(value))

	var city := {"world":{"stage":"city","origin_chunk":["-9000000000000000000","8000000000000000000"]}}
	var chest := {"stage":"city","position":[0,0],"address":{}}
	t.check(Loot.set_position(city,chest,Vector2(-10,770)),"large signed WorldAddress normalizes without global float")
	var address: Dictionary = chest.address.duplicate(true)
	city.world.origin_chunk = ["-9000000000000000001","8000000000000000001"]
	var relative: Dictionary = Loot.local_position(city,chest)
	t.check(relative.get("ok",false) and relative.position == Vector2(758,2) and chest.address == address,"rebase derives local position without changing saved address")
	city.world.origin_chunk = ["0","0"]
	t.check(not Loot.local_position(city,chest).get("ok",false) and chest.address == address,"out-of-working-set chest remains stored")

	for origin in [["0","0"],["-9007199254740993","9007199254740994"]]:
		city.world.origin_chunk = origin
		for point in [Vector2.ZERO,Vector2(767.9999,200),Vector2(768.0001,200),Vector2(-767.9999,200),Vector2(-768.0001,200),Vector2(0.000001,200),Vector2(-768.000001,200),Vector2(767.999999,200),Vector2(-0.000001,200),Vector2(200,-0.000001),Vector2(-0.000001,-0.000001),Vector2(768,768),Vector2(-768,-768),Vector2.from_angle(TAU*4.0/16.0)*200.0]:
			var edge := {"stage":"city","position":[0.0,0.0],"address":{}}
			t.check(Loot.set_position(city,edge,point),"LOOT boundary writer accepts finite edge point")
			var a: Dictionary = edge.address
			t.check(a.local[0] >= 0.0 and a.local[0] < 768.0 and a.local[1] >= 0.0 and a.local[1] < 768.0,"LOOT persisted edge coordinates obey half-open chunk range")
			var again: Dictionary = Loot.Address.normalize(a.chunk,Vector2(a.local[0],a.local[1]))
			t.check(again.get("ok",false) and again.chunk == a.chunk and again.local == Vector2(a.local[0],a.local[1]),"LOOT boundary writer emits canonical idempotent address")
			var back: Dictionary = Loot.local_position(city,edge)
			t.check(back.get("ok",false) and back.position.distance_to(point) <= 0.0001,"LOOT rounded edge preserves local position within float32 precision")
			var decoded: Dictionary = JSON.parse_string(JSON.stringify(edge,"",true,true))
			var copied: Dictionary = Loot.local_position(city,decoded)
			t.check(copied.get("ok",false) and copied.position == back.position,"LOOT edge address survives precise JSON roundtrip")
