#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
将 pages/ components/ 中的硬编码颜色迁移为 $r('app.color.<token>')。
只在属性参数位置替换，跳过渐变数组、颜色拼接、用户可配置色。
"""
import os, re, sys, json

ROOT = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    'entry', 'src', 'main', 'ets'
)

EXACT = {
    # 页面 / 容器
    '#121215': 'page_background', '#121216': 'page_background', '#131318': 'page_background',
    '#101014': 'page_background', '#0f0f14': 'page_background',
    '#1b1b20': 'surface_card', '#19191f': 'surface_card', '#1a1a1f': 'surface_card',
    '#1d1d22': 'surface_card_alt', '#1e1e23': 'surface_card_alt', '#1e1e24': 'surface_card_alt',
    '#1f1f24': 'surface_card_alt', '#202026': 'surface_card_alt', '#1d1d23': 'surface_card_alt',
    '#18181d': 'surface_card_alt', '#18181e': 'surface_card_alt',
    '#24242a': 'surface_inset', '#232329': 'surface_inset', '#222228': 'surface_inset',
    '#24242b': 'surface_inset', '#23232a': 'surface_inset',
    '#29292f': 'chip_background', '#292930': 'chip_background', '#2a2a30': 'surface_raised',
    '#25252b': 'surface_raised', '#25252c': 'surface_raised', '#303038': 'surface_raised',
    '#303037': 'surface_raised', '#2c2c33': 'surface_raised', '#26262d': 'surface_raised',
    '#27272d': 'surface_raised', '#2a2a2e': 'surface_raised', '#222226': 'surface_raised',
    '#38383f': 'divider', '#383840': 'divider',
    '#19191e': 'surface_card', '#16161b': 'surface_card_alt', '#2b2b32': 'surface_raised',
    '#222229': 'surface_raised', '#28282f': 'surface_raised', '#2a2a2a': 'surface_raised',
    '#333339': 'surface_raised', '#2b2b33': 'surface_raised', '#1a1a1f': 'surface_card',

    # 文本
    '#ffffff': 'text_primary',
    '#ededf0': 'text_body', '#eeeeee': 'text_body', '#eeeef2': 'text_body',
    '#eeeef1': 'text_body', '#e8e8eb': 'text_body', '#d0d0d5': 'text_body',
    '#b0b0b8': 'text_body', '#b9b9c0': 'text_body', '#aaaab2': 'text_body',
    '#dedee2': 'text_body', '#d9d9de': 'text_body', '#d9d9df': 'text_body',
    '#d7d7dc': 'text_body', '#d8d8dd': 'text_body', '#dddde2': 'text_body',
    '#dcdce1': 'text_body', '#e4e4e8': 'text_body', '#e2e2e6': 'text_body',
    '#e3e3e6': 'text_body', '#e7e7eb': 'text_body', '#d3d3d8': 'text_body',
    '#f4f4f6': 'text_body', '#f1f1f3': 'text_body', '#f0f0f3': 'text_body',
    '#e9e9e7': 'text_body', '#bbbbc5': 'text_body', '#b8b8c0': 'text_body',
    '#b8b8bf': 'text_body', '#bdbdc4': 'text_body', '#bcbcc6': 'text_body',
    '#b5b5bc': 'text_body', '#c8c8ce': 'text_body',

    '#92929a': 'text_secondary', '#9999a1': 'text_secondary', '#9999a3': 'text_secondary',
    '#9999a4': 'text_secondary', '#9a9aa2': 'text_secondary', '#8a8a92': 'text_secondary',
    '#9999a0': 'text_secondary', '#ccc': 'text_secondary', '#cccccc': 'text_secondary',

    '#77777f': 'text_tertiary', '#777781': 'text_tertiary', '#85858e': 'text_tertiary',
    '#85858f': 'text_tertiary', '#888890': 'text_tertiary', '#888888': 'text_tertiary',
    '#8b8b93': 'text_tertiary', '#8d8d95': 'text_tertiary', '#8c8c94': 'text_tertiary',
    '#777780': 'text_tertiary', '#777777': 'text_tertiary', '#888892': 'text_tertiary',
    '#888891': 'text_tertiary', '#8a8a8f': 'text_tertiary',

    '#66666e': 'text_quaternary', '#686870': 'text_quaternary', '#6f6f7b': 'text_quaternary',
    '#62626a': 'text_quaternary', '#55555d': 'text_quaternary', '#5f5f67': 'text_quaternary',
    '#a9a9b0': 'text_quaternary', '#aaaab5': 'text_quaternary', '#a0a0a8': 'text_quaternary',
    '#a0a0aa': 'text_quaternary', '#6f6f77': 'text_quaternary', '#707078': 'text_quaternary',
    '#696971': 'text_quaternary', '#696972': 'text_quaternary', '#666666': 'text_quaternary',

    # 品牌色
    '#ef233c': 'accent',
    '#ff6577': 'accent_soft', '#ef4058': 'accent_soft', '#ef6577': 'accent_soft',
    '#ff7587': 'accent_soft', '#ff8291': 'accent_soft', '#ff8292': 'accent_soft',
    '#ff7d8e': 'accent_soft', '#ff7b8b': 'accent_soft', '#ff7785': 'accent_soft',
    '#ff4058': 'accent_soft', '#ff372c2c': 'accent_soft',
    '#ff3b4f': 'accent', '#ff7a8a': 'accent_soft', '#ef8795': 'accent_soft',
    '#ff765f': 'accent_soft', '#ff8b9a': 'accent_soft', '#ff8b65': 'accent_soft',
    '#ff9a78': 'accent_soft', '#ff8b78': 'accent_soft', '#ff9c57': 'accent_soft',
    '#ffb47c': 'accent_soft', '#fe010d': 'accent',
    '#fff': 'text_primary',
}

ATTR_RE = re.compile(r"\.(fontColor|backgroundColor|selectedColor|borderColor|caretColor|placeholderColor|color)\(")
LIT_RE = re.compile(r"'#([0-9a-fA-F]{3,8})'")

SKIP_WORDS = ('linearGradient', 'colors:', 'QRCode', 'shadow(', 'fillStyle', '.rgba', 'gradient(')


def grey_token(hexv: str):
    """仅对灰色系字体色按亮度兜底归类"""
    if len(hexv) != 6:
        return None
    r, g, b = int(hexv[0:2], 16), int(hexv[2:4], 16), int(hexv[4:6], 16)
    if max(r, g, b) - min(r, g, b) > 10:
        return None
    lum = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255
    if lum >= 0.60:
        return 'text_body'
    if lum >= 0.50:
        return 'text_secondary'
    if lum >= 0.40:
        return 'text_tertiary'
    return 'text_quaternary'


def convert_line(line: str, stats: dict, leftovers: list, path: str, lineno: int) -> str:
    if any(w in line for w in SKIP_WORDS):
        return line
    if "' +" in line or "+ '" in line:
        return line

    def repl(m):
        attr, quote_open, hexv, quote_close = m.group(1), "", m.group(0), "", ""
        raw = m.group(0)
        low = hexv.lower()
        token = EXACT.get('#' + low)
        if token is None and attr in ('fontColor', 'color', 'placeholderColor'):
            token = grey_token(low)
        if token is None:
            leftovers.append(f"{path}:{lineno}  {raw}")
            return raw
        # 白底文字保持资源色，其他按 token
        stats[token] = stats.get(token, 0) + 1
        return f".{attr}($r('app.color.{token}'))"

    # 匹配 .attr('#xxxxxx') 或 .attr(['#xxxxxx'])
    pattern = re.compile(
        r"\.(fontColor|backgroundColor|selectedColor|borderColor|caretColor|placeholderColor|color)\(\s*(\[)?\s*'#([0-9a-fA-F]{3,8})'\s*(\])?\s*\)"
    )

    def repl2(m):
        attr, bracket_open, hexv, bracket_close = m.group(1), m.group(2) or '', m.group(3), m.group(4) or ''
        low = hexv.lower()
        token = EXACT.get('#' + low)
        if token is None and attr in ('fontColor', 'color', 'placeholderColor'):
            token = grey_token(low)
        if token is None:
            leftovers.append(f"{path}:{lineno}  {m.group(0)}")
            return m.group(0)
        stats[token] = stats.get(token, 0) + 1
        inner = f"$r('app.color.{token}')"
        if bracket_open:
            return f".{attr}([{inner}])"
        return f".{attr}({inner})"

    return pattern.sub(repl2, line)


def main():
    apply = '--apply' in sys.argv
    stats, leftovers, changed = {}, [], []
    targets = []
    for sub in ('pages', 'components'):
        d = os.path.join(ROOT, sub)
        if not os.path.isdir(d):
            continue
        for f in sorted(os.listdir(d)):
            if f.endswith('.ets'):
                targets.append(os.path.join(d, f))

    for path in targets:
        with open(path, encoding='utf-8') as fh:
            lines = fh.readlines()
        out, n = [], 0
        for i, line in enumerate(lines, 1):
            new = convert_line(line, stats, leftovers, os.path.relpath(path, ROOT), i)
            if new != line:
                n += 1
            out.append(new)
        if n:
            changed.append((os.path.relpath(path, ROOT), n))
            if apply:
                with open(path, 'w', encoding='utf-8') as fh:
                    fh.writelines(out)

    print(f"{'已写入' if apply else '预览'}：{len(changed)} 个文件，{sum(n for _, n in changed)} 行")
    print("\n按 token 统计：")
    for k, v in sorted(stats.items(), key=lambda x: -x[1]):
        print(f"  {k:<18} {v}")
    print(f"\n未映射（保留原值）{len(leftovers)} 处，前 40：")
    for item in leftovers[:40]:
        print("  " + item)


if __name__ == '__main__':
    main()
