/*
 * 快捷方式图标生成器：把白色图形合成到 #EF233C 全圆底色上，输出 PNG。
 * 纯 Node 实现（自写 PNG 编码 + 路径光栅化），不依赖任何第三方库。
 * 用法：node tools/gen_shortcut_icons.js
 */
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

const SIZE = 216;
const RED = [0xef, 0x23, 0x3c];
const SS = 4;                       // 每像素 4x4 超采样
const GLYPH_BOX = SIZE * 0.56;      // 图形占画布比例
const OFFSET = (SIZE - GLYPH_BOX) / 2;

/* ---------------- 路径解析 ---------------- */
function parsePath(d) {
  const tokens = d.match(/[a-zA-Z]|-?\d*\.?\d+(?:e-?\d+)?/g) || [];
  const subpaths = [];
  let cur = null;
  let x = 0, y = 0, sx = 0, sy = 0, i = 0, cmd = '';
  const num = () => parseFloat(tokens[i++]);
  const push = (px, py) => { if (cur) cur.push([px, py]); };
  const start = (px, py) => { cur = [[px, py]]; subpaths.push(cur); x = px; y = py; sx = px; sy = py; };

  while (i < tokens.length) {
    if (/[a-zA-Z]/.test(tokens[i])) cmd = tokens[i++];
    const rel = cmd === cmd.toLowerCase();
    const C = cmd.toUpperCase();
    if (C === 'M') {
      const px = num(), py = num();
      start(rel ? x + px : px, rel ? y + py : py);
      cmd = rel ? 'l' : 'L';
    } else if (C === 'L') {
      const px = num(), py = num();
      x = rel ? x + px : px; y = rel ? y + py : py; push(x, y);
    } else if (C === 'H') {
      const px = num(); x = rel ? x + px : px; push(x, y);
    } else if (C === 'V') {
      const py = num(); y = rel ? y + py : py; push(x, y);
    } else if (C === 'C') {
      const x1 = num(), y1 = num(), x2 = num(), y2 = num(), x3 = num(), y3 = num();
      const c1x = rel ? x + x1 : x1, c1y = rel ? y + y1 : y1;
      const c2x = rel ? x + x2 : x2, c2y = rel ? y + y2 : y2;
      const ex = rel ? x + x3 : x3, ey = rel ? y + y3 : y3;
      for (let t = 1; t <= 24; t++) {
        const u = t / 24, v = 1 - u;
        push(v * v * v * x + 3 * v * v * u * c1x + 3 * v * u * u * c2x + u * u * u * ex,
             v * v * v * y + 3 * v * v * u * c1y + 3 * v * u * u * c2y + u * u * u * ey);
      }
      x = ex; y = ey;
    } else if (C === 'Q') {
      const x1 = num(), y1 = num(), x2 = num(), y2 = num();
      const c1x = rel ? x + x1 : x1, c1y = rel ? y + y1 : y1;
      const ex = rel ? x + x2 : x2, ey = rel ? y + y2 : y2;
      for (let t = 1; t <= 16; t++) {
        const u = t / 16, v = 1 - u;
        push(v * v * x + 2 * v * u * c1x + u * u * ex, v * v * y + 2 * v * u * c1y + u * u * ey);
      }
      x = ex; y = ey;
    } else if (C === 'Z') {
      x = sx; y = sy;
      cur = null;
    } else {
      i++;
    }
  }
  return subpaths;
}

/* 从外部 SVG 取填充路径（原始素材是 48x48 坐标，需按自身网格换算）。 */
function loadSvg(rel) {
  const text = fs.readFileSync(path.resolve(__dirname, rel), 'utf8');
  const ds = [...text.matchAll(/<path[^>]*\sd="([^"]+)"/g)].map(m => m[1]);
  let grid = 24;
  const vb = text.match(/viewBox="([^"]+)"/);
  if (vb) {
    const nums = vb[1].trim().split(/[\s,]+/).map(Number);
    grid = nums[2] || 24;
  } else {
    const w = text.match(/\swidth="([\d.]+)"/);
    if (w) grid = parseFloat(w[1]);
  }
  return { ds, grid };
}

function toPixel(subpaths, grid = 24, box = GLYPH_BOX) {
  const unit = box / grid;
  const offset = (SIZE - box) / 2;
  return subpaths.map(sp => sp.map(([px, py]) => [offset + px * unit, offset + py * unit]));
}

function inFill(px, py, polys) {
  let inside = false;
  for (const poly of polys) {
    for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
      const [xi, yi] = poly[i], [xj, yj] = poly[j];
      if ((yi > py) !== (yj > py) && px < ((xj - xi) * (py - yi)) / (yj - yi) + xi) inside = !inside;
    }
  }
  return inside;
}

function distToSeg(px, py, x1, y1, x2, y2) {
  const dx = x2 - x1, dy = y2 - y1;
  const len = dx * dx + dy * dy;
  let t = len === 0 ? 0 : ((px - x1) * dx + (py - y1) * dy) / len;
  t = Math.max(0, Math.min(1, t));
  return Math.hypot(px - (x1 + t * dx), py - (y1 + t * dy));
}

function inStroke(px, py, polys, w) {
  const r = w / 2;
  for (const poly of polys) {
    for (let i = 1; i < poly.length; i++) {
      if (distToSeg(px, py, poly[i - 1][0], poly[i - 1][1], poly[i][0], poly[i][1]) <= r) return true;
    }
  }
  return false;
}

