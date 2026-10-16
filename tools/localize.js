#!/usr/bin/env node
// Localization helper for Pocket Goblin.
//
//   node tools/localize.js wrap [--dry]   wrap player-facing strings in L["..."]
//   node tools/localize.js template       write Locales/template.lua (every L[] key)
//
// Needs luaparse: npm install luaparse@0.3.1
// "wrap" is a one-time conversion; new code should use L["..."] directly.

const fs = require('fs');
const path = require('path');
const lp = require('luaparse');

const ROOT = path.join(__dirname, '..');
const FILES = ['PocketGoblin.lua', 'UI.lua', 'Voice.lua', 'MerchantPanel.lua', 'DestroyButton.lua', 'OpenButton.lua', 'BagSort.lua', 'Minimap.lua'];

// Strings that look like text but aren't: brand, widget types, saved values.
const NEVER = new Set(['Pocket Goblin', '|cffd4a72cPocket|r Goblin', '|cffd4a72cPocket Goblin|r: ', 'Default', 'Frame', 'Button',
  'EditBox', 'Slider', 'ScrollFrame', 'EventFrame', 'CheckButton', 'Version',
  'Baganator', 'Bagnon', 'AdiBags', 'ArkInventory', 'BetterBags', 'Combuctor', 'OneBag3']);
// Calls whose string arguments are never shown as text.
const SKIP_CALLS = new Set(['CreateFrame', 'SetScript', 'HookScript', 'RegisterEvent', 'UnregisterEvent',
  'hooksecurefunc', 'RegisterForClicks', 'RegisterForDrag', 'SetPoint', 'CreateTexture', 'CreateFontString',
  'SetFrameStrata', 'SetBlendMode', 'date', 'IsAddOnLoaded', 'GetAddOnMetadata', 'SetFont', 'SetAtlas',
  'SetTexture', 'Icon', 'Rounded', 'SetHighlightTexture', 'RegisterRegion', 'RegisterJunkPlugin',
  'RegisterCanvasLayoutCategory', 'GetItemInfo', 'tostring']);
// Developer-only output stays English.
const SKIP_FUNCTIONS = new Set(['Debug', 'DebugDestroyButtons', 'FrameName']);

// Files are UTF-8; reading them as latin1 keeps every byte as-is for the parser.
const read = (file) => fs.readFileSync(path.join(ROOT, file), 'latin1');

function parse(source) {
  return lp.parse(source, { luaVersion: '5.1', ranges: true, comments: false, encodingMode: 'pseudo-latin1' });
}

// Raw inner text of a string literal, or of a concatenation of literals.
function literalText(node, source) {
  if (node.type === 'StringLiteral') {
    const raw = source.slice(node.range[0], node.range[1]);
    if (raw[0] !== '"' && raw[0] !== "'") return null; // long strings: leave alone
    let inner = raw.slice(1, -1);
    if (raw[0] === "'") inner = inner.replace(/\\'/g, "'").replace(/"/g, '\\"');
    return inner;
  }
  if (node.type === 'BinaryExpression' && node.operator === '..') {
    const left = literalText(node.left, source), right = literalText(node.right, source);
    return left !== null && right !== null ? left + right : null;
  }
  return null;
}

function isText(inner) {
  if (NEVER.has(inner)) return false;
  if (/^\/goblin/.test(inner) && !/ - /.test(inner)) return false; // command names stay as typed
  const plain = inner.replace(/\|c[0-9a-fA-F]{8}|\|r/g, '').replace(/%[-0-9.]*[a-zA-Z%]/g, '');
  if (!/[A-Za-z]/.test(plain)) return false;
  if (/\\\\/.test(inner)) return false; // file paths
  if (/[ ]/.test(plain.trim()) || /^[A-Z][a-z]+[.!?:]?$/.test(plain.trim())) return true;
  return /^[A-Z]{2,}$/.test(plain.trim()) && ['YOU'].includes(plain.trim());
}

function calleeName(call) {
  const base = call.base;
  if (base.type === 'Identifier') return base.name;
  if (base.type === 'MemberExpression') return base.identifier.name;
  return null;
}

