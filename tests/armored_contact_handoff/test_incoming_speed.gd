extends RefCounted
const T = preload("res://tests/armored_contact_handoff/test_contact_handoff.gd")
const S = preload("res://tests/armored_actor/armored_support.gd")
func run(t) -> void:
 var seed:=T.actual_contact(184.25)
 var previous_distance: float=seed.prior_observation.charge_distance
 var profile: Dictionary=seed.fixture.state.rules.enemy_catalog.armored_titan.action_profile
 var nominal: float=seed.fixture.core._final_charge_speed(profile,int(seed.observation.contact.tick)-int(seed.observation.attack_started_tick))/60.0
 var rows: Array=[]
 for fraction in [0.0,.000001,.00001,.0001,.001,.01,.1,.5,.9,1.0]:
  var actual:=T.actual_contact(previous_distance+nominal*fraction)
  t.check(not actual.is_empty(),"fraction-speed public Core probe reaches contact "+str(fraction))
  if actual.is_empty(): continue
  var obs: Dictionary=actual.observation; var witness: Dictionary=obs.contact
  var expected: float=actual.fixture.core._final_charge_speed(profile,int(witness.tick)-int(witness.attack_started_tick))/60.0
  var estimate: Variant=float(obs.last_travel)/float(witness.fraction) if witness.fraction>0 else null
  var error: Variant=absf(estimate-expected) if estimate!=null else null
  if witness.fraction>=.01: t.check(error<.0001,"positive resolvable fraction recovers attempted tick distance against Core speed")
  rows.append({"requested_fraction":fraction,"actual_fraction":witness.fraction,"last_accepted_travel":obs.last_travel,"nominal_core_tick_distance":expected,"inferred_tick_distance":estimate,"absolute_error":error,"entry_distance":obs.charge_distance,"contact_tick":witness.tick,"inference_used_by_stop_curve":false})
 print("CONTACT_SPEED_EXPERIMENT ",JSON.stringify({"scope":"public Core speed comparison; no pose change","rows":rows}))
