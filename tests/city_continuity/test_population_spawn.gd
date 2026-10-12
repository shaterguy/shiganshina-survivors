extends RefCounted
const Core = preload("res://game/core/run_simulation.gd")
const City = preload("res://game/director/streamed_chapter_provider.gd")
const H = preload("res://game/core/streamed_run_world.gd")
const P = preload("res://game/core/city_population.gd")
const F = preload("res://tests/core_world/new_streamed_helper_fixture.gd")
const C = preload("res://tests/core/core_fixture.gd")
var _tester
func check(ok: bool, msg: String) -> void:
	_tester.check(ok,msg)
func fixture() -> Dictionary:
	var provider := City.new()
	var chapter: Dictionary = provider.load_chapter("chapter_01_shiganshina").chapter
	var core := Core.new(provider)
	var state := core.new_run(chapter,42,C.run_config())
	state.player.position = [384.0,384.0]
	state.player.attack_ready_ticks = {"blade_slash":1000000}
	state.active_tick = 17999; state.survival_tick = 17999
	var command := {"command_id":"fixture-boss","kind":"spawn_boss","origin_revision":0,"payload":{"entity_id":"parked-boss","enemy_id":"boss_charger","boss_id":"ch01_b05","position":[-1154.0,384.0],"scheduled_tick":18000}}
	var hydration := F.hydration(H.requirements(state,[command]))
	check(core.prepare_world(state,hydration,[command]).get("ok",false),"initial fixture prepares")
	C.step(core,state,Vector2.ZERO,[command]); C.step(core,state,Vector2.ZERO)
	check(state.world.schema_version == 2 and state.world.dormant.entities.size() == 1,"fixture has one genuinely parked boss")
	return {"core":core,"state":state,"hydration":hydration}
func run(t) -> void:
	_tester = t
	for mode in ["duplicate_id","global_cap"]:
		var f := fixture()
		var seed_command := {"command_id":"seed","kind":"spawn_enemy","origin_revision":0,"payload":{"entity_id":"seed-walker","enemy_id":"walker","position":[650.0,384.0],"spawned_tick":18001}}
		if mode == "global_cap":
			C.step(f.core,f.state,Vector2.ZERO,[seed_command])
			var template: Dictionary = f.state.entities[0].duplicate(true)
			f.state.entities.clear()
			for i in 511:
				var actor: Dictionary = template.duplicate(true)
				actor.id = "ordinary-%d"%i; actor.entity_id = actor.id
				f.state.entities.append(actor)
		var hydration := F.hydration(H.requirements(f.state))
		var valid: Dictionary = f.core.prepare_world(f.state,hydration)
		check(valid.get("ok",false),"adversarial input cold-valid: "+mode)
		var command := seed_command.duplicate(true)
		command.command_id = "challenge:"+mode
		command.payload.entity_id = "parked-boss" if mode == "duplicate_id" else "new-ordinary"
		command.payload.spawned_tick = f.state.active_tick
		C.step(f.core,f.state,Vector2.ZERO,[command])
		var total: int = f.state.entities.size()+f.state.world.dormant.entities.size()
		var restored: Dictionary = f.core.restore(f.state,hydration)
		print("PROBE ",JSON.stringify({"mode":mode,"status":f.core.step_status(),"total_bodies":total,"restore_ok":restored.get("ok",false),"restore_error":restored.get("error_code","")}))
		check(total <= 512,"spawn enforces combined active+dormant512 body bound")
		check(restored.get("ok",false),"successful tick remains cold-restorable: "+mode)
