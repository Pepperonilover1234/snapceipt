// Reads a typed line like "Pop corn 60", "ข้าวมันไก่ 50 เมื่อวาน" or "เงินเดือน 30000".
// A port of the app's QuickEntryRules (Keptang/Intelligence/QuickEntry.swift), with the same keyword
// lists (keywords.json is exported from the app) and the same test cases, so the bot and the app
// understand a line the same way. Amounts only ever come from what was typed.

import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const keywords = require('./keywords.json');

export const CATEGORY_NAMES = {
  groceries: 'Groceries',
  dining: 'Food & Drinks',
  transport: 'Transportation',
  shopping: 'Shopping',
  health: 'Health',
  home: 'Home',
  utilities: 'Utilities',
  entertainment: 'Entertainment',
  subscriptions: 'Subscriptions',
  education: 'Education',
  other: 'Other',
};

/** The categories people can choose, in the app's order. */
export const SELECTABLE = ['dining', 'groceries', 'utilities', 'transport', 'shopping', 'health', 'entertainment', 'subscriptions', 'education', 'other'];

export const INCOME_NAMES = {
  salary: 'Salary',
  freelance: 'Freelance & side work',
  sales: 'Sold something',
  gift: 'Gift & allowance',
  refund: 'Refund',
  investment: 'Interest & dividends',
  other: 'Other income',
};

const MERCHANT_CATEGORY = {
  supermarket: 'groceries',
  restaurant: 'dining',
  transport: 'transport',
  subscription: 'subscriptions',
  education: 'education',
  entertainment: 'entertainment',
  health: 'health',
  utility: 'utilities',
};

const isThai = (ch) => { const c = ch.codePointAt(0); return c >= 0x0e00 && c <= 0x0e7f; };
const isLatinKeyword = (word) => [...word].every((ch) => ch.codePointAt(0) < 0x0e00);

/** Lower case, single spaces, accents folded on Latin letters only (Thai marks change the word). */
export function normalize(text) {
  const folded = [...text].map((ch) => (isThai(ch) ? ch : ch.normalize('NFKD').replace(/[̀-ͯ]/g, '').toLowerCase())).join('');
  return folded.replace(/’/g, "'").replace(/\s+/g, ' ').trim();
}

