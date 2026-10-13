extends RefCounted
const F = preload("res://tests/core_world/new_streamed_helper_fixture.gd")
const Generator = preload("res://game/world/city_generator.gd")
const World = preload("res://game/world/streamed_world.gd")
const Props = preload("res://game/world/world_prop_catalog.gd")
func run(t) -> void:
	var d := F.definitions()
	var narrow: Dictionary = d.props.definitions.house_narrow
	var image := Image.load_from_file("res://assets/art/environment/house_narrow.png")
	var minimum := 999
	var maximum := -1
	for y in range(140,192):
		for x in range(160):
			if image.get_pixel(x,y).a < 0.5: continue
			minimum = mini(minimum,x-80)
			maximum = maxi(maximum,x-80+1)
	var footprint := Props.rect(narrow.ground_footprint)
	t.check(footprint.position.x <= minimum and footprint.end.x >= maximum and footprint.size.x <= maximum-minimum+8,"narrow-house floor follows actual opaque front wall without a wide invisible side wall")
	t.check(Props.rect(narrow.mobility_anchor.pass_range) == footprint,"roof passage permission follows corrected physical floor, not full sprite bounds")
	for template in d.templates.templates:
		var local: Dictionary = d.templates.duplicate(true)
		for item in local.templates: item.slots = template.slots.duplicate(true)
		var world := World.new(Generator.new(local,d.props),42)
		var chunks := []
		var hydration := {}
		for y in range(-1,2):
			for x in range(-1,2):
				chunks.append([str(x),str(y)])
				hydration[str(x)+","+str(y)] = []
		t.check(world.prepare(chunks,[],hydration,["0","0"]).ok,"visible alley fixture prepares actual city geometry")
		var narrow_alleys := 0
		var solids: Array = world.chunk_at(Vector2(384,384)).props.filter(func(p): return p.definition_id in ["house_narrow","house_bakery","house_warehouse","house_ruined"])
		for left in solids:
			for right in solids:
				var a: Rect2 = left.ground_footprint
				var b: Rect2 = right.ground_footprint
				if a.position.x >= b.position.x or left.position.y != right.position.y: continue
				var gap: float = b.position.x-a.end.x
				if gap < 16.0 or gap >= 64.0: continue
				var x: float = (a.end.x+b.position.x)*0.5
				var start := Vector2(x,maxf(a.end.y,b.end.y)+16)
				var end := Vector2(x,minf(a.position.y,b.position.y)-16)
				var sweep: Dictionary = world.sweep(start,end-start,8)
				t.check(sweep.ok and sweep.fraction == 1.0,"visible narrow alley is a real continuous player route: "+template.template_id+"/"+left.slot_id+"/"+right.slot_id)
				var middle := Vector2(x,(maxf(a.position.y,b.position.y)+minf(a.end.y,b.end.y))*0.5)
				t.check(not world.walkable(middle,32),"small alley remains smaller than a boss; boss uses preserved connected main routes")
				narrow_alleys += 1
		t.check(narrow_alleys >= 1,"district has an actual side-by-side visible alley instead of stacked silhouettes: "+template.template_id)
