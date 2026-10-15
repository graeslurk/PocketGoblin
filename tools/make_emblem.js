#!/usr/bin/env node
// Renders the emblem (Art/pocket-goblin-logo.svg) for Pocket Goblin:
//
//   Media/emblem.tga             128x128 full colour (navy disc), shown in-game at 48-56px
//   Media/emblem-mono.tga        64x64 white shape, tinted gold in-game at 22-24px
//   Media/icon.tga               64x64 gold shape, for the AddOns list and minimap button
//   Art/pocket-goblin-logo.png   512x512 full colour (navy disc), the CurseForge/GitHub project logo
//
//   node tools/make_emblem.js
//
// Needs resvg: npm install @resvg/resvg-js@2.6.2

const fs = require('fs');
const path = require('path');
const { Resvg } = require('@resvg/resvg-js');

const ROOT = path.join(__dirname, '..');
const svg = fs.readFileSync(path.join(ROOT, 'Art', 'pocket-goblin-logo.svg'), 'utf8');

// The emblem's gold and green fills. In the one-colour version these become
// the shape; the dark lines, whites and creams are cut out of it.
const FILLED = ['#EFB03D', '#E39C35', '#B17230', '#5FB48E', '#5BAB82'];
// The ring starts here (as a fraction of the radius) and is left off the
// one-colour version, so the goblin and pot fill the small icons.
const RING = 0.88;
// The drawing's white disc behind the goblin becomes deep navy, lighter in
// the middle: the gold and green stand out on it, and it sets Pocket Goblin
// apart from the other addons' logos. Used in-game and for the project logo.
const DISC = '<radialGradient id="disc" cx="50%" cy="45%" r="60%">'
  + '<stop offset="0" stop-color="#2C3B66"/><stop offset="1" stop-color="#141B33"/></radialGradient>';

// The disc is the large white paths; the small ones are teeth and eye whites.
function navyDisc(source) {
  return source
    .replace(/<path fill="#FEFEFD" d="([^"]*)"/g, (path, d) => {
      const xs = d.match(/-?\d+(?:\.\d+)?/g).map(Number).filter((_, i) => i % 2 === 0);
      return Math.max(...xs) - Math.min(...xs) > 300 ? `<path fill="url(#disc)" d="${d}"` : path;
    })
    .replace(/(<svg[^>]*>)/, `$1<defs>${DISC}</defs>`);
}

function render(source, size) {
  return new Resvg(source, { fitTo: { mode: 'width', value: size } }).render();
}

// 32-bit uncompressed TGA, top-left origin, like tools/make_media.py writes.
// rgba: straight (not premultiplied) RGBA bytes, rows top to bottom.
function writeTga(file, size, rgba) {
  const header = Buffer.alloc(18);
  header[2] = 2;                 // uncompressed true-colour
  header.writeUInt16LE(size, 12);
  header.writeUInt16LE(size, 14);
  header[16] = 32;
  header[17] = 0x28;             // 8 alpha bits, rows top to bottom
  const bgra = Buffer.alloc(size * size * 4);
  for (let i = 0; i < bgra.length; i += 4) {
    bgra[i] = rgba[i + 2];
    bgra[i + 1] = rgba[i + 1];
    bgra[i + 2] = rgba[i];
    bgra[i + 3] = rgba[i + 3];
  }
  fs.writeFileSync(file, Buffer.concat([header, bgra]));
}

// Full colour. resvg gives premultiplied RGBA, so undo that for the TGA.
function colourPixels(source, size) {
  const pixels = render(source, size).pixels;
  const rgba = Buffer.alloc(pixels.length);
  for (let i = 0; i < rgba.length; i += 4) {
    const a = pixels[i + 3];
    for (let c = 0; c < 3; c++) rgba[i + c] = a ? Math.min(255, Math.round((pixels[i + c] * 255) / a)) : 0;
    rgba[i + 3] = a;
  }
  return rgba;
}

// One colour: coverage (0-1) of the gold and green areas inside the ring,
// cropped to a square around them and box-filtered down to size.
function monoCoverage(size) {
  const N = 1024;
  const flat = svg.replace(/fill="(#[0-9A-Fa-f]{6})"/g,
    (_, c) => `fill="${FILLED.includes(c.toUpperCase()) ? '#FFFFFF' : '#000000'}"`);
  const pixels = render(flat, N).pixels;
  const full = new Float32Array(N * N);
  let x0 = N, y0 = N, x1 = 0, y1 = 0;
  for (let y = 0; y < N; y++) {
    for (let x = 0; x < N; x++) {
      if (Math.hypot(x + 0.5 - N / 2, y + 0.5 - N / 2) > RING * N / 2) continue;
      const v = pixels[(y * N + x) * 4] / 255; // premultiplied white = coverage
      full[y * N + x] = v;
      if (v > 0.5) {
        x0 = Math.min(x0, x); x1 = Math.max(x1, x);
        y0 = Math.min(y0, y); y1 = Math.max(y1, y);
      }
    }
  }
  const side = (Math.max(x1 - x0, y1 - y0) + 1) * 1.02; // a little room for filtering
  const left = (x0 + x1 + 1) / 2 - side / 2, top = (y0 + y1 + 1) / 2 - side / 2;
  const step = side / size;
  const coverage = new Float32Array(size * size);
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      let sum = 0, count = 0;
      for (let j = Math.floor(top + y * step); j < top + (y + 1) * step; j++) {
        for (let i = Math.floor(left + x * step); i < left + (x + 1) * step; i++) {
          count++;
          if (i >= 0 && j >= 0 && i < N && j < N) sum += full[j * N + i];
        }
      }
      coverage[y * size + x] = sum / count;
    }
  }
  return coverage;
}

function tinted(coverage, [r, g, b]) {
  const rgba = Buffer.alloc(coverage.length * 4);
  coverage.forEach((v, i) => rgba.set([r, g, b, Math.round(v * 255)], i * 4));
  return rgba;
}

const logo = navyDisc(svg);
writeTga(path.join(ROOT, 'Media', 'emblem.tga'), 128, colourPixels(logo, 128));
const mono = monoCoverage(64);
writeTga(path.join(ROOT, 'Media', 'emblem-mono.tga'), 64, tinted(mono, [255, 255, 255]));
writeTga(path.join(ROOT, 'Media', 'icon.tga'), 64, tinted(mono, [212, 167, 44])); // not tinted in-game
fs.writeFileSync(path.join(ROOT, 'Art', 'pocket-goblin-logo.png'), render(logo, 512).asPng());
