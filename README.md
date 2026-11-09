# winemiku

nixpkgs Wine(`wineWow64Packages.stagingFull`, wine-staging)에 `patches/*.patch`를 얹은 커스텀 Wine.

## 사용 (Nix)

```bash
nix run github:uskdk1/winemiku -- 설치파일.exe            # 실행 (아래 설정이 모두 적용됨)
nix run github:uskdk1/winemiku -- --reset                 # prefix 초기화
nix run github:uskdk1/winemiku -- --kill                  # 남은 Wine 프로세스 종료
nix profile install github:uskdk1/winemiku               # 설치하면 winemiku 명령으로
```

- prefix: `~/.local/share/winemiku/prefix` (`WINEPREFIX`로 바꿀 수 있음), 템플릿: `~/.cache/winemiku/prefix-template`
- Wayland 전용, 한국어 로캘·폰트, DXVK, 트레이 창 끔 (아래 "실행 환경" 참고)
- `.#winemiku`(기본)는 패치된 Wine과 패치된 DXVK를 쓴다.
  `.#winemiku-unpatched`는 nixpkgs 캐시의 Wine을 그대로 써서 바로 받지만 `patches/*.patch`(Wine 패치)가 빠진다.

### 바이너리 캐시 (Cachix)

패치된 Wine·DXVK는 `https://winemiku.cachix.org`에 올라가 있다. 캐시를 쓰지 못하면 직접 빌드한다
(Wine 약 1시간 + DXVK 약 10분).

flake의 `nixConfig`에 캐시가 적혀 있어서 처음 `nix run` 할 때 쓸지 물어보지만,
**Nix의 신뢰된 사용자(`trusted-users`)일 때만 적용된다.** NixOS 기본값(`trusted-users = root`)이면
아래 경고와 함께 캐시를 무시하고 직접 빌드한다.

```
warning: ignoring untrusted substituter 'https://winemiku.cachix.org', you are not a trusted user.
```

NixOS에서는 시스템 설정에 캐시를 넣고 `sudo nixos-rebuild switch` 한다.

```nix
nix.settings = {
  substituters = [ "https://winemiku.cachix.org" ];
  trusted-public-keys = [ "winemiku.cachix.org-1:BbEx+MwxsPdW3eekGCtxLQZlyemmnOXwvpgCijKVfxk=" ];
};
```

NixOS가 아니면 `/etc/nix/nix.conf`에 같은 내용을 넣거나(`extra-substituters`, `extra-trusted-public-keys`)
`cachix use winemiku`를 root로 실행한다.

캐시 올리기(관리자): `nix build .#winemiku --print-out-paths | cachix push winemiku`
(Wine·DXVK·실행기가 의존성째로 올라가고, 이미 있거나 cache.nixos.org에 있는 것은 건너뛴다.)

| 패키지 | 내용 |
|---|---|
| `winemiku` (기본) | 실행기 + 패치된 Wine + 데이터 |
| `winemiku-unpatched` | 실행기 + 캐시의 Wine(패치 없음) + 데이터 |
| `wine-miku` | 패치된 Wine만 |
| `winemiku-share` | prefix 데이터 (레지스트리 설정, 폰트, 패치된 DXVK 링크) |

## 개발

시스템에 Wine을 설치하지 않습니다. 모든 것이 이 폴더와 `/nix/store` 안에만 있습니다.

```bash
nix develop          # 빌드 의존성 + 빌드된 vanilla wine + 헬퍼 함수
wm-prepare           # src/ 에 같은 버전 소스 풀기, 패치 적용, configure (최초 1회)
# src/wine-*/dlls/<dll>/ 수정
wm-build <dll>       # 그 DLL만 빌드해서 override/ 에 복사 (예: d3d11, winex11.drv, server=wineserver)
wm-run app.exe       # 실행 (bin/winemiku 와 같음, WINEPREFIX=./prefix)
wm-clean [app.exe]   # prefix 초기화 (+ 바로 실행)
wm-kill [--all]      # Wine 프로세스 종료
wm-patch <이름>      # 수정사항을 patches/NNNN-<이름>.patch 로 저장
wm-reset             # override/ runtime/ 삭제 (vanilla 로 복귀)
wm-prefix            # 템플릿 버리고 prefix 처음부터 재생성
```

### 실행: wm-run = bin/winemiku

`wm-run`(개발 셸)과 `bin/winemiku`(어디서나, nix develop 불필요)는 같은 실행기다.
같은 prefix, 같은 Wine(runtime/ + override/), 같은 설정을 쓴다. 차이는 `wm-run`이 runtime/을 먼저 최신화한다는 것뿐.

```bash
bin/winemiku "C:\\users\\miku\\Desktop\\카카오톡.lnk"   # 설치한 앱 (바로가기 .lnk 또는 .exe)
bin/winemiku --reset                                     # prefix 초기화 (≈1초)
bin/winemiku --reset KakaoTalk_Setup.exe                 # 초기화 후 바로 설치
bin/winemiku --kill                                      # 이 prefix의 Wine 프로세스 전부 종료 (트레이에 숨은 앱 포함)
bin/winemiku --kill-all                                  # 이 저장소 Wine으로 뜬 모든 prefix
```

