extends SceneTree
const Core = preload("res://game/core/run_simulation.gd")
const City = preload("res://game/director/streamed_chapter_provider.gd")
const H = preload("res://game/core/streamed_run_world.gd")
const F = preload("res://tests/core/core_fixture.gd")
const D = preload("res://game/director/spawn_director.gd")
const Disk = preload("res://game/persistence/world_delta_store.gd")
func _initialize() -> void:
	var provider := City.new()
	var chapter: Dictionary = provider.load_chapter("chapter_01_shiganshina").chapter
	var core := Core.new(provider)
	var state := core.new_run(chapter,42,F.run_config())
	state.player.position = [384.0,384.0]
	var disk := Disk.new("/tmp/city_continuity_travel_%d"%OS.get_process_id())
	disk.prepare(state.world.delta_root,[],0)
	var needed := H.requirements(state)
	var hydration := disk.hydrate(state.world.delta_root,needed.chunks)
	print("INITIAL ",core.prepare_world(state,hydration.deltas))
	var director := D.new()
	var tick_limit := 4500
	var endurance := "--endurance" in OS.get_cmdline_user_args()
	if endurance:
		tick_limit = 108000
		print("ENDURANCE_FIXTURE hp_refill_between_ticks=true target_active_ticks=108000")
	var peak_entities := 0
	var peak_drops := 0
	for tick in tick_limit:
		# Explicit endurance fixture only: isolate world/population lifetime from
		# combat survivability. Default4500 replay remains unmodified gameplay.
		if endurance: state.player.hp = state.player.max_hp
		var commands: Array[Dictionary] = director.plan(state,chapter)
		for command in commands:
			if H.spatial_command(command): command.origin_revision = state.world.origin_revision
		core.step(state,Vector2.RIGHT,commands)
		var status := core.step_status()
		if not status.get("ok",false):
			needed = H.requirements(state,commands)
			if status.get("error_code") == "world_not_ready" and needed.get("ok",false):
				hydration = disk.hydrate(state.world.delta_root,needed.chunks)
				status = core.prepare_world(state,hydration.deltas,commands)
				if status.get("ok",false):
					core.step(state,Vector2.RIGHT,commands)
					status = core.step_status()
			if not status.get("ok",false):
				print("TRAVEL_FAILURE ",JSON.stringify({"tick":tick,"active_tick":state.active_tick,"player":state.player.position,"origin":state.world.origin_chunk,"entities":state.entities.size(),"status":status,"needed":needed}))
				FileAccess.open("/tmp/city-continuity-travel-refused.json",FileAccess.WRITE).store_string(JSON.stringify({"state":state,"commands":commands},"",true,true))
				quit(1)
				return
		while not state.upgrade_offer.is_empty():
			var selected := core.choose_upgrade(state,state.upgrade_offer.offer_id,state.upgrade_offer.options[0].option_id)
			if not selected.get("ok",false):
				print("OFFER_FAILURE ",selected)
				quit(2)
				return
		peak_entities = maxi(peak_entities,state.entities.size()+state.world.get("dormant",{}).get("entities",[]).size())
		peak_drops = maxi(peak_drops,state.drops.size()+state.world.get("dormant",{}).get("drops",[]).size())
		if state.phase in ["dead","won"]:
			print("TRAVEL_TERMINAL ",state.phase," tick=",state.active_tick)
			quit(3)
			return
		if tick % (6000 if endurance else 600) == 0: print("TRAVEL_PROGRESS ",tick," ",state.world.origin_chunk," ",state.player.position," entities=",state.entities.size()," active_tick=",state.active_tick)
	print("TRAVEL_SUCCESS ",state.active_tick," ",state.world.origin_chunk," ",state.player.position," phase=",state.phase," peak_bodies=",peak_entities," peak_drops=",peak_drops," dormant=",state.world.get("dormant",{})," bosses_fired=",state.boss_ids_fired)
	quit(0)