/* ---------------- PNG 编码 ---------------- */
function crc32(buf) {
  let c, table = crc32.t;
  if (!table) {
    table = crc32.t = new Int32Array(256);
    for (let n = 0; n < 256; n++) {
      c = n;
      for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
      table[n] = c;
    }
  }
  let crc = -1;
  for (let i = 0; i < buf.length; i++) crc = (crc >>> 8) ^ table[(crc ^ buf[i]) & 0xff];
  return (crc ^ -1) >>> 0;
}

function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length);
  const body = Buffer.concat([Buffer.from(type, 'ascii'), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body));
  return Buffer.concat([len, body, crc]);
}

function writePng(file, rgba, w, h) {
  const raw = Buffer.alloc((w * 4 + 1) * h);
  for (let y = 0; y < h; y++) {
    raw[y * (w * 4 + 1)] = 0;
    rgba.copy(raw, y * (w * 4 + 1) + 1, y * w * 4, (y + 1) * w * 4);
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0);
  ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8; ihdr[9] = 6; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
  fs.writeFileSync(file, Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', zlib.deflateSync(raw, { level: 9 })),
    chunk('IEND', Buffer.alloc(0)),
  ]));
}

/* ---------------- 图标定义（24x24 图形坐标系） ---------------- */
const ICONS = [
  {
    name: 'ic_shortcut_identify',
    // 麦克风：识别正在播放的歌曲
    fills: [
      'M9 6.2 C9 4.5 10.25 3.2 12 3.2 C13.75 3.2 15 4.5 15 6.2 L15 11 C15 12.7 13.75 14 12 14 C10.25 14 9 12.7 9 11 L9 6.2 Z',
    ],
    strokes: [
      { d: 'M6.4 11.3 C6.4 14.4 8.9 16.9 12 16.9 C15.1 16.9 17.6 14.4 17.6 11.3', w: 2.05 },
      { d: 'M12 16.9 L12 20.6', w: 2.05 },
    ],
  },
  {
    name: 'ic_shortcut_heart',
    // 实心心形：心动模式
    fills: [
      'M12 20.7 C9.5 18.9 3.4 14.4 3.4 9.6 C3.4 6.5 5.8 4.2 8.6 4.2 C10.3 4.2 11.5 5.1 12 6.2 C12.5 5.1 13.7 4.2 15.4 4.2 C18.2 4.2 20.6 6.5 20.6 9.6 C20.6 14.4 14.5 18.9 12 20.7 Z',
    ],
    strokes: [],
  },
  {
    name: 'ic_shortcut_search',
    // 放大镜：搜索
    fills: [],
    strokes: [
      { d: 'M10.2 3.2 C13.9 3.2 16.9 6.2 16.9 9.9 C16.9 13.6 13.9 16.6 10.2 16.6 C6.5 16.6 3.5 13.6 3.5 9.9 C3.5 6.2 6.5 3.2 10.2 3.2 Z', w: 2.2 },
      { d: 'M15.3 15.1 L20.4 20.2', w: 2.4 },
    ],
  },
  {
    name: 'ic_shortcut_local',
    // 下载/落本地：直接用素材原始 SVG（48x48 网格）
    svg: 'svg-source/download.svg',
    box: SIZE * 0.52,
    fills: [],
    strokes: [],
  },
];

/* ---------------- 渲染 ---------------- */
function render(icon, file) {
  const box = icon.box || GLYPH_BOX;
  let fillDefs = icon.fills;
  let grid = 24;
  if (icon.svg) {
    const src = loadSvg(icon.svg);
    fillDefs = src.ds;
    grid = src.grid;
  }
  const polys = [];
  for (const d of fillDefs) polys.push(...toPixel(parsePath(d), grid, box));
  const strokes = icon.strokes.map(s => ({ polys: toPixel(parsePath(s.d), grid, box), w: s.w * (box / 24) }));

  const buf = Buffer.alloc(SIZE * SIZE * 4);
  const CX = SIZE / 2;
  const R = SIZE / 2 - 2;
  const step = 1 / SS;
  const samples = SS * SS;

  for (let y = 0; y < SIZE; y++) {
    for (let x = 0; x < SIZE; x++) {
      let redCov = 0, whiteCov = 0;
      for (let sy = 0; sy < SS; sy++) {
        for (let sx = 0; sx < SS; sx++) {
          const px = x + (sx + 0.5) * step;
          const py = y + (sy + 0.5) * step;
          if (Math.hypot(px - CX, py - CX) <= R) redCov++;
          let hit = false;
          if (polys.length && inFill(px, py, polys)) hit = true;
          if (!hit) {
            for (const s of strokes) {
              if (inStroke(px, py, s.polys, s.w)) { hit = true; break; }
            }
          }
          if (hit) whiteCov++;
        }
      }
      const a = redCov / samples;
      const wgt = whiteCov / samples;
      const idx = (y * SIZE + x) * 4;
      buf[idx] = Math.round(RED[0] + (255 - RED[0]) * wgt);
      buf[idx + 1] = Math.round(RED[1] + (255 - RED[1]) * wgt);
      buf[idx + 2] = Math.round(RED[2] + (255 - RED[2]) * wgt);
      buf[idx + 3] = Math.round(255 * a);
    }
  }
  writePng(file, buf, SIZE, SIZE);
  console.log('written', file);
}

const outDir = path.resolve(__dirname, '../entry/src/main/resources/base/media');
for (const icon of ICONS) render(icon, path.join(outDir, icon.name + '.png'));
