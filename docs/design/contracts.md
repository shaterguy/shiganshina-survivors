# Chapter One 공통 인터페이스 v1.2

상태: 현재 구현의 공통 API 계약. 2026-10-10 현재 코드와 통합 검사를 기준으로 갱신했다. Android 실기기 검증 및 최종 아트 승인은 별도 게이트다.

## 좌표·시간

- GDScript 4.6, `Dictionary` 기반 직렬화 DTO를 사용한다. 저장 DTO에는 Node/Resource/Callable/Vector2를 넣지 않고 위치는 `[x, y]` 실수 배열로 저장한다. transient 입력만 `Vector2`다.
- 월드 1단위 = 원본 도트 1픽셀. 타일 32단위, 이동 초깃값 100단위/초. 모든 속도·대미지·보상은 데이터에서 조정한다.
- 고정 시뮬레이션 60Hz. `active_tick`은 최종 탈출 구간에도 증가, `survival_tick`은 108000에서 정지한다. 메뉴·성장·회전·백그라운드·패드 해제 pause 중에는 둘 다 정지한다. 프레임 지연 때문에 틱을 건너뛰거나 시스템 시계를 게임 시간으로 쓰지 않는다.
- 보스 발생 틱은 `[18000,36000,54000,72000,90000,108000]`. 최종 대피 준비 틱은 `final_started_tick + 4500`이며 탈출 영역 진입은 별도 조건이다.
- 실행 재현 범위는 동일 엔진/빌드/콘텐츠/시드/입력열이다. 서로 다른 CPU에서 부동소수점 비트 단위 동등성을 보장한다고 쓰지 않는다.

## RunState v1

| 키 | 타입·초기값 또는 의미 |
|---|---|
| schema_version / content_revision | int `1` / string `ch01.2` |
| chapter_id / character_id | `chapter_01_shiganshina` / `garrison_01` |
| seed / rng_state | 32-bit nonnegative int / Godot RNG state를 10진 문자열로 보존 |
| active_tick / survival_tick / next_entity_id / event_seq | int, 시간·ID·이벤트 단조 증가 |
| phase | `survival`, `evacuation`, `won`, `dead` 중 하나 |
| pause_reasons | string 배열: `user`, `upgrade`, `rotation`, `background`, `controller_lost`, `slow_frame` |
| player | id, position, velocity, hp, max_hp, invulnerable_until, xp, level |
| equipment / passives | 안정된 item_id → level 사전; 공격/지원 슬롯 최대 4 |
| entities / projectiles / drops / telegraphs | entity_id로 식별되는 직렬화 레코드 배열 |
| boss_ids_fired / reward_ids_claimed / command_ids_applied | 중복 방지 ID 집합을 정렬된 string 배열로 보존 |
| upgrade_offer / pending_offers | 빈 사전 또는 offer_id, options 3개, selected_option_id(의미 기반 포커스) / 후속 offer의 FIFO 배열 |
| final_started_tick / evacuation_ready / escape_zone | int `-1`, bool `false`, rect `[x,y,w,h]` |
| stats | kills, damage_dealt, minibosses_defeated |

Core만 RunState의 게임플레이 필드를 변경한다. UI는 읽기 전용 복사본을 받는다. UI/Platform은 공통 메서드로 pause reason·선택 포커스를 갱신하며 원본 사전을 직접 바꾸지 않는다. 진행 저장에는 `unlocked_character_ids`, `cleared_chapter_ids`, `best_runs`, `settings`를 둔다. 이번 실제 character_id는 `garrison_01`뿐이다. 후속 캐릭터 해금·챕터 시점에 맞는 선택 방향은 후속 확장 방향이며, 후속 캐릭터의 실제 데이터/아트는 만들지 않는다.

## 공개 API

아래 경로는 저장소 루트 기준이다. 반환 실패는 null이 아니라 `{ok:false,error_code:String}`로 표현한다.

