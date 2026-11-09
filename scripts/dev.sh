# nix develop 셸에서 source 되는 헬퍼 함수들
# 프로젝트 루트에서 `nix develop` 했다고 가정한다.

WM_ROOT="$PWD"
WM_SRC="$WM_ROOT/src"
WM_OVERRIDE="$WM_ROOT/override"
export WINEPREFIX="$WM_ROOT/prefix"

_wm_tree() {
    local d
    d=$(find "$WM_SRC" -mindepth 1 -maxdepth 1 -type d -name 'wine-*' 2>/dev/null | head -n1)
    [ -n "$d" ] || { echo "소스가 없음. 먼저 wm-prepare 실행" >&2; return 1; }
    echo "$d"
}

# 소스 받기 + nixpkgs 패치 + patches/*.patch 적용 + configure
wm-prepare() {
    if [ -d "$WM_SRC" ]; then
        echo "$WM_SRC 가 이미 있음. 다시 하려면 지우고 실행" >&2
        return 1
    fi
    mkdir -p "$WM_SRC"
    (
        set -e
        cd "$WM_SRC"
        unpackPhase
        cd "$sourceRoot"
        patchPhase
        # 수정 내역 추적용 git 기준점
        git init -q
        git add -A
        git -c user.name=wm -c user.email=wm@local commit -qm base
        appendToVar configureFlags --disable-tests
        configurePhase
        # configure 가 고친 추적 파일(shebang 등)도 기준점에 포함 -> 패치에 안 섞이게
        git add -u
        git -c user.name=wm -c user.email=wm@local commit -qm configured --allow-empty
    ) && echo "준비 완료: $(_wm_tree)"
}

