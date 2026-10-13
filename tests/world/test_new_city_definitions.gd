extends RefCounted
# Newly authored definition tests. These do not assert lost historical layouts.
const Generator = preload("res://game/world/city_generator.gd")
const Catalog = preload("res://game/world/world_prop_catalog.gd")
const World = preload("res://game/world/streamed_world.gd")
const Navigation = preload("res://game/world/city_navigation.gd")
const Address = preload("res://game/world/world_address.gd")
const DEFINITIONS_PATH := "res://chapters/chapter_01/city_templates.json"
const GOLDEN_PATH := "res://tests/world/fixtures/NEW-city-vectors-dense-roofs.json"
const IDS := ["new_bakery_market","new_garrison_battery","new_supply_warehouses","new_breach_refuge"]

func run(t) -> void:
	var definitions: Dictionary = _read(DEFINITIONS_PATH)
	var props: Dictionary = _read("res://data/world_props.json")
	var generator = Generator.new(definitions,props)
	var errors: Array = generator.validate()
	t.check(errors.is_empty(),"NEW city data passes the recovered generator's contract and radius 8/32 connected-retreat checks: "+str(errors))
	if not errors.is_empty(): return
	t.check(definitions.get("provenance",{}).get("origin_class") == "newly_authored_compatible_definitions", "NEW data cannot claim original recovery")
	t.check(definitions.get("content_revision") == "ch01.3-rebuild.7-grabber-hand", "NEW data labels its distinct Core content revision")
	t.check(definitions.templates.map(func(template): return template.template_id) == IDS,"four independently named districts have stable generator order")
	_definition_semantics(t,definitions,props,generator)
	_connected_navigation(t,definitions,generator)
	_all_template_seams(t,generator)
	_new_vectors(t,generator)

func _definition_semantics(t,definitions: Dictionary,props: Dictionary,generator) -> void:
	var manifest: Dictionary = _read("res://assets/manifest.json")
	t.check(Catalog.validate(props,manifest).is_empty(),"existing prop footprint/art metadata agrees with the existing asset manifest")
	var signatures := {}
	for template in definitions.templates:
		var seed := _seed_for_template(generator,template.template_id,["0","0"])
		var chunk: Dictionary = generator.generate(seed,["0","0"])
		t.check(chunk.props.size() >= 8 and chunk.props.size() <= int(definitions.get("max_props",12)),"district stays within its bounded authored prop limit: "+template.template_id)
		var counts := {}
		var destructible_count := 0
		var durable_count := 0
		var geometry := []
		for prop in chunk.props:
			counts[prop.definition_id] = int(counts.get(prop.definition_id,0))+1
			geometry.append([prop.definition_id,prop.position.x,prop.position.y])
			var declared: Dictionary = props.definitions[prop.definition_id]
			t.check(prop.render_bounds == Rect2(prop.position+Vector2(declared.render_bounds[0],declared.render_bounds[1]),Vector2(declared.render_bounds[2],declared.render_bounds[3])),"art bounds follow catalog, not collision bounds: "+prop.prop_id)
			t.check(prop.depth_y == prop.position.y and prop.rotation_degrees == 0,"feet determine depth with unrotated existing raster art: "+prop.prop_id)
			if prop.collision_mask != 0:
				t.check(Rect2(0,0,768,768).encloses(prop.ground_footprint),"solid footprint stays in chunk: "+prop.prop_id)
				t.check(not prop.ground_footprint.intersects(Rect2(288,0,192,768)) and not prop.ground_footprint.intersects(Rect2(0,288,768,192)),"both reserved cross streets stay clear: "+prop.prop_id)
				t.check(prop.render_bounds.size.y > prop.ground_footprint.size.y,"upright art height differs from physical ground depth: "+prop.prop_id)
			if prop.destructible:
				destructible_count += 1
				var damaged: Dictionary = generator.hydrate(chunk,[{"slot_id":prop.slot_id,"hp":2,"destroyed":false}])
				var collapsed: Dictionary = generator.hydrate(chunk,[{"slot_id":prop.slot_id,"hp":0,"destroyed":true}])
				t.check(damaged.ok and collapsed.ok,"destructible district building accepts partial damage and collapse: "+prop.prop_id)
				var ruin: Dictionary = collapsed.chunk.props.filter(func(p): return p.slot_id == prop.slot_id)[0]
				t.check(ruin.collision_mask == 0 and ruin.cover_mask == 0 and ruin.asset_id == "burning_rubble" and ruin.ground_footprint.size == Vector2.ZERO,"collapse opens physical/cover space using existing rubble art: "+prop.prop_id)
			elif prop.collision_mask != 0:
				durable_count += 1
				var denied: Dictionary = generator.hydrate(chunk,[{"slot_id":prop.slot_id,"hp":0,"destroyed":true}])
				t.check(not denied.ok and denied.error_code == "invalid_prop_delta","durable district landmark cannot be destroyed: "+prop.prop_id)
		t.check(destructible_count >= 2 and durable_count >= 1,"each district offers breakable routes and durable cover: "+template.template_id)
		var signature: String = JSON.stringify(geometry)
		t.check(not signatures.has(signature),"district is not an empty or repeated layout: "+template.template_id)
		signatures[signature] = true
		var expected: Dictionary = {
			"new_bakery_market":{"house_bakery":2,"refugee_wagon":2},
			"new_garrison_battery":{"cannon_prop":4},
			"new_supply_warehouses":{"house_warehouse":4,"refugee_wagon":4},
			"new_breach_refuge":{"house_ruined":2,"burning_rubble":3}
		}[template.template_id]
		for id in expected:
			t.check(counts.get(id,0) == expected[id],"district landmark composition is deliberate: "+template.template_id+"/"+id)

