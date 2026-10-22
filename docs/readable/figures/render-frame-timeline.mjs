// Local SVG exporter for the Mermaid sequence subset used by this figure.
// Supports participants, ->>/-->> messages, notes, rect, alt/else, opt, par/and.
// This deliberately does not implement the full Mermaid language.
// Usage: node render-frame-timeline.mjs input.mmd output.svg [output.png sharp-module-path note.md]
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';

const [input, output, pngOutput, sharpModule, notePath] = process.argv.slice(2);
if (!input || !output) throw new Error('Provide input.mmd and output.svg.');
const source = fs.readFileSync(input, 'utf8');
const W = 1760, TOP = 194, STEP = 360, LEFT = 160, FONT = 19, LINE = 27;
const participants = [], entries = [], blocks = [], stack = [];
let y = TOP;
const measure = s => [...s].reduce((n, c) => n + (/[\u0000-\u007f]/.test(c) ? 0.55 : 1) * FONT, 0);
const wrap = (text, width) => {
  const result = [];
  for (const paragraph of text.split(/<br\s*\/?\s*>/i)) {
    let line = '';
    const tokens = paragraph.match(/[A-Za-z_][A-Za-z0-9_.]*|[\s\S]/gu) || [];
    for (const token of tokens) {
      if (line && measure(line + token) > width) { result.push(line.trimEnd()); line = ''; }
      line += token;
    }
    result.push(line);
  }
  return result;
};
const pos = id => {
  const index = participants.findIndex(p => p.id === id);
  if (index < 0) throw new Error(`Unknown participant ${id}`);
  return LEFT + index * STEP;
};
for (const original of source.split(/\r?\n/)) {
  const line = original.trim();
  if (!line || line === 'sequenceDiagram' || line.startsWith('%%')) continue;
  let m;
  if ((m = line.match(/^participant\s+(\w+)\s+as\s+(.+)$/))) {
    participants.push({ id: m[1], label: m[2] }); continue;
  }
  if ((m = line.match(/^(rect|alt|opt|par)\s+(.+)$/))) {
    const b = { kind: m[1], label: m[2], start: y, depth: stack.length };
    stack.push(b);
    if (b.kind === 'rect') { y += 14; }
    else { entries.push({ kind: 'blockHead', y, block: b }); y += 43; }
    continue;
  }
  if ((m = line.match(/^(else|and)\s+(.+)$/))) {
    if (!stack.length || !['alt', 'par'].includes(stack.at(-1).kind)) throw new Error(`Invalid branch ${line}`);
    entries.push({ kind: 'branch', y, label: m[2], depth: stack.length - 1 });
    y += 43; continue;
  }
  if (line === 'end') {
    const b = stack.pop();
    if (!b) throw new Error('Unmatched end');
    y += 14; b.end = y; blocks.push(b); y += b.kind === 'rect' ? 16 : 4;
    continue;
  }
  if ((m = line.match(/^Note over (\w+)(?:,(\w+))?:\s*(.+)$/i))) {
    const wide = Boolean(m[2]);
    const width = wide ? W - 140 : 300;
    const lines = wrap(m[3], width - 32);
    const height = lines.length * LINE + 24;
    entries.push({ kind: 'note', y, x: wide ? W / 2 : pos(m[1]), width, height, lines, wide });
    y += height + 18; continue;
  }
  if ((m = line.match(/^(\w+)(-->>|->>)(\w+):\s*(.+)$/))) {
    const x1 = pos(m[1]), x2 = pos(m[3]), self = x1 === x2;
    const lines = wrap(m[4], self ? 275 : Math.abs(x2 - x1) - 48);
    const height = lines.length * LINE + (self ? 44 : 26);
    entries.push({ kind: 'message', y, x1, x2, self, dashed: m[2] === '-->>', lines, height });
    y += height; continue;
  }
  throw new Error(`Unsupported Mermaid line: ${line}`);
}
if (stack.length) throw new Error('Unclosed sequence block');
if (participants.length !== 5) throw new Error('This figure layout expects five participants.');
const H = y + 60;
const xml = s => String(s).replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
const text = (lines, x, yy, anchor = 'middle', extra = '') =>
  `<text x="${x}" y="${yy}" text-anchor="${anchor}" ${extra}>${lines.map((s, i) => `<tspan x="${x}" dy="${i ? LINE : 0}">${xml(s)}</tspan>`).join('')}</text>`;
