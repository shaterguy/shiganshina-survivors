extends RefCounted
# Controlled geometry only. The actual World and View scripts stay native.
# Boundary records may extend outside the home chunk on purpose. This is a
# synthetic broad-phase edge fixture, not a claim about CityGenerator output.
# test_contracts also exercises the unchanged real CityGenerator fixture.
var _records: Array = []
var _home: Array = []
func _init(records: Array = [], home: Array = ["0","0"]) -> void:
	_records = records.duplicate(true)
	_home = home.duplicate()
func generate(_seed: int, chunk: Array) -> Dictionary:
	var key: String = chunk[0]+","+chunk[1]
	var props: Array = []
	if chunk == _home:
		for record in _records:
			var bounds: Rect2 = record.bounds
			props.append({"prop_id":key+":"+record.id,"slot_id":record.id,"position":bounds.position,"ground_footprint":bounds,"render_bounds":bounds,"depth_y":bounds.end.y,"collision_mask":record.mask,"cover_mask":record.cover,"destructible":true,"hp":10,"max_hp":10,"destroyed":false})
	return {"chunk_id":key,"chunk":chunk.duplicate(),"props":props,"geometry_revision":0,"passage_rect":Rect2(0,0,768,768),"street_nodes":[]}
func hydrate(source: Dictionary, deltas: Array) -> Dictionary:
	var chunk: Dictionary = source.duplicate(true)
	for delta in deltas:
		var found := false
		for prop in chunk.props:
			if prop.slot_id != delta.slot_id: continue
			found = true
			prop.hp = int(delta.hp)
			prop.destroyed = bool(delta.destroyed)
			if prop.destroyed:
				prop.collision_mask = 0
				prop.cover_mask = 0
		if not found: return {"ok":false,"error_code":"fixture_unknown_slot"}
	return {"ok":true,"chunk":chunk}
