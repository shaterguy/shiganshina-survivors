extends RefCounted
# NEW exit-sentinel boundary only. Automatic rebasing and scene transitions are
# separate integration work; this uses the real pure proposal and actual store.
const Core = preload("res://game/core/run_simulation.gd")
const City = preload("res://game/director/streamed_chapter_provider.gd")
const Helper = preload("res://game/core/streamed_run_world.gd")
const Disk = preload("res://game/persistence/world_delta_store.gd")
const Save = preload("res://game/persistence/game_save_store.gd")
const Adapter = preload("res://game/app/world_checkpoint_adapter.gd")
const F = preload("res://tests/core/core_fixture.gd")
func run(t) -> void:
	for origin in [["0","0"],["9007199254740993","-9007199254740994"]]:
		_disk_cut(t,origin)
	var finite := Core.new()
	var state := finite.new_run(F.v2_chapter(),42,F.run_config())
	t.check(finite.restore(state).get("ok",false),"finite positive escape rectangle remains valid")
	state.escape_zone = [0,0,0,0]
	t.check(not finite.restore(state).get("ok",false),"city inactive exit is never admitted in finite state")
func _disk_cut(t,origin: Array) -> void:
	var path := "/tmp/c4_rebase_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()]
	var provider := City.new()
	var chapter: Dictionary = provider.load_chapter("chapter_01_shiganshina").chapter
	var validator := Core.new(provider)
	var disk := Disk.new(path.path_join("world"))
	var adapter := Adapter.new(disk,Callable(Helper,"requirements"),Callable(validator,"restore"))
	var store := Save.new(path,Callable(adapter,"validate_checkpoint"))
	var initial := store.load_game()
	t.check(initial.get("ok",false),"rebase disk test initializes real GameSave authority")
	if not initial.get("ok",false): return
	var config := F.run_config()
	config.run_id = initial.game_save.career_id+":1"
	config.loot_rules_version = 1 # Newly committed departures require the current optional rule marker.
	var sim := Core.new(provider)
	var source := sim.new_run(chapter,42,config)
	source.player.position = [1152.0,384.0]
	source.world.origin_chunk = origin.duplicate()
	t.check(source.escape_zone == [0.0,0.0,0.0,0.0],"city constructor owns only an inactive exit sentinel")
	var root := disk.prepare(source.world.delta_root,[],0)
	var hydration := disk.hydrate(source.world.delta_root,Helper.requirements(source).chunks)
	t.check(root.ok and hydration.ok and sim.prepare_world(source,hydration.deltas).ok,"pre-rebase state is real Core-valid with verified disk terrain")
	var game: Dictionary = initial.game_save.duplicate(true)
	game.next_run_serial = 2
	game.checkpoint = source.duplicate(true)
	var saved := store.commit_game(game,int(game.store_revision))
	t.check(saved.get("ok",false),"pre-rebase Core state durably commits")
	if not saved.get("ok",false): return
	var before := source.duplicate(true)
	var command := {"command_id":"future-final","kind":"begin_evacuation","origin_revision":0,"payload":{"boss_id":"ch01_final_armored","escape_zone":source.escape_zone.duplicate(),"evacuation_ticks":4500}}
	var old_command := command.duplicate(true)
	var proposal := Helper.rebase_proposal(source,[command])
	t.check(proposal.get("ok",false) and proposal.get("changed",false),"actual helper proposes a one-chunk rebase")
	if not proposal.get("ok",false): return
	t.check(source == before and command == old_command,"rebase proposal preserves caller state and command")
	t.check(proposal.state.escape_zone == [0.0,0.0,0.0,0.0] and proposal.commands[0].payload.escape_zone == [0.0,0.0,0.0,0.0],"inactive city state and command exits are never translated")
	t.check(proposal.state.player.position == [384.0,384.0] and proposal.state.world.origin_revision == 1 and proposal.commands[0].origin_revision == 1,"live positions and command revision shift exactly once")
	var expected_x := "1" if origin[0] == "0" else "9007199254740994"
	t.check(proposal.state.world.origin_chunk == [expected_x,origin[1]],"rebase preserves full int64 absolute chunk address")
	var next_hydration := disk.hydrate(proposal.state.world.delta_root,Helper.requirements(proposal.state).chunks)
	var cut = JSON.parse_string(JSON.stringify(proposal.state,"",true,true))
	var restored := sim.restore(cut,next_hydration.deltas)
	t.check(restored.get("ok",false),"rebased state restores after full-precision JSON save cut")
	t.check(restored.get("ok",false) and restored.state == proposal.state,"rebased JSON cut retains exact canonical state types")
	var candidate: Dictionary = saved.game_save.duplicate(true)
	candidate.checkpoint = cut
	var committed := store.commit_game(candidate,int(candidate.store_revision))
	t.check(committed.get("ok",false),"actual GameSave commits the rebased checkpoint")
	if committed.get("ok",false):
		var fresh := Core.new(City.new())
		var cold_adapter := Adapter.new(Disk.new(path.path_join("world")),Callable(Helper,"requirements"),Callable(fresh,"restore"))
		var loaded := Save.new(path,Callable(cold_adapter,"validate_checkpoint")).load_game()
		t.check(loaded.get("ok",false) and loaded.game_save == committed.game_save,"cold disk load validates the exact rebased player/world pair")
		if loaded.get("ok",false):
			var state: Dictionary = loaded.game_save.checkpoint
			t.check(fresh.prepare_world(state,next_hydration.deltas).ok,"fresh rebased Core adopts matching terrain")
			F.step(fresh,state,Vector2.RIGHT)
			t.check(state.active_tick == 1 and state.player.position == [386.5,384.0] and fresh.restore(state,next_hydration.deltas).get("ok",false),"restored rebased Core moves and remains restorable")
	_dock_exit(t,sim,source,hydration.deltas,chapter)
	for bad in [[0,0,1,1],[-56,320,112,80],[0,0,0,false],[0,0,0,NAN]]:
		var invalid := source.duplicate(true)
		invalid.escape_zone = bad
		t.check(not sim.restore(invalid,hydration.deltas).get("ok",false),"city restore rejects non-sentinel or unsafe exit: "+str(bad))
		t.check(not Helper.rebase_proposal(invalid).get("ok",false),"city rebase rejects non-sentinel or unsafe exit: "+str(bad))

