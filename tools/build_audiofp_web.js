/*
 * 把浏览器版 AFP 引擎（afp.js + afp.wasm.js）内联成单文件 HTML，
 * 放进 rawfile 供 ArkWeb 离线加载。单文件是为了规避 resource:// 下的
 * 跨目录/CORS 限制（ES Module + 相对资源在 rawfile 里不可靠）。
 *
 * 用法：node tools/build_audiofp_web.js
 */
const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const srcDir = path.join(__dirname, 'audiofp-web');
const outFile = path.join(root, 'entry/src/main/resources/rawfile/audiofp/index.html');

function readEngine() {
  let wasm = fs.readFileSync(path.join(srcDir, 'afp.wasm.js'), 'utf8');
  let glue = fs.readFileSync(path.join(srcDir, 'afp.js'), 'utf8');

  // 去掉 ES Module 语法，改为同一个 IIFE 内的普通作用域。
  wasm = wasm
    .replace(/^export \{ WASM_BINARY \};?\s*$/m, '')
    .replace(/if \(typeof exports != 'undefined'\)\s*\n\s*exports\.WASM_BINARY = WASM_BINARY;?/, '');
  glue = glue
    .replace(/^import \{ WASM_BINARY \} from '\.\/afp\.wasm\.js'\s*$/m, '')
    .replace(/^export \{ GenerateFP \};?\s*$/m, '');

  return `(function () {\n${wasm}\n${glue}\nwindow.GenerateFP = GenerateFP;\n})();`;
}

