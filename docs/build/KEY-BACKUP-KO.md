# 게임 서명키 백업: 사용자가 휴대폰에서 직접 할 일

소스는 비공개 GitHub에 저장되어 있습니다. 다른 컴퓨터에서 같은 앱을 업데이트하려면 **지금 사용한 서명키도 복원**해야 합니다. 아래 작업은 사용자가 Termux에서 직접 합니다. 키·기존 암호·새 백업 암호를 채팅에 보내지 마세요.

## 1. 준비

휴대폰 Termux에서 `gpg --version`을 실행합니다. 명령이 없을 때만 공식 Termux 저장소에서 `pkg install gnupg`로 설치합니다. 해당 휴대폰의 GnuPG 설치 여부는 아직 확인하지 않았습니다.

## 2. 암호화하고, 복원 암호를 확인하고, 본인이 저장

다음 전체를 Termux에 붙여 넣습니다. 화면에서 **새 백업용 암호**를 직접 정하고, 검증 때 같은 암호를 다시 입력합니다. 기존 키 암호를 알거나 입력할 필요는 없습니다. 원본 두 파일은 유지됩니다.

```bash
(
  set -eu
  set -o pipefail
  umask 077
  export GPG_TTY="$(tty)"
  backup="$HOME/shiganshina-dev-signing-$(date +%Y%m%d-%H%M%S).tar.gpg"
  test ! -e "$backup"
  tar -C "$HOME/.shiganshina-survivors/signing" -cf - -- \
    dev-keystore.p12 dev-keystore.pass | \
    gpg --no-symkey-cache --symmetric --cipher-algo AES256 --output "$backup"
  gpg --no-symkey-cache --decrypt "$backup" | tar -tf -
  printf '\n검증한 암호화 백업: %s\n' "$backup"
  termux-open --send --chooser --content-type application/octet-stream "$backup"
)
```

검증 목록에는 `dev-keystore.p12`, `dev-keystore.pass` 두 이름이 나와야 합니다. 오류가 나오면 공유 단계로 넘어가지 않습니다. Android 공유창에서는 **.tar.gpg 파일만** 본인이 선택한 비공개 보관처에 저장하세요. 별도 안전한 위치에도 한 부를 두고, 새 백업 암호는 파일과 다른 곳의 암호 관리자에 보관하세요. 앱 소스 저장소와 평문 키/암호를 섞지 마세요.

공유창이 열리지 않으면 출력된 암호화 파일을 보존한 채 멈추면 됩니다. 원본 키 폴더를 통째로 공유하거나 평문으로 내보내지 마세요. 새 보관처를 연결하거나 공유 권한을 바꿀 필요는 없습니다.

## 3. 다른 컴퓨터에서 복원

신뢰하는 컴퓨터에서 위 .tar.gpg 파일을 직접 내려받고 GnuPG로 복호화합니다. 새 비공개 폴더를 사용하세요. 예시는 `BACKUP_FILE`에 본인이 내려받은 실제 경로를 넣습니다.

```bash
(
  set -eu
  umask 077
  BACKUP_FILE="/실제/다운로드/백업파일.tar.gpg"
  restore="$HOME/shiganshina-signing-restored-$(date +%Y%m%d-%H%M%S)"
  mkdir "$restore"
  gpg --output "$restore/restore.tar" --decrypt "$BACKUP_FILE"
  tar -xf "$restore/restore.tar" -C "$restore" -- dev-keystore.p12 dev-keystore.pass
  chmod 600 "$restore/dev-keystore.p12" "$restore/dev-keystore.pass"
  printf 'KEYSTORE_PATH=%s\nKEYSTORE_PASSWORD_FILE=%s\n' \
    "$restore/dev-keystore.p12" "$restore/dev-keystore.pass"
)
```

출력된 **파일 경로**를 [로컬 빌드 안내](android-local.md#4-sign-locally-with-your-existing-dev-key)에 넣습니다. 서명 도구가 기존 공개 인증서 지문을 검사하므로 다른 키를 실수로 사용할 수 없습니다. 복원과 빌드를 확인한 뒤 임시 평문 `restore.tar`는 본인이 정리하세요. 원래 키와 암호화 백업은 유지합니다.

키를 잃으면 기존 앱과 같은 서명으로 업데이트할 수 없습니다. 새 키로 만든 앱을 쓰기 위해 기존 앱을 제거하면 저장 진행을 잃을 수 있습니다.

## 확인 근거와 한계

- 실제 DEV1 APK에 사용된 인증서 SHA-256: `4256200e2c63dbfec3d0e9370ecca4b611ee11c65e1e2edad88003ea858c174c`.
- 명령 옵션은 [공식 GnuPG 설명](https://www.gnupg.org/documentation/manuals/gnupg24/gpg.1.html), [공식 Termux 공유 명령](https://github.com/termux/termux-tools/blob/master/scripts/termux-open.in), [공식 GnuPG 패키지](https://github.com/termux/termux-packages/tree/master/packages/gnupg)에 대조했습니다.
- 문서의 shell 문법은 검증했습니다. 실제 키를 읽거나 백업·복원·외부 전송을 대신 수행하지 않았으므로, 백업 완료 여부는 사용자가 실행한 뒤 확인해야 합니다.
