# 패치 설명

`patches/*.patch`는 Wine(wine-staging), `patches/dxvk/*.patch`는 DXVK에 얹는다. 이름순으로 적용한다.
마지막 절은 패치가 아니라 prefix에 넣는 레지스트리·폰트 설명이다.

각 패치마다 **문제**, **원인**, **수정**, **확인·끄기** 순서로 적는다. 로그는 `WINEDEBUG=<채널> wm-run app.exe`.

| 패치 | 모듈 | 한 줄 |
|---|---|---|
| [0001](#0001-uac-normal-user) | ntdll, shell32, server | 일반 실행을 앱에 "관리자 아님"으로 보고 |
| [0002](#0002-menubuilder-launcher) | winemenubuilder | 바로가기 `Exec=`에 `wine` 대신 지정한 실행기 |
| [0003](#0003-winewayland-noactivate-popup) | winewayland.drv | 메뉴·툴팁 팝업이 포커스를 뺏지 않게 |
| [0004](#0004-winewayland-systray-sni) | winewayland.drv | 트레이 아이콘을 StatusNotifierItem(D-Bus)으로 |
| [0005](#0005-wintrust-builtin-signature) | wintrust | 내장 DLL에 가짜 "Microsoft Windows" 서명 |
| [0006](#0006-gdi32-setbkmode-invalid) | gdi32 | `SetBkMode`에 이상한 값을 주면 투명으로 |
| [dxvk 0001](#dxvk-0001-d3d11-auto-generate-mips) | DXVK d3d11 | 큰 이미지를 작게 그릴 때 숨은 mipmap |

---

## 0001 uac-normal-user

**문제**: 관리자 여부를 검사하는 앱이 일반 실행인데도 "관리자 권한으로 실행됨" 경고를 띄운다.

**원인**: Wine은 일반 실행(Limited 토큰) 프로세스에도 Administrators 그룹을 enabled로, 무결성 수준을 High로 보고한다.
Windows의 UAC는 일반 실행 토큰에서 Administrators를 deny-only로 바꾸고 무결성을 Medium으로 둔다.

**수정**
- `server/token.c`: Limited 토큰의 `TokenGroups`에서 Administrators를 `SE_GROUP_USE_FOR_DENY_ONLY`로 **보고만** 한다.
  접근 검사에 쓰는 실제 그룹은 그대로다. Wine의 기본 레지스트리 ACL이 Administrators에게만 쓰기를 주기 때문에 여기까지 바꾸면 앱이 레지스트리에 못 쓴다.
- `dlls/ntdll/unix/security.c`: `TokenIntegrityLevel`을 Limited면 Medium, 그 외 High로 (원래는 항상 High).
- `dlls/shell32/shellord.c`: `IsUserAnAdmin`이 deny-only·비활성 그룹을 세지 않게 (Windows와 같게).

관리자로 띄운 것(`runas`, `requireAdministrator` 매니페스트)은 전처럼 Full 토큰이라 관리자다.

---

## 0002 menubuilder-launcher

**문제**: winemenubuilder가 만드는 `.desktop`의 `Exec=`가 `wine "..."`로 고정돼 있다. 우리 Wine은 PATH에 없고, 실행기를 거쳐야 환경이 맞는다.

**수정**: 환경 변수 `WINEMENUBUILDER_LAUNCHER`가 있으면 `Exec=env "WINEPREFIX=..." "<그 값>" "..."`로 쓴다.
앱 바로가기와 파일 연결(`wine start /ProgIDOpen`) 둘 다.

**지금 상태**: wiku는 winemenubuilder를 꺼 두고 메뉴를 직접 만들며, 그때 `Exec=`를 자기가 고쳐 쓴다.
그래서 이 패치는 현재 쓰이지 않는다. winemenubuilder를 켜고 쓰는 변형을 위해 남겨 뒀고, 필요 없으면 지워도 된다.

---

## 0003 winewayland-noactivate-popup

**문제**: 카카오톡에서 우클릭 메뉴가 뜨자마자 사라진다.

**원인**: Wayland에서 새 `xdg_toplevel`은 무조건 키보드 포커스를 가져간다. Qt의 테두리 없는 메뉴는 `WS_EX_NOACTIVATE`인데도 `WS_CAPTION`을 달고 있어서
winewayland가 "관리되는 창"(xdg_toplevel)으로 만들었고, 메뉴가 활성 창이 되자 Qt가 포커스를 잃었다고 보고 메뉴를 닫았다.

**수정** (`dlls/winewayland.drv/window.c`, `is_window_managed`): `WS_POPUP` + `WS_EX_NOACTIVATE`인 창은 관리하지 않는다.
그러면 메인 창의 subsurface로 뜨고 포커스를 건드리지 않는다. 메뉴, 툴팁, 콤보 박스 목록이 여기 해당한다.

---

## 0004 winewayland-systray-sni

**문제**: Wayland에는 XEmbed 트레이가 없다. 카카오톡·LINE처럼 트레이로 숨는 앱의 아이콘이 어디에도 안 보이고,
explorer의 대체 트레이 창은 Wayland에서 진짜 창이 되어 포커스를 뺏는다.

**수정**: explorer가 `Shell_NotifyIcon`으로 받는 아이콘을 `org.kde.StatusNotifierItem`(SNI) D-Bus 객체로 내보낸다.
waybar, KDE Plasma, AGS/quickshell 등 SNI를 보는 바에 뜬다. 새 파일 `dlls/winewayland.drv/wayland_systray.c`.

- **구조**: explorer 프로세스에서만 systray 스레드 하나가 돈다. 아이콘마다 세션 버스 연결과 well-known 이름을 따로 가져서, 아이콘 제거 = 그 연결 닫기다
  (호스트는 이름 주인이 사라진 항목을 지운다). `NotifyIcon` 호출은 아이콘 데이터만 바꾸고 스레드를 깨운다.
  아이콘은 SNI가 원하는 non-premultiplied big-endian ARGB32로 바꿔 보낸다.
- **클릭**: Windows 트레이처럼 앱에 전달한다. `Activate` = 왼쪽 클릭, 더블클릭 시간 안의 두 번째 `Activate` = 더블클릭(카카오톡은 이때 창을 띄운다),
  `SecondaryActivate` = 우클릭, 가운데 버튼도. waybar는 두 번째 누름에 `Activate`를 두 번 보내서 50ms 안의 중복은 버린다.
- **트레이 메뉴**: Wayland에서는 클라이언트가 창 위치를 정할 수 없고, 메뉴 밖 클릭도 전달되지 않는다. 그래서
  - 클릭 직후(2초 안) 그 앱이 띄우는 첫 팝업을 layer-shell(overlay) 표면으로 만들어, 클릭한 곳·바 바로 아래에 띄운다 (`wayland_surface_make_layer`).
  - 그 아래에 투명한 막(top 레이어, 바는 안 덮음)을 깐다. 막을 클릭하면 메뉴 밖 좌표의 클릭으로 앱에 보내서 메뉴가 닫힌다.
  - 클릭 위치는 explorer가 데스크톱 창 속성 `__wine_tray_*`에 적고, 아이콘 주인 프로세스가 읽는다 (`wayland_systray_take_menu_pos`).
- **바가 나중에 켜져도** `StatusNotifierWatcher`를 지켜보다 다시 등록한다. 세션 버스가 없으면 explorer의 기본 트레이로 돌아간다 (`WAYLAND_NotifyIcon`이 -1).
- 빌드에 D-Bus가 필요하다 (`Makefile.in`에 `DBUS_CFLAGS`/`DBUS_LIBS`). 프로토콜 `wlr-layer-shell-unstable-v1.xml` 추가.

**확인·끄기**: `WINEDEBUG=+systray`. 끄기 `WINE_WAYLAND_SNI=0`.
explorer의 대체 트레이 창은 prefix 레지스트리 `HKCU\Software\Wine\Explorer\ShowSystray=0`으로 계속 꺼 둔다 ([아래](#prefix-레지스트리폰트) 참고).

---

## 0005 wintrust-builtin-signature

**문제**: LINE 설치기가 `Security verification failed ... gdiplus.dll NO_SIGNATURE`로 멈춘다.
시스템 DLL이 "Microsoft Windows" 서명을 가졌는지 검사하는 앱이 있는데, Wine 내장 DLL에는 서명이 없다.

**수정**: **Wine 설치 폴더의 내장 DLL과 바이트 단위로 같은 파일**에만 가짜 서명을 돌려주고 검증을 통과시킨다.

- `WINTRUST_IsWineBuiltinFile` (`crypt.c`): 파일이 다음 중 하나면 참.
  1. `Wine builtin DLL` 표식이 있고, `WINEDLLDIR<n>/<arch>-windows/<이름>` 또는 `WINEDLLDIR<n>/<이름>`과 내용이 같다.
  2. 표식이 없는 native DLL이지만, `WINEMIKU_SIGNED_DLL_DIRS`(`:`로 구분한 유닉스 디렉터리)의 같은 이름 파일과 내용이 같다.
     wiku가 이 변수를 DXVK DLL 폴더로 넘겨서, prefix에 복사된 `dxgi.dll`·`d3d11.dll` 등도 통과한다.
- `ImageGetCertificateData`: 서명이 없는 그런 파일에 `builtin_sig.h`의 PKCS#7 SignedData를 돌려준다.
- `softpub.c`: 그 파일에 한해 `TRUST_E_BAD_DIGEST`(가짜 서명은 파일 해시를 담지 않는다)와 인증서 체인 오류를 성공으로 바꾼다. 그래서 `WinVerifyTrust`가 성공한다.

**인증서**: 자체 서명이고 `OU=Wine builtin (not a real Microsoft certificate)`가 붙어 있다. 신뢰된 루트에 연결되지 않고,
개인키는 더미 파일에 서명한 직후 버렸다. 앱이 보는 이름만 있을 뿐 다른 것에 서명할 수 없다.
내장 DLL 표식만 흉내 낸 파일이나 수정된 파일은 내용이 다르므로 전과 같이 실패한다.

**확인**: `WINEDEBUG=+wintrust`.

---

## 0006 gdi32-setbkmode-invalid

**문제**: LINE 설치기의 "설치" 버튼 글자가 흰 사각형으로 나온다.

**원인**: 설치기가 `SetBkMode`에 모드가 아니라 색상값을 넘긴다. Windows는 OPAQUE/TRANSPARENT 외의 값을 거부하지 않고 투명으로 그리는데,
Wine은 `ERROR_INVALID_PARAMETER`로 거부해서 기본값 OPAQUE가 남았다.

**수정** (`dlls/gdi32/dc.c`): 그런 값은 `WARN`을 남기고 TRANSPARENT로 저장한다.

**확인**: `WINEDEBUG=warn+gdi`.

---

## dxvk 0001 d3d11-auto-generate-mips

**문제**: 카카오톡 광고 이미지(1200×600을 약 120×60으로)가 자글자글하다.

**원인**: Qt Quick이 큰 이미지를 mipmap 없이 bilinear 샘플러로 작게 줄여 그린다. 윈도우에서는 이 광고를 WebView2가 그리는데,
Wine에는 DirectComposition이 없어서 WebView2가 못 그리고 Qt 이미지로 떨어진다.

**수정**: 옵션 `d3d11.autoGenerateMips`.
- 크고(single-level, shader-resource 전용, RGBA8) 샘플만 하는 텍스처에 **숨은 mip 체인**을 붙이고, 텍스처가 쓰일 때마다 다시 만든다 (`AutoGenerateMips`: `CopyImage`, `UpdateImage` 뒤에 호출).
- D3D11 쪽 설명은 그대로 1 레벨이라 앱의 subresource 번호 계산은 안 바뀐다. 셰이더 뷰만 숨은 체인 전체를 본다.
- `MinLOD = MaxLOD = 0`인 샘플러(Qt RHI가 "mipmap 없음"이라고 말하는 방식)는 숨은 체인이 있는 텍스처에서만 LOD 범위를 푼다.
- `config.cpp`의 앱 프로필로 `KakaoTalkUI.exe`에서만 자동으로 켜진다.

**끄기·켜기**: `DXVK_CONFIG="d3d11.autoGenerateMips = False" wm-run ...` (다른 앱에서 켜려면 `= True`).

nixpkgs의 DXVK 버전이 바뀌면 이 패치를 새 버전에 맞춰 다시 만들어야 할 수 있다.

---

## prefix 레지스트리·폰트

패치가 아니라 prefix에 넣는 것들이다. Nix가 빌드하고 wiku가 prefix에 적용한다 (`flake.nix`의 `prefix.reg`, `prefix.fonts`).

### 폰트 ([scripts/gen-fonts.py](scripts/gen-fonts.py))

앱은 폰트를 **이름**으로 찾는다. Wine에 그 이름이 없으면 엉뚱한 폰트로 빠진다.

- **한글**: 맞는 이름이 없으면 시스템의 **가변** Noto CJK로 빠지는데, Wine은 가변 폰트를 제대로 못 다뤄 글자 간격이 벌어진다.
  → 고정 굵기(400/700)로 뽑은 Noto Sans CJK KR을 `Malgun Gothic` 이름으로 등록한다.
- **영어·숫자**: Wine 내장 Tahoma·Arial은 Wine이 만든 대체품이라 작은 글씨가 깨진다 (카카오톡이 영어·숫자를 이 둘로 그린다).
  → 내장본을 runtime에서 **뺀다** (`flake.nix`의 `runtimeHook`). Wine은 같은 이름의 폰트가 있으면 Replacements를 무시하기 때문이다.
  → `Replacements`로 Tahoma → DejaVu Sans, Arial → Arimo(Arial과 글자 폭이 같다). Noto Sans는 `Segoe UI` 이름으로.
- Wine의 DirectWrite는 레지스트리 `FontSubstitutes`를 보지 않고(GDI·Qt는 본다), `HKLM\...\Fonts`에 등록된 파일만 본다.
  그래서 대체가 아니라 **이름 자체를 바꿔 등록**한다.

### 레지스트리 ([scripts/gen-prefix-reg.py](scripts/gen-prefix-reg.py))

- 위 폰트 등록(`HKLM\...\Fonts`), `Replacements`, `FontSubstitutes`(굴림·돋움·바탕·궁서 → Malgun Gothic, `*체` → Noto Sans Mono CJK KR,
  `Helvetica Neue` → Malgun Gothic: LINE 설치기가 요청하고 `GetGlyphIndices`로 그려서 FontLink가 안 먹는다).
- `FontLink`: Tahoma, Segoe UI, Arial 등 한글이 없는 서양 UI 폰트에 한글 폴백 (GDI용).
- `HKCU\Software\Wine\Explorer\ShowSystray=0`: explorer의 대체 트레이 창 끄기 (0004가 바로 보낸다).

Wayland 드라이버(`Graphics=wayland`), DXVK DllOverrides, winemenubuilder 끄기는 wiku 토글이 이 파일 **다음에** 적용한다.
이 스크립트를 고치면 다음 실행 때 자동으로 다시 적용된다 (개발 셸에서는 `nix develop`을 다시 할 것).
