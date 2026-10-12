extends RefCounted
const City = preload("res://game/director/streamed_chapter_provider.gd")
const H = preload("res://game/core/streamed_run_world.gd")
const Director = preload("res://game/director/spawn_director.gd")
const F = preload("res://tests/core/core_fixture.gd")
const HF = preload("res://tests/core_world/new_streamed_helper_fixture.gd")
class GuardHelper:
	extends "res://game/core/streamed_run_world.gd"
	var control := {"armed":false,"moves":0,"injected":false,"failure":{}}
	func fresh():
		var next = GuardHelper.new(_definitions)
		next.control = control
		return next
	func move(position: Vector2, delta: Vector2, radius: float) -> Dictionary:
		if control.armed and radius == 18.0:
			control.moves += 1
			if control.moves == 2:
				# A real helper guard and actual world coverage lookup produce the
				# failure; no fabricated failure return replaces production logic.
				control.failure = super.walkable(Vector2(9000.0,384.0),radius)
				control.injected = true
		return super.move(position,delta,radius)
class ObserveCore:
	extends "res://game/core/run_simulation.gd"
	var review_enabled := false
	var review_uncached := false
	var review_rows: Array = []
	func _movement_target(state: Dictionary, target: Vector2, radius: float, cache: Variant) -> Vector2:
		var id_before: int = _streamed.get_instance_id()
		var queries_before: int = _streamed._world.diagnostics().query_count
		var populated: bool = cache is Dictionary and cache.has("targets") and not cache.targets.is_empty()
		var result: Vector2 = _nearest_world(state,target,radius) if review_uncached else super._movement_target(state,target,radius,cache)
		if review_enabled:
			review_rows.append({"helper":id_before,"revision":state.world.world_revision,"populated_before":populated,"queries":_streamed._world.diagnostics().query_count-queries_before,"target":[target.x,target.y],"result":[result.x,result.y],"ok":_streamed.query_status().get("ok",false),"cache_empty":cache is Dictionary and cache.is_empty()})
		return result
class NoLegalCore:
	extends "res://game/core/run_simulation.gd"
	var nearest_calls := 0
	func _nearest_world(_state: Dictionary,_point: Vector2,_radius: float) -> Vector2:
		nearest_calls += 1
		return Vector2(INF,INF)
var failures := 0
var checks := 0
var summaries := {}
var harness
func check(value: bool,note: String) -> void:
	harness.check(value,note)
	checks += 1
	if not value: failures += 1
	print(("PASS " if value else "FAIL ")+note)
func fixture() -> Dictionary:
	var city = City.new()
	var chapter: Dictionary = city.load_chapter("chapter_01_shiganshina").chapter
	var sim = ObserveCore.new(city,GuardHelper.new(chapter.world_definitions))
	var state: Dictionary = sim.new_run(chapter,42,F.run_config())
	state.player.position=[384.0,384.0]
	state.player.attack_ready_ticks={"blade_slash":200000}
	var commands: Array[Dictionary]=[]
	for i in 3: commands.append({"command_id":"review:spawn:"+str(i),"kind":"spawn_enemy","origin_revision":0,"payload":{"entity_id":"review:actor:"+str(i),"enemy_id":"walker","position":[480.0+i*20.0,384.0],"spawned_tick":0}})
	var hydration: Dictionary=HF.hydration(H.requirements(state,commands))
	check(sim.prepare_world(state,hydration,commands).get("ok",false),"review fixture actual Core prepares")
	F.step(sim,state,Vector2.ZERO,commands)
	check(sim.step_status().get("ok",false) and state.entities.size()==3,"review fixture actually spawns three walkers")
	return {"sim":sim,"state":state,"hydration":hydration,"chapter":chapter}
func query_count(sim) -> int: return int(sim._streamed._world.diagnostics().query_count)
func fresh_query(sim,state: Dictionary,target: Vector2,radius: float,cache: Dictionary,note: String) -> void:
	var before := query_count(sim)
	var result: Vector2=sim._movement_target(state,target,radius,cache)
	var count := query_count(sim)-before
	var actual: Vector2=sim._nearest_world(state,target,radius)
	check(count>0 and result==actual,note+" recomputes and equals uncached")
