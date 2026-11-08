#!/usr/bin/env python3
"""prefix 기본 설정 .reg 생성 (UTF-16LE, regedit /S 로 import).

- 한글 폰트: Windows 기본 한글/UI 폰트 이름을 Noto Sans CJK KR 로 대체 + FontLink
- Wayland 전용: Graphics 드라이버를 wayland 로 고정

사용법: gen-prefix-reg.py <출력.reg>
"""
import sys

SANS = "Noto Sans CJK KR"
MONO = "Noto Sans Mono CJK KR"
FONT_FILE = "NotoSansCJK-Regular.ttc"

# 앱이 이름으로 요청하는 한글 폰트 -> 대체 폰트
SUBSTITUTES = {
    "Gulim": SANS, "굴림": SANS,
    "Dotum": SANS, "돋움": SANS,
    "Batang": SANS, "바탕": SANS,
    "Gungsuh": SANS, "궁서": SANS,
    "Malgun Gothic": SANS, "맑은 고딕": SANS,
    "GulimChe": MONO, "굴림체": MONO,
    "DotumChe": MONO, "돋움체": MONO,
    "BatangChe": MONO, "바탕체": MONO,
    "GungsuhChe": MONO, "궁서체": MONO,
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
        r"[HKEY_LOCAL_MACHINE\Software\Microsoft\Windows NT\CurrentVersion\FontSubstitutes]",
        *(f"{q(k)}={q(v)}" for k, v in SUBSTITUTES.items()),
        "",
        r"[HKEY_LOCAL_MACHINE\Software\Microsoft\Windows NT\CurrentVersion\FontLink\SystemLink]",
        *(f"{q(k)}={multi_sz([f'{FONT_FILE},{SANS}'])}" for k in LINK_SANS),
        *(f"{q(k)}={multi_sz([f'{FONT_FILE},{MONO}'])}" for k in LINK_MONO),
        "",
        r"[HKEY_CURRENT_USER\Software\Wine\Drivers]",
        f'"Graphics"={q("wayland")}',
        "",
        # Wayland 엔 트레이가 없어서 explorer 가 대신 띄우는 작은 트레이 창(Shell_TrayWnd)이
        # 진짜 창이 되어 포커스를 뺏는다(SWP_NOACTIVATE 무시). 끈다.
        # DXVK (bin/winemiku 가 system32/syswow64 에 DLL 을 넣는다): native 우선
        r"[HKEY_CURRENT_USER\Software\Wine\DllOverrides]",
        *(f'"{dll}"="native,builtin"' for dll in ("d3d8", "d3d9", "d3d10core", "d3d11", "dxgi")),
        "",
        r"[HKEY_CURRENT_USER\Software\Wine\Explorer]",
        '"ShowSystray"=dword:00000000',
        "",
        # 기본값 "winemenubuilder.exe -a -r": 세션 시작마다 -a 가 Wine 기본 파일 연결
        # (~/.local/share/applications/wine-extension-*.desktop)을 다시 만드는데, 파일 이름이
        # prefix 간에 공유돼서 마지막에 실행한 prefix 가 덮어쓴다. -r(지워진 앱 메뉴 정리)만 남긴다.
        r"[HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\RunServices]",
        f'"winemenubuilder"={q(r"C:\windows\system32\winemenubuilder.exe -r")}',
        "",
    ]
    with open(sys.argv[1], "w", encoding="utf-16", newline="\r\n") as f:
        f.write("\n".join(out))


if __name__ == "__main__":
    main()
