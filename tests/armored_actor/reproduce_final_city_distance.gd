extends SceneTree
const R = preload("res://tests/armored_actor/test_armored_rebase.gd")
const S = preload("res://tests/armored_actor/armored_support.gd")
const H = preload("res://game/core/streamed_run_world.gd")
const F = preload("res://tests/core_world/new_streamed_helper_fixture.gd")
func check(value: bool, label: String):
	if not value: print("SETUP_FAILED ",label)
func _initialize(): call_deferred("run")
func run():
	var f := R.new()._make(self)
	f.state.passives.movement = 5
	var actor := S.actor(f.state)
	actor.position = [506.0,384.0]
	actor.locked_origin = actor.position.duplicate()
	f.state.telegraphs.clear()
	var needed := H.requirements(f.state)
	f.core.prepare_world(f.state,F.hydration(needed))
	for tick in 4500:
		f.state.player.hp = f.state.player.max_hp
		var before: int = f.state.active_tick
		S.step(f,Vector2.RIGHT)
		if f.state.active_tick == before:
			needed = H.requirements(f.state)
			if needed.get("ok",false):
				var ready: Dictionary = f.core.prepare_world(f.state,F.hydration(needed))
				if ready.get("ok",false): S.step(f,Vector2.RIGHT)
			if f.state.active_tick == before:
				print("FINAL_CITY_DISTANCE_BLOCK ",JSON.stringify({"elapsed":f.state.active_tick-108000,"status":f.core.step_status(),"requirements":needed,"actor":S.actor(f.state).position,"player":f.state.player.position,"phase":S.actor(f.state).action_state}))
				quit(1); return
	print("FINAL_CITY_DISTANCE_COMPLETE ",f.state.active_tick)
	quit()
