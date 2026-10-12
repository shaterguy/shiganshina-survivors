extends SceneTree
const Cases = preload("res://tests/core/test_enemy_recovery_contact.gd")
const Core = preload("res://game/core/run_simulation.gd")
const F = preload("res://tests/core/new_current_regression_fixture.gd")
const COLD_PATH := "res://../evidence/cold-cases.json"
var checks := 0
var failures: Array[String] = []
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		print("FAIL: "+message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var cases := Cases.new()
	if "--cold-write" in OS.get_cmdline_user_args():
		var records := []
		for id in Cases.IDS:
			var f: Dictionary = cases.make(id)
			check(cases.until(f,"recover"),id+" cold producer reaches actual recovery")
			var first: Dictionary = f.state.duplicate(true)
			var duration: int = int(first.entities[0].action_ends_tick)-int(first.active_tick)
			for offset in [0,duration/2,duration-1]:
				f.state = first.duplicate(true)
				for index in int(offset): F.step(f.sim,f.state,Vector2.ZERO)
				cases.overlap(f.state)
				var saved: Dictionary = f.sim.snapshot(f.state)
				var expected_events: Array = F.step(f.sim,f.state,Vector2.ZERO)
				var should_hit := int(offset) == duration-1
				check((cases.hits(expected_events).size() == 1) == should_hit,id+" cold producer expected recovery/move damage boundary")
				records.append({"id":id,"offset":offset,"saved":saved,"expected_state":f.state,"expected_events":expected_events})
		var file := FileAccess.open(COLD_PATH,FileAccess.WRITE)
		file.store_string(JSON.stringify({"core_sha256":FileAccess.get_sha256("res://game/core/run_simulation.gd"),"records":records},"",true,true)+"\n")
		file.close()
	elif "--cold-read" in OS.get_cmdline_user_args():
		var packet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(COLD_PATH))
		check(packet.core_sha256 == FileAccess.get_sha256("res://game/core/run_simulation.gd"),"cold consumer has exact producer Core bytes")
		check(packet.records.size() == 27,"cold consumer has nine actors times three recovery positions")
		for record in packet.records:
			var sim := Core.new(Cases.Provider.new())
			var restored: Dictionary = sim.restore(record.saved)
			check(restored.get("ok",false),record.id+" cold restore accepts newly generated exact-identity recovery checkpoint")
			if not restored.get("ok",false): continue
			var events: Array = F.step(sim,restored.state,Vector2.ZERO)
			check(sim._same_json(restored.state,record.expected_state) and sim._same_json(events,record.expected_events),record.id+" cold first step preserves clock, damage ownership, IDs and events at offset "+str(record.offset))
	else:
		cases.run(self)
	print("RECOVERY_CONTACT_RESULT checks=%d failures=%d" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
