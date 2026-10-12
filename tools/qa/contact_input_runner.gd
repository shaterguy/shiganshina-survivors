extends SceneTree
var checks := 0
var failures: Array[String] = []
var suites: Array = []
func check(value: bool, message: String) -> void:
 checks += 1
 if not value: failures.append(message); push_error("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
 for file in DirAccess.get_files_at("res://tests/armored_contact_input"):
  if not file.begins_with("test_") or not file.ends_with(".gd"): continue
  if not OS.get_cmdline_user_args().is_empty() and not OS.get_cmdline_user_args()[0] in file: continue
  print("SUITE ",file)
  var start := checks; var bad := failures.size(); var script = load("res://tests/armored_contact_input/"+file)
  if script == null or not script.can_instantiate(): check(false,"parse failure "+file); continue
  await script.new().run(self)
  suites.append({"file":file,"checks":checks-start,"failures":failures.size()-bad})
 await process_frame
 await process_frame
 await create_timer(0.25).timeout
 if checks == 0: check(false,"no checks executed")
 var result := {"checks":checks,"failures":failures,"suites":suites}
 print("CONTACT_INPUT_RESULT ",JSON.stringify(result))
 if not OS.get_environment("REVIEW_REPORT").is_empty(): FileAccess.open(OS.get_environment("REVIEW_REPORT"),FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
 quit(0 if failures.is_empty() else 1)
