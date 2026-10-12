extends RefCounted
const Hash = preload("res://game/combat/spatial_hash.gd")
func run(t) -> void:
	var hash = Hash.new()
	t.check(hash.has_method("relocate"),"existing combat hash supports exact one-record relocation")
	if not hash.has_method("relocate"): return
	var records := [{"id":"a","position":[63.0,0.0]},{"id":"b","position":[65.0,0.0]},{"id":"dead","position":[300.0,300.0]}]
	hash.rebuild(records)
	hash.relocate(0,Vector2(63,0),Vector2(65,0))
	t.check(hash.query(Vector2(30,0),1).is_empty(),"old cell no longer contains moved record")
	t.check(hash.query(Vector2(80,0),1)==[0,1],"new bucket preserves exact ascending array-index order")
	hash.relocate(0,Vector2(65,0),Vector2(66,0))
	t.check(hash.query(Vector2(80,0),1)==[0,1],"same-cell relocation neither duplicates nor drops the record")
	hash.relocate(0,Vector2(66,0),Vector2(-1,0))
	t.check(hash.query(Vector2(-30,0),1)==[0] and hash.query(Vector2(80,0),1)==[1],"negative cell transition preserves both old and new buckets")
