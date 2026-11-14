#!/usr/bin/env python3
"""prefix 기본 설정 .reg 생성 (UTF-16LE, regedit /S 로 import).

- 폰트: scripts/gen-fonts.py 가 만든 폰트를 등록하고, Windows 기본 한글 폰트 이름은
  Malgun Gothic 으로 대체, Tahoma -> DejaVu Sans, Arial -> Arimo + FontLink
- 트레이: explorer 의 대체 트레이 창 끄기 (patches/0004 가 바로 보낸다)

Wayland 드라이버(Graphics), DXVK DllOverrides, winemenubuilder 옵션은 wiku 토글이 한다
(flake.nix defaults: wayland, dxvk. fileAssoc 는 wiku 기본값 끔). wiku 는 이 파일 다음에 자기 것을 적용한다.

사용법: gen-prefix-reg.py <출력.reg>
"""
import sys

# scripts/gen-fonts.py 결과 (wiku 가 prefix 의 Fonts/ 에 링크): 이름 -> 파일
FONTS = {
    "Segoe UI": "segoeui.ttf", "Segoe UI Bold": "segoeuib.ttf",          # Noto Sans
    "Malgun Gothic": "malgun.otf", "Malgun Gothic Bold": "malgunbd.otf",  # Noto Sans CJK KR
    "DejaVu Sans": "DejaVuSans.ttf", "DejaVu Sans Bold": "DejaVuSans-Bold.ttf",
    "Arimo": "arimo.ttf", "Arimo Bold": "arimobd.ttf",
}

# Wine 내장 Tahoma/Arial(대체품, 작은 글씨가 깨짐) 대신 쓸 폰트. 카카오톡은 영어·숫자를 이 둘로 그린다
REPLACEMENTS = {"Tahoma": "DejaVu Sans", "Arial": "Arimo"}

SANS = "Malgun Gothic"
MONO = "Noto Sans Mono CJK KR"
# FontLink(GDI 한글 보충): "파일,글꼴이름" 쌍. 이름은 그 파일 안의 글꼴 이름이어야 한다
LINK_SANS_FONT = f"{FONTS[SANS]},{SANS}"         # malgun.otf,Malgun Gothic
LINK_MONO_FONT = f"NotoSansCJK-Regular.ttc,{MONO}"

# 앱이 이름으로 요청하는 한글 폰트 -> 대체 폰트 (GDI 와 Qt 가 읽는다. DirectWrite 는 안 읽음)
SUBSTITUTES = {
    "Gulim": SANS, "굴림": SANS,
    "Dotum": SANS, "돋움": SANS,
    "Batang": SANS, "바탕": SANS,
    "Gungsuh": SANS, "궁서": SANS,
    "맑은 고딕": SANS,
    "GulimChe": MONO, "굴림체": MONO,
    "DotumChe": MONO, "돋움체": MONO,
    "BatangChe": MONO, "바탕체": MONO,
    "GungsuhChe": MONO, "궁서체": MONO,
    # macOS 폰트 이름 (LINE 설치기가 요청). 없으면 Courier New(고정폭)로 떨어진다.
    # 설치기는 GetGlyphIndices 로 글리프 번호를 얻어 그려서 FontLink 가 안 먹는다 -> 한글이 있는 폰트로
    "Helvetica Neue": SANS,
}

# 한글 글리프가 없는 서양 UI 폰트 -> 한글은 Noto 로 폴백
LINK_SANS = [
    "Tahoma", "Microsoft Sans Serif", "MS Sans Serif", "MS Shell Dlg",
    "MS Shell Dlg 2", "Segoe UI", "Arial", "Lucida Sans Unicode",
    "Times New Roman", "Verdana",
]
LINK_MONO = ["Courier New", "Consolas", "Lucida Console"]


def q(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def multi_sz(items) -> str:
    data = "".join(i + "\0" for i in items) + "\0"
    return "hex(7):" + ",".join(f"{b:02x}" for b in data.encode("utf-16-le"))


def main() -> None:
    out = [
        "Windows Registry Editor Version 5.00",
        "",
        r"[HKEY_LOCAL_MACHINE\Software\Microsoft\Windows NT\CurrentVersion\Fonts]",
        *(f"{q(k + ' (TrueType)')}={q(v)}" for k, v in FONTS.items()),
        "",
        r"[HKEY_LOCAL_MACHINE\Software\Microsoft\Windows NT\CurrentVersion\FontSubstitutes]",
        *(f"{q(k)}={q(v)}" for k, v in SUBSTITUTES.items()),
        # 이제 진짜 폰트가 있다. 예전 prefix 의 "Malgun Gothic" -> Noto Sans CJK KR 대체를 지운다
        '"Malgun Gothic"=-',
        "",
        # 내장 Tahoma/Arial 은 runtime 에서 빼고(flake.nix runtimeHook, scripts/dev.sh) 이 이름들을
        # 다른 폰트로 연결한다. 같은 이름의 폰트가 있으면 무시되므로(GDI·DirectWrite 모두) 빼야 한다.
        r"[HKEY_CURRENT_USER\Software\Wine\Fonts\Replacements]",
        *(f"{q(k)}={q(v)}" for k, v in REPLACEMENTS.items()),
        "",
        r"[HKEY_LOCAL_MACHINE\Software\Microsoft\Windows NT\CurrentVersion\FontLink\SystemLink]",
        *(f"{q(k)}={multi_sz([LINK_SANS_FONT])}" for k in LINK_SANS),
        *(f"{q(k)}={multi_sz([LINK_MONO_FONT])}" for k in LINK_MONO),
        "",
        # 트레이 아이콘은 patches/0004 가 바(StatusNotifierItem)로 보낸다. 그게 안 될 때(세션 버스 없음)
        # explorer 가 대신 띄우는 작은 트레이 창(Shell_TrayWnd)은 진짜 창이 되어 포커스를 뺏는다
        # (SWP_NOACTIVATE 무시). 끈다.
        r"[HKEY_CURRENT_USER\Software\Wine\Explorer]",
        '"ShowSystray"=dword:00000000',
        "",
    ]
    with open(sys.argv[1], "w", encoding="utf-16", newline="\r\n") as f:
        f.write("\n".join(out))


if __name__ == "__main__":
    main()