func boundaries() -> void:
	var f=fixture();var sim=f.sim;var state: Dictionary=f.state;var cache := {};var target := Vector2(384,384)
	fresh_query(sim,state,target,18.0,cache,"first exact key")
	var before:=query_count(sim)
	check(sim._movement_target(state,target,18.0,cache)==target and query_count(sim)==before,"identical target and radius is an exact cache hit")
	var close_target := Vector2(384.00006103515625,384)
	check(close_target!=target,"close target fixture remains distinct at Vector2 precision")
	fresh_query(sim,state,close_target,18.0,cache,"close target")
	fresh_query(sim,state,target,18.000000000001,cache,"close double-precision radius")
	state.active_tick += 1
	fresh_query(sim,state,target,18.0,cache,"changed active tick")
	state.entities.append(state.entities[0].duplicate(true))
	fresh_query(sim,state,target,18.0,cache,"changed actor count")
	state.entities.pop_back()
	fresh_query(sim,state,target,18.0,cache,"restored actor count")
	state.world.origin_revision += 1
	fresh_query(sim,state,target,18.0,cache,"changed origin revision")
	state.world.origin_revision -= 1
	state.world.origin_chunk=["1","0"]
	fresh_query(sim,state,target,18.0,cache,"changed saved origin chunk")
	state.world.origin_chunk=["0","0"]
	state.world.world_revision += 1
	fresh_query(sim,state,target,18.0,cache,"changed saved world revision")
	state.world.world_revision -= 1
	var applied: Dictionary=sim._streamed._world.apply_props([],1)
	check(applied.get("ok",false),"real geometry apply increments actual world revision")
	fresh_query(sim,state,target,18.0,cache,"changed actual world revision")
	var prepared: Dictionary=sim._streamed._world.prepare([["0","0"]],[],f.hydration,["0","0"])
	check(prepared.get("ok",false),"real world prepare changes resident coverage")
	fresh_query(sim,state,target,18.0,cache,"changed actual coverage revision")
	var uncovered: Dictionary=sim._streamed._world.prepare([["1","0"]],[],f.hydration,["0","0"])
	check(uncovered.get("ok",false),"real world coverage removal retires cached target chunk")
	var missing: Vector2=sim._movement_target(state,target,18.0,cache)
	check(not is_finite(missing.x) and cache.is_empty() and sim._streamed.query_status().get("error_code")=="world_not_ready","removed target coverage cannot reuse cached success")
	check(sim._streamed.prepare(state,f.hydration).get("ok",false),"real helper preparation repairs removed coverage")
	var previous=sim._streamed
	var next=previous.fresh()
	check(next.prepare(state,f.hydration).get("ok",false),"fresh real helper prepares")
	sim._streamed=next
	fresh_query(sim,state,target,18.0,cache,"helper replacement")
	var old_world=sim._streamed._world
	var world_source=sim._streamed.fresh()
	check(world_source.prepare(state,f.hydration).get("ok",false),"separate replacement world prepares")
	sim._streamed._world=world_source._world
	fresh_query(sim,state,target,18.0,cache,"world replacement without helper replacement")
	sim._streamed._world=old_world
	# Direct helper calls deliberately omit the local movement dictionary.
	before=query_count(sim)
	var d1: Vector2=sim._direction_world(state,Vector2(480,384),target,18.0,"direct-a")
	var first:=query_count(sim)-before
	before=query_count(sim)
	var d2: Vector2=sim._direction_world(state,Vector2(480,384),target,18.0,"direct-a")
	check(d1==d2 and first==query_count(sim)-before and first>0,"direct direction calls revalidate and never share the batch cache")
	var bad: Dictionary=sim._streamed.walkable(Vector2(9000,384),18)
	check(not bad.get("ok",false) and bad.error_code=="world_not_ready","actual missing-coverage query fails through production guard")
	before=query_count(sim)
	sim._movement_target(state,target,18.0,cache)
	check(query_count(sim)>before and cache.is_empty() and not sim._streamed.query_status().get("ok",false),"sticky failure bypasses and clears a populated cache despite a later successful point query")
	check(sim._streamed.begin_query_batch(state).get("ok",false),"new valid batch resets earlier query failure")
	for radius in [-0.000001,32.000001,INF,NAN]:
		cache.clear();sim._movement_target(state,target,18.0,cache)
		sim._movement_target(state,target,radius,cache)
		check(cache.is_empty() and sim._streamed.query_status().get("error_code")=="unsupported_radius","invalid radius is never cached: "+str(radius))
		sim._streamed.begin_query_batch(state)
	for point in [Vector2(INF,384),Vector2(384,INF),Vector2(NAN,384),Vector2(50000,384)]:
		cache.clear();sim._movement_target(state,target,18.0,cache)
		var output: Vector2=sim._movement_target(state,point,18.0,cache)
		check(cache.is_empty() and not is_finite(output.x),"invalid or nonfinite target is never cached: "+str(point))
		sim._streamed.begin_query_batch(state)
	# Narrow sentinel-path test: only no-legal-target output is synthetic. Real
	# Core/helper/world initialization, identity and admission logic are retained.
	var sentinel=NoLegalCore.new(City.new());var sentinel_state: Dictionary=sentinel.new_run(f.chapter,42,F.run_config())
	sentinel_state.player.position=[384.0,384.0]
	check(sentinel.prepare_world(sentinel_state,HF.hydration(H.requirements(sentinel_state))).get("ok",false),"no-legal sentinel fixture has real prepared helper")
	cache.clear();sentinel._movement_target(sentinel_state,target,18.0,cache);sentinel._movement_target(sentinel_state,target,18.0,cache)
	check(sentinel.nearest_calls==2 and cache.is_empty() and sentinel._streamed.query_status().get("ok",false),"successful-status nonfinite clearance output is never cached")
