extends RefCounted
const Codec = preload("res://game/world/world_delta_codec.gd")
const Disk = preload("res://game/persistence/world_delta_store.gd")
const Helpers = preload("res://tests/world/test_world_delta_store.gd")
class CountingStore extends "res://game/persistence/world_delta_store.gd":
	var page_visits := 0
	var stop_after := 4096
	func _read_page(hash: String) -> Dictionary:
		page_visits += 1
		# Test-owned guard bounds the pre-fix malicious regression itself.
		if page_visits > stop_after: return Codec.fail("probe_visit_limit")
		return super._read_page(hash)
func run(t) -> void:
	var helper := Helpers.new()
	var directory := helper.directory("retention")
	var store := Disk.new(directory)
	t.check(store.has_method("audit_pages"),"orphan-only page audit exists")
	if not store.has_method("audit_pages"): return
	var first := store.prepare(Codec.empty_root(),[helper.record(0)],1)
	var second := store.prepare(first.receipt.candidate_root,[helper.record(0,1)],2)
	var orphan := store.prepare(Codec.empty_root(),[helper.record(19)],3)
	var roots := [Codec.empty_root(),first.receipt.candidate_root,second.receipt.candidate_root]
	var before: int = count_pages(directory.path_join("pages"))
	var uncertain: Dictionary = store.audit_pages(roots,true)
	t.check(not uncertain.ok and uncertain.error_code == "commit_outcome_unknown" and count_pages(directory.path_join("pages")) == before,"uncertain commits block audits without page deletion")
	var audited: Dictionary = store.audit_pages(roots,false)
	t.check(audited.ok and audited.reachable_count == 3 and audited.orphan_count >= 1 and FileAccess.file_exists(audited.audit_path),"primary backup live prepared roots all marked; orphan reported")
	t.check(count_pages(directory.path_join("pages")) == before and not store.diagnostics().sweep_enabled and not store.has_method("delete_pages"),"diagnostic audit exposes no destructive sweep")
	var orphan_hash: String = orphan.receipt.candidate_root.root_hash
	t.check(FileAccess.file_exists(directory.path_join("pages").path_join(orphan_hash.substr(0,2)).path_join(orphan_hash+".json")),"even unprotected orphan retained")
	for stage in ["audit_mark","audit_enumerate","audit_complete"]:
		var interrupted := Disk.new(directory,func(s): return ERR_CANT_CREATE if s == stage else OK)
		var result: Dictionary = interrupted.audit_pages(roots,false)
		t.check(not result.ok and count_pages(directory.path_join("pages")) == before,"audit interruption preserves every file: "+stage)
		t.check(Disk.new(directory).audit_pages(roots,false).ok,"fresh startup ignores partial audit marks: "+stage)
	var mutable_roots: Array = roots.duplicate(true)
	var mutate := Disk.new(directory,func(stage):
		if stage == "audit_complete": mutable_roots.append(orphan.receipt.candidate_root)
		return OK)
	t.check(not mutate.audit_pages(mutable_roots,false).ok,"changed protected root set aborts audit")
	var missing: Array = roots.duplicate(true)
	missing.append({"format_revision":1,"root_hash":"f".repeat(64)})
	t.check(not Disk.new(directory).audit_pages(missing,false).ok and count_pages(directory.path_join("pages")) == before,"missing protected page aborts and retains all files")
	var leaf := Codec.encode({"format_revision":1,"kind":"leaf","records":[helper.record(5)]})
	write_fixture(directory,leaf)
	var key_hash := Codec.digest("5,-5".to_utf8_buffer())
	var wrong_nibble := ("0123456789abcdef".find(key_hash[0])+1)%16
	var bad_branch := Codec.encode({"format_revision":1,"kind":"branch","depth":0,"children":[{"nibble":wrong_nibble,"hash":leaf.hash}]})
	write_fixture(directory,bad_branch)
	var bad_root := {"format_revision":1,"root_hash":bad_branch.hash}
	t.check(not Disk.new(directory).lookup(bad_root,["5","-5"]).ok,"cold lookup rejects misrouted records instead of reporting intact absence")
	helper.remove_fixture(directory)
	empty_shared_subtree_regressions(t)
func count_pages(path: String) -> int:
	var dir := DirAccess.open(path)
	if dir == null: return 0
	var count := 0
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if dir.current_is_dir(): count += count_pages(path.path_join(name))
		elif name.ends_with(".json"): count += 1
		name = dir.get_next()
	dir.list_dir_end()
	return count

func write_fixture(directory: String, encoded: Dictionary) -> void:
	var path: String = directory.path_join("pages").path_join(encoded.hash.substr(0,2)).path_join(encoded.hash+".json")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_buffer(encoded.bytes)
	file.close()

