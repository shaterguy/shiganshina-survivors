extends SceneTree
var failures: Array[String] = []
var checks := 0
func check(value: bool, message: String) -> void:
 checks += 1
 if not value:
  failures.append(message)
  push_error("FAIL: " + message)
func _initialize() -> void:
 call_deferred("run")
func run() -> void:
 var args := OS.get_cmdline_user_args()
 if args.size() != 1:
  quit(2)
  return
 var path := str(args[0])
 print("FILE_START "+path)
 var trace_started := Time.get_ticks_usec()
 var script = load(path)
 check(script != null and script.can_instantiate(),"test script loads: "+path)
 var trace_body_checks_before := checks
 var trace_body_failures_before := failures.size()
 var trace_body_returned := false
 if script != null and script.can_instantiate():
  await script.new().run(self)
  trace_body_returned = true
 var trace_body_checks := checks-trace_body_checks_before
 var trace_body_failures := failures.size()-trace_body_failures_before
 var trace_elapsed_usec := Time.get_ticks_usec()-trace_started
 await process_frame
 await process_frame
 await create_timer(0.25).timeout
 check(checks > 0,"at least one test assertion ran")
 print("SINGLE_FILE_TRACE "+JSON.stringify({"path":path,"script_loaded":script != null and script.can_instantiate(),"body_returned":trace_body_returned,"body_checks":trace_body_checks,"body_failures":trace_body_failures,"elapsed_usec":trace_elapsed_usec}))
 print("FILE_END "+path)
 print("RESULT checks=%d failures=%d" % [checks,failures.size()])
 quit(0 if failures.is_empty() else 1)