func _connected_navigation(t,definitions: Dictionary,generator) -> void:
	for template in definitions.templates:
		var seed := _seed_for_template(generator,template.template_id,["0","0"])
		var world = World.new(generator,seed)
		var chunks: Array = []
		for y in range(-1,2):
			for x in range(-1,2): chunks.append([str(x),str(y)])
		t.check(world.prepare(chunks,[],_hydration(chunks),["0","0"]).ok,"real world prepares district neighborhood: "+template.template_id)
		var navigation = Navigation.new(world)
		for radius in [8.0,32.0]:
			var free_count := 0
			var reachable := true
			var safe_segments := true
			var longest := 0.0
			for y in 24:
				for x in 24:
					var start := Vector2(x*32+16,y*32+16)
					if not world.walkable(start,radius): continue
					free_count += 1
					var route: Dictionary = navigation.direction(start,Vector2(384,384),radius,0)
					reachable = reachable and route.ok
					if not route.ok: continue
					longest = maxf(longest,route.length)
					var previous := start
					for point in route.waypoints:
						var hit: Dictionary = world.sweep(previous,point-previous,radius)
						safe_segments = safe_segments and hit.ok and hit.fraction == 1
						previous = point
			print("NEW_NAV district=%s radius=%s free_cells=%s longest_route=%.2f reachable=%s safe_segments=%s" % [template.template_id,radius,free_count,longest,reachable,safe_segments])
			t.check(free_count > 300 and reachable and safe_segments and longest <= 900,"every free 32px cell reaches retreat by actual safe navigation within 900px: %s radius %s count %s longest %.2f" % [template.template_id,radius,free_count,longest])
			for point in [Vector2(336,336),Vector2(432,336),Vector2(432,432),Vector2(336,432),Vector2(384,0),Vector2(768,384),Vector2(384,768),Vector2(0,384)]:
				var route: Dictionary = navigation.direction(point,Vector2(384,384),radius,0)
				t.check(route.ok,"retreat corners and all cardinal ports reach center: %s radius %s point %s" % [template.template_id,radius,point])


		# A concrete new travel choice uses the actual world/query pair, not prose.
		var central: Dictionary = world.chunk_at(Vector2(384,384))
		var building: Dictionary = central.props.filter(func(p): return p.destructible)[0]
		var footprint: Rect2 = building.ground_footprint
		var start := Vector2(footprint.position.x-16,footprint.get_center().y)
		var goal := Vector2(footprint.end.x+16,footprint.get_center().y)
		var before: Dictionary = world.sweep(start,goal-start,8)
		var detour: Dictionary = navigation.direction(start,goal,8,20)
		t.check(before.ok and before.fraction < 1 and detour.ok,"intact district building requires a navigable detour: "+template.template_id)
		t.check(world.apply_props([{"chunk":["0","0"],"props":[{"slot_id":building.slot_id,"hp":0,"destroyed":true}]}],1).ok,"real world commits collapse once: "+template.template_id)
		navigation.invalidate(["0,0"])
		var after: Dictionary = world.sweep(start,goal-start,8)
		var shortcut: Dictionary = navigation.direction(start,goal,8,21)
		t.check(after.ok and after.fraction == 1 and shortcut.ok and shortcut.length < detour.length,"collapse creates a shorter safe travel choice in the real world: "+template.template_id)
		t.check(world.walkable(footprint.get_center(),8),"former footprint becomes traversable: "+template.template_id)

