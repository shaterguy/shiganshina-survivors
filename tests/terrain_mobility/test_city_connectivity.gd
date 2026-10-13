extends RefCounted
const F = preload("res://tests/core_world/new_streamed_helper_fixture.gd")
const H = preload("res://game/core/streamed_run_world.gd")
const Generator = preload("res://game/world/city_generator.gd")
const World = preload("res://game/world/streamed_world.gd")
const Navigation = preload("res://game/world/precise_city_navigation.gd")
const View = preload("res://game/world/streamed_navigation_view.gd")
func run(t) -> void:
	var d := F.definitions()
	var generator := Generator.new(d.templates,d.props)
	t.check(generator.validate().is_empty(),"all four dense templates retain generator connectivity contract")
	t.check(d.templates.chunk_size == 768 and d.templates.templates.size() == 4 and d.templates.street_interval == [288.0,480.0],"dense city preserves 768px/four-template/central street boundary")
	for template in d.templates.templates:
		var counts := [0,0,0,0]
		var solids: Array[Rect2] = []
		for slot in template.slots:
			var definition: Dictionary = d.props.definitions[slot.definition_id]
			if slot.definition_id in ["house_narrow","house_bakery","house_warehouse","house_ruined"]:
				var quadrant := (1 if slot.position[0] >= 480 else 0)+(2 if slot.position[1] >= 480 else 0)
				counts[quadrant] += 1
			if int(definition.collision_mask) != 0:
				var r := Rect2(float(slot.position[0])+float(definition.ground_footprint[0]),float(slot.position[1])+float(definition.ground_footprint[1]),float(definition.ground_footprint[2]),float(definition.ground_footprint[3]))
				t.check(not r.intersects(Rect2(288,0,192,768)) and not r.intersects(Rect2(0,288,768,192)),"solid avoids reserved streets: "+template.template_id+"/"+slot.slot_id)
				for previous in solids: t.check(not r.intersects(previous),"dense building/landmark footprints never overlap")
				solids.append(r)
			t.check(slot.get("rotation_degrees",0) == 0,"authored density uses existing unrotated assets")
		# Broad warehouse/ruin fronts need single-building loading courts.
		# Actual alpha overlap and traversable paired alleys are separate gates;
		# a building-count minimum alone previously accepted stacked facades.
		t.check(counts.min() >= 1,"each quadrant retains an authored building frontage: "+template.template_id+" "+str(counts))
		# All real walkable grid positions must reach the preserved retreat.
		var local_definitions: Dictionary = d.templates.duplicate(true)
		for index in 4: local_definitions.templates[index].slots = template.slots.duplicate(true)
		var world := World.new(Generator.new(local_definitions,d.props),42)
		var chunks := []
		for y in range(-1,2):
			for x in range(-1,2): chunks.append([str(x),str(y)])
		var hydration := {}
		for chunk in chunks: hydration[chunk[0]+","+chunk[1]] = []
		t.check(world.prepare(chunks,[],hydration,["0","0"]).ok,"real dense neighborhood prepares: "+template.template_id)
		var navigation := Navigation.new(View.new(world))
		for radius in [8.0,32.0]:
			var failures := []
			for y in 24:
				for x in 24:
					var point := Vector2(x*32+16,y*32+16)
					if not world.walkable(point,radius): continue
					var route: Dictionary = navigation.direction(point,Vector2(384,384),radius,0)
					if not route.get("ok",false): failures.append([x,y])
			t.check(failures.is_empty(),"all free dense cells have an actual navigation exit at radius "+str(radius)+": "+template.template_id+" "+str(failures))
			for endpoint in [Vector2(384,-384),Vector2(1152,384),Vector2(384,1152),Vector2(-384,384)]:
				var sweep: Dictionary = world.sweep(Vector2(384,384),endpoint-Vector2(384,384),radius)
				t.check(sweep.ok and sweep.fraction == 1.0,"all four ports stay safely connected in both chunk directions")
	for limit in [-1,0,12.5,25,NAN,"20"]:
		var malformed: Dictionary = d.templates.duplicate(true)
		malformed.max_props = limit
		t.check(not Generator.new(malformed,d.props).validate().is_empty(),"invalid optional prop limit is rejected: "+str(limit))
	var old_limit: Dictionary = d.templates.duplicate(true)
	old_limit.erase("max_props")
	for template in old_limit.templates:
		template.slots = []
		for index in 13:
			template.slots.append({"slot_id":"limit_"+str(index),"definition_id":"burning_rubble","position":[96,96],"rotation_degrees":0})
	t.check("too_many_props" in Generator.new(old_limit,d.props).validate(),"missing optional max_props retains the exact old limit of twelve")
	for seed in [0,42,77,2147483647]:
		var helper := H.new(d)
		var state := F.state(helper)
		state.seed = seed
		var needed := H.requirements(state)
		t.check(needed.ok and needed.chunks.size() <= 49,"dense candidate preserves bounded active requirements")
		t.check(helper.prepare(state,F.hydration(needed)).ok and helper.status().resident_chunks <= 49,"dense geometry retains resident working-set ceiling")