# 빌드하고 override/ 에 복사. override/ 는 runtime/ 과 같은 구조(bin/, lib/wine/<arch>/).
# 예: wm-build d3d11 / wm-build winex11.drv / wm-build server (wineserver) / wm-build programs/winemenubuilder
wm-build() {
    [ $# -ge 1 ] || { echo "사용법: wm-build <dlls/ 아래 디렉터리명 | server | programs/<이름>>..." >&2; return 1; }
    local tree; tree=$(_wm_tree) || return 1
    local d
    for d in "$@"; do
        d="${d#dlls/}"
        if [ "$d" = server ]; then
            make -C "$tree" -j"$(nproc)" server/all || return 1
            mkdir -p "$WM_OVERRIDE/bin"; cp -f "$tree/server/wineserver" "$WM_OVERRIDE/bin/"
            echo "override/ 에 wineserver 복사됨"
            continue
        fi
        local top=dlls ext=dll
        if [[ "$d" == programs/* ]]; then top=programs; ext=exe; d="${d#programs/}"; fi
        make -C "$tree" -j"$(nproc)" "$top/$d/all" || return 1
        local mod="$d"; [[ "$mod" == *.* ]] || mod="$mod.$ext"
        local so="${mod%.*}.so" arch f copied=0
        for arch in x86_64-windows i386-windows; do
            f="$tree/$top/$d/$arch/$mod"
            if [ -f "$f" ]; then
                mkdir -p "$WM_OVERRIDE/lib/wine/$arch"; cp -f "$f" "$WM_OVERRIDE/lib/wine/$arch/"; copied=1
            fi
        done
        if [ -f "$tree/$top/$d/$so" ]; then
            mkdir -p "$WM_OVERRIDE/lib/wine/x86_64-unix"; cp -f "$tree/$top/$d/$so" "$WM_OVERRIDE/lib/wine/x86_64-unix/"; copied=1
        fi
        [ $copied = 1 ] && echo "override/ 에 $mod 복사됨" || echo "경고: $d 결과물을 못 찾음" >&2
    done
}

# runtime/ = vanilla wine 의 심볼릭 링크 복제본 (+ 실행 시 bin/winemiku 가 override/ 를 반영).
# Wine 은 ntdll.so 의 realpath 기준 디렉터리를 WINEDLLPATH 보다 먼저 찾기 때문에
# (dlls/ntdll/unix/loader.c set_dll_path) WINEDLLPATH 로는 빌트인 DLL 을 덮어쓸 수 없다.
# 그래서 wine 실행파일과 ntdll.so 만 실제 복사해서 기준 디렉터리를 runtime/ 으로 옮긴다.
# bin/winemiku 가 nix develop 없이 쓸 수 있게 prefix.reg(생성된 레지스트리)와 cjk-fonts 링크도 여기 둔다.
WM_RUNTIME="$WM_ROOT/runtime"
_wm_runtime() {
    if [ "$(cat "$WM_RUNTIME/.vanilla" 2>/dev/null)" != "$WINE_VANILLA" ]; then
        rm -rf "$WM_RUNTIME"
        cp -rs "$WINE_VANILLA/." "$WM_RUNTIME/" && chmod -R u+w "$WM_RUNTIME" || return 1
        local f
        for f in bin/wine bin/.wine lib/wine/x86_64-unix/{wine,wine-preloader,ntdll.so}; do
            [ -e "$WINE_VANILLA/$f" ] || continue
            rm -f "$WM_RUNTIME/$f"; cp -L "$WINE_VANILLA/$f" "$WM_RUNTIME/$f"
        done
        # staging 등: bin/wine 이 store 경로를 박은 바이너리 래퍼면 runtime 용으로 다시 만든다
        python3 -I "$WM_ROOT/scripts/rewrap.py" "$WINE_VANILLA" "$WM_RUNTIME" >/dev/null || return 1
        echo "$WINE_VANILLA" > "$WM_RUNTIME/.vanilla"
    fi
    _wm_gcroot wine "$WINE_VANILLA"
    _wm_gcroot cjk-fonts "${WM_CJK_FONTS%/share/*}"
    _wm_gcroot dxvk "$WM_DXVK"
    ln -sfn "$WM_CJK_FONTS" "$WM_RUNTIME/cjk-fonts"
    ln -sfn "$WM_DXVK" "$WM_RUNTIME/dxvk"
    python3 -I "$WM_ROOT/scripts/gen-prefix-reg.py" "$WM_RUNTIME/prefix.reg.new" || return 1
    if cmp -s "$WM_RUNTIME/prefix.reg.new" "$WM_RUNTIME/prefix.reg"; then
        rm -f "$WM_RUNTIME/prefix.reg.new"
    else
        mv "$WM_RUNTIME/prefix.reg.new" "$WM_RUNTIME/prefix.reg"
    fi
}

# nix-collect-garbage 에서 보호 (.gcroots/<이름> -> store 경로)
_wm_gcroot() {
    [ "$(readlink "$WM_ROOT/.gcroots/$1" 2>/dev/null)" = "$2" ] && return 0
    mkdir -p "$WM_ROOT/.gcroots"
    nix-store --add-root "$WM_ROOT/.gcroots/$1" --realise "$2" >/dev/null
}

# 실행은 전부 bin/winemiku 가 한다 (Wayland, 한국어, override 반영, prefix 자동 생성).
# 앱 바로가기도 같은 실행기를 쓴다. 예: wm-run winecfg
wm-run() {
    _wm_runtime || return 1
    "$WM_ROOT/bin/winemiku" "$@"
}

# 이 prefix 의 Wine 프로세스 종료 (트레이에 숨은 앱 포함). 모든 prefix: wm-kill --all
wm-kill() {
    if [ "$1" = --all ]; then "$WM_ROOT/bin/winemiku" --kill-all; else "$WM_ROOT/bin/winemiku" --kill; fi
}

# prefix 초기화 (drive_c + 레지스트리 + 이 prefix 의 메뉴 항목). 템플릿에서 즉시 다시 만든다
wm-clean() {
    _wm_runtime || return 1
    "$WM_ROOT/bin/winemiku" --reset "$@"
}

# prefix 기본 설정(gen-prefix-reg.py)을 처음부터 다시: 템플릿 버리고 prefix 재생성
wm-prefix() {
    rm -rf "$WM_ROOT/.cache/prefix-template"
    wm-clean
}

# override/ 를 비우고 vanilla 상태로 되돌리기
wm-reset() {
    [ -x "$WM_RUNTIME/bin/wineserver" ] && "$WM_RUNTIME/bin/wineserver" -k 2>/dev/null
    rm -rf "$WM_OVERRIDE" "$WM_RUNTIME"
    echo "override/ 와 runtime/ 삭제됨 (다음 wm-run 때 다시 만든다)"
}

# 현재 수정사항을 patches/NNNN-<이름>.patch 로 저장. 예: wm-patch fix-dxgi
wm-patch() {
    [ $# -eq 1 ] || { echo "사용법: wm-patch <이름>" >&2; return 1; }
    local tree; tree=$(_wm_tree) || return 1
    # 기존 파일 수정분만 담는다. 새로 추가한 소스 파일은 먼저 직접 `git -C <src> add <파일>` 할 것
    git -C "$tree" add -u
    if git -C "$tree" diff --cached --quiet; then
        echo "변경사항 없음" >&2; return 1
    fi
    local n; n=$(find "$WM_ROOT/patches" -maxdepth 1 -name '*.patch' | wc -l)
    local out; out=$(printf '%s/patches/%04d-%s.patch' "$WM_ROOT" $((n + 1)) "$1")
    git -C "$tree" diff --cached > "$out"
    git -C "$tree" -c user.name=wm -c user.email=wm@local commit -qm "$1"
    git -C "$WM_ROOT" add "$out" 2>/dev/null
    echo "저장됨: $out"
}

echo "winemiku 개발 셸 (wine $(${WINE_VANILLA}/bin/wine --version 2>/dev/null))"
echo "  wm-prepare | wm-build <dll> | wm-run <exe> | wm-patch <이름> | wm-clean | wm-kill | wm-reset | wm-prefix"
