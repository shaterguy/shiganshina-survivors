extends RefCounted
func record(x: String, y: String, hp: Variant = 2) -> Dictionary:
	return {"chunk":[x,y],"props":[{"slot_id":"house_1","hp":hp,"destroyed":false}]}
func run(t) -> void:
	var path := "res://game/world/world_delta_codec.gd"
	t.check(FileAccess.file_exists(path),"delta codec exists")
	if not FileAccess.file_exists(path): return
	var c = load(path)
	if not c.can_instantiate(): return
	var p := {"format_revision":1,"kind":"leaf","records":[record("10","-2"),record("-2","-2")]}
	var original := p.duplicate(true)
	var a: Dictionary = c.encode(p)
	var b: Dictionary = c.encode({"records":[record("-2","-2",2.0),record("10","-2")],"kind":"leaf","format_revision":1.0})
	t.check(a.ok and b.ok and a.bytes == b.bytes and a.hash == b.hash and p == original,"canonical bytes normalize order and integral numbers without mutation")
	if not a.ok: return
	var d: Dictionary = c.decode(a.bytes,a.hash)
	t.check(d.ok and d.page.records[0].chunk == ["-2","-2"],"signed numeric Y/X order")
	var corrupt: PackedByteArray = a.bytes.duplicate()
	corrupt[0] = 91
	t.check(c.decode(corrupt,a.hash).error_code == "world_hash_mismatch","hash verified before parse")
	for hp in [-1,0.5,NAN,INF]:
		t.check(not c.encode({"format_revision":1,"kind":"leaf","records":[record("0","0",hp)]}).ok,"bad HP rejected "+str(hp))
	for chunk in [["01","0"],["-0","0"],["9223372036854775808","0"],[1,"0"]]:
		var bad := record("0","0")
		bad.chunk = chunk
		t.check(not c.encode({"format_revision":1,"kind":"leaf","records":[bad]}).ok,"bad chunk rejected")
	var duplicates := [record("0","0"),record("0","0")]
	t.check(not c.encode({"format_revision":1,"kind":"leaf","records":duplicates}).ok,"duplicate chunk rejected")
	var slots := record("0","0")
	slots.props.append(slots.props[0].duplicate())
	t.check(not c.encode({"format_revision":1,"kind":"leaf","records":[slots]}).ok,"duplicate slot rejected")
	var many := []
	for i in 17: many.append(record(str(i),"0"))
	t.check(not c.encode({"format_revision":1,"kind":"leaf","records":many}).ok,"17 records rejected")
	slots.props = []
	for i in 13: slots.props.append({"slot_id":str(i),"hp":2,"destroyed":false})
	t.check(not c.encode({"format_revision":1,"kind":"leaf","records":[slots]}).ok,"13 slots rejected")
	var huge := record("0","0")
	huge.props[0].slot_id = "a".repeat(65536)
	t.check(c.encode({"format_revision":1,"kind":"leaf","records":[huge]}).error_code == "world_page_oversize","oversize page rejected")
	for bad in [{"format_revision":2,"kind":"leaf","records":[]},{"format_revision":1,"kind":"unknown","records":[]},{"format_revision":1,"kind":"branch","depth":64,"children":[]},{"format_revision":1,"kind":"branch","depth":0,"children":[{"nibble":0,"hash":"invalid"}]},{"format_revision":1,"kind":"leaf","records":[],"extra":true}]:
		t.check(not c.encode(bad).ok,"unknown page schema rejected")
	var h: String = a.hash
	t.check(not c.encode({"format_revision":1,"kind":"branch","depth":0,"children":[{"nibble":0,"hash":h},{"nibble":0,"hash":h}]}).ok,"duplicate branch child rejected")
	t.check(c.changes_digest(p.records).hash == c.changes_digest(b.get("page",p).get("records",p.records)).hash,"dirty digest deterministic")
	var huge_integer := record("0","0",9223372036854775807)
	var bounded: Dictionary = c.encode({"format_revision":1,"kind":"leaf","records":[huge_integer]})
	t.check(not bounded.ok or c.decode(bounded.bytes,bounded.hash).ok,"encoder never emits integer HP bytes its decoder rejects")
	var fixture_path := "res://tests/world/fixtures/world_pages.json"
	t.check(FileAccess.file_exists(fixture_path),"canonical golden fixture exists")
	if FileAccess.file_exists(fixture_path):
		for vector in JSON.parse_string(FileAccess.get_file_as_string(fixture_path)):
			var encoded: Dictionary = c.encode(vector.page)
			t.check(encoded.ok and encoded.hash == vector.hash and encoded.bytes.get_string_from_utf8() == vector.bytes,"golden canonical page "+vector.name)