| 모듈 | 파일 / 공개 API | 계약 |
|---|---|---|
| App | `game/contracts/game_contracts.gd`: `validate_snapshot(value: Dictionary) -> Array[String]` | 오류 목록. JSON 안전성·필수 키·phase·ID 검사 |
| Core | `game/core/run_simulation.gd`: `new_run(chapter: Dictionary, seed: int) -> Dictionary` | chapter 초기 병사/장비로 상태 생성 |
| Core | 같은 파일: `step(state: Dictionary, move: Vector2, commands: Array[Dictionary]) -> Array[Dictionary]` | pause/terminal이면 무변경. 그 외 정확히 1틱 갱신, 이벤트 배열 반환 |
| Core | 같은 파일: `choose_upgrade(state: Dictionary, offer_id: String, option_id: String) -> Dictionary` | 현재 offer의 유효 option만 적용; 중복/이전 offer 거부; 다음 대기 offer 또는 pause 해제 |
| Core | 같은 파일: `set_pause(state: Dictionary, reason: String, enabled: bool) -> void` | reason별 독립 해제. `user`를 제거해도 background 등이 남으면 전투 정지 |
| Core | 같은 파일: `set_offer_focus(state: Dictionary, option_id: String) -> void` | 유효 offer 항목에 한정; 회전 후 동일 선택 의미 보존 |
| Core | 같은 파일: `abandon_run(state: Dictionary) -> Array[Dictionary]` | 명시 종료 확인 뒤 dead 전환, run_ended reason=`abandoned`, 클리어/보상 없음 |
| Core | 같은 파일: `snapshot(state: Dictionary) -> Dictionary`, `restore(value: Dictionary) -> Dictionary` | deep copy / `{ok,state}` 또는 오류; 원본 변형 금지 |
| Director | `game/director/spawn_director.gd`: `plan(state: Dictionary, chapter: Dictionary) -> Array[Dictionary]` | 읽기만; 다음 1틱에 적용할 spawn/보스/위험/최종 명령. pause/terminal이면 빈 배열 |
| Director | `game/director/chapter_catalog.gd`: `load_chapter(chapter_id: String) -> Dictionary` | `{ok,chapter}` 또는 오류; 무효/미존재 ID 조용한 fallback 금지 |
| UI/Platform | `game/input/input_router.gd`: `sample_move() -> Vector2`, `clear_transient_input() -> void` | deadzone 후 길이≤1; 패드해제/회전/포커스상실시 0 |
| UI/Platform | 같은 파일 signals: `ui_action(action: String)`, `active_controller_lost`, `input_hint_changed(kind: String)` | action=`accept,cancel,pause,up,down,left,right`; kind=`touch,gamepad` |
| UI/Platform | `game/ui/game_ui.gd`: `present(snapshot: Dictionary) -> void`, `reflow(size_px: Vector2i, safe_rect_px: Rect2i) -> void` | 화면 표현만; signal `upgrade_chosen(offer_id:String,option_id:String)`, `upgrade_focus_changed(option_id:String)`, `pause_changed(enabled:bool)`, `new_run_requested`, `resume_requested`, `settings_changed(values:Dictionary)`, `end_run_requested` |
| UI/Platform | `game/input/lifecycle_guard.gd`: `map_safe_area(viewport_size:Vector2i,window_size:Vector2i,safe_screen_rect:Rect2i,window_position:Vector2i) -> Rect2i` | 물리 디스플레이 safe area를 논리 좌표로 안쪽 반올림. 실제 OS/회전 callbacks와 Core pause 적용은 run_controller가 처리 |
| UI/Platform | `game/persistence/save_store.gd`: `save_checkpoint(snapshot: Dictionary) -> Dictionary`, `load_checkpoint() -> Dictionary` | `{ok}` / `{ok,snapshot}` 또는 오류; app-private temp+검증+원자교체+이전본 보존 |
| UI/Platform | 같은 파일: `save_profile(profile: Dictionary) -> Dictionary`, `load_profile() -> Dictionary` | profile schema migration 후 `{ok,profile}` 반환; 런 불일치가 profile 삭제로 번지지 않음 |
| App | `game/app/run_controller.gd`: `start_run(seed: int) -> void`, `advance_frame(delta: float) -> void`, `request_resume() -> void`, `request_end_run() -> void` | 입출력·director·simulation·UI·저장 조립, bounded catch-up; 남은 backlog는 보존/과다시 명시적 slow_frame pause |

## 명령·이벤트

- 명령 공통 `{command_id:String, kind:String, payload:Dictionary}`. core는 command_id를 한 번만 적용한다. 반복 호출·재개에서 같은 ID를 사용한다. 프레임 번호를 ID로 쓰지 않는다.
- `spawn_enemy`: payload=`entity_id, enemy_id, position, spawned_tick`.
- `spawn_boss`: payload=`boss_id, entity_id, enemy_id, position, scheduled_tick`. 보스 ID는 `ch01_b05`, `ch01_b10`, `ch01_b15`, `ch01_b20`, `ch01_b25`.
- `telegraph_attack`: payload=`source_id, shape(circle/sector/line), origin, direction, radius, length, width, warning_ticks, active_ticks, damage`. shape에 필요한 수치만 필수. 피격 판정과 보이는 범위는 동일한 데이터다. 보스 경고는 초깃값 최소 45틱; 화면 밖 위험은 UI 방향 경고와 함께 충분히 예고한다.
- `begin_evacuation`: payload=`boss_id:ch01_final_armored, escape_zone, evacuation_ticks:4500`. 일반 spawn 종료, 이전 적/드롭을 보상 없이 정리하고 hp·장비 유지. final 위협은 처치 대상이 아니다.
- `evacuation_ready`: payload 빈 사전. 전환 시각부터 4500 active ticks 뒤 true. 해당 틱의 피해→사망 판정→탈출 판정 순으로 처리한다.
- 이벤트 공통 `{event_id:String, type:String, tick:int, payload:Dictionary}`. type=`damage,xp_gained,upgrade_opened,upgrade_applied,boss_spawned,boss_defeated,phase_changed,run_ended`. UI/오디오/체크포인트는 같은 event_id를 두 번 소비하지 않는다.
- `run_ended.payload.result`는 `won/dead` 중 하나, 런당 한 번. 보상 offer는 현재 성장 offer 뒤 FIFO로 보관해 중간보스와 레벨업 동시 발생에도 선택을 잃지 않는다.

