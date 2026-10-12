extends RefCounted
func run(t) -> void:
	var path := "res://game/presentation/city_render.gd"
	t.check(FileAccess.file_exists(path),"CityRender module exists")
	if not FileAccess.file_exists(path): return
	var r = load(path)
	var house := {"prop_id":"house","asset_id":"house_narrow","position":Vector2(100,224),"depth_y":224.0,"render_bounds":Rect2(20,32,160,192),"pose":"intact"}
	var world := {"stage":"city","chunks":[{"chunk_id":"0,0","local_origin":Vector2.ZERO,"ground_variant":2,"props":[house]}]}
	var actors := [_actor("rear",210),_actor("front",240),_actor("player",215)]
	actors[2].is_player = true
	var camera := Rect2(0,0,400,300)
	var result: Dictionary = r.build(world,actors,[],[],camera)
	t.check(result.upright.map(func(c): return c.id) == ["actor:s:rear","actor:s:player","house","actor:s:front"],"rear Titan and player behind house; front Titan ahead")
	t.check(result.visibility_markers.size() == 1 and result.visibility_markers[0].kind == "player_outline","occluded player gets outline data, no full-body foreground override")
	var roof: Dictionary = r.build(world,[],[],[],Rect2(0,0,200,150))
	t.check(roof.upright.size() == 1,"visible roof retained when foot below viewport")
	t.check(r.build(world,[],[],[],Rect2(300,0,100,100)).upright.is_empty(),"off-art-bounds house culled")
	var tied: Dictionary = r.build({"chunks":[]},[_actor("z",100),_actor("a",100)],[],[],camera)
	t.check(tied.upright.map(func(c): return c.id) == ["actor:s:a","actor:s:z"],"depth ties use stable IDs")
	var jumping := _actor("air",240)
	jumping.visual_height = 50.0
	var air: Dictionary = r.build(world,[jumping],[],[],camera)
	t.check(air.upright.back().depth_y == 240 and air.upright.back().position.y == 190 and air.ground.any(func(c): return c.kind == "shadow"),"airborne visual elevation preserves ground depth and shadow")
	var portrait: Dictionary = r.build(world,actors,[],[],Rect2(0,0,220,600))
	t.check(portrait.upright == result.upright,"portrait and landscape overlapping art has identical order")
	var shifted := world.duplicate(true)
	var offset := Vector2(-768,768)
	shifted.chunks[0].local_origin += offset
	shifted.chunks[0].props[0].position += offset
	shifted.chunks[0].props[0].depth_y += offset.y
	shifted.chunks[0].props[0].render_bounds.position += offset
	var shifted_actors := actors.duplicate(true)
	for a in shifted_actors:
		a.position += offset
		a.depth_y += offset.y
		a.render_bounds.position += offset
	camera.position += offset
	var rebased: Dictionary = r.build(shifted,shifted_actors,[],[],camera)
	t.check(rebased.upright.map(func(c): return c.id) == result.upright.map(func(c): return c.id),"whole-chunk rebase preserves depth ordering")
	for i in result.upright.size(): t.check(rebased.upright[i].position-result.upright[i].position == offset,"rebase relative art position invariant")
	_numeric_identity_regressions(t,r)
	_actual_core_projectile_regression(t,r)

static func _actor(id: Variant,y: float) -> Dictionary:
	return {"id":id,"asset_id":"titan_basic","position":Vector2(100,y),"depth_y":y,"render_bounds":Rect2(52,y-144,96,144),"pose":"move"}

