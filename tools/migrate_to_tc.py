# -*- coding: utf-8 -*-
"""
把 pages/ 与 components/ 下的 $r('app.color.<语义token>') 迁移为 TC.<camel>()，
并为每个 @Component struct 注入皮肤刷新订阅 @StorageProp('skinVersion')。

用法：
  python tools/migrate_to_tc.py          # 试运行，只打印统计
  python tools/migrate_to_tc.py --apply  # 实际写入
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ETS = os.path.join(ROOT, 'entry', 'src', 'main', 'ets')
DIRS = [os.path.join(ETS, 'pages'), os.path.join(ETS, 'components')]

TOKENS = [
    'page_background', 'nav_background', 'surface_card', 'surface_card_alt',
    'surface_inset', 'surface_raised', 'chip_background', 'sheet_background',
    'text_primary', 'text_body', 'text_secondary', 'text_tertiary', 'text_quaternary',
    'text_on_accent', 'text_on_media', 'text_on_media_secondary', 'text_on_media_tertiary',
    'accent', 'accent_soft', 'divider', 'border_subtle', 'scrim',
    'header_scrim_top', 'header_scrim_mid',
]


def camel(token: str) -> str:
    parts = token.split('_')
    return parts[0] + ''.join(p[:1].upper() + p[1:] for p in parts[1:])


COLOR_RE = re.compile(
    r"\$r\(\s*'app\.color\.(" + '|'.join(TOKENS) + r")'\s*\)")

IMPORT_RE = re.compile(r"^import[\s\S]*?from\s+['\"][^'\"]+['\"];?\s*$", re.M)

STRUCT_RE = re.compile(r"(@Component\n(?:export\s+)?struct\s+\w+\s*\{)")

IMPORT_LINE = "import { TC } from '../services/ThemeColors'\n"
PROP_LINE = "\n  @StorageProp('skinVersion') skinVersionObs: number = 0"


def replace_colors(text: str):
    count = [0]

    def sub(m):
        count[0] += 1
        return 'TC.' + camel(m.group(1)) + '()'

    return COLOR_RE.sub(sub, text), count[0]


def ensure_import(text: str) -> str:
    if '../services/ThemeColors' in text:
        return text
    matches = list(IMPORT_RE.finditer(text))
    if matches:
        pos = matches[-1].end()
        return text[:pos] + ('\n' if not text[pos - 1] == '\n' else '') + IMPORT_LINE + text[pos:]
    return IMPORT_LINE + text


def inject_props(text: str):
    count = [0]

    def sub(m):
        count[0] += 1
        return m.group(1) + PROP_LINE

    if 'skinVersionObs' in text:
        return text, 0
    return STRUCT_RE.sub(sub, text), count[0]


def main():
    apply = '--apply' in sys.argv
    total_repl = 0
    total_props = 0
    total_files = 0
    for d in DIRS:
        for name in sorted(os.listdir(d)):
            if not name.endswith('.ets'):
                continue
            path = os.path.join(d, name)
            text = open(path, encoding='utf-8').read()
            new_text, repl = replace_colors(text)
            if repl > 0:
                new_text = ensure_import(new_text)
            new_text, props = inject_props(new_text)
            if new_text != text:
                total_files += 1
                total_repl += repl
                total_props += props
                if apply:
                    open(path, 'w', encoding='utf-8').write(new_text)
                print(f'{name:<34} 颜色替换 {repl:>4}  订阅注入 {props}')
    print(f'\n共 {total_files} 个文件，{total_repl} 处颜色替换，{total_props} 个组件注入 skinVersion 订阅')
    if not apply:
        print('（试运行，未写入；加 --apply 落盘）')


if __name__ == '__main__':
    main()
