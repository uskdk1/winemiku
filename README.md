# winemiku

nixpkgs의 wine-staging(`wineWow64Packages.stagingFull`)에 패치를 얹은 Wine. 카카오톡·LINE 같은 한국 앱을 Wayland에서 쓰기 위한 것이다.

- Wayland 전용, 한국어 로캘·폰트, DXVK, 트레이 아이콘을 바(waybar 등)에 표시
- 패치 내용은 [PATCHES.md](PATCHES.md)

**Nix 전용이고, 단독으로 배포하지 않는다.** [wiku](https://github.com/uskdk1/wiku)(여러 Wine 변형과 prefix 관리)의 변형 `miku`로 쓴다.
이 저장소는 패치와 prefix 설정, 그리고 그것을 개발하는 환경이다.

## 사용

home-manager에 변형으로 등록하고 `wiku` 명령으로 실행한다. 자세한 것은 wiku README.

```nix
# flake inputs: wiku.url = "github:uskdk1/wiku";  winemiku.url = "github:uskdk1/winemiku";
imports = [ inputs.wiku.homeManagerModules.default ];

programs.wiku = {
  enable = true;
  wines.miku = inputs.winemiku.packages.x86_64-linux.default;
  prefixes.kakao.wine = "miku";
  prefixes.line.wine = "miku";
};
```

```bash
wiku kakao KakaoTalk_Setup.exe    # 설치 (끝나면 앱 메뉴에 "카카오톡 (kakao)")
wiku kakao --reset                # prefix 초기화
wiku kakao --kill                 # 이 prefix 의 Wine 프로세스 종료
```

- prefix는 `~/.local/share/wiku/<이름>`.
- Wayland·DXVK·로캘은 wiku 토글이라 prefix마다 바꿀 수 있다 (기본값: `flake.nix`의 `defaults`).
- `winemiku-unpatched`는 nixpkgs 캐시의 Wine을 그대로 쓴다. 빌드 없이 바로 받지만 Wine 패치가 빠진다 (DXVK·폰트·레지스트리는 같다).

### 바이너리 캐시

패치된 Wine 모듈과 DXVK는 `https://winemiku.cachix.org`에 있다. 캐시를 쓰지 못하면 직접 빌드한다 (모듈 약 4분 + DXVK 약 10분).
Wine 본체는 cache.nixos.org에서 받는다.

home-manager에서 input으로 받을 때는 이 flake의 `nixConfig`가 쓰이지 않으니 시스템 설정에 넣고 `sudo nixos-rebuild switch`:

```nix
nix.settings = {
  substituters = [ "https://winemiku.cachix.org" ];
  trusted-public-keys = [ "winemiku.cachix.org-1:BbEx+MwxsPdW3eekGCtxLQZlyemmnOXwvpgCijKVfxk=" ];
};
```

NixOS가 아니면 `/etc/nix/nix.conf`에 같은 내용을(`extra-substituters`, `extra-trusted-public-keys`) 넣거나 root로 `cachix use winemiku`.
넣지 않으면 `warning: ignoring untrusted substituter` 경고와 함께 직접 빌드한다.

캐시는 CI가 올린다 (`.github/workflows/build.yml`, wiku의 재사용 워크플로). 손으로: `nix build .#winemiku --print-out-paths | cachix push winemiku`.

### 패키지

| 패키지 | 내용 |
|---|---|
| `winemiku` (기본) | 변형 `miku`: 실행기(wiku) + 캐시의 Wine + 패치된 모듈 + 패치된 DXVK + 폰트·레지스트리 |
| `winemiku-unpatched` | 변형 `miku-unpatched`: 캐시의 Wine(패치 없음) + 같은 DXVK·폰트·레지스트리 |
| `wine-miku-modules` | 패치가 건드리는 모듈만 빌드한 결과 (dll·so·wineserver) |
| `wine-miku` | 패치된 Wine 전체 (약 1시간, 확인용) |
| `winemiku-reg`, `winemiku-fonts`, `winemiku-cjk-fonts` | prefix 레지스트리와 폰트 ([PATCHES.md](PATCHES.md#prefix-레지스트리폰트)) |

## 개발

시스템에 Wine을 설치하지 않는다. 모든 것이 이 폴더와 `/nix/store` 안에만 있다.

```bash
nix develop          # 빌드 의존성 + 패치된 Wine(캐시) + 아래 명령
wm-prepare           # src/ 에 같은 버전 소스 풀기, 패치 적용, configure (최초 1회)
# src/wine-*/dlls/<dll>/ 수정
wm-build <dll>       # 그 모듈만 빌드해서 override/ 에 복사 (예: d3d11, winewayland.drv, server, programs/winemenubuilder)
wm-run app.exe       # 실행 (prefix 는 ./prefix)
wm-patch <이름>      # 수정사항을 patches/NNNN-<이름>.patch 로 저장
wm-clean [app.exe]   # prefix 초기화 (+ 바로 실행)
wm-kill [--all]      # Wine 프로세스 종료 (트레이에 숨은 앱 포함)
wm-reset             # override/ runtime/ 삭제 (patches/ 만 들어간 상태로)
wm-prefix            # 템플릿 버리고 prefix 처음부터 재생성
```

### 실행 방식

`wm-run`은 두 단계다. **prefix는 wiku가, 실행은 직접.**

1. `wiku miku --env`: prefix 생성·갱신(레지스트리·폰트·DXVK), `override/` 반영을 하고 실행 환경(`WINEPREFIX`, 로캘, Wayland, 변형 env)을 출력한다.
   그래서 개발 prefix는 배포판과 같다.
2. 그 환경으로 `runtime/bin/wine`을 바로 띄운다. 앱 메뉴 갱신 같은 wiku의 부가 동작은 없다.

`runtime/`은 배포용 runtime(vanilla wine + `wine-miku-modules`)의 심볼릭 링크 복제본이고, 그 위에 `override/`(`wm-build` 결과)를 덮어쓴다.
`override/`가 비어 있어도 `patches/`가 다 들어간 Wine으로 돈다. Wine은 설치 디렉터리를 `WINEDLLPATH`보다 먼저 찾기 때문에 이렇게 한다.

`scripts/dev.sh`가 배포용 설정에서 wine만 `runtime/`으로, prefix는 `./prefix`, `override/` 반영을 켠 설정을 `.cache/wiku-dev.json`에,
그 설정으로 wiku를 부르는 실행기를 `.cache/wiku-dev`에 만든다. `nix develop` 밖에서도 돌아서 개발 prefix의 앱 메뉴 바로가기가 이걸 부른다.

```bash
wm-run prefix/drive_c/users/$USER/Desktop/카카오톡.lnk    # 설치한 앱 (.lnk 또는 .exe, "C:\\..." 경로도 됨)
.cache/wiku-dev miku app.exe                              # 배포판과 똑같이 wiku 로 실행 (앱 메뉴도 만든다)
.cache/wiku-dev miku --menus                              # 개발 prefix 의 앱 메뉴 다시 만들기
WIKU_LANG=ja_JP.UTF-8 wm-run app.exe                      # 이번만 로캘 바꾸기
WINEDEBUG=+loaddll wm-run app.exe                         # 어떤 DLL 이 로딩되는지
```

- prefix 초기화는 템플릿(`.cache/templates/<key>`)에서 reflink로 복사해서 거의 즉시다. Wine이나 설정이 바뀌면 템플릿도 자동으로 다시 만든다.
  `rm -rf prefix/drive_c` 해도 다음 실행 때 새로 만든다.
- 앱 메뉴는 `~/.local/share/applications/wiku/miku/`(이름 `카카오톡 (miku)`). wiku로 실행할 때만 갱신된다.
- 배포용 runtime과 wiku 패키지는 `.gcroots/`로 GC에서 보호된다.
- 터미널로 파이프한 출력(`wm-run reg query ... | less`)은 CP949라 깨진다. `| iconv -f CP949`.

### 패치 작업

- 새로 추가한 소스 파일은 `wm-patch` 전에 `git -C src/wine-* add <파일>`.
- 패치를 바꾼 뒤 `nix build .#winemiku`로 확인 (약 4분). 모듈 목록: `nix eval .#wine-miku-modules.buildPhase`.
  헤더(`include/`)나 여러 모듈이 같이 쓰는 코드를 고쳤으면 모듈만 덮어써서는 안 맞을 수 있다. `nix build .#wine-miku`(전체)로 확인할 것.
- `scripts/gen-prefix-reg.py`·`gen-fonts.py`를 고쳤으면 `nix develop`을 다시 한다. 다음 실행 때 prefix에 자동으로 다시 적용된다.
- DXVK: `src/dxvk-<버전>/`에 소스를 풀고 git 기준점을 만든 뒤 고치고 `git diff > patches/dxvk/NNNN-<이름>.patch`.
- wiku를 고쳤으면: 로컬에서 바로 `nix develop --override-input wiku path:/경로/wiku`, 푸시 후 `nix flake update wiku`.
- 소스를 처음부터: `rm -rf src && wm-prepare`.

## 라이선스

Wine은 LGPL-2.1-or-later. 바이너리(Cachix 포함)를 배포하므로 수정 소스인 `patches/`를 함께 공개한다.