func _dock_exit(t,sim,source: Dictionary,hydration: Dictionary,chapter: Dictionary) -> void:
	var state := source.duplicate(true)
	state.active_tick = 107999
	state.survival_tick = 107999
	# This historical source has not yet installed its matching resident terrain.
	# Add due pending records without geometry queries; real placement runs after prepare.
	for index in range(sim.Loot.FIELD_TICKS.size()):
		sim._add_loot(state,sim.Loot.field_spec(index),Vector2(state.player.position[0],state.player.position[1]))
	var final_prepared: Dictionary = sim.prepare_world(state,hydration)
	if not final_prepared.get("ok",false): print("LOOT_REBASE_FINAL_PREPARE ",JSON.stringify({"result":final_prepared,"loot_valid":sim.Loot.validate(state),"loot":state.loot,"origin":state.world.origin_chunk,"player":state.player.position}))
	t.check(final_prepared.ok,"sentinel survives preparation immediately before final command")
	var command := {"command_id":"actual-final","kind":"begin_evacuation","origin_revision":state.world.origin_revision,"payload":{"boss_id":"ch01_final_armored","escape_zone":[0,0,0,0],"evacuation_ticks":4500}}
	F.step(sim,state,Vector2.ZERO,[command])
	t.check(state.phase == "evacuation" and state.escape_zone == [0.0,0.0,0.0,0.0] and sim.restore(state,hydration).get("ok",false),"actual city begin_evacuation preserves inactive city exit")
	var canonical: Dictionary = sim.restore(state,hydration)
	t.check(canonical.get("ok",false) and canonical.state == state,"integral JSON command exit becomes canonical live state immediately")
	var passage: Dictionary = sim._streamed.passage_proposal(state)
	t.check(passage.get("ok",false),"actual city navigation selects a connected absolute evacuation passage")
	if not passage.get("ok",false): return
	state.world = passage.world
	var transition := {"command_id":"dock-exit-contract","kind":"dock_transition","origin_revision":state.world.origin_revision,"payload":{"passage_id":state.world.evacuation.passage_id}}
	var proposal: Dictionary = sim._streamed.dock_transition_proposal(state,transition,chapter.authored_dock)
	t.check(proposal.get("ok",false),"real dock proposal validates physical passage contact")
	if not proposal.get("ok",false): return
	state.world = proposal.candidate_world
	state.player.position = [proposal.player_position.x,proposal.player_position.y]
	state.escape_zone = chapter.authored_dock.escape_rect.duplicate()
	sim.transfer_loot_to_dock(state)
	t.check(sim.restore(state).get("ok",false),"dock checkpoint requires and accepts its actual authored exit rectangle")
	state.escape_zone = [0,0,0,0]
	t.check(not sim.restore(state).get("ok",false),"inactive city sentinel is forbidden after docking")