앱 메뉴 바로가기(`~/.local/share/applications/wine/…`)도 `bin/winemiku`를 부른다
(patches/0002: `WINEMENUBUILDER_LAUNCHER`). `runtime/`·폰트는 `.gcroots/`로 GC에서 보호된다.

### prefix 초기화

- `rm -rf prefix/drive_c` 해도 된다. 다음 실행 때 prefix 전체(레지스트리 포함)를 새로 만든다.
- 새 prefix는 `.cache/prefix-template`(깨끗한 prefix + 한글/Wayland 설정)에서 btrfs reflink로 복사해서 거의 즉시 생긴다.
  템플릿은 Wine 버전·설정이 바뀌면 자동으로 다시 만든다(그때만 ~20초).
- 초기화할 때 이 prefix를 가리키는 앱 메뉴 항목(`.desktop`, `.menu`)도 지운다. 다른 prefix 것은 건드리지 않는다.
- 안전장치: winemiku가 만든 prefix(`.wm-prefix` 표시)만 지운다.
- Wine 기본 파일 연결(`wine-extension-*.desktop`)은 만들지 않는다. 이 파일들은 이름이 prefix끼리 공유돼서 서로 덮어쓴다.

### 실행 환경 (wm-run)

- **DXVK**(D3D8/9/10/11 → Vulkan, nixpkgs `dxvk` + `patches/dxvk/*.patch`)를 prefix에 자동 설치(system32/syswow64 + DllOverrides native).
  Wayland에서 Wine 기본 wined3d(D3D → OpenGL)는 화면이 갱신되지 않는 앱이 있다 (카카오톡: 입력은 받는데 화면이 멈춤).
  - `patches/dxvk/0001`: 큰 이미지를 mipmap 없이 작게 줄여 그리는 앱을 위해 숨은 mipmap을 붙인다(`d3d11.autoGenerateMips`).
    카카오톡 광고 이미지(1200x600 → 약 120x60)가 자글자글해지는 문제. 윈도우는 이 광고를 WebView2로 그리는데,
    Wine에는 DirectComposition이 없어서 WebView2가 화면을 못 그린다. `KakaoTalkUI.exe`에서만 자동으로 켜진다.
    끄기: `DXVK_CONFIG="d3d11.autoGenerateMips = False" bin/winemiku ...` (다른 앱에서 켜려면 `= True`)
  - DXVK 소스 수정: `src/dxvk-<버전>/`에 소스를 풀고 git 기준점을 만든 뒤 고치고, `git diff > patches/dxvk/NNNN-<이름>.patch`.
    nixpkgs의 DXVK 버전이 바뀌면 패치를 새 버전에 맞춰 다시 만들어야 할 수 있다.
- **트레이 창 끔**(`HKCU\Software\Wine\Explorer\ShowSystray=0`): Wayland엔 트레이가 없어 explorer가 띄우는 대체 창이 포커스를 뺏는다.
  트레이로 숨은 앱(카카오톡 등)은 다시 실행하면 창이 뜬다. 완전히 끄려면 `bin/winemiku --kill`.
- **Wayland 전용**: `DISPLAY`를 지우고 레지스트리 `HKCU\Software\Wine\Drivers\Graphics=wayland`로 고정. XWayland로 빠지지 않음.
- **한국어**: `LANG/LC_ALL=ko_KR.UTF-8` (코드페이지 949, 비유니코드 앱 대응). 바꾸려면 `WM_LANG=ja_JP.UTF-8 wm-run ...`
- **한글 폰트**: Noto Sans CJK KR(static)을 prefix `Fonts/`에 링크하고, 굴림·돋움·바탕·맑은 고딕 등을 대체(FontSubstitutes),
  Tahoma·MS Shell Dlg·Segoe UI 등 서양 UI 폰트에 한글 폴백(FontLink)을 건다. 설정 내용은 [scripts/gen-prefix-reg.py](scripts/gen-prefix-reg.py).
  이 파일을 고치면 다음 `wm-run` 때 자동 재적용.
- 터미널로 파이프한 출력(`wm-run reg query ... | less` 등)은 CP949라 깨져 보인다. `| iconv -f CP949`를 붙일 것.

`wm-run`은 `runtime/`(vanilla wine의 심볼릭 링크 복제본)에 `override/`의 DLL을 끼워 넣어 실행합니다.
Wine은 설치 디렉터리를 `WINEDLLPATH`보다 먼저 찾기 때문에 `WINEDLLPATH`로는 빌트인 DLL을 덮어쓸 수 없습니다.

- 새로 추가한 소스 파일은 `wm-patch` 전에 `git -C src/wine-* add <파일>` 필요.
- 패치를 추가/변경한 뒤 `nix build`로 전체 빌드를 확인. `./result/bin/wine`
- 소스를 처음부터 다시: `rm -rf src && wm-prepare`
- 로딩 확인: `WINEDEBUG=+loaddll wm-run app.exe`

## 배포

- **Nix 사용자**: 이 저장소 + Cachix 바이너리 캐시 (위 "바이너리 캐시" 참고)
- **그 외**: 같은 Wine 버전이면 `override/*-windows/*.dll` 만 전달 가능, 또는 `patches/` 배포
- **라이선스**: Wine은 LGPL-2.1-or-later. 바이너리 배포 시 `patches/`(수정 소스)를 함께 공개할 것.
