class_name WorldDeltaStore
extends RefCounted
const Codec = preload("res://game/world/world_delta_codec.gd")
const Index = preload("res://game/world/world_delta_index.gd")
const Address = preload("res://game/world/world_address.gd")
const QUOTA_BYTES := 128*1024*1024
const CACHE_LIMIT := 64
# The smallest canonical page is the 48-byte empty root. This conservative
# bound admits every closure the 128 MiB page quota can store; it is not a
# gameplay history cap. Each protected root gets its own budget during audit.
const MAX_WALK_PAGE_VISITS: int = QUOTA_BYTES / 48
var _walk_visits := 0
var _root_walk_visits := 0
var _walk_stack_depth := 0
var _directory: String
var _fault_injector: Callable
var _page_cache := {}
var _delta_cache := {}
var _verified_roots := {}
var _closure_manifest := ""
var _disk_bytes := 0
var _disk_reads := 0
var _pages_written := 0
var _peak_pages := 0
var _peak_deltas := 0
var _sequence := 0
func _init(directory: String, fault_injector: Callable = Callable()) -> void:
	_directory = directory
	_fault_injector = fault_injector
func prepare(base_root: Dictionary, dirty_chunks: Array, world_revision: int) -> Dictionary:
	var valid := Codec.valid_root(base_root)
	if not valid.ok: return valid
	if world_revision < 0: return Codec.fail("world_page_invalid")
	var digest := Codec.changes_digest(dirty_chunks)
	if not digest.ok: return digest
	var usage := _measure(_directory.path_join("pages"))
	if not usage.ok: return usage
	_disk_bytes = usage.bytes
	if base_root.root_hash == Codec.empty_root().root_hash and not FileAccess.file_exists(_path(base_root.root_hash)):
		var empty := _write_page({"format_revision":1,"kind":"leaf","records":[]})
		if not empty.ok: return empty
	begin_verified_read()
	var verified := verify_root(base_root)
	if not verified.ok: return verified
	var index = Index.new(Callable(self,"_read_page"),Callable(self,"_write_page"))
	var patched: Dictionary = index.prepare_patch(base_root,dirty_chunks)
	if not patched.ok: return patched
	# The base closure was verified; the pure index only reuses its immutable
	# descendants or codec-verified, durably published pages from this operation.
	_touch(_verified_roots,patched.root.root_hash,true,8)
	if _fault("after_pages_before_receipt") != OK: return Codec.fail("world_prepare_interrupted")
	return {"ok":true,"receipt":{"base_root":base_root.duplicate(true),"candidate_root":patched.root,"world_revision":world_revision,"changes_digest":digest.hash},"write_summary":patched.write_summary}
func lookup(root: Dictionary, chunk: Array) -> Dictionary:
	var valid := Codec.valid_root(root)
	if not valid.ok: return valid
	if not Address.parse(chunk).ok: return Codec.fail("world_page_invalid")
	var verified := verify_root(root)
	if not verified.ok: return verified
	var key: String = root.root_hash+":"+Address.key(chunk)
	if _delta_cache.has(key):
		var props: Array = _delta_cache[key]
		_touch(_delta_cache,key,props,CACHE_LIMIT)
		return {"ok":true,"props":props.duplicate(true)}
	var result: Dictionary = Index.new(Callable(self,"_read_page"),Callable(self,"_write_page")).lookup(root,chunk)
	if result.ok:
		_touch(_delta_cache,key,result.props.duplicate(true),CACHE_LIMIT)
		_peak_deltas = maxi(_peak_deltas,_delta_cache.size())
	return result
func hydrate(root: Dictionary, chunks: Array) -> Dictionary:
	if chunks.size() > 64: return Codec.fail("world_page_invalid")
	var seen := {}
	for chunk in chunks:
		if not chunk is Array or not Address.parse(chunk).ok or seen.has(Address.key(chunk)): return Codec.fail("world_page_invalid")
		seen[Address.key(chunk)] = true
	var verified := verify_root(root)
	if not verified.ok: return verified
	var deltas := {}
	for chunk in chunks:
		var result := lookup(root,chunk)
		if not result.ok: return result
		deltas[Address.key(chunk)] = result.props
	return {"ok":true,"deltas":deltas}
