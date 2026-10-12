extends RefCounted
# Environment-only test adapter. In this headless Godot environment DirAccess
# user:// listing resolves to cwd; absolute paths address the same owned files.
# Production, source fixtures and the existing test assertions remain untouched.
func run(t) -> void:
 var original := FileAccess.get_file_as_string("res://tests/armored_contact/test_contact_dock.gd")
 var needle := 'S.make(t,"",false)'
 t.check(original.count(needle) == 2,"existing dock regression adapter matches exactly two default-directory calls")
 var adapted := original.replace(needle,'S.make(t,ProjectSettings.globalize_path("user://existing_dock_%d_%d/saves"%[OS.get_process_id(),Time.get_ticks_usec()]),false)')
 var script := GDScript.new(); script.source_code = adapted
 t.check(script.reload() == OK,"existing dock assertions compile with absolute-path fixture only")
 if script.can_instantiate(): script.new().run(t)
