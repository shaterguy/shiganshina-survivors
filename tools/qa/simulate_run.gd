extends SceneTree
const Simulation = preload("res://game/core/run_simulation.gd")
const Director = preload("res://game/director/spawn_director.gd")
const Chapters = preload("res://game/director/chapter_catalog.gd")
const Geometry = preload("res://game/combat/attack_geometry.gd")
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var seed_value := 42
	var args := OS.get_cmdline_user_args()
	if not args.is_empty(): seed_value = int(args[0])
	var chapter: Dictionary = Chapters.new().load_chapter("chapter_01_shiganshina").chapter
	var sim := Simulation.new()
	var director := Director.new()
	var state: Dictionary = sim.new_run(chapter,seed_value)
	var start := Time.get_ticks_usec()
	var worst_us := 0
	var max_entities := 0
	var choices := 0
	var priority := ["blade_slash","spin_slash","wall_cannon","ally_cover","damage","fire_interval","movement","recovery","armor","max_health","range","pickup"]
	for tick in range(114000):
		if state.phase in ["won","dead"]: break
		if not state.upgrade_offer.is_empty():
			var selected: Dictionary = state.upgrade_offer.options[0]
			var best := 100
			for option in state.upgrade_offer.options:
				var rank: int = priority.find(str(option.item_id))
				if option.kind == "recovery": rank = -1 if float(state.player.hp)/float(state.player.max_hp)<0.5 else 50
				if rank >= 0 and rank < best:
					best = rank
					selected = option
			sim.choose_upgrade(state,state.upgrade_offer.offer_id,selected.option_id)
			choices += 1
		var position := Vector2(state.player.position[0],state.player.position[1])
		var nearest := Vector2(10000,10000)
		for enemy in state.entities:
			var offset := Vector2(enemy.position[0],enemy.position[1])-position
			if offset.length() < nearest.length(): nearest = offset
		var move := Vector2.ZERO
		if nearest.length() > 65 and nearest.length() < 900: move = nearest.normalized()
		elif nearest.length() < 45: move = -nearest.normalized()
		elif nearest.length() < 900: move = nearest.normalized().orthogonal()
		for danger in state.telegraphs:
			if Geometry.overlaps(danger,position,24):
				var direction := Vector2(danger.direction[0],danger.direction[1])
				move = direction.orthogonal() if danger.shape != "circle" else Vector2(danger.origin[0],danger.origin[1]).direction_to(position)
				if move.is_zero_approx(): move = Vector2.RIGHT
		if state.phase == "evacuation" and state.telegraphs.is_empty():
			var zone: Array = state.escape_zone
			move = position.direction_to(Vector2(zone[0]+zone[2]/2,zone[1]+zone[3]/2))
		var before := Time.get_ticks_usec()
		sim.step(state,move,director.plan(state,chapter))
		worst_us = maxi(worst_us,Time.get_ticks_usec()-before)
		max_entities = maxi(max_entities,state.entities.size())
		if state.active_tick%18000 == 0: print("MILESTONE ",state.active_tick," HP ",state.player.hp," LV ",state.player.level," entities ",state.entities.size())
	var report := {"seed":seed_value,"phase":state.phase,"active_tick":state.active_tick,"survival_tick":state.survival_tick,"hp":state.player.hp,"level":state.player.level,"kills":state.stats.kills,"boss_ids":state.boss_ids_fired,"boss_kills":state.stats.minibosses_defeated,"equipment":state.equipment,"passives":state.passives,"choices":choices,"max_entities":max_entities,"worst_tick_us":worst_us,"wall_seconds":float(Time.get_ticks_usec()-start)/1000000.0,"static_memory_bytes":OS.get_static_memory_usage(),"limit":"Deterministic heuristic bot, not a human balance or Android frame-rate test."}
	DirAccess.make_dir_recursive_absolute("res://dist/qa")
	var file := FileAccess.open("res://dist/qa/bot-%d.json" % seed_value,FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	print(JSON.stringify(report))
	quit()