func empty_shared_subtree_regressions(t) -> void:
	var helper := Helpers.new()
	for depth in [1,4,64]:
		var directory := helper.directory("shared_empty_"+str(depth))
		var writer := Disk.new(directory)
		var hash: String = writer._write_page({"format_revision":1,"kind":"leaf","records":[]}).hash
		for d in range(depth-1,-1,-1):
			var children := []
			for nibble in 16: children.append({"nibble":nibble,"hash":hash})
			hash = writer._write_page({"format_revision":1,"kind":"branch","depth":d,"children":children}).hash
		var root := {"format_revision":1,"root_hash":hash}
		for operation in ["verify","lookup","audit"]:
			var cold := CountingStore.new(directory)
			var started := Time.get_ticks_usec()
			var result: Dictionary
			if operation == "verify": result = cold.verify_root(root)
			elif operation == "lookup": result = cold.lookup(root,["0","0"])
			else: result = cold.audit_pages([root],false)
			t.check(not result.ok and result.get("error_code") == "world_page_invalid" and cold.page_visits <= depth+1,"shared empty DAG fails within unique depth for "+operation+" depth "+str(depth))
			var stats := cold.diagnostics()
			t.check(stats.get("last_walk_page_visits",-1) == depth+1 and stats.get("last_walk_stack_depth",-1) <= 65 and stats.get("walk_page_visit_limit_per_root",0) > 10000,"cold traversal exposes bounded work diagnostics")
			print("EMPTY_DAG_BOUND "+JSON.stringify({"operation":operation,"depth":depth,"unique_pages":depth+1,"page_visits":cold.page_visits,"result":result,"usec":Time.get_ticks_usec()-started}))
		helper.remove_fixture(directory)
	# Nonempty shared leaf is route-invalid rather than empty; retain the full
	# prefix check instead of accepting it via a global seen-hash shortcut.
	var nonempty_directory := helper.directory("shared_nonempty_64")
	var nonempty_writer := Disk.new(nonempty_directory)
	var nonempty_hash: String = nonempty_writer._write_page({"format_revision":1,"kind":"leaf","records":[helper.record(0)]}).hash
	for d in range(63,-1,-1):
		var children := []
		for nibble in 16: children.append({"nibble":nibble,"hash":nonempty_hash})
		nonempty_hash = nonempty_writer._write_page({"format_revision":1,"kind":"branch","depth":d,"children":children}).hash
	var nonempty_root := {"format_revision":1,"root_hash":nonempty_hash}
	for operation in ["verify","lookup","audit"]:
		var cold := CountingStore.new(nonempty_directory)
		var result: Dictionary
		if operation == "verify": result = cold.verify_root(nonempty_root)
		elif operation == "lookup": result = cold.lookup(nonempty_root,["0","0"])
		else: result = cold.audit_pages([nonempty_root],false)
		t.check(not result.ok and result.get("error_code") == "world_page_invalid" and cold.page_visits <= 65,"nonempty shared DAG keeps route validation bounded for "+operation)
		print("NONEMPTY_DAG_BOUND "+JSON.stringify({"operation":operation,"depth":64,"page_visits":cold.page_visits,"result":result}))
	# A valid first traversal must not cause a later misrouted shared reference
	# to be skipped by a hash-only validation cache/mark.
	var key_digest := Codec.digest("0,0".to_utf8_buffer())
	var correct_nibble := "0123456789abcdef".find(key_digest[0])
	var routed_hash: String = nonempty_writer._write_page({"format_revision":1,"kind":"leaf","records":[helper.record(0)]}).hash
	for d in range(63,0,-1):
		routed_hash = nonempty_writer._write_page({"format_revision":1,"kind":"branch","depth":d,"children":[{"nibble":"0123456789abcdef".find(key_digest[d]),"hash":routed_hash}]}).hash
	var routed: Dictionary = nonempty_writer._write_page({"format_revision":1,"kind":"branch","depth":0,"children":[{"nibble":correct_nibble,"hash":routed_hash},{"nibble":correct_nibble+1,"hash":routed_hash}]})
	t.check(correct_nibble < 15 and routed.ok,"fixture admits valid first and misrouted second shared path")
	for operation in ["verify","lookup","audit"]:
		var cold := CountingStore.new(nonempty_directory)
		var shared_root := {"format_revision":1,"root_hash":routed.hash}
		var result: Dictionary
		if operation == "verify": result = cold.verify_root(shared_root)
		elif operation == "lookup": result = cold.lookup(shared_root,["0","0"])
		else: result = cold.audit_pages([shared_root],false)
		t.check(not result.ok and result.get("error_code") == "world_page_invalid" and cold.page_visits == 129,"validated nonempty shared hash is rechecked against each route: "+operation)
		print("RECHECK_SHARED_ROUTE "+JSON.stringify({"operation":operation,"depth":64,"page_visits":cold.page_visits,"result":result}))
	helper.remove_fixture(nonempty_directory)
	# Sharing immutable nonempty subtrees across two protected historical roots
	# is legitimate; no global already-seen shortcut may conceal route checks.
	var directory := helper.directory("valid_shared_history")
	var store := Disk.new(directory)
	var changes := []
	for i in 64: changes.append(helper.record(i))
	var first := store.prepare(Codec.empty_root(),changes,1)
	var next := store.prepare(first.receipt.candidate_root,[helper.record(0,1)],2)
	var cold := CountingStore.new(directory)
	t.check(cold.verify_root(Codec.empty_root()).ok,"canonical empty leaf remains legal at root")
	t.check(cold.verify_root(first.receipt.candidate_root).ok and cold.verify_root(next.receipt.candidate_root).ok,"historical roots sharing nonempty pages still verify")
	var audited := cold.audit_pages([first.receipt.candidate_root,next.receipt.candidate_root],false)
	t.check(audited.ok and audited.reachable_count > 1,"audit allows valid shared immutable subtrees across roots")
	helper.remove_fixture(directory)