func begin_verified_read() -> void:
	_closure_manifest = ""
	# Checkpoint trust boundaries must observe current page bytes, even when a
	# previous boundary verified the same content address. Only the synchronous
	# verify/hydrate operation that follows may reuse its derived read caches.
	_page_cache.clear()
	_delta_cache.clear()
	_verified_roots.clear()
func verify_root(root: Dictionary) -> Dictionary:
	var valid := Codec.valid_root(root)
	if not valid.ok: return valid
	if _verified_roots.has(root.root_hash):
		_touch(_verified_roots,root.root_hash,true,8)
		return {"ok":true}
	_walk_visits = 0
	_root_walk_visits = 0
	_walk_stack_depth = 0
	var manifest := HashingContext.new()
	manifest.start(HashingContext.HASH_SHA256)
	var visit := func(hash: String) -> Dictionary:
		manifest.update(hash.to_utf8_buffer())
		return {"ok":true}
	var verified := _walk(root.root_hash,"",visit)
	if verified.ok: _closure_manifest = manifest.finish().hex_encode()
	if verified.ok: _touch(_verified_roots,root.root_hash,true,8)
	return verified
func diagnostics() -> Dictionary:
	return {"delta_cache_entries":_delta_cache.size(),"page_cache_entries":_page_cache.size(),"peak_delta_cache_entries":_peak_deltas,"peak_page_cache_entries":_peak_pages,"verified_roots":_verified_roots.size(),"disk_bytes":_disk_bytes,"disk_reads":_disk_reads,"pages_written":_pages_written,"quota_bytes":QUOTA_BYTES,"sweep_enabled":false,"last_walk_page_visits":_walk_visits,"last_walk_stack_depth":_walk_stack_depth,"walk_page_visit_limit_per_root":MAX_WALK_PAGE_VISITS}
func _read_page(hash: String) -> Dictionary:
	if not Codec.valid_hash(hash): return Codec.fail("world_page_invalid")
	if _page_cache.has(hash):
		var page: Dictionary = _page_cache[hash]
		_touch(_page_cache,hash,page,CACHE_LIMIT)
		return {"ok":true,"page":page.duplicate(true)}
	var loaded := _read_file(_path(hash),hash)
	if loaded.ok:
		_touch(_page_cache,hash,loaded.page.duplicate(true),CACHE_LIMIT)
		_peak_pages = maxi(_peak_pages,_page_cache.size())
	return loaded
func _read_file(path: String, hash: String) -> Dictionary:
	if not FileAccess.file_exists(path): return Codec.fail("world_page_missing")
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null: return Codec.fail("world_read_failed")
	var length := file.get_length()
	if length > Codec.MAX_BYTES:
		file.close()
		return Codec.fail("world_page_oversize")
	var bytes := file.get_buffer(length)
	file.close()
	_disk_reads += 1
	if bytes.size() != length: return Codec.fail("world_read_failed")
	return Codec.decode(bytes,hash)
func _write_page(page: Dictionary) -> Dictionary:
	var encoded := Codec.encode(page)
	if not encoded.ok: return encoded
	var path := _path(encoded.hash)
	if FileAccess.file_exists(path):
		# Never overwrite even a corrupt existing hash address; preserve evidence.
		var existing := _read_file(path,encoded.hash)
		if not existing.ok: return existing
		return {"ok":true,"hash":encoded.hash}
	if _disk_bytes+encoded.bytes.size() > QUOTA_BYTES: return Codec.fail("world_quota_exceeded")
	if DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK or _fault("page_write") != OK: return Codec.fail("world_write_failed")
	_sequence += 1
	var temp := path+".%d.%d.%d.tmp" % [OS.get_process_id(),Time.get_ticks_usec(),_sequence]
	var file := FileAccess.open(temp,FileAccess.WRITE)
	if file == null: return Codec.fail("world_write_failed")
	file.store_buffer(encoded.bytes)
	_disk_bytes += file.get_length()
	if file.get_error() != OK or _fault("page_flush") != OK:
		file.close()
		return Codec.fail("world_write_failed")
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK: return Codec.fail("world_write_failed")
	if _fault("page_readback") != OK: return Codec.fail("world_readback_failed")
	var readback := _read_file(temp,encoded.hash)
	if not readback.ok: return readback
	if _fault("page_publish") != OK: return Codec.fail("world_publish_failed")
	# Caller serializes app-world staging. Recheck for independently published data.
	if FileAccess.file_exists(path):
		var existing := _read_file(path,encoded.hash)
		return {"ok":true,"hash":encoded.hash} if existing.ok else existing
	if DirAccess.rename_absolute(temp,path) != OK: return Codec.fail("world_publish_failed")
	_pages_written += 1
	_touch(_page_cache,encoded.hash,readback.page.duplicate(true),CACHE_LIMIT)
	_peak_pages = maxi(_peak_pages,_page_cache.size())
	return {"ok":true,"hash":encoded.hash}
