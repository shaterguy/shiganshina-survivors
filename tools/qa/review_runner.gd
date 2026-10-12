extends SceneTree
var checks := 0
var failures: Array[String] = []
var suites := []
func check(value: bool, message: String) -> void:
 checks += 1
 if not value: failures.append(message); push_error("FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
 for folder in ["armored_actor","armored_contact"]:
  var files := DirAccess.get_files_at("res://tests/"+folder)
  for file in files:
   if not file.begins_with("test_") or not file.ends_with(".gd"): continue
   var path: String = "res://tests/"+folder+"/"+file
   if not OS.get_cmdline_user_args().is_empty() and not OS.get_cmdline_user_args()[0].is_empty() and not OS.get_cmdline_user_args()[0] in path: continue
   print("SUITE ",path)
   var prior := checks; var bad := failures.size()
   var script = load(path)
   if script == null or not script.can_instantiate(): check(false,"parse failure "+path); continue
   await script.new().run(self)
   suites.append({"path":path,"checks":checks-prior,"failures":failures.size()-bad})
 await process_frame
 await process_frame
 await create_timer(0.25).timeout
 if checks == 0: check(false,"no selected assertions were executed")
 var result := {"checks":checks,"failures":failures,"suites":suites}
 if not OS.get_environment("REVIEW_REPORT").is_empty(): FileAccess.open(OS.get_environment("REVIEW_REPORT"),FileAccess.WRITE).store_string(JSON.stringify(result,"\t",true,true)+"\n")
 print("REVIEW_RESULT checks=%d failures=%d"%[checks,failures.size()])
 quit(0 if failures.is_empty() else 1)