func _numeric_identity_regressions(t,r) -> void:
	var camera := Rect2(0,0,200,200)
	# Exact independent-review reproducer: valid local geometry with numeric id7.
	var projectile := {"id":7,"asset_id":"vfx_cannon_shell","position":Vector2(100,100),"render_bounds":Rect2(96,96,8,8)}
	var result: Dictionary = r.build({"chunks":[]},[],[],[projectile],camera)
	t.check(result.get("upright",[]).size() == 1,"numeric projectile review probe returns a full packet without engine error")
	if result.get("upright",[]).is_empty(): return
	t.check(result.upright[0].id == "projectile:i:7" and result.upright[0].source_id == 7,"numeric projectile normalized once with source identity retained")
	var numeric_actor := _actor(7,100)
	var string_actor := _actor("7",100)
	var fallback_actor := _actor("unused",100)
	fallback_actor.erase("id")
	fallback_actor.entity_id = 8
	var corpse := _actor(7,100)
	var fallback_projectile := projectile.duplicate(true)
	fallback_projectile.erase("id")
	fallback_projectile.projectile_id = 7
	var actors := [string_actor,fallback_actor,numeric_actor]
	var before := actors.duplicate(true)
	var mixed: Dictionary = r.build({"chunks":[]},actors,[corpse],[fallback_projectile],camera)
	var ids: Array = mixed.upright.map(func(c): return c.id)
	t.check(ids == ["actor:i:7","actor:i:8","actor:s:7","corpse:i:7","projectile:i:7"],"mixed numeric/string and actor/corpse/projectile identities have deterministic namespace-safe depth ties")
	actors.reverse()
	t.check(r.build({"chunks":[]},actors,[corpse],[fallback_projectile],camera).upright == mixed.upright,"depth ties independent of input order")
	actors.reverse()
	t.check(actors == before,"render identity normalization does not mutate input")
	var parsed := projectile.duplicate(true)
	parsed.id = JSON.parse_string('{"id":7}').id
	t.check(r.build({"chunks":[]},[],[],[parsed],camera).upright[0].id == "projectile:i:7","integral JSON numeric identity normalizes identically to core int")
	for invalid_id in [1.5,INF,[],{},null]:
		var invalid := projectile.duplicate(true)
		invalid.id = invalid_id
		var packet: Dictionary = r.build({"chunks":[]},[numeric_actor],[],[invalid],camera)
		t.check(not packet.get("ok",true) and packet.get("error_code") == "invalid_render_identity" and packet.get("upright",[]).is_empty(),"invalid identity rejects packet without partial command output")
	var shifted := projectile.duplicate(true)
	var offset := Vector2(-768,768)
	shifted.position += offset
	shifted.render_bounds.position += offset
	var translated_camera := camera
	translated_camera.position += offset
	var rebased: Dictionary = r.build({"chunks":[]},[],[],[shifted],translated_camera)
	t.check(rebased.upright[0].id == result.upright[0].id and rebased.upright[0].position-result.upright[0].position == offset and rebased.upright[0].depth_y-result.upright[0].depth_y == offset.y,"projectile rebase preserves namespace identity and relative geometry")
	t.check(r.build({"chunks":[]},[],[],[shifted],camera).upright.is_empty(),"numeric projectile culled only by local art bounds")
	var marked := numeric_actor.duplicate(true)
	marked.is_player = true
	marked.visual_height = 20.0
	var elevated: Dictionary = r.build({"chunks":[]},[marked],[],[],camera)
	t.check(elevated.visibility_markers[0].actor_id == "actor:i:7" and elevated.ground[0].id == "shadow:actor:i:7","numeric marker/shadow references use the same canonical identity")

func _actual_core_projectile_regression(t,r) -> void:
	var fixture = load("res://tests/core/core_fixture.gd")
	var sim = fixture.simulation(t)
	if sim == null: return
	# NEW fixture for the current Core contract, using authored chapter content.
	var state: Dictionary = sim.new_run(fixture.v2_chapter(),777,fixture.run_config())
	t.check(not state.has("error_code"),"actual RunSimulation projectile fixture accepts current chapter and run config")
	if state.has("error_code"): return
	state.equipment = {"wall_cannon":1}
	fixture.step(sim,state,Vector2.ZERO,[fixture.spawn("review-target",[200.0,0.0],"brute")])
	t.check(state.projectiles.size() == 1,"actual RunSimulation wall-cannon fixture emits one projectile")
	if state.projectiles.size() != 1: return
	var core: Dictionary = state.projectiles[0]
	t.check(core.id is int,"real core projectile identity is integer at adapter boundary")
	var point := Vector2(core.position[0],core.position[1])
	var radius: float = core.radius
	# I-owned geometry conversion is explicit; raw core position arrays never
	# enter the pure renderer, while the numeric identity remains unmodified.
	var dto := {"id":core.id,"asset_id":"vfx_cannon_shell","position":point,"render_bounds":Rect2(point-Vector2.ONE*radius,Vector2.ONE*radius*2)}
	var packet: Dictionary = r.build({"chunks":[]},[],[],[dto],Rect2(-64,-64,400,200))
	t.check(packet.get("upright",[]).size() == 1 and packet.get("upright",[])[0].id == "projectile:i:"+str(core.id) and packet.get("upright",[])[0].source_id == core.id,"actual core numeric projectile renders after explicit geometry normalization with source identity retained")
