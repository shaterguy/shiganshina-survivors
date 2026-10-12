extends "res://tests/core/core_fixture.gd"
# Current combat arrangements use actual gameplay definitions with an explicit
# finite_test identity. Frozen historical providers and saves remain unchanged.
const Current = preload("res://tests/core/current_combat_provider.gd")
const Core = preload("res://game/core/run_simulation.gd")
const Chapters = preload("res://game/director/chapter_catalog.gd")
static func chapter() -> Dictionary:
	return Current.new().load_chapter("chapter_01_shiganshina").chapter
static func simulation(t):
	var sim := Core.new(Current.new())
	t.check(not sim.new_run(chapter(),1,run_config()).has("error_code"),"explicit current finite combat provider constructs current Core")
	return sim
static func spawn(id: String, position: Array, enemy_id := "walker") -> Dictionary:
	return {"command_id":"spawn:"+id,"kind":"spawn_enemy","payload":{"entity_id":id,"enemy_id":enemy_id,"position":position,"spawned_tick":0}}
static func boss(id: String, position: Array) -> Dictionary:
	var definition: Dictionary = chapter().boss_schedule[["ch01_b05","ch01_b10","ch01_b15","ch01_b20","ch01_b25"].find(id)]
	return {"command_id":"boss:"+id,"kind":"spawn_boss","payload":{"entity_id":"entity:"+id,"boss_id":id,"enemy_id":definition.enemy_id,"position":position,"scheduled_tick":definition.tick}}
static func actor_command(state: Dictionary, enemy_id: String, position: Array, entity_id: Variant = "actor") -> Dictionary:
	if enemy_id.begins_with("boss_"):
		for definition in chapter().boss_schedule:
			if definition.enemy_id != enemy_id: continue
			state.active_tick = int(definition.tick)-1
			state.survival_tick = state.active_tick
			var command := boss(definition.boss_id,position)
			command.payload.entity_id = entity_id
			return command
	return {"command_id":"spawn:"+str(entity_id),"kind":"spawn_enemy","payload":{"entity_id":entity_id,"enemy_id":enemy_id,"position":position,"spawned_tick":0}}
static func drop_xp(sim, state: Dictionary, xp: int, id := "arranged_xp") -> Array[Dictionary]:
	state.drops.append({"id":id,"position":state.player.position.duplicate(),"xp":xp})
	return step(sim,state,Vector2.ZERO)
static func earn_offer(sim, seed := 21, xp := 24) -> Dictionary:
	var state: Dictionary = sim.new_run(chapter(),seed,run_config())
	drop_xp(sim,state,xp)
	return state
static func final_command(state: Dictionary, id := "final") -> Dictionary:
	return {"command_id":id,"kind":"begin_evacuation","payload":{"boss_id":"ch01_final_armored","escape_zone":state.escape_zone.duplicate(),"evacuation_ticks":4500}}
static func boss_reward_state(sim, seed := 11) -> Dictionary:
	var state: Dictionary = sim.new_run(chapter(),seed,run_config())
	state.active_tick = 17999
	state.survival_tick = 17999
	state.player.attack_ready_ticks.blade_slash = 18001
	state.player.hp = 50.0
	state.player.level = 3
	step(sim,state,Vector2.ZERO,[boss("ch01_b05",[25,0])])
	# Arrange only remaining health, then use the real killing hit/reward path.
	state.entities[0].hp = 12.0
	return state

# Geometry-only arrangements retain current gameplay definitions. Their derived
# finite_test identity includes the new geometry and spawn; Core validates the
# explicit test provider without weakening production or historical identities.
class GeometryProvider:
	extends RefCounted
	var _definition: Dictionary
	func _init(world: Dictionary, spawn_position: Array) -> void:
		_definition = Current.new().load_chapter("chapter_01_shiganshina").chapter
		var base_fingerprint: String = _definition.content_fingerprint
		_definition.world_geometry = world.duplicate(true)
		_definition.spawn_position = spawn_position.duplicate()
		_definition.escape_zone = [-20.0,280.0,40.0,40.0]
		_definition.content_identity_kind = "current_finite_regression_geometry"
		_definition.content_fingerprint = Chapters.new().definition_digest({"base_fingerprint":base_fingerprint,"geometry_arrangement":_definition})
	func load_chapter(id: String) -> Dictionary:
		return {"ok":true,"chapter":_definition.duplicate(true)} if id == _definition.chapter_id else {"ok":false,"error_code":"unknown_chapter"}
static func geometry_chapter(world: Dictionary, position := [150,0]) -> Dictionary:
	return GeometryProvider.new(world,position).load_chapter("chapter_01_shiganshina").chapter
static func geometry_sim(chapter_data: Dictionary):
	return Core.new(GeometryProvider.new(chapter_data.world_geometry,chapter_data.spawn_position))