const svg = [
  `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}" role="img" aria-labelledby="title description">`,
  '<title id="title">Waylith 帧交接：等待、唤醒与返回</title>',
  '<desc id="description">五个参与者分四段展示：队列满与空、提交槽位和图像获取、CPU 与 GPU 并行推进，以及可选维护等待。各段分别阅读，不代表每帧经历全部等待。</desc>',
  '<defs><marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="8" markerHeight="8" orient="auto-start-reverse"><path d="M 0 0 L 10 5 L 0 10 z" fill="#34506a"/></marker></defs>',
  '<style>text{font-family:"Microsoft YaHei","Noto Sans CJK SC",sans-serif;font-size:19px;fill:#17324d}.small{font-size:17px}.heading{font-size:20px;font-weight:700}.title{font-size:31px;font-weight:700}.lane{stroke:#c2cbd5;stroke-width:1.2;stroke-dasharray:6 7}.message{stroke:#34506a;stroke-width:1.8;fill:none;marker-end:url(#arrow)}</style>',
  `<rect width="${W}" height="${H}" fill="#fff"/>`,
  text(['Waylith 帧交接：等待、唤醒与返回'], 42, 47, 'start', 'class="title"'),
  text(['实线：调用、请求或提交　｜　虚线：返回、等待解除或同步信号　｜　黄色：条件成立时的阻塞'], 44, 83, 'start', 'class="small"'),
  text(['箭头是同步关系示意；CPU 等待发生在调用线程，信号量等待随提交登记。各片段独立阅读，图高不表示耗时。'], 44, 112, 'start', 'class="small"')
];
for (const b of blocks.sort((a, b) => a.depth - b.depth || a.start - b.start)) {
  const x = 24 + b.depth * 12, width = W - x * 2;
  const fill = b.kind === 'rect' ? '#f6f8fc' : b.kind === 'par' ? '#edf5fc' : '#fffdf6';
  svg.push(`<rect x="${x}" y="${b.start}" width="${width}" height="${b.end - b.start}" rx="9" fill="${fill}" stroke="#c8d3df" stroke-width="1.2"/>`);
}
for (const p of participants) {
  const x = pos(p.id);
  svg.push(`<line class="lane" x1="${x}" y1="178" x2="${x}" y2="${H - 28}"/>`);
  svg.push(`<rect x="${x - 140}" y="133" width="280" height="48" rx="8" fill="#e9f0f7" stroke="#9eb1c4"/>`);
  svg.push(text([p.label], x, 164, 'middle', 'font-weight="700"'));
}
for (const e of entries) {
  if (e.kind === 'blockHead') {
    const { block: b } = e, x = 38 + b.depth * 12;
    svg.push(`<rect x="${x}" y="${e.y + 4}" width="55" height="28" rx="4" fill="${b.kind === 'par' ? '#d3e7f7' : '#f3e7bd'}"/>`);
    svg.push(text([b.kind], x + 27, e.y + 25, 'middle', 'class="small" font-weight="700"'));
    svg.push(text([b.label], x + 70, e.y + 26, 'start', 'class="small"'));
  } else if (e.kind === 'branch') {
    const x = 38 + e.depth * 12;
    svg.push(`<line x1="${x}" x2="${W - x}" y1="${e.y + 3}" y2="${e.y + 3}" stroke="#adbccc" stroke-dasharray="5 5"/>`);
    svg.push(`<rect x="${x + 8}" y="${e.y + 8}" width="${Math.min(W - x * 2 - 20, measure(e.label) + 26)}" height="27" fill="#fff"/>`);
    svg.push(text([e.label], x + 20, e.y + 29, 'start', 'class="small" font-weight="700"'));
  } else if (e.kind === 'note') {
    const left = Math.max(36, Math.min(W - e.width - 36, e.x - e.width / 2));
    const waiting = !e.wide && /阻塞|渲染线程等待|主线程等待/.test(e.lines.join(''));
    const fill = waiting ? '#fff0c7' : '#e4edf6', stroke = waiting ? '#d2a74e' : '#c2d3e4';
    svg.push(`<rect x="${left}" y="${e.y}" width="${e.width}" height="${e.height}" rx="7" fill="${fill}" stroke="${stroke}"/>`);
    svg.push(text(e.lines, left + e.width / 2, e.y + 30, 'middle', e.wide ? 'class="heading"' : ''));
  } else if (e.kind === 'message') {
    const lineY = e.y + e.lines.length * LINE + 8;
    if (e.self) {
      const side = e.x1 > W - 380 ? -1 : 1;
      const labelX = e.x1 + side * 24, anchor = side === 1 ? 'start' : 'end';
      const width = Math.max(...e.lines.map(measure)) + 14;
      const bx = side === 1 ? labelX - 7 : labelX - width + 7;
      svg.push(`<rect x="${bx}" y="${e.y + 2}" width="${width}" height="${e.lines.length * LINE}" fill="#fff" fill-opacity="0.94" rx="3"/>`);
      svg.push(text(e.lines, labelX, e.y + 23, anchor));
      svg.push(`<path class="message" d="M ${e.x1} ${lineY} h ${side * 98} v 23 h ${-side * 98}" ${e.dashed ? 'stroke-dasharray="7 5"' : ''}/>`);
    } else {
      const mid = (e.x1 + e.x2) / 2, width = Math.max(...e.lines.map(measure)) + 18;
      svg.push(`<rect x="${mid - width / 2}" y="${e.y + 2}" width="${width}" height="${e.lines.length * LINE}" fill="#fff" fill-opacity="0.94" rx="3"/>`);
      svg.push(text(e.lines, mid, e.y + 23));
      svg.push(`<line class="message" x1="${e.x1}" y1="${lineY}" x2="${e.x2}" y2="${lineY}" ${e.dashed ? 'stroke-dasharray="7 5"' : ''}/>`);
    }
  }
}
svg.push(text(['正常成功路径与条件片段的源码关系示意；没有假设具体等待时长或固定的跨线程先后。'], 44, H - 13, 'start', 'class="small"'));
svg.push('</svg>');
fs.writeFileSync(output, svg.join('\n') + '\n', 'utf8');
const summary = { svg: path.resolve(output), width: W, height: H };
if (notePath) {
  const note = fs.readFileSync(notePath, 'utf8');
  const pattern = /```mermaid\r?\n[\s\S]*?\r?\n```/;
  if (!pattern.test(note)) throw new Error('The note has no Mermaid block to synchronize.');
  fs.writeFileSync(notePath, note.replace(pattern, () => '```mermaid\n' + source.trim() + '\n```'), 'utf8');
  summary.note = path.resolve(notePath);
}
if (pngOutput) {
  if (!sharpModule) throw new Error('Provide sharp-module-path for PNG preview export.');
  const sharp = createRequire(import.meta.url)(sharpModule);
  await sharp(Buffer.from(svg.join('\n'))).png().toFile(pngOutput);
  summary.png = path.resolve(pngOutput);
}
console.log(JSON.stringify(summary));