const bridge = `
(function () {
  var chunks = [];
  var busy = false;
  var NEED = 24000;   // 3 秒 @ 8kHz
  var RATE = 8000;

  function b64ToBytes(b64) {
    var bin = atob(b64);
    var out = new Uint8Array(bin.length);
    for (var i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out;
  }

  function fail(e) {
    busy = false;
    chunks = [];
    var msg = e && (e.message || e) ? String(e.message || e) : '指纹计算失败';
    try { afpBridge.onError(msg); } catch (_) {}
  }

  // ---- 原始 PCM 通道（麦克风采集）----
  function runPcmJob() {
    busy = true;
    var b64 = chunks.join('');
    chunks = [];
    try {
      var bytes = b64ToBytes(b64);
      var pcm = new Float32Array(bytes.buffer, bytes.byteOffset, bytes.length >> 2);
      window.GenerateFP(pcm).then(function (fp) {
        busy = false;
        try { afpBridge.onFp(fp); } catch (e) { fail(e); }
      }).catch(fail);
    } catch (e) {
      fail(e);
    }
  }

  // ---- 音频文件通道（媒体选择器选的本机文件）----
  function resample(input, from, to) {
    if (!from || from === to) return input;
    var ratio = from / to;
    var len = Math.max(1, Math.floor(input.length / ratio));
    var out = new Float32Array(len);
    for (var i = 0; i < len; i++) {
      var start = i * ratio;
      var end = start + ratio;
      var j = Math.floor(start);
      var sum = 0;
      var weight = 0;
      while (j < end && j < input.length) {
        var w = Math.min(end, j + 1) - Math.max(start, j);
        if (w > 0) { sum += input[j] * w; weight += w; }
        j++;
      }
      out[i] = weight > 0 ? sum / weight : 0;
    }
    return out;
  }

  function toMono(buffer) {
    var channels = buffer.numberOfChannels;
    var len = buffer.length;
    var out = new Float32Array(len);
    if (channels <= 1) {
      out.set(buffer.getChannelData(0));
      return out;
    }
    for (var c = 0; c < channels; c++) {
      var data = buffer.getChannelData(c);
      for (var i = 0; i < len; i++) out[i] += data[i];
    }
    for (var k = 0; k < len; k++) out[k] /= channels;
    return out;
  }

  function decodeAudio(bytes) {
    var Ctor = window.AudioContext || window.webkitAudioContext;
    if (!Ctor) return Promise.reject(new Error('当前环境不支持音频解码'));
    var ctx;
    try { ctx = new Ctor({ sampleRate: RATE }); } catch (_) { ctx = new Ctor(); }
    return new Promise(function (resolve, reject) {
      var copy = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
      var settled = false;
      var ok = function (buf) { if (!settled) { settled = true; resolve(buf); } };
      // 解码失败大多是格式/编码不被浏览器支持，直接给用户可读的提示。
      var bad = function () { if (!settled) { settled = true; reject(new Error('无法解码这段音频，请换 MP3 / M4A / WAV 文件')); } };
      var pending;
      try { pending = ctx.decodeAudioData(copy, ok, bad); } catch (e) { bad(e); }
      if (pending && typeof pending.then === 'function') pending.then(ok, bad);
    }).then(function (buf) {
      try { ctx.close(); } catch (_) {}
      return buf;
    });
  }

  // 文件可能很长，挑能量最大的一段 3 秒，命中率比固定取开头高。
  function pickSegment(pcm) {
    if (pcm.length === 0) throw new Error('音频文件没有可用的声音');
    if (pcm.length <= NEED) {
      var loop = new Float32Array(NEED);
      for (var i = 0; i < NEED; i++) loop[i] = pcm[i % pcm.length];
      return loop;
    }
    var step = 4000;
    var best = 0;
    var bestScore = -1;
    for (var start = 0; start + NEED <= pcm.length; start += step) {
      var sum = 0;
      for (var j = start; j < start + NEED; j += 6) sum += pcm[j] * pcm[j];
      if (sum > bestScore) { bestScore = sum; best = start; }
    }
    return pcm.slice(best, best + NEED);
  }

  function runFileJob() {
    busy = true;
    var b64 = chunks.join('');
    chunks = [];
    var bytes;
    try { bytes = b64ToBytes(b64); } catch (e) { return fail(e); }
    decodeAudio(bytes).then(function (buffer) {
      var mono = toMono(buffer);
      var pcm = resample(mono, buffer.sampleRate, RATE);
      var peak = 0;
      for (var i = 0; i < pcm.length; i += 4) {
        var v = Math.abs(pcm[i]);
        if (v > peak) peak = v;
      }
      if (peak < 0.0008) throw new Error('这段音频没有声音，请换一个文件');
      return window.GenerateFP(pickSegment(pcm));
    }).then(function (fp) {
      busy = false;
      try { afpBridge.onFp(fp); } catch (e) { fail(e); }
    }).catch(fail);
  }

  function tick() {
    if (busy || !window.afpBridge) return;
    var msg;
    try { msg = afpBridge.poll(); } catch (_) { return; }
    if (!msg) return;
    var tag = msg.charAt(0);
    var body = msg.slice(1);
    if (tag === 'S') { chunks = [body]; }
    else if (tag === 'C') { chunks.push(body); }
    else if (tag === 'E') { runPcmJob(); }
    else if (tag === 'F') { chunks = [body]; }
    else if (tag === 'G') { chunks.push(body); }
    else if (tag === 'H') { runFileJob(); }
  }

  setInterval(tick, 10);

  window.addEventListener('error', function (e) {
    try { afpBridge.onError(String(e.message || 'js error')); } catch (_) {}
  });

  // 预热一次，确认 WebAssembly 可用并让引擎完成首次编译。
  window.GenerateFP(new Float32Array(8000)).then(function () {
    try { afpBridge.onReady(); } catch (_) {}
  }).catch(function (e) {
    try { afpBridge.onError('engine init: ' + String(e && (e.message || e))); } catch (_) {}
  });
})();
`;

const html = `<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>AFP Engine</title>
<style>html,body{margin:0;padding:0;background:#000;overflow:hidden}</style>
</head>
<body>
<script>
${readEngine()}
</script>
<script>
${bridge}
</script>
</body>
</html>
`;

fs.mkdirSync(path.dirname(outFile), { recursive: true });
fs.writeFileSync(outFile, html);
console.log('written', outFile, (html.length / 1024).toFixed(0) + 'KB');