func _walk(hash: String, prefix: String, visitor: Callable) -> Dictionary:
	var previous: Variant = null
	var continuation := false
	while hash != "":
		if _root_walk_visits >= MAX_WALK_PAGE_VISITS: return Codec.fail("world_work_limit")
		_root_walk_visits += 1
		_walk_visits += 1
		_walk_stack_depth = maxi(_walk_stack_depth,prefix.length()+1)
		var loaded := _read_page(hash)
		if not loaded.ok: return loaded
		var page: Dictionary = loaded.page
		if continuation and page.kind != "collision": return Codec.fail("world_page_invalid")
		if page.kind == "branch":
			if page.depth != prefix.length() or prefix.length() >= 64: return Codec.fail("world_page_invalid")
			if visitor.is_valid():
				var visited: Dictionary = visitor.call(hash)
				if not visited.ok: return visited
			for child in page.children:
				var checked := _walk(child.hash,prefix+"0123456789abcdef"[child.nibble],visitor)
				if not checked.ok: return checked
			return {"ok":true}
		if page.kind == "collision" and prefix.length() != 64: return Codec.fail("world_page_invalid")
		# Canonical radix construction never emits empty descendants. Reject on
		# the first path, before a tiny shared empty DAG expands exponentially.
		if page.kind == "leaf" and not prefix.is_empty() and page.records.is_empty(): return Codec.fail("world_page_invalid")
		for record in page.records:
			var key_hash := Codec.digest(Address.key(record.chunk).to_utf8_buffer())
			if not key_hash.begins_with(prefix) or (previous != null and not Address.less(previous,record.chunk)): return Codec.fail("world_page_invalid")
			previous = record.chunk
		if visitor.is_valid():
			var visited: Dictionary = visitor.call(hash)
			if not visited.ok: return visited
		if page.kind == "leaf": return {"ok":true}
		hash = page.next_hash
		continuation = true
	return {"ok":true}
func _measure(path: String, depth: int = 0) -> Dictionary:
	if not DirAccess.dir_exists_absolute(path): return {"ok":true,"bytes":0}
	if depth > 3: return Codec.fail("world_storage_invalid")
	var dir := DirAccess.open(path)
	if dir == null or dir.list_dir_begin() != OK: return Codec.fail("world_read_failed")
	var total := 0
	var name := dir.get_next()
	while name != "":
		var child := path.path_join(name)
		if dir.current_is_dir():
			var nested := _measure(child,depth+1)
			if not nested.ok:
				dir.list_dir_end()
				return nested
			total += nested.bytes
		else:
			var file := FileAccess.open(child,FileAccess.READ)
			if file == null:
				dir.list_dir_end()
				return Codec.fail("world_read_failed")
			total += file.get_length()
			file.close()
		name = dir.get_next()
	dir.list_dir_end()
	return {"ok":true,"bytes":total}
func _path(hash: String) -> String:
	return _directory.path_join("pages").path_join(hash.substr(0,2)).path_join(hash+".json")
func _touch(cache: Dictionary, key: String, value: Variant, limit: int) -> void:
	cache.erase(key)
	cache[key] = value
	while cache.size() > limit: cache.erase(cache.keys()[0])
func _fault(stage: String) -> int:
	return int(_fault_injector.call(stage)) if _fault_injector.is_valid() else OK
