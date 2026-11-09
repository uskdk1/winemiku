#!/usr/bin/env python3
"""prefix 에 넣을 폰트 생성: Windows 기본 UI 폰트 이름으로 Noto 를 등록한다.

앱(카카오톡 등)은 폰트를 이름으로 찾는다. Wine 에 그 이름이 없으면 엉뚱한 폰트로 빠진다.
- 영어·숫자: Wine 내장 Tahoma/Arial 은 Wine 이 만든 대체품이라 작은 글씨가 깨진다
  -> 내장본은 빼고 prefix.reg 의 Replacements 로 Tahoma -> DejaVu Sans, Arial -> Arimo
  -> Noto Sans 는 "Segoe UI" 로 (Segoe UI 를 직접 찾는 앱용)
- 한글: 맞는 이름이 없으면 시스템의 가변 Noto CJK 로 빠지는데, Wine 은 가변 폰트를 제대로
  못 다뤄서 글자 간격이 벌어진다 -> 고정 굵기 Noto Sans CJK KR 을 "Malgun Gothic" 으로
Wine 의 DirectWrite 는 레지스트리 FontSubstitutes 를 보지 않아서 이름 자체를 바꿔야 한다.
가변 폰트는 고정 굵기(Regular 400, Bold 700)로 뽑는다.

사용법: gen-fonts.py <NotoSans.ttf(가변)> <NotoSansCJK-Regular.ttc> <NotoSansCJK-Bold.ttc>
                    <DejaVuSans.ttf> <DejaVuSans-Bold.ttf> <Arimo[wght].ttf(가변)> <출력 디렉터리>
"""
import os
import shutil
import sys

from fontTools.ttLib import TTCollection, TTFont
from fontTools.varLib import instancer


def cjk_kr_face(path):
    for face in TTCollection(path).fonts:
        if face["name"].getDebugName(1) == "Noto Sans CJK KR":
            return face
    sys.exit(f"{path}: Noto Sans CJK KR 없음")


def static_instance(path, weight):
    font = TTFont(path)
    if "fvar" in font:
        pins = {a.axisTag: a.defaultValue for a in font["fvar"].axes}
        pins["wght"] = weight
        font = instancer.instantiateVariableFont(font, pins)
    return font


def rename(font, family, bold):
    style = "Bold" if bold else "Regular"
    full = f"{family} Bold" if bold else family
    ps = family.replace(" ", "") + ("-Bold" if bold else "")
    name = font["name"]
    for nid in (1, 2, 3, 4, 6, 16, 17, 21, 22):
        name.removeNames(nameID=nid)
    for nid, val in ((1, family), (2, style), (3, f"{ps};winemiku"), (4, full), (6, ps)):
        name.setName(val, nid, 3, 1, 0x409)
    os2 = font["OS/2"]
    os2.usWeightClass = 700 if bold else 400
    os2.fsSelection = (os2.fsSelection & ~0x61) | (0x20 if bold else 0x40)  # BOLD / REGULAR
    font["head"].macStyle = (font["head"].macStyle & ~1) | (1 if bold else 0)
    return font


def main():
    sans, cjk_regular, cjk_bold, dejavu, dejavu_bold, arimo, out = sys.argv[1:8]
    os.makedirs(out, exist_ok=True)
    rename(static_instance(sans, 400), "Segoe UI", False).save(os.path.join(out, "segoeui.ttf"))
    rename(static_instance(sans, 700), "Segoe UI", True).save(os.path.join(out, "segoeuib.ttf"))
    rename(cjk_kr_face(cjk_regular), "Malgun Gothic", False).save(os.path.join(out, "malgun.otf"))
    rename(cjk_kr_face(cjk_bold), "Malgun Gothic", True).save(os.path.join(out, "malgunbd.otf"))
    # 원래 이름 그대로 (DejaVu 는 이미 고정 굵기)
    shutil.copyfile(dejavu, os.path.join(out, "DejaVuSans.ttf"))
    shutil.copyfile(dejavu_bold, os.path.join(out, "DejaVuSans-Bold.ttf"))
    rename(static_instance(arimo, 400), "Arimo", False).save(os.path.join(out, "arimo.ttf"))
    rename(static_instance(arimo, 700), "Arimo", True).save(os.path.join(out, "arimobd.ttf"))


if __name__ == "__main__":
    main()