## 챕터·자산 계약

`chapters/chapter_01/manifest.json`: `chapter_id,content_revision,story_year:845,character_availability:[{character_id:garrison_01,unlock_condition:default}],map_id,spawn_position,allowed_equipment_ids,enemy_ids,boss_schedule,story_events,clear_rule:evacuate_then_exit,evacuation_ticks:4500,next_unlocks:[]`.

`assets/manifest.json`: asset_id별 `path,kind,source_method,license_note,width,height,cell_w,cell_h,anchor_px,animations,sha256`. 이미지는 PNG RGBA, nearest filter, mipmap off. 발 anchor는 셀 하단 중앙; 동일 캐릭터의 모든 프레임에서 같은 위치다. animation 키는 `idle,move,hit,death,windup,attack`; 존재하지 않는 동작은 목록에서 빼고 사용하는 쪽이 요구한 동작은 누락시키지 않는다. 재생 fps는 asset별 메타데이터를 사용하며, 공격 경고 시간은 시뮬레이션이 결정하며 애니메이션에 종속되지 않는다.

설정 변경은 U가 signal로 전달하고 I가 profile 검증·저장·실제 오디오/렌더/입력 적용을 담당한다. 명시적 resume은 foreground에서만 가능하며 transient 입력을 비운 뒤 background/controller_lost/user/slow_frame 사유를 해제한다. upgrade 사유는 임의 해제하지 않는다. focus 상실과 패드 연결 시 A는 release 후 재입력해야 한다. 물리 스틱 중립을 실기기에서 확인하는 별도 재개 게이트까지 구현됐다고 주장하지 않는다. 종료 확인 modal 뒤 I.request_end_run이 C.abandon_run을 호출한다.

입력은 U의 raw InputEvent 어댑터가 처리한다. 공통 semantic UI action은 `accept,cancel,pause,up,down,left,right`이고 이동은 정규화 Vector2다. Godot 기본 ui_accept의 GUI 중복 소비는 실제 이벤트 통합 검사에서 1회 적용을 확인한다. D-pad 반복은 300ms 지연/100ms 간격으로 직접 처리한다. 터치 A/B/Menu 아이콘은 A가 제작하며 U가 임의 SVG로 대체하지 않는다.

## 계약 검증

`tests/contracts/test_snapshot.gd`: 독립 fixture의 JSON roundtrip 후 ID·RNG·타이머 동일, 알 수 없는 phase 거부. Core 완성 뒤 `tests/core/test_run_state.gd`에서 중복 command 무효와 snapshot 외부 변경의 원본 무영향을 검증한다.
`tests/contracts/test_module_interfaces.gd`: 위 파일/API와 signals 존재, B.plan 실제 보스 경계 호출 전후 상태 동일, U.present/reflow 호출 전후 동일. 계약 변경은 I 검토→문서·계약 테스트 동시 수정→소비자 담당에게 전달 순서다.

## ch01.2 실제 지도 및 저장 경계

- `chapters/chapter_01/map.json.geometry`의 bounds/obstacles를 ChapterCatalog가 `chapter.world_geometry`로 전달하고 Core가 `rules.world_geometry`에 포함한다. 플레이어·적 반경, 건물 지면 충돌, 월드 경계, 돌진 정지/도약 착지 모두 같은 geometry를 사용한다.
- Core restore는 입력을 바꾸지 않고 JSON의 정수 의미 float를 사본에서 int로 정규화한다. 분수/overflow ID는 거절하며 StringName 사전 키는 JSON-safe로 인정한다. 실제 director 숫자 ID와 모든 행동 phase, 디스크 SaveStore 왕복을 검증한다.
- App은 content revision과 geometry가 모두 일치할 때만 전투 checkpoint를 재개한다. 이전 revision 전투는 파일을 보존하고 새 출격을 안내한다. profile 진행/설정은 독립 보존한다.
- 거절된 자산은 manifest의 export_blocked/final_export_allowed에 의해 최종 APK 생성이 차단된다. 개발 렌더는 승인된 basic 거인만 대체 표시하며 수정중 문구를 표시한다. 후보 보행 sheet는 runtime 승인과 분리 보존한다.