func rollback_batch() -> void:
	var f=fixture();var sim=f.sim;var state: Dictionary=f.state;var before:=state.duplicate(true)
	sim.review_enabled=true;sim._streamed.control.armed=true
	var events: Array=F.step(sim,state,Vector2.RIGHT)
	check(sim.review_rows.size()==3 and sim.review_rows[1].populated_before and sim.review_rows[1].queries==0,"actual movement batch has a populated target cache hit before failure")
	check(sim._streamed.control.injected and sim._streamed.control.failure.get("error_code")=="world_not_ready","second actor causes actual geometry coverage-guard failure")
	check(sim.review_rows.size()==3 and sim.review_rows[2].populated_before and sim.review_rows[2].queries>0 and sim.review_rows[2].cache_empty,"actor after failure revalidates and clears successful cache")
	check(events.is_empty() and state==before and not sim.step_status().get("ok",false),"actual Core failure rolls back entire tick state and events")
	summaries.rollback_rows=sim.review_rows.duplicate(true)
	sim._streamed.control.armed=false;sim.review_rows.clear()
	var retried: Array=F.step(sim,state,Vector2.RIGHT)
	check(sim.step_status().get("ok",false) and state.active_tick==before.active_tick+1,"repaired real geometry batch retries exactly one tick")
	check(sim.review_rows[0].queries>0 and sim.review_rows[1].queries==0,"retry starts a fresh target cache and then shares successes")
	check(sim.restore(JSON.parse_string(JSON.stringify(state,"",true,true)),sim._streamed._hydration).get("ok",false),"successful retry cold-restores")