function findWraps(source) {
  const ast = parse(source);
  const wraps = [];
  function visit(node, ctx) {
    if (!node || typeof node !== 'object') return;
    if (Array.isArray(node)) { node.forEach((n) => visit(n, ctx)); return; }
    if (node.type === 'FunctionDeclaration' && node.identifier) {
      const name = node.identifier.type === 'Identifier' ? node.identifier.name
        : node.identifier.identifier && node.identifier.identifier.name;
      if (SKIP_FUNCTIONS.has(name)) return;
    }
    if ((node.type === 'CallExpression' || node.type === 'StringCallExpression') && SKIP_CALLS.has(calleeName(node))) {
      // Literal arguments are identifiers, not text; but look inside the
      // rest (e.g. the handler function given to SetScript).
      visit(node.base, ctx);
      for (const arg of node.arguments || []) {
        if (literalText(arg, source) === null) visit(arg, ctx);
      }
      return;
    }
    if (node.type === 'IndexExpression' && node.base.type === 'Identifier' && node.base.name === 'L') return;
    if (node.type === 'BinaryExpression' && (node.operator === '==' || node.operator === '~=')) return;
    if (node.type === 'TableKey') { visit(node.value, ctx); return; }
    const inner = literalText(node, source);
    if (inner !== null) {
      if (isText(inner)) wraps.push({ start: node.range[0], end: node.range[1], inner });
      return;
    }
    for (const key of Object.keys(node)) {
      if (key === 'range' || key === 'loc') continue;
      visit(node[key], ctx);
    }
  }
  visit(ast, {});
  return wraps;
}

function wrap(dry) {
  let total = 0;
  for (const file of FILES) {
    let source = read(file);
    const wraps = findWraps(source).sort((a, b) => b.start - a.start);
    total += wraps.length;
    if (dry) {
      for (const w of wraps.slice().reverse()) console.log(`${file}: ${w.inner.slice(0, 90)}`);
      continue;
    }
    for (const w of wraps) {
      source = source.slice(0, w.start) + 'L[' + source.slice(w.start, w.end) + ']' + source.slice(w.end);
    }
    if (!/\nlocal L = ns\.L\n/.test(source)) {
      source = source.replace(/(local [A-Z_]+, ns = \.\.\.\n)/, '$1local L = ns.L\n');
    }
    fs.writeFileSync(path.join(ROOT, file), source, 'latin1');
  }
  console.log(`${dry ? 'Would wrap' : 'Wrapped'} ${total} strings.`);
}

function template() {
  const keys = new Map(); // inner text -> files
  for (const file of FILES) {
    const source = read(file);
    (function visit(node) {
      if (!node || typeof node !== 'object') return;
      if (Array.isArray(node)) { node.forEach(visit); return; }
      if (node.type === 'IndexExpression' && node.base.type === 'Identifier' && node.base.name === 'L') {
        const inner = literalText(node.index, source);
        if (inner !== null) {
          if (!keys.has(inner)) keys.set(inner, new Set());
          keys.get(inner).add(file);
        }
      }
      for (const key of Object.keys(node)) if (key !== 'range' && key !== 'loc') visit(node[key]);
    })(parse(source));
  }
  const lines = [...keys.keys()].sort((a, b) => a.localeCompare(b)).map((k) => `    ["${k}"] = "",`);
  const out = `-- Translation template for Pocket Goblin. Generated by tools/localize.js; don't edit.
--
-- To translate: copy this file to Locales/<locale>.lua (e.g. deDE.lua), change
-- the locale below, fill in the translations (leave out any you skip; they
-- stay English) and add the file to PocketGoblin.toc after Locales/Locales.lua.
-- Keep %s, %d and |c...|r codes as they are.

local _, ns = ...

ns.AddTranslations("xxXX", {
${lines.join('\n')}
})
`;
  fs.mkdirSync(path.join(ROOT, 'Locales'), { recursive: true });
  fs.writeFileSync(path.join(ROOT, 'Locales', 'template.lua'), out, 'latin1');
  console.log(`Wrote ${keys.size} strings to Locales/template.lua`);
}

const [command, flag] = process.argv.slice(2);
if (command === 'wrap') wrap(flag === '--dry');
else if (command === 'template') template();
else console.log('Usage: node tools/localize.js wrap [--dry] | template');