func audit_pages(protected_roots: Array, commit_uncertain: bool) -> Dictionary:
	if commit_uncertain: return Codec.fail("commit_outcome_unknown")
	var initial := _root_set_digest(protected_roots)
	if not initial.ok: return initial
	_sequence += 1
	var directory := _directory.path_join("audits").path_join("%d_%d_%d" % [OS.get_process_id(),Time.get_ticks_usec(),_sequence])
	if DirAccess.make_dir_recursive_absolute(directory.path_join("marks")) != OK: return Codec.fail("world_write_failed")
	# A new audit does not trust partial markers or previous cache observations.
	_page_cache.clear()
	_delta_cache.clear()
	_verified_roots.clear()
	var count := [0]
	var mark := func(hash: String) -> Dictionary:
		if _fault("audit_mark") != OK: return Codec.fail("world_audit_interrupted")
		var path := directory.path_join("marks").path_join(hash.substr(0,2)).path_join(hash)
		if FileAccess.file_exists(path): return {"ok":true}
		if DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK: return Codec.fail("world_write_failed")
		var file := FileAccess.open(path,FileAccess.WRITE)
		if file == null: return Codec.fail("world_write_failed")
		file.store_8(1)
		file.flush()
		var error := file.get_error()
		file.close()
		if error != OK: return Codec.fail("world_write_failed")
		count[0] += 1
		return {"ok":true}
	var roots: Array = protected_roots.duplicate(true)
	_walk_visits = 0
	_walk_stack_depth = 0
	for root in roots:
		_root_walk_visits = 0
		var walked := _walk(root.root_hash,"",mark)
		if not walked.ok: return walked
	var orphan_file := FileAccess.open(directory.path_join("orphans.txt"),FileAccess.WRITE)
	if orphan_file == null: return Codec.fail("world_write_failed")
	var enumerated := _enumerate_orphans(_directory.path_join("pages"),directory.path_join("marks"),orphan_file)
	orphan_file.flush()
	var error := orphan_file.get_error()
	orphan_file.close()
	if not enumerated.ok: return enumerated
	if error != OK: return Codec.fail("world_write_failed")
	if _fault("audit_complete") != OK: return Codec.fail("world_audit_interrupted")
	var final_set := _root_set_digest(protected_roots)
	if not final_set.ok or final_set.hash != initial.hash: return Codec.fail("world_roots_changed")
	var result := {"ok":true,"reachable_count":count[0],"orphan_count":enumerated.count,"audit_path":directory.path_join("report.json")}
	var report := FileAccess.open(result.audit_path,FileAccess.WRITE)
	if report == null: return Codec.fail("world_write_failed")
	report.store_string(JSON.stringify({"complete":true,"roots_digest":initial.hash,"reachable_count":count[0],"orphan_count":enumerated.count,"sweep_enabled":false},"",true,true))
	report.flush()
	error = report.get_error()
	report.close()
	return result if error == OK else Codec.fail("world_write_failed")
func _root_set_digest(roots: Array) -> Dictionary:
	if roots.is_empty() or roots.size() > 64: return Codec.fail("world_page_invalid")
	var hashes := []
	for root in roots:
		if not root is Dictionary: return Codec.fail("world_page_invalid")
		var valid := Codec.valid_root(root)
		if not valid.ok: return valid
		if not hashes.has(root.root_hash): hashes.append(root.root_hash)
	hashes.sort()
	return {"ok":true,"hash":Codec.digest(JSON.stringify(hashes).to_utf8_buffer())}
func _enumerate_orphans(path: String, marks: String, output: FileAccess, depth: int = 0) -> Dictionary:
	if depth > 3: return Codec.fail("world_storage_invalid")
	var dir := DirAccess.open(path)
	if dir == null or dir.list_dir_begin() != OK: return Codec.fail("world_read_failed")
	var count := 0
	var name := dir.get_next()
	while name != "":
		if _fault("audit_enumerate") != OK:
			dir.list_dir_end()
			return Codec.fail("world_audit_interrupted")
		if dir.current_is_dir():
			var nested := _enumerate_orphans(path.path_join(name),marks,output,depth+1)
			if not nested.ok:
				dir.list_dir_end()
				return nested
			count += nested.count
		elif name.ends_with(".json"):
			var hash := name.trim_suffix(".json")
			if Codec.valid_hash(hash) and not FileAccess.file_exists(marks.path_join(hash.substr(0,2)).path_join(hash)):
				count += 1
				output.store_line(hash)
		name = dir.get_next()
	dir.list_dir_end()
	return {"ok":true,"count":count}
