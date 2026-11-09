{
  description = "winemiku - 커스텀 패치를 얹은 Wine (Wayland, 한국어, DXVK)";

  # 빌드된 wine-miku 를 받는 바이너리 캐시 (없으면 직접 빌드: 1시간 가까이)
  nixConfig = {
    extra-substituters = [ "https://winemiku.cachix.org" ];
    extra-trusted-public-keys = [ "winemiku.cachix.org-1:BbEx+MwxsPdW3eekGCtxLQZlyemmnOXwvpgCijKVfxk=" ];
  };

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      lib = nixpkgs.lib;

      # nixpkgs 캐시에 있는 빌드된 wine (개발 중 실행용, 컴파일 없음)
      wine-vanilla = pkgs.wineWow64Packages.stagingFull;

      # patches/ 안의 *.patch 를 이름순으로 자동 적용
      myPatches =
        let files = builtins.attrNames (builtins.readDir ./patches);
        in map (f: ./patches + "/${f}")
          (lib.sort lib.lessThan (lib.filter (lib.hasSuffix ".patch") files));

      # 패치 적용된 전체 wine
      wine-miku = wine-vanilla.overrideAttrs (o: {
        pname = "wine-miku";
        patches = (o.patches or [ ]) ++ myPatches;
      });

      # 한글 폰트 (static 버전: Wine 은 가변 폰트 처리가 불완전)
      cjkFonts = "${pkgs.noto-fonts-cjk-sans-static}/share/fonts/opentype/noto-cjk";
      # D3D8/9/10/11 -> Vulkan. Wayland 에서 wined3d(D3D->OpenGL)는 화면 갱신이 안 되는 앱이 있음 (카카오톡)
      # patches/dxvk/*.patch 를 이름순으로 적용 (예: 카카오톡 큰 이미지 축소 시 자동 mipmap)
      dxvkPatches =
        let files = builtins.attrNames (builtins.readDir ./patches/dxvk);
        in map (f: ./patches/dxvk + "/${f}")
          (lib.sort lib.lessThan (lib.filter (lib.hasSuffix ".patch") files));
      patchDxvk = d: d.overrideAttrs (o: {
        pname = "dxvk-miku";
        patches = (o.patches or [ ]) ++ dxvkPatches;
      });
      dxvk = pkgs.runCommand "dxvk-miku-${pkgs.dxvk.version}-bin" { } ''
        mkdir -p $out
        ln -s ${patchDxvk pkgs.dxvk.dxvk64}/bin $out/x64
        ln -s ${patchDxvk pkgs.dxvk.dxvk32}/bin $out/x32
      ''; # x64/ x32/ 에 DLL

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

      # bin/winemiku 가 prefix 에 적용하는 데이터: 레지스트리 설정, 폰트, DXVK
      winemiku-share = pkgs.runCommand "winemiku-share" { nativeBuildInputs = [ pkgs.python3 ]; } ''
        mkdir -p $out
        python3 -I ${./scripts/gen-prefix-reg.py} $out/prefix.reg
        ln -s ${cjkFonts} $out/cjk-fonts
        ln -s ${winemiku-fonts} $out/fonts
        ln -s ${dxvk} $out/dxvk
      '';

      # 실행용 wine: 빌드된 wine 의 심볼릭 링크 복제본에서 내장 Tahoma/Arial 만 뺀다 (컴파일 없음).
      # 내장본은 작은 글씨가 깨지는 대체품이라 prefix.reg 의 Replacements 로 Segoe UI(Noto Sans)에
      # 연결하는데, 같은 이름의 폰트가 있으면 Wine 이 Replacements 를 무시한다.
      # Wine 은 ntdll.so 의 실제 위치 기준으로 share/wine 을 찾으므로 실행파일과 ntdll.so 는 복사
      # (개발 모드 runtime/ 과 같은 방식, scripts/dev.sh _wm_runtime).
      wineRuntime = wine: pkgs.runCommand "${wine.name}-runtime"
        { nativeBuildInputs = [ pkgs.python3 ]; passthru = { inherit (wine) version; }; } ''
        cp -rs ${wine}/. $out && chmod -R u+w $out
        for f in bin/wine bin/.wine lib/wine/x86_64-unix/{wine,wine-preloader,ntdll.so}; do
          [ -e ${wine}/$f ] || continue
          rm -f $out/$f; cp -L ${wine}/$f $out/$f
        done
        python3 -I ${./scripts/rewrap.py} ${wine} $out
        rm -f $out/share/wine/fonts/{tahoma,tahomabd,arial}.ttf
        echo ${wine} > $out/.vanilla
      '';

      # 배포용: 실행기 + 패치된 wine + 데이터. nix run 으로 바로 쓴다.
      # prefix 는 ~/.local/share/winemiku/prefix, 템플릿은 ~/.cache/winemiku/prefix-template
      mkWinemiku = wine: pkgs.runCommand "winemiku-${wine.version}"
        {
          nativeBuildInputs = [ pkgs.makeWrapper ];
          meta.mainProgram = "winemiku";
          passthru = { inherit wine; share = winemiku-share; };
        } ''
        install -Dm755 ${./bin/winemiku} $out/libexec/winemiku
        patchShebangs $out/libexec/winemiku
        makeWrapper $out/libexec/winemiku $out/bin/winemiku \
          --prefix PATH : ${lib.makeBinPath (with pkgs; [ coreutils findutils gnugrep gnused procps diffutils ])} \
          --set WINEMIKU_WINE ${wineRuntime wine} \
          --set WINEMIKU_SHARE ${winemiku-share} \
          --set WINEMIKU_OVERRIDE "" \
          --set WINEMIKU_SELF $out/bin/winemiku \
          --run 'export WINEMIKU_PREFIX="''${WINEMIKU_PREFIX:-''${XDG_DATA_HOME:-$HOME/.local/share}/winemiku/prefix}"' \
          --run 'export WINEMIKU_TEMPLATE="''${WINEMIKU_TEMPLATE:-''${XDG_CACHE_HOME:-$HOME/.cache}/winemiku/prefix-template}"'
      '';
      winemiku = mkWinemiku wine-miku;
      # 패치 없이 캐시의 wine 으로 (빌드 없이 바로 받음. UAC/바로가기 패치 빠짐)
      winemiku-unpatched = mkWinemiku wine-vanilla;
    in {
      packages.${system} = {
        default = winemiku;
        inherit winemiku winemiku-unpatched wine-miku wine-vanilla winemiku-share winemiku-fonts;
      };

      apps.${system}.default = {
        type = "app";
        program = "${winemiku}/bin/winemiku";
      };

      # 개발 셸: wine 빌드 의존성 전부 + 실행용 vanilla wine + 헬퍼 함수
      devShells.${system}.default = wine-miku.overrideAttrs (o: {
        nativeBuildInputs = (o.nativeBuildInputs or [ ]) ++ [ pkgs.git ];
        WINE_VANILLA = wine-vanilla;
        WM_CJK_FONTS = cjkFonts;
        WM_FONTS = winemiku-fonts;
        WM_DXVK = dxvk;
        shellHook = ''
          source ${./scripts/dev.sh}
        '';
      });
    };
}
