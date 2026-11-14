{
  description = "winemiku - 커스텀 패치를 얹은 Wine (Wayland, 한국어, DXVK). wiku 변형";

  # 빌드된 패치 모듈·DXVK 를 받는 바이너리 캐시 (없으면 직접 빌드: 모듈 약 4분 + DXVK 약 10분)
  nixConfig = {
    extra-substituters = [ "https://winemiku.cachix.org" ];
    extra-trusted-public-keys = [ "winemiku.cachix.org-1:BbEx+MwxsPdW3eekGCtxLQZlyemmnOXwvpgCijKVfxk=" ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # Wine 변형·prefix 관리 틀 (모듈만 빌드, runtime, DXVK, prefix, wiku 명령).
    wiku = {
      url = "github:uskdk1/wiku";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, wiku }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      lib = nixpkgs.lib;

      # nixpkgs 캐시에 있는 빌드된 wine (개발 중 실행용, 컴파일 없음)
      wine-vanilla = pkgs.wineWow64Packages.stagingFull;

      # 한글 폰트 (static 버전: Wine 은 가변 폰트 처리가 불완전)
      cjkFonts = "${pkgs.noto-fonts-cjk-sans-static}/share/fonts/opentype/noto-cjk";
      # prefix 에 넣는 CJK 폰트는 Regular·Bold 두 개만 (FontLink 의 고정폭 글꼴 등)
      winemiku-cjk-fonts = pkgs.runCommand "winemiku-cjk-fonts" { } ''
        mkdir -p $out
        ln -s ${cjkFonts}/NotoSansCJK-Regular.ttc ${cjkFonts}/NotoSansCJK-Bold.ttc $out/
      '';

      # Arimo (Arial 대체, Google Fonts. 가변 폰트 -> gen-fonts.py 가 고정 굵기로)
      arimo = pkgs.fetchurl {
        name = "Arimo-wght.ttf";
        url = "https://raw.githubusercontent.com/google/fonts/5bb28733cec313b63fbd415b574b5ae35c8aa8b8/ofl/arimo/Arimo%5Bwght%5D.ttf";
        hash = "sha256-5DiYsUPsgmrIy0A0gWRYpwR/vgg2VY3iofjGIjrj4Mo=";
      };

      # prefix 에 넣을 고정 굵기 폰트: Segoe UI = Noto Sans, Malgun Gothic = Noto Sans CJK KR,
      # DejaVu Sans(Tahoma 대체), Arimo(Arial 대체). scripts/gen-fonts.py 설명 참고
      winemiku-fonts = pkgs.runCommand "winemiku-fonts"
        { nativeBuildInputs = [ (pkgs.python3.withPackages (p: [ p.fonttools ])) ]; } ''
        python3 -I ${./scripts/gen-fonts.py} ${pkgs.noto-fonts}/share/fonts/noto/NotoSans.ttf \
          ${cjkFonts}/NotoSansCJK-Regular.ttc ${cjkFonts}/NotoSansCJK-Bold.ttc \
          ${pkgs.dejavu_fonts}/share/fonts/truetype/DejaVuSans.ttf \
          ${pkgs.dejavu_fonts}/share/fonts/truetype/DejaVuSans-Bold.ttf \
          ${arimo} $out
      '';

      # prefix 레지스트리 (폰트 등록·대체·FontLink, 트레이 창 끄기). scripts/gen-prefix-reg.py
      # (Wayland 드라이버, DXVK override, winemenubuilder 옵션은 wiku 토글이 한다)
      winemiku-reg = pkgs.runCommand "winemiku-reg" { nativeBuildInputs = [ pkgs.python3 ]; } ''
        mkdir -p $out
        python3 -I ${./scripts/gen-prefix-reg.py} $out/prefix.reg
      '';

      # 두 변형의 공통 설정
      common = {
        inherit pkgs;
        base = wine-vanilla;
        prefix = {
          reg = "${winemiku-reg}/prefix.reg";
          fonts = [ winemiku-fonts winemiku-cjk-fonts ];
        };
        # 내장 Tahoma/Arial 빼기: Wine 이 만든 대체품이라 작은 글씨가 깨진다. prefix.reg 의
        # Replacements 로 DejaVu Sans / Arimo 에 연결하는데, 같은 이름의 폰트가 있으면 무시된다
        runtimeHook = "rm -f $out/share/wine/fonts/{tahoma,tahomabd,arial}.ttf";
        # patches/0005: prefix 에 넣은 DXVK DLL 도 "서명된" 것으로 본다 (LINE 설치기)
        env = { dxvk, ... }: { WINEMIKU_SIGNED_DLL_DIRS = "${dxvk.x64}:${dxvk.x32}"; };
        defaults = { locale = "ko_KR.UTF-8"; wayland = true; dxvk = true; };
      };

      # 캐시의 vanilla wine + 패치된 모듈만 (Wine 전체를 다시 빌드하지 않는다)
      # + patches/dxvk/*.patch 를 얹은 DXVK
      winemiku = wiku.lib.mkWine (common // {
        name = "miku";
        patches = wiku.lib.patchesIn ./patches;
        dxvkPatches = wiku.lib.patchesIn ./patches/dxvk;
      });
      # 패치 없이 캐시의 wine 으로 (빌드 없이 바로 받음. UAC/바로가기 등 Wine 패치 빠짐, DXVK 는 같은 것)
      winemiku-unpatched = wiku.lib.mkWine (common // {
        name = "miku-unpatched";
        inherit (winemiku) dxvk;
      });
    in
    {
      packages.${system} = {
        default = winemiku;
        inherit winemiku winemiku-unpatched wine-vanilla winemiku-fonts winemiku-cjk-fonts winemiku-reg;
        # 패치된 Wine 전체 (약 1시간, 확인용. 배포에는 안 씀)
        wine-miku = winemiku.wine-full;
        # 패치가 건드리는 모듈만 빌드한 결과 (dll·so·wineserver)
        wine-miku-modules = winemiku.modules;
      };

      apps.${system}.default = {
        type = "app";
        program = "${winemiku}/bin/wiku";
      };

      # 개발 셸: wine 빌드 의존성 전부 + 실행용 vanilla wine + 헬퍼 함수
      devShells.${system}.default = winemiku.wine-full.overrideAttrs (o: {
        nativeBuildInputs = (o.nativeBuildInputs or [ ]) ++ [ pkgs.git ];
        WINE_VANILLA = wine-vanilla;
        # wm-run 은 wiku 실행기를 개발용 설정(runtime/, override/, ./prefix)으로 부른다
        WM_WIKU = winemiku;
        WM_WIKU_CONFIG = winemiku.config;
        WM_WIKU_PATH = winemiku.path;
        shellHook = ''
          source ${./scripts/dev.sh}
        '';
      });
    };
}
