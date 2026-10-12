extends RefCounted
const X = preload("res://tests/fantasy_skills/fantasy_fixture.gd")
const Core = preload("res://game/core/run_simulation.gd")
const Finite = preload("res://tests/core/finite_chapter_provider.gd")
const F = preload("res://tests/core/new_current_regression_fixture.gd")
const A = preload("res://tests/core/test_rebuild_attack_events.gd")
func run(t) -> void:
	var inputs := {}
	for path in Core.GAMEPLAY_PATHS: inputs[path] = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fantasy_skills/legacy_inputs/"+path.get_file()))
	for bonus in [0,1,5]:
		for item in F.EQUIPMENT_IDS:
			var old := Core.new(Finite.new(),null,inputs)
			var current = X.simulation()
			var config: Dictionary = F.run_config()
			if bonus > 0: config.permanent_upgrades = {"permanent_might":bonus}
			var original: Dictionary = old.new_run(Finite.new().load_chapter("chapter_01_shiganshina").chapter,33,config)
			var candidate: Dictionary = current.new_run(X.chapter(),33,config)
			for state in [original,candidate]:
				state.equipment = {item:5}
				state.passives = {"damage":2,"attack_range":2,"fire_interval":3}
			var hits := 0
			for tick in 200:
				var commands := [F.spawn("original-target",[45,0],"brute")] if tick == 0 else []
				var legacy := F.step(old,original,Vector2.ZERO,commands)
				var live := F.step(current,candidate,Vector2.ZERO,commands)
				t.check(legacy == live,"original six weapon events remain equivalent at permanent bonus "+str(bonus)+" "+item)
				hits += F.types(live,"damage").size()
			t.check(hits > 0,"comparison exercised actual original weapon damage "+item)
		for evolution in ["evo_wing_cut","evo_crossfire"]:
			var old := Core.new(Finite.new(),null,inputs)
			var current = X.simulation()
			var original := A.evolved_state(old,Finite.new().load_chapter("chapter_01_shiganshina").chapter,evolution)
			var candidate := A.evolved_state(current,X.chapter(),evolution)
			# Immutable purchased bonus uses the existing run config/rules binding.
			if bonus > 0:
				for state in [original,candidate]:
					state.run_config.permanent_upgrades = {"permanent_might":bonus}
					state.rules.permanent_damage_bonus = 0.05*bonus
			for tick in 100:
				var commands := [F.spawn("original-evolved-target",[45,0],"brute")] if tick == 0 else []
				t.check(F.step(old,original,Vector2.ZERO,commands) == F.step(current,candidate,Vector2.ZERO,commands),"original evolved schedules and hits remain unchanged "+evolution)
