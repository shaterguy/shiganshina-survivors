extends RefCounted
const Core = preload("res://game/core/run_simulation.gd")
const Chapters = preload("res://game/director/chapter_catalog.gd")
const F = preload("res://tests/core/core_fixture.gd")
const Director = preload("res://game/director/spawn_director.gd")
class Provider:
	extends RefCounted
	var chapter: Dictionary
	func _init(geometry: Dictionary, position: Array = [0.0,0.0]):
		chapter = Chapters.new().load_chapter("chapter_01_shiganshina").chapter
		chapter.world_mode = "finite_test"
		chapter.world_geometry = geometry.duplicate(true)
		chapter.spawn_position = position.duplicate()
		chapter.escape_zone = [-56.0,1200.0,112.0,80.0]
		chapter.content_identity_kind = "armored_finite_test"
		chapter.content_fingerprint = Chapters.new().definition_digest(chapter)
	func load_chapter(id: String) -> Dictionary:
		return {"ok":true,"chapter":chapter.duplicate(true)} if id == chapter.chapter_id else {"ok":false}
static func make(geometry: Dictionary = {"bounds":[-2000,-2000,4000,4000],"obstacles":[]}, position: Array = [0.0,0.0]) -> Dictionary:
	var provider := Provider.new(geometry,position)
	var core := Core.new(provider)
	var state := core.new_run(provider.chapter,42,F.run_config())
	state.active_tick = 107999
	state.survival_tick = 107999
	state.player.attack_ready_ticks.blade_slash = 200000
	return {"core":core,"state":state,"chapter":provider.chapter,"provider":provider}
static func begin(f: Dictionary) -> Array[Dictionary]:
	return F.step(f.core,f.state,Vector2.ZERO,Director.new().plan(f.state,f.chapter))
static func actor(state: Dictionary) -> Dictionary:
	for entity in state.entities:
		if entity.enemy_id == "armored_titan": return entity
	return {}
static func step(f: Dictionary, direction: Vector2 = Vector2.ZERO) -> Array[Dictionary]:
	return F.step(f.core,f.state,direction,Director.new().plan(f.state,f.chapter))
static func arrange_windup(f: Dictionary, point: Vector2, player: Vector2) -> void:
	var a := actor(f.state)
	a.position = [point.x,point.y]
	f.state.player.position = [player.x,player.y]
	f.state.telegraphs.clear()
	f.core._set_action(a,"move",int(f.state.active_tick),0)
	a.next_action_tick = int(f.state.active_tick)
	step(f)