func final_fixture() -> Dictionary:
	var f=fixture();var sim=f.sim;var state: Dictionary=f.state
	f.walkers=state.entities.duplicate(true)
	state.entities.clear();state.active_tick=107999;state.survival_tick=107999
	var commands: Array=Director.new().plan(state,f.chapter)
	for command in commands:
		if H.spatial_command(command): command.origin_revision=state.world.origin_revision
	check(sim.prepare_world(state,HF.hydration(H.requirements(state,commands)),commands).get("ok",false),"final boundary actual Core prepares")
	F.step(sim,state,Vector2.ZERO,commands)
	check(state.entities.size()==1 and state.entities[0].enemy_id=="armored_titan","real final actor spawned")
	if state.entities.size()!=1: return {}
	var target: Dictionary={};var origin:=Vector2.ZERO;var player:=Vector2.ZERO;var walker_point:=Vector2.ZERO
	for prop in sim._streamed.props_query(Rect2(-512,-512,1792,1792)).props:
		if not prop.destructible or prop.collision_mask==0: continue
		var box: Rect2=prop.ground_footprint
		# Stay inside this same origin chunk but admit either horizontal face.
		# The retired64px/body-only setup cannot admit current97px preparation.
		for direction in [Vector2.RIGHT,Vector2.LEFT]:
			var start:Vector2=box.get_center()-direction*(box.size.x*.5+110)
			var finish:Vector2=box.get_center()+direction*(box.size.x*.5+10)
			var walk:Vector2=box.get_center()+direction*(box.size.x*.5+100)
			if not Rect2(0,0,768,768).has_point(finish):continue
			if sim._streamed.walkable(start,32).get("walkable",false) and sim._streamed.walkable(finish,8).get("walkable",false) and not sim._streamed.walkable(finish,18).get("walkable",false) and sim._streamed.walkable(walk,18).get("walkable",false):
				if not sim._final_contact_ready(state,start,direction,state.rules.enemy_catalog.armored_titan.action_profile,sim._streamed).get("clear",false):continue
				target=prop;origin=start;player=finish;walker_point=walk;break
		if not target.is_empty():break
	check(not target.is_empty(),"real destructible fixture has radius8 player target blocked for radius18 walkers")
	if target.is_empty(): return {}
	var actor: Dictionary=state.entities[0]
	actor.position=[origin.x,origin.y];state.player.position=[player.x,player.y]
	state.telegraphs.clear();sim._set_action(actor,"move",int(state.active_tick),0);actor.next_action_tick=state.active_tick
	check(sim.prepare_world(state,HF.hydration(H.requirements(state))).get("ok",false),"arranged actual final attack fully restores")
	var reached:=false
	for tick in 140:
		actor=state.entities[0]
		if actor.action_state=="attack":
			var profile: Dictionary=state.rules.enemy_catalog.armored_titan.action_profile
			var speed: float=sim._final_charge_speed(profile,int(state.active_tick)+1-int(actor.action_started_tick))
			var direction:=Vector2(actor.locked_direction[0],actor.locked_direction[1])
			var contact: Dictionary=sim._final_contact_sweep(state,Vector2(actor.position[0],actor.position[1]),direction*speed/60.0,direction,profile,sim._streamed)
			if contact.get("ok",false) and contact.contact.get("shape")=="shoulder_circle" and contact.contact.get("prop_id","")==target.prop_id and contact.fraction<1:
				reached=true;break
		F.step(sim,state,Vector2.ZERO,Director.new().plan(state,f.chapter))
	check(reached,"next actual final charge tick physically reaches selected destructible")
	if not reached: return {}
	for walker in f.walkers:
		walker.position=[walker_point.x,walker_point.y]
		sim._initialize_action(state,walker)
	# Arrange actual spawned actor records only for adversarial ordering, then
	# validate them via the complete Core restore before executing the batch.
	state.entities=[f.walkers[0],f.walkers[1],actor,f.walkers[2]]
	check(sim.prepare_world(state,HF.hydration(H.requirements(state))).get("ok",false),"cache-before-and-after-destruction ordering passes actual full Core restore")
	f.target=target
	return f
