extends RefCounted
const Codec = preload("res://game/world/world_delta_codec.gd")
const Address = preload("res://game/world/world_address.gd")
const Memory = preload("res://tests/world/fixtures/memory_world_pages.gd")
func record(i: int, hp: int = 2) -> Dictionary:
	return {"chunk":[str(i),str(-i)],"props":[{"slot_id":"house_1","hp":hp,"destroyed":hp == 0}]}
func run(t) -> void:
	var path := "res://game/world/world_delta_index.gd"
	t.check(FileAccess.file_exists(path),"delta index exists")
	if not FileAccess.file_exists(path): return
	var script = load(path)
	if not script.can_instantiate(): return
	var memory := Memory.new()
	var index = script.new(Callable(memory,"read_page"),Callable(memory,"write_page"))
	var changes := []
	for i in 17: changes.append(record(i))
	var first: Dictionary = index.prepare_patch(Codec.empty_root(),changes)
	t.check(first.ok,"17 chunks split into a radix tree")
	if not first.ok: return
	var next: Dictionary = index.prepare_patch(first.root,[record(8,1)])
	t.check(next.ok and index.lookup(first.root,record(8).chunk).props[0].hp == 2 and index.lookup(next.root,record(8).chunk).props[0].hp == 1,"copy-on-write keeps old root immutable")
	var repeated: Dictionary = index.prepare_patch(next.root,[record(8,1)])
	t.check(repeated.ok and repeated.root == next.root,"unchanged content reuses hashes")
	t.check(index.lookup(next.root,["987654321","0"]).props.is_empty(),"verified missing key is empty")
	var lost: Dictionary = next.root.duplicate()
	lost.root_hash = "f".repeat(64)
	t.check(index.lookup(lost,["0","0"]).error_code == "world_page_missing","missing page is never intact fallback")
	var other_memory := Memory.new()
	var other = script.new(Callable(other_memory,"read_page"),Callable(other_memory,"write_page"))
	changes.reverse()
	t.check(other.prepare_patch(Codec.empty_root(),changes).root == first.root,"insertion order does not change root")
	var root: Dictionary = next.root
	for start in range(0,10000,64):
		var batch := []
		for i in range(start,mini(start+64,10000)): batch.append(record(i,i%3))
		var result: Dictionary = index.prepare_patch(root,batch)
		t.check(result.ok,"memory 10000 chunk batch "+str(start))
		if not result.ok: return
		root = result.root
	for i in range(9999,-1,-1):
		var found: Dictionary = index.lookup(root,record(i).chunk)
		t.check(found.ok and found.props == record(i,i%3).props,"memory distant delta survives "+str(i))
	var collision_memory := Memory.new()
	var collision = script.new(Callable(collision_memory,"read_page"),Callable(collision_memory,"write_page"),func(_key): return "a".repeat(64))
	var all_collisions := []
	for i in 33: all_collisions.append(record(i))
	var collided: Dictionary = collision.prepare_patch(Codec.empty_root(),all_collisions)
	t.check(collided.ok,"33 same-digest keys use collision continuation")
	if collided.ok:
		for i in 33: t.check(collision.lookup(collided.root,record(i).chunk).props == record(i).props,"full key collision lookup "+str(i))
		var updated: Dictionary = collision.prepare_patch(collided.root,[record(0,0),record(32,1)])
		t.check(updated.ok and collision.lookup(updated.root,record(0).chunk).props[0].hp == 0 and collision.lookup(collided.root,record(0).chunk).props[0].hp == 2,"collision update is persistent")
	for bytes in memory.pages.values(): t.check(bytes.size() <= 65536,"memory page bounded")
	collision_write_summary_regressions(t)

func collision_write_summary_regressions(t) -> void:
	var script = load("res://game/world/world_delta_index.gd")
	for count in [33,257,1025,4097]:
		var memory := Memory.new()
		var records := []
		for i in count: records.append(record(i))
		records.sort_custom(func(a,b): return Address.less(a.chunk,b.chunk))
		var hash := ""
		for end in range(records.size(),0,-16):
			hash = memory.write_page({"format_revision":1,"kind":"collision","records":records.slice(maxi(0,end-16),end),"next_hash":hash}).hash
		for depth in range(63,-1,-1):
			hash = memory.write_page({"format_revision":1,"kind":"branch","depth":depth,"children":[{"nibble":10,"hash":hash}]}).hash
		var old_root := {"format_revision":1,"root_hash":hash}
		var index = script.new(Callable(memory,"read_page"),Callable(memory,"write_page"),func(_key): return "a".repeat(64))
		memory.begin_write_sequence()
		var started := Time.get_ticks_usec()
		var patched: Dictionary = index.prepare_patch(old_root,[record(0,1)])
		var expected := memory.finish_write_sequence()
		t.check(patched.ok and patched.has("write_summary") and not patched.has("written_hashes"),"collision write summary replaces history-sized array: "+str(count))
		if not patched.has("write_summary"): continue
		t.check(patched.write_summary == expected and expected.page_write_calls == 64+ceili(float(count)/16.0),"summary counts successful calls and hashes the complete ordered write stream: "+str(count))
		var stats: Dictionary = index.diagnostics()
		t.check(stats.retained_write_hashes == 0 and stats.write_digest_bytes == 32 and stats.peak_collision_window_records <= 17,"collision tracking stays constant as history grows: "+str(count))
		# Lookups prove damage and historical root behavior, including both ends
		# and page boundaries. Larger production-like 10k noncollision coverage
		# still revisits every record in the main run.
		for i in [0,1,15,16,count/2,count-2,count-1]:
			var found: Dictionary = index.lookup(patched.root,record(int(i)).chunk)
			t.check(found.ok and found.props == record(int(i),1 if int(i) == 0 else 2).props,"collision full key retained at "+str(count)+"/"+str(i))
		t.check(index.lookup(old_root,record(0).chunk).props[0].hp == 2,"collision rewrite leaves historical root immutable: "+str(count))
		print("COLLISION_WRITE_BOUND "+JSON.stringify({"records":count,"changed":1,"summary":patched.write_summary,"diagnostics":stats,"usec":Time.get_ticks_usec()-started}))
	var empty_memory := Memory.new()
	var empty_index = script.new(Callable(empty_memory,"read_page"),Callable(empty_memory,"write_page"))
	empty_memory.begin_write_sequence()
	var empty_patch: Dictionary = empty_index.prepare_patch(Codec.empty_root(),[])
	var empty_expected := empty_memory.finish_write_sequence()
	t.check(empty_patch.get("write_summary",{}) == empty_expected and empty_expected.sequence_digest == "6c49705541875efab5c3a5a8c69525be8250a025817002b0460dd6f0c34d5c3e","empty write sequence has a frozen domain-separated digest")
	var single: Dictionary = empty_index.prepare_patch(Codec.empty_root(),[record(0)])
	t.check(single.get("write_summary",{}) == {"page_write_calls":1,"sequence_digest":"ae358b06a3c8ac3583fad7efea11652b4c707e6ca90b841c717ec5cf91cc78a9"},"one-write sequence matches independent SHA256 golden encoding")
	# An attempted callback that fails must never be counted as a successful
	# write or return a success receipt/summary. Fixture failures are typed.
	var failed_index = script.new(Callable(empty_memory,"read_page"),func(_page): return Codec.fail("fixture_write_failed"))
	var failed: Dictionary = failed_index.prepare_patch(Codec.empty_root(),[record(0)])
	t.check(not failed.ok and not failed.has("write_summary"),"failed write callback cannot produce a success summary")
