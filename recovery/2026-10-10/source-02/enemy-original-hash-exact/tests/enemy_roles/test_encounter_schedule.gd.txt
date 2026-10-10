extends RefCounted
func run(t) -> void:
	var path := "res://game/director/enemy_encounter_schedule.gd"
	t.check(FileAccess.file_exists(path),"independent role introduction schedule exists")
	if not FileAccess.file_exists(path): return
	var schedule = load(path)
	t.check(schedule != null and schedule.can_instantiate(),"role schedule compiles")
	if schedule == null or not schedule.can_instantiate(): return
	test_unlocks_and_introductions(t,schedule)
	test_inputs_and_boss_schedule_preserved(t,schedule)
	test_singleton_batches_rotate_within_pairs(t,schedule)
func test_unlocks_and_introductions(t,schedule) -> void:
	var ids := ["walker","runner","grabber","sweeper","brute","leaper"]
	var ticks := [0,2100,4500,7200,10800,23400]
	for index in ids.size():
		var id: String = ids[index]
		var unlock: int = ticks[index]
		t.check(not schedule.available_roles(unlock-1).has(id),id + " locked at preceding tick")
		for offset in [0,1]: t.check(schedule.available_roles(unlock+offset).has(id),id + " exact unlock boundary")
		if index == 0: continue
		for offset in [0,1,599]:
			var roles: Array = schedule.choose_roles(unlock+offset,12,7)
			t.check(roles.size() == 7 and roles.count(id) == 1 and roles.count("walker") == 6,id + " first 600 ticks introduce at most one with walkers")
		var after: Array = schedule.choose_roles(unlock+600,index-1,7)
		t.check(after.count(id) > 1,id + " ordinary combination opens exactly after introduction")
	var pairs := [["walker","runner"],["walker","grabber"],["walker","sweeper"],["brute","runner"],["leaper","walker"]]
	for ordinal in range(10):
		var roles: Array = schedule.choose_roles(30000,ordinal,7)
		for index in roles.size(): t.check(roles[index] == pairs[ordinal%5][index%2],"stable approved pair rotation")
	for tick in [0,2700,5100,7800,11400,24000]:
		var allowed: Array = schedule.available_roles(tick)
		for ordinal in range(8):
			for role in schedule.choose_roles(tick,ordinal,7): t.check(role in allowed,"combination never chooses locked role")
func test_inputs_and_boss_schedule_preserved(t,schedule) -> void:
	for count in [0,1,7]:
		var first: Array = schedule.choose_roles(30000,42,count)
		t.check(first.size() == count and first == schedule.choose_roles(30000,42,count),"requested count and deterministic ordinal")
	for bad in [[-1,0,7],[0,-1,7],[0,0,-1],[108000,0,7],[112500,0,7]]:
		t.check(schedule.choose_roles(bad[0],bad[1],bad[2]).is_empty(),"invalid or evacuation wave is empty")
	for tick in [18000,36000,54000,72000,90000]:
		for role in schedule.choose_roles(tick,7,7): t.check(not str(role).begins_with("boss_") and role != "thrower_original","ordinary selector does not own bosses or throwers")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://chapters/chapter_01/manifest.json"))
	var before := manifest.duplicate(true)
	schedule.choose_roles(90000,3,7)
	t.check(manifest == before,"pure schedule does not mutate chapter input")

func test_singleton_batches_rotate_within_pairs(t,schedule) -> void:
	# Exact independent-review probes: retained early waves have count one,
	# and the live director can admit only one free slot in later waves.
	var expected := {2700:{"walker":10,"runner":10},5100:{"walker":10,"runner":5,"grabber":5},30000:{"walker":8,"runner":4,"grabber":2,"sweeper":2,"brute":2,"leaper":2}}
	for tick in expected:
		var counts := {}
		for ordinal in range(20):
			var role: String = schedule.choose_roles(tick,ordinal,1)[0]
			counts[role] = int(counts.get(role,0))+1
		t.check(counts == expected[tick],"singleton cycle continues each learned pair member at " + str(tick))
	for tick in [2700,5100,7800,11400,24000,30000]:
		for ordinal_start in [0,17,200]:
			var seen: Array[String] = []
			for ordinal in range(ordinal_start,ordinal_start+20):
				var selected: Array = schedule.choose_roles(tick,ordinal,1)
				t.check(selected == schedule.choose_roles(tick,ordinal,1),"singleton selection is deterministic")
				if not selected[0] in seen: seen.append(selected[0])
			for role in schedule.available_roles(tick): t.check(role in seen,"learned role cannot starve under repeated singleton admission: " + role)
	# Existing full pair order remains fixed even after singleton calls.
	var pairs := [["walker","runner"],["walker","grabber"],["walker","sweeper"],["brute","runner"],["leaper","walker"]]
	for ordinal in range(20):
		schedule.choose_roles(30000,ordinal,1)
		t.check(schedule.choose_roles(30000,ordinal,2) == pairs[ordinal%5],"singleton fix preserves full-pair ordering")
