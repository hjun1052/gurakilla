<img src="Design/logo.png" width="160" alt="GuraKilla 로고">

# GuraKilla (구라킬라)

**한국어** | [English](README.en.md)

내 Mac에 깔린 은행·공공기관 보안 프로그램(TouchEn nxKey, Veraport, Delfino, INISAFE CrossWeb EX, CrossEX,
AhnLab Safe Transaction, IPinside, MagicLine4NX, nProtect, AnySign4PC와 그 잔여물)을 찾아내고, 들여다보고,
종료하고, 자동 실행을 끄고, 제거하는 macOS 네이티브 유틸리티입니다.

Swift + SwiftUI, macOS 26, Apple 실리콘과 Intel 지원. 외부 의존성 없음.

## 다운로드

[Releases](https://github.com/hjun1052/gurakilla/releases/latest)에서 최신 `.dmg`를 받으세요. macOS 26 이상이
필요합니다(유니버설). 앱은 ad-hoc 서명만 되어 있고 공증(notarization)을 받지 않았습니다. 처음 열 때는 오른쪽 클릭 → 열기,
또는 시스템 설정 → 개인정보 보호 및 보안 → 그래도 열기를 사용하세요.

## 빌드

```sh
xcodegen generate            # project.yml → GuraKilla.xcodeproj
xcodebuild -project GuraKilla.xcodeproj -scheme GuraKilla -configuration Release -derivedDataPath build build
open build/Build/Products/Release/GuraKilla.app
```

테스트(단위 테스트 + 지원 제품마다 회귀 테스트 1개):

```sh
xcodebuild -project GuraKilla.xcodeproj -scheme GuraKilla -destination 'platform=macOS,arch=arm64' -derivedDataPath build test
```

명령줄에서 읽기 전용 검사(JSON):

```sh
build/Build/Products/Release/GuraKilla.app/Contents/MacOS/GuraKilla --scan-json
```

명령줄에서 제거하기. 제거 시트와 같은 계획을 출력하며, `--yes`를 붙이지 않으면 실제로는 아무것도 하지 않습니다(dry run).
관리자 권한이 필요한 단계는 macOS 암호 입력 창을 쓰거나, `--sudo`를 주면 `sudo -n`을 씁니다(sudo 인증이 이미 되어 있지 않으면 묻지 않고 실패):

```sh
build/Build/Products/Release/GuraKilla.app/Contents/MacOS/GuraKilla --remove wizvera-veraport          # 계획만 보기
build/Build/Products/Release/GuraKilla.app/Contents/MacOS/GuraKilla --remove wizvera-veraport --yes    # 실행
```

## 하는 일

- **감지**: 정확하고 검증된 식별자로만 제품을 찾습니다. 코드 서명 Team ID, 제조사 설치 폴더, launchd 레이블,
  패키지 영수증, 인증서 주체, 시스템 확장 ID. 이름으로 추측하지 않습니다.
- **표시**: 실행 중인 프로세스(CPU, 메모리, PID, 소유자, 실제 실행 파일 경로), launchd 작업, 자동 실행 상태,
  신뢰된 루트 인증서, 커널/시스템 확장, 파일과 영수증.
- **종료**: 먼저 정상 종료를 시도하고, 엉뚱한 프로세스를 건드리지 않도록 PID를 다시 확인합니다. root 소유 프로세스는
  검토할 수 있는 관리자 확인 창을 거칩니다. KeepAlive 작업을 launchd가 다시 띄우는 경우 그 사실을 알려 줍니다.
- **자동 실행 관리**: `launchctl disable/enable`(launchd 자체의 override 목록, 제조사 파일은 건드리지 않음). 종료와는 별개입니다.
- **제거**: 제조사 제거 프로그램을 우선 권하고, 없으면 검토 가능한 제거 계획을 만듭니다. 파일은 휴지통으로 옮기고,
  제조사 인증서는 지우기 전에 백업하며, 다른 프로그램과 공유하는 항목은 체크 해제되어 있고, 커널/시스템 확장은 절대 건드리지 않습니다.
- **설정 복원**: 자동 실행 변경, 옮긴 파일, 삭제한 인증서를 되돌립니다.
- **감사 로그**: `~/Library/Logs/GuraKilla/audit.log`.

관리자 작업은 항상 실행할 명령을 먼저 보여 준 뒤 macOS 표준 암호 입력 창을 띄웁니다. 인증서의 시스템 전체 신뢰를 해제하는 단계는
macOS가 직접 보호하므로 한 번 더 물어볼 수 있습니다. 인증서는 그 단계 전에 이미 삭제되므로, 거기서 취소해도 신뢰된 루트 인증서가 남지 않습니다.
GuraKilla는 암호를 볼 수 없으며 SIP, Endpoint Security, MDM, Apple 구성 요소를 절대 건드리지 않습니다.

## 언어

한국어와 영어. 앱은 macOS 언어 순서를 따릅니다. GuraKilla만 한국어로 쓰려면 시스템 설정 › 일반 › 언어 및 지역 › 응용 프로그램에서
지정하세요. UI 문자열은 `GuraKilla/Resources/Localizable.xcstrings`, 제조사·분류·설명은 `Products.xcstrings`에 있습니다.
제품 이름은 제조사 표기(은행 사이트에 나오는 이름) 그대로 둡니다. `--scan-json`과 `--remove` 계획 출력은 영어이고,
감사 로그의 동작 코드는 영어, 세부 내용은 앱을 실행한 언어로 기록됩니다. 한국어 번역이 빠진 문자열이 있으면 `LocalizationTests`가 실패합니다.

## 레지스트리 확장

다시 빌드하지 않고 제품을 추가할 수 있습니다. `~/Library/Application Support/GuraKilla/registry.json`에
`GuraKilla/Engine/Registry.swift`의 `ProductDefinition`과 같은 필드를 가진 JSON 배열을 두세요(기존 `id`와 같은 항목은 그것을 대체합니다).

## 조사 자료

`research/`에는 레지스트리의 근거가 들어 있습니다. 시스템 기준선, 공식 설치 프로그램 분석, 제거 프로그램 동작, 정리 검증,
호환성 매트릭스, 그리고 일회용 macOS VM에서 6개 제품을 설치 → 제거해 본 테스트(`research/vm-test/`). `research/README.md`부터 보세요(영어).