func destruction_batch() -> void:
	var f=final_fixture()
	if f.is_empty(): return
	var sim=f.sim;var state: Dictionary=f.state
	var before:=state.duplicate(true);var old_helper=sim._streamed
	# First force a real geometry error after cache population, before contact.
	sim.review_enabled=true;old_helper.control.armed=true;old_helper.control.moves=0
	var failed_events: Array=F.step(sim,state,Vector2.ZERO)
	check(old_helper.control.injected and sim.review_rows.size()==3 and sim.review_rows[1].queries==0,"destruction regression injects geometry failure after a real cache hit")
	check(state==before and failed_events.is_empty() and sim._streamed==old_helper and not sim.step_status().get("ok",false),"earlier real guard failure prevents destructive helper replacement and atomically rolls back")
	summaries.failed_destruction_rows=sim.review_rows.duplicate(true)
	old_helper.control.armed=false;sim.review_rows.clear()
	# A fresh uncached control executes the identical accepted state and geometry.
	var control=ObserveCore.new(City.new(),GuardHelper.new(f.chapter.world_definitions))
	var control_state:=before.duplicate(true)
	check(control.prepare_world(control_state,sim._streamed._hydration).get("ok",false),"uncached destruction control fully prepares")
	control.review_uncached=true;control.review_enabled=true
	var events: Array=F.step(sim,state,Vector2.ZERO)
	var control_events: Array=F.step(control,control_state,Vector2.ZERO)
	var rows: Array=sim.review_rows
	check(sim.step_status().get("ok",false) and state.world.world_revision==before.world.world_revision+1 and events.filter(func(e): return e.type=="structure_destroyed").size()==1,"actual reached structure destruction commits exactly once")
	check(rows.size()==3 and rows[0].queries>0 and rows[1].queries==0 and rows[1].populated_before,"same actual batch fills then hits target clearance before destruction")
	check(rows.size()==3 and rows[2].helper!=rows[0].helper and rows[2].revision==1 and rows[2].queries>0,"actor after destruction recomputes against actual replacement helper/revision")
	check(rows.size()==3 and rows[0].result!=rows[0].target and rows[2].result==rows[2].target,"real destroyed geometry changes clearance result from adjusted target to exact player target")
	check(state==control_state and events==control_events and sim.step_status()==control.step_status(),"cached destructive batch exactly equals uncached state/events/navigation/status")
	var cached_diagnostics: Dictionary=sim._streamed.status()
	var uncached_diagnostics: Dictionary=control._streamed.status()
	summaries.destruction_diagnostic_differences={}
	for key in cached_diagnostics:
		if cached_diagnostics[key]!=uncached_diagnostics.get(key):
			summaries.destruction_diagnostic_differences[key]={"cached":cached_diagnostics[key],"uncached":uncached_diagnostics.get(key)}
	for key in ["query_count","clearance_cache_entries"]:
		cached_diagnostics.erase(key);uncached_diagnostics.erase(key)
	check(cached_diagnostics==uncached_diagnostics,"destructive helper diagnostics match beyond approved query/cache cost fields")
	check(sim.restore(JSON.parse_string(JSON.stringify(state,"",true,true)),sim._streamed._hydration).get("ok",false),"destructive batch cold-restores")
	summaries.destruction_rows=rows.duplicate(true)
	summaries.destruction_control_rows=control.review_rows.duplicate(true)
	var repeated: Array=F.step(sim,state,Vector2.ZERO)
	check(repeated.filter(func(e): return e.type=="structure_destroyed").is_empty() and state.world.world_revision==1,"next actual tick cannot repeat committed destruction")
func rebase_batch() -> void:
	var f=fixture();var sim=f.sim;var state: Dictionary=f.state
	state.player.position=[1152.0,384.0]
	var hydration: Dictionary=HF.hydration(H.requirements(state))
	check(sim.prepare_world(state,hydration).get("ok",false),"actual rebase fixture fully prepares beyond one chunk")
	var control=ObserveCore.new(City.new(),GuardHelper.new(f.chapter.world_definitions))
	var control_state:=state.duplicate(true)
	check(control.prepare_world(control_state,hydration).get("ok",false),"uncached actual rebase control fully prepares")
	control.review_uncached=true;sim.review_enabled=true
	var old_helper=sim._streamed
	var events: Array=F.step(sim,state,Vector2.ZERO)
	var control_events: Array=F.step(control,control_state,Vector2.ZERO)
	check(sim.step_status().get("ok",false) and state.world.origin_chunk==["1","0"] and state.world.origin_revision==1 and sim._streamed!=old_helper,"actual Core tick rebases and replaces helper")
	check(sim.review_rows.size()==3 and sim.review_rows[0].queries>0 and sim.review_rows[1].queries==0,"rebased movement batch recomputes first target before sharing")
	check(state==control_state and events==control_events and sim.step_status()==control.step_status(),"cached rebased batch exactly equals uncached state/events/navigation/status")
	check(sim.restore(JSON.parse_string(JSON.stringify(state,"",true,true)),sim._streamed._hydration).get("ok",false),"actual rebased batch cold-restores")
	summaries.rebase_rows=sim.review_rows.duplicate(true)
func run(t) -> void:
	harness=t
	boundaries();rollback_batch();destruction_batch();rebase_batch()
