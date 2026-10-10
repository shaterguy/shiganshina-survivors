# Shiganshina Survivors DEV

Godot 4.6.3 기반 비공개 팬 게임 프로토타입. 첫 번째 챕터, 모바일 가로 화면과 터치/게임패드 입력을 대상으로 합니다. 원작 세계관의 권리는 해당 권리자에게 있으며 공식 작품이 아닙니다.

## 로컬 실행과 테스트

필요한 도구: 공식 **Godot 4.6.3 standard** (`4.6.3.stable.official.7d41c59c4`), **Python 3.10 이상**. 아트 검증에는 Pillow가 추가로 필요합니다.

```sh
godot --editor --path .
bash tools/test.sh
python3 -m unittest discover -s tests/build -p 'test_*.py'
python3 tests/assets/test_canon_candidates.py
python3 tests/assets/test_armored_walk_candidate.py
python3 tools/art/validate_assets.py
```

Windows에서는 `python3` 대신 `py -3`, Godot 실행파일의 절대 경로를 사용할 수 있습니다. `tools/test.sh`는 Bash/WSL/Git Bash가 필요하며, Godot 테스트 자체는 `godot --headless --path . --script tests/run_all.gd`로도 실행할 수 있습니다. 종료 코드뿐 아니라 `SCRIPT ERROR`/`ERROR` 및 `RESULT`의 실패 수도 확인합니다.

## Android 로컬 빌드

[설치, 빌드, 검증, 키 백업·복구 안내](docs/build/android-local.md)를 따릅니다. GitHub Actions, Work 또는 클라우드 빌드 서비스는 사용하지 않습니다.

```sh
python3 tools/build/build_android.py --check-ready
python3 tools/build/build_android.py \
  --godot /absolute/path/to/godot \
  --template /absolute/path/to/android_debug-4.6.3.apk \
  --output dist/shiganshina-dev-unsigned.apk
```

- ARM64, `com.shaterguy.shiganshina.dev`, `0.1.0-dev1` / code `1`
- 인터넷 권한 없음, 자체 제작 512×512 앱 아이콘
- 표준 템플릿의 **미서명 APK 생성에는 Android SDK가 필요 없습니다**
- 설치 가능한 서명 APK는 사용자가 별도로 준비한 기존 키와 Android Build Tools로 만듭니다
- 원화 승인 게이트는 모든 내보내기에 필수입니다. 미승인 아트가 있거나 `final_export_allowed`가 `false`이면 빌드는 중단됩니다. `--check-ready`가 최신 상태를 보여 줍니다

## 자료

- [챕터 설계](docs/design/chapter-one.md)
- [제품 API 계약](docs/design/contracts.md)
- [아트 현황](docs/art/HANDOFF.md)
- [로컬 Android 빌드](docs/build/android-local.md)

비공개 저장소에도 키스토어, 암호 파일, 인증정보, 암호화한 키 백업을 올리지 않습니다. 원본 아트·오디오와 Godot `.import` 설정 및 `.gd.uid`는 소스에 포함하고, 생성 캐시는 제외합니다.
