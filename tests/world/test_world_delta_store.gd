extends RefCounted
const Codec = preload("res://game/world/world_delta_codec.gd")
func record(i: int, hp: int = 2) -> Dictionary:
	return {"chunk":[str(i),str(-i)],"props":[{"slot_id":"house_1","hp":hp,"destroyed":hp == 0}]}
func directory(label: String) -> String:
	return "/tmp/world_delta_%d_%d_%s" % [OS.get_process_id(),Time.get_ticks_usec(),label]
func remove_fixture(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null: return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if dir.current_is_dir(): remove_fixture(path.path_join(name))
		else: DirAccess.remove_absolute(path.path_join(name))
		name = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)
func run(t) -> void:
	print("WORLD_STORE_PROGRESS "+JSON.stringify({"phase":"early_cases_begin","usec":Time.get_ticks_usec()}))
	var path := "res://game/persistence/world_delta_store.gd"
	t.check(FileAccess.file_exists(path),"delta file store exists")
	if not FileAccess.file_exists(path): return
	var script = load(path)
	if not script.can_instantiate(): return
	var root_dir := directory("durable")
	var store = script.new(root_dir)
	print("WORLD_STORE_PROGRESS "+JSON.stringify({"phase":"initial_prepare_begin","records":1,"usec":Time.get_ticks_usec()}))
	var first: Dictionary = store.prepare(Codec.empty_root(),[record(0)],1)
	print("WORLD_STORE_PROGRESS "+JSON.stringify({"phase":"initial_prepare_returned","ok":first.ok,"usec":Time.get_ticks_usec(),"diagnostics":store.diagnostics()}))
	t.check(first.ok,"prepare durably stages first root")
	if not first.ok: return
	var immutable: String = root_dir.path_join("pages").path_join(first.receipt.candidate_root.root_hash.substr(0,2)).path_join(first.receipt.candidate_root.root_hash+".json")
	var bytes := FileAccess.get_file_as_bytes(immutable)
	var retry: Dictionary = store.prepare(Codec.empty_root(),[record(0)],1)
	t.check(retry.ok and retry.receipt == first.receipt and FileAccess.get_file_as_bytes(immutable) == bytes,"same staged patch reuses immutable bytes")
	t.check(not FileAccess.file_exists(root_dir.path_join("CURRENT")) and not FileAccess.file_exists(root_dir.path_join("game_save.json")),"world store creates no authority")
	var hydrated: Dictionary = store.hydrate(first.receipt.candidate_root,[["0","0"],["999","0"]])
	t.check(hydrated.ok and hydrated.deltas["0,0"] == record(0).props and hydrated.deltas["999,0"].is_empty(),"hydrate includes explicit verified absence")
	for stage in ["page_write","page_flush","page_readback","page_publish","after_pages_before_receipt"]:
		print("WORLD_STORE_PROGRESS "+JSON.stringify({"phase":"fault_case_begin","fault":stage,"usec":Time.get_ticks_usec()}))
		var failed_dir := directory(stage)
		DirAccess.make_dir_recursive_absolute(failed_dir)
		var authority := FileAccess.open(failed_dir.path_join("game_save.json"),FileAccess.WRITE)
		authority.store_string("previous player and world")
		authority.close()
		var injected = script.new(failed_dir,func(s): return ERR_CANT_CREATE if s == stage else OK)
		var dirty := [record(4)]
		var original := dirty.duplicate(true)
		var failed: Dictionary = injected.prepare(Codec.empty_root(),dirty,1)
		t.check(not failed.ok and dirty == original and FileAccess.get_file_as_string(failed_dir.path_join("game_save.json")) == "previous player and world","staging fault preserves authority/dirty: "+stage)
		remove_fixture(failed_dir)
	var corrupt := FileAccess.open(immutable,FileAccess.WRITE)
	corrupt.store_string("{}")
	corrupt.close()
	var fresh = script.new(root_dir)
	t.check(not fresh.verify_root(first.receipt.candidate_root).ok,"cold root rejects corrupt page")
	t.check(not fresh.prepare(Codec.empty_root(),[record(0)],1).ok and FileAccess.get_file_as_string(immutable) == "{}","existing corrupt content-address file never overwritten")
	remove_fixture(root_dir)
	print("WORLD_STORE_PROGRESS "+JSON.stringify({"phase":"quota_case_begin","usec":Time.get_ticks_usec()}))
	var quota_dir := directory("quota")
	DirAccess.make_dir_recursive_absolute(quota_dir.path_join("pages"))
	var fill := FileAccess.open(quota_dir.path_join("pages/quota.tmp"),FileAccess.WRITE)
	fill.seek(128*1024*1024-1)
	fill.store_8(0)
	fill.close()
	var full = script.new(quota_dir)
	t.check(full.prepare(Codec.empty_root(),[record(1)],1).error_code == "world_quota_exceeded","actual retained plus staged file bytes enforce quota")
	remove_fixture(quota_dir)
	print("WORLD_STORE_PROGRESS "+JSON.stringify({"phase":"stress_prepare_begin","records":10000,"batch":64,"usec":Time.get_ticks_usec()}))
	var stress_dir := directory("stress")
	var stress = script.new(stress_dir)
	var root := Codec.empty_root()
	for start in range(0,10000,64):
		var batch := []
		for i in range(start,mini(10000,start+64)): batch.append(record(i,i%3))
		var qa_batch_started_usec: int = Time.get_ticks_usec()
		print("WORLD_STORE_PROGRESS "+JSON.stringify({"phase":"stress_prepare_batch_begin","start":start,"batch_records":batch.size(),"usec":qa_batch_started_usec}))
		var staged: Dictionary = stress.prepare(root,batch,start+1)
		print("WORLD_STORE_PROGRESS "+JSON.stringify({"phase":"stress_prepare_batch_returned","start":start,"completed_records":mini(start+64,10000),"ok":staged.ok,"elapsed_usec":Time.get_ticks_usec()-qa_batch_started_usec,"usec":Time.get_ticks_usec(),"diagnostics":stress.diagnostics()}))
		t.check(staged.ok,"disk 10000 batch "+str(start))
		if not staged.ok: return
		root = staged.receipt.candidate_root
	print("WORLD_STORE_PROGRESS "+JSON.stringify({"phase":"stress_lookup_begin","records":10000,"usec":Time.get_ticks_usec()}))
	for i in range(9999,-1,-1):
		var found: Dictionary = stress.lookup(root,record(i).chunk)
		t.check(found.ok and found.props == record(i,i%3).props,"disk distant delta survives "+str(i))
		if i%1000 == 0: print("WORLD_STORE_PROGRESS "+JSON.stringify({"phase":"stress_lookup_progress","completed_lookups":10000-i,"usec":Time.get_ticks_usec()}))
	var stats: Dictionary = stress.diagnostics()
	t.check(stats.delta_cache_entries <= 64 and stats.page_cache_entries <= 64 and stats.verified_roots <= 8 and stats.disk_bytes > 0,"disk stress bounded resident caches and root receipts")
	print("WORLD_STORE_PROGRESS "+JSON.stringify({"phase":"stress_audit_begin","usec":Time.get_ticks_usec()}))
	var audit: Dictionary = stress.audit_pages([root,Codec.empty_root()],false)
	print("WORLD_STORE_PROGRESS "+JSON.stringify({"phase":"stress_audit_returned","ok":audit.ok,"usec":Time.get_ticks_usec()}))
	t.check(audit.ok and audit.reachable_count > 16 and audit.orphan_count > 0 and stress.diagnostics().page_cache_entries <= 64,"10000 chunk audit streams marks and retains orphan pages")
	print("WORLD_STORAGE_STRESS "+JSON.stringify(stats)+" audit="+JSON.stringify(audit))
	print("WORLD_STORE_PROGRESS "+JSON.stringify({"phase":"cold_closure_begin","usec":Time.get_ticks_usec()}))
	var cold = script.new(stress_dir)
	t.check(cold.verify_root(root).ok,"cold full closure verification 10000 chunks")
	print("WORLD_STORE_PROGRESS "+JSON.stringify({"phase":"cold_closure_returned","usec":Time.get_ticks_usec()}))
	var reads: int = cold.diagnostics().disk_reads
	t.check(cold.verify_root(root).ok and cold.diagnostics().disk_reads == reads,"repeat root verification is read-only and cached")
	# Distant leaf absent: cold closure must fail even when requested player chunk exists.
	var leaf_path := find_leaf(stress_dir.path_join("pages"),root.root_hash)
	t.check(leaf_path != "","stress contains a leaf")
	if leaf_path != "":
		DirAccess.remove_absolute(leaf_path)
		t.check(not script.new(stress_dir).verify_root(root).ok,"missing distant referenced leaf fails full closure")
	print("WORLD_STORE_PROGRESS "+JSON.stringify({"phase":"cleanup_begin","usec":Time.get_ticks_usec()}))
	remove_fixture(stress_dir)
	print("WORLD_STORE_PROGRESS "+JSON.stringify({"phase":"body_complete","usec":Time.get_ticks_usec()}))
func find_leaf(pages: String, hash: String) -> String:
	var path := pages.path_join(hash.substr(0,2)).path_join(hash+".json")
	var page: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	if page.kind == "branch": return find_leaf(pages,page.children.back().hash)
	return path