func _all_template_seams(t,generator) -> void:
	var origins := [["0","0"],["-7","-11"],["9007199254740993","-9007199254740993"],["-9223372036854775807","9223372036854775806"]]
	var steps := [[0,-1],[1,0],[0,1],[-1,0]]
	for origin in origins:
		var parsed: Dictionary = Address.parse(origin)
		for step in steps:
			var neighbor := [str(parsed.x+step[0]),str(parsed.y+step[1])]
			var pairs := {}
			for seed in range(4096):
				var a: int = Address.domain_digest(seed,origin,"layout").substr(0,8).hex_to_int()%4
				var b: int = Address.domain_digest(seed,neighbor,"layout").substr(0,8).hex_to_int()%4
				var key := "%s:%s" % [a,b]
				if not pairs.has(key): pairs[key] = seed
				if pairs.size() == 16: break
			t.check(pairs.size() == 16,"all ordered district pairs have deterministic seed witnesses at seam %s/%s" % [origin,step])
			for key in pairs:
				var seed: int = pairs[key]
				var world = World.new(generator,seed)
				var chunks := [origin,neighbor]
				t.check(world.prepare(chunks,[],_hydration(chunks),origin).ok,"exact signed-address adjacent chunks prepare: %s/%s/%s" % [origin,step,key])
				var delta := Vector2(step[0]*768,step[1]*768)
				for radius in [8.0,32.0]:
					var hit: Dictionary = world.sweep(Vector2(384,384),delta,radius)
					var reverse: Dictionary = world.sweep(Vector2(384,384)+delta,-delta,radius)
					t.check(hit.ok and reverse.ok and hit.fraction == 1 and reverse.fraction == 1,"all four directed edge pairs cross both ways at radius %s: %s/%s/%s" % [radius,origin,step,key])

func _new_vectors(t,generator) -> void:
	var fixture: Dictionary = _read(GOLDEN_PATH)
	t.check(FileAccess.get_sha256("res://tests/world/fixtures/NEW-city-vectors-recovery.json") == "df31557449c4f0227cb9c90461891c99341a47cdf8a86959d1954a1ed05cec40","prior recovery vectors remain byte-identical")
	t.check(fixture.get("origin_class") == "NEW_independent_reference_vectors", "determinism vectors are explicitly NEW, not missing original goldens")
	if fixture.is_empty(): return
	t.check(fixture.definition_sha256 == FileAccess.get_sha256(DEFINITIONS_PATH),"NEW vectors bind actual current city definition bytes")
	for vector in fixture.vectors:
		var chunk: Dictionary = generator.generate(int(vector.seed),vector.chunk)
		t.check(chunk.template_id == vector.template_id and chunk.ground_variant == int(vector.ground_variant) and chunk.decor_variant == int(vector.decor_variant),"independently computed NEW layout/ground/decor domain vectors: "+str(vector.chunk))
		t.check(chunk.props.map(func(p): return p.prop_id) == vector.prop_ids,"stable slot IDs include exact signed address strings: "+str(vector.chunk))
		var repeated: Dictionary = generator.generate(int(vector.seed),vector.chunk)
		t.check(repeated == chunk,"repeated generation has identical geometry: "+str(vector.chunk))
		chunk.props[0].hp = -999
		t.check(generator.generate(int(vector.seed),vector.chunk) == repeated,"caller mutation cannot corrupt template data: "+str(vector.chunk))
	for invalid in [["-0","0"],["01","0"],["9223372036854775808","0"],["-9223372036854775809","0"]]:
		t.check(generator.generate(42,invalid).is_empty(),"invalid decimal address rejected without fabricating new city: "+str(invalid))

func _seed_for_template(generator,id: String,chunk: Array) -> int:
	for seed in range(4096):
		if generator.generate(seed,chunk).template_id == id: return seed
	return -1

func _hydration(chunks: Array) -> Dictionary:
	var result := {}
	for chunk in chunks: result[Address.key(chunk)] = []
	return result

func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var value = JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if value is Dictionary else {}