function latinWords(name) {
  return ' ' + name.replace(/[^a-z0-9'.+&-]+/g, ' ') + ' ';
}

function matches(keyword, name, words) {
  return isLatinKeyword(keyword) ? words.includes(` ${keyword} `) : name.includes(keyword);
}

export function merchantType(shopName) {
  const name = normalize(shopName);
  if (!name) return null;
  const words = latinWords(name);
  for (const [type, list] of keywords.merchants) {
    if (list.some((k) => matches(k, name, words))) return type;
  }
  return null;
}

/** Keyword guess on the item name, checked in the app's order. Never a legacy category. */
export function keywordGuess(name) {
  const key = normalize(name);
  for (const [category, list] of keywords.itemKeywords) {
    if (list.some((word) => key.includes(word))) return category === 'home' ? 'shopping' : category;
  }
  return null;
}

/** The merchant's own category for shops that only sell one kind of thing, then keywords. */
function categoryOnce(name) {
  const type = merchantType(name);
  if (type && type !== 'supermarket') return MERCHANT_CATEGORY[type];
  const guess = keywordGuess(name) ?? 'other';
  if (type === 'supermarket' && guess === 'other') return 'groceries';
  return guess;
}

/** Tried again with the spaces taken out, so "pop corn" finds "popcorn". */
export function categoryFor(name) {
  const first = categoryOnce(name);
  if (first !== 'other') return first;
  const joined = name.replace(/ /g, '');
  return joined === name ? first : categoryOnce(joined);
}

/** Where income came from, if the words say. "ร้านขายยา" (a pharmacy) is a shop, not a sale. */
export function incomeSource(text) {
  const t = normalize(text).replace(/ร้านขาย/g, ' ').replace(/ขายยา/g, ' ');
  const words = ' ' + t.replace(/[^a-z0-9']+/g, ' ') + ' ';
  for (const [source, list] of keywords.incomeKeywords) {
    for (const k of list) {
      if (isLatinKeyword(k) ? words.includes(` ${k} `) : t.includes(k)) return source;
    }
  }
  return null;
}

export function flowOf(text) {
  const t = text.trim();
  if (t.startsWith('+')) return 'moneyIn';
  if (t.startsWith('-')) return 'moneyOut';
  return incomeSource(t) ? 'moneyIn' : 'moneyOut';
}

const DATE_WORDS = [
  [['เมื่อวานซืน', 'day before yesterday'], 2],
  [['เมื่อวาน', 'เมื่อคืน', 'yesterday', 'last night'], 1],
  [['วันนี้', 'today', 'tonight', 'คืนนี้'], 0],
];

const AMOUNT = /(\d[\d,]*(?:\.\d+)?)\s*(k|พัน|หมื่น|แสน)?(?!\d)/giu;

function amounts(text) {
  return [...text.matchAll(AMOUNT)];
}

/** Pieces split at commas, new lines and semicolons, then at "and", "และ" and "+" where both sides have a price. */
export function chunks(text) {
  const grouped = text.replace(/(\d),(?=\d{3}(?!\d))/g, '$1');
  return grouped
    .split(/[,;\n、]/)
    .flatMap((part) => (amounts(part).length > 1 ? part.replace(/\s+(and|&|\+)\s+|และ/g, '\u0001').split('\u0001') : [part]))
    .map((p) => p.trim())
    .filter(Boolean);
}

function cleanName(text) {
  let name = text;
  for (const word of ['บาท', 'baht', 'bht', 'thb', '฿', 'ค่า ']) name = name.split(word).join(' ');
  return name.replace(/\s+/g, ' ').trim().replace(/^[\s\-:x×@=.]+|[\s\-:x×@=.]+$/g, '');
}

/** The last number in a piece is its price ("2 coffee 90" costs 90); the rest is its name. */
export function nameAndAmount(chunk) {
  const found = amounts(chunk);
  if (!found.length) return [cleanName(chunk), null];
  const m = found[found.length - 1];
  let value = Number(m[1].replace(/,/g, ''));
  switch ((m[2] ?? '').toLowerCase()) {
    case 'k': case 'พัน': value *= 1_000; break;
    case 'หมื่น': value *= 10_000; break;
    case 'แสน': value *= 100_000; break;
  }
  const name = chunk.slice(0, m.index) + chunk.slice(m.index + m[0].length);
  return [cleanName(name), value];
}

export function language(text) {
  const thai = [...text].some(isThai);
  const latin = /[A-Za-z]/.test(text);
  if (thai && latin) return 'Thai and English';
  if (thai) return 'Thai';
  if (latin) return 'English';
  return 'numbers only';
}

/**
 * Reads one typed line.
 * @returns {{flow: 'moneyOut'|'moneyIn', items: {name: string, amount: number, category: string}[],
 *            source: string, daysAgo: number, text: string, language: string, total: number}}
 */
export function readEntry(text) {
  const trimmed = text.trim();
  let working = normalize(trimmed);
  const flow = flowOf(working);
  const source = incomeSource(working) ?? 'other';
  if (working.startsWith('+') || working.startsWith('-')) working = working.slice(1);

  let daysAgo = 0;
  for (const [words, days] of DATE_WORDS) {
    for (const word of words) {
      if (working.includes(word)) {
        daysAgo = Math.max(daysAgo, days);
        working = working.split(word).join(' ');
      }
    }
  }

  let items = [];
  let pending = '';
  for (const chunk of chunks(working)) {
    const [name, amount] = nameAndAmount(chunk);
    if (amount === null) {
      pending = [pending, name].filter(Boolean).join(' & ');
      continue;
    }
    const full = [pending, name].filter(Boolean).join(' & ');
    pending = '';
    items.push({ name: full, amount, category: categoryFor(full) });
  }
  if (pending && !items.length) items.push({ name: pending, amount: 0, category: categoryFor(pending) });

  if (flow === 'moneyIn') {
    const total = items.reduce((sum, i) => sum + i.amount, 0);
    const name = items.map((i) => i.name).filter(Boolean).join(', ');
    items = [{ name: name || INCOME_NAMES[source], amount: total, category: 'other' }];
  }
  const total = items.reduce((sum, i) => sum + i.amount, 0);
  return { flow, items, source, daysAgo, text: trimmed, language: language(trimmed), total };
}

/** ฿1,290.00 */
export function baht(value) {
  return '฿' + value.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

/** ฿1,290 */
export function bahtWhole(value) {
  return '฿' + Math.round(value).toLocaleString('en-US');
}
