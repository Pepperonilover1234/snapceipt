// The bot's conversations, end to end, against the in-memory store.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { makeHandlers, dateFor, sentence } from '../src/handlers.js';
import { memoryStore } from '../src/store.js';

const now = new Date('2026-10-18T11:30:00Z'); // 18:30 in Bangkok
const setup = () => {
  const store = memoryStore();
  const handle = makeHandlers(store, { now: () => now, fetchImage: async () => Buffer.from('jpeg') });
  store.codes.set('482913', { userId: 'user-1', expires: Date.now() + 60_000 });
  return { store, handle };
};
const json = (payload) => JSON.parse(JSON.stringify(payload));

test('Unlinked people are told how to link', async () => {
  const { handle } = setup();
  const reply = await handle.text('discord-1', 'Pop corn 60');
  assert.match(reply.content, /Connect Discord/);
});

test('Linking with the 6-digit code, and a wrong or expired code', async () => {
  const { store, handle } = setup();
  assert.match((await handle.link('discord-1', 'riv', '000000')).content, /didn’t work/);
  assert.match((await handle.link('discord-1', 'riv', '12')).content, /6 digits/);
  assert.match((await handle.link('discord-1', 'riv', '482 913')).content, /Linked/);
  assert.equal(await store.userFor('discord', 'discord-1'), 'user-1');
  assert.equal(store.codes.size, 0, 'a code works once');
  await handle.unlink('discord-1');
  assert.equal(await store.userFor('discord', 'discord-1'), null);
});

test('A typed line becomes a pending card; changing the category and saving confirms it', async () => {
  const { store, handle } = setup();
  await handle.link('discord-1', 'riv', '482913');
  const card = json(await handle.text('discord-1', 'Pop corn 60'));
  assert.match(card.embeds[0].title, /Money out · ฿60\.00/);
  assert.equal(card.embeds[0].description, 'You spent ฿60.00 on pop corn (Entertainment) today.');
  const [row] = [...store.inbox.values()];
  assert.equal(row.status, 'pending');
  assert.equal(row.parsed.items[0].category, 'entertainment');
  const save = card.components[0].components[0].custom_id;
  assert.equal(save, `save:${row.id}`);

  const changed = json(await handle.component('discord-1', `cat:${row.id}:0`, ['dining']));
  assert.match(changed.embeds[0].description, /Food & Drinks/);
  const saved = json(await handle.component('discord-1', save));
  assert.match(saved.embeds[0].title, /Saved/);
  assert.equal(saved.components.length, 0);
  assert.equal(store.inbox.get(row.id).status, 'confirmed');
  assert.equal(store.inbox.get(row.id).parsed.items[0].category, 'dining');
  assert.match((await handle.component('discord-1', save)).content, /already done/);
});

test('Money in, flipping in and out, and the income source menu', async () => {
  const { store, handle } = setup();
  await handle.link('discord-1', 'riv', '482913');
  const card = json(await handle.text('discord-1', 'เงินเดือน 30000'));
  assert.match(card.embeds[0].title, /Money in · ฿30,000\.00/);
  const [row] = [...store.inbox.values()];
  assert.equal(row.parsed.source, 'salary');
  const flipped = json(await handle.component('discord-1', `flip:${row.id}`));
  assert.match(flipped.embeds[0].title, /Money out/);
  const back = json(await handle.component('discord-1', `flip:${row.id}`));
  assert.match(back.embeds[0].title, /Money in/);
  await handle.component('discord-1', `src:${row.id}`, ['freelance']);
  assert.equal(store.inbox.get(row.id).parsed.source, 'freelance');
});

test('Only the owner can press the buttons', async () => {
  const { store, handle } = setup();
  await handle.link('discord-1', 'riv', '482913');
  await handle.text('discord-1', 'coffee 45, cake 80 yesterday');
  const [row] = [...store.inbox.values()];
  assert.equal(row.parsed.items.length, 2);
  assert.equal(row.parsed.date, '2026-10-17T05:00:00.000Z', 'midday yesterday in Bangkok');
  const other = await handle.component('discord-2', `save:${row.id}`);
  assert.equal(other.ephemeral, true);
  assert.equal(store.inbox.get(row.id).status, 'pending');
});

test('A photo is copied into storage and waits in the inbox for the app', async () => {
  const { store, handle } = setup();
  await handle.link('discord-1', 'riv', '482913');
  const reply = json(await handle.photo('discord-1', { url: 'https://cdn/x.jpg', contentType: 'image/jpeg', size: 1000 }, 'lunch'));
  assert.match(reply.embeds[0].title, /Got your receipt/);
  const [row] = [...store.inbox.values()];
  assert.equal(row.kind, 'photo');
  assert.equal(row.status, 'pending');
  assert.ok(store.photos.has(row.photo_path));
  assert.ok(row.photo_path.startsWith('user-1/'));
  assert.match((await handle.photo('discord-1', { url: 'x', contentType: 'application/pdf', size: 1 })).content, /photo/);
});

test('Summary and goal come from the shared monthly summary', async () => {
  const { store, handle } = setup();
  await handle.link('discord-1', 'riv', '482913');
  assert.match((await handle.summary('discord-1')).content, /Share a monthly summary/);
  store.summaries.set('user-1', { month: '2026-10-01', spent: 17926, income: 31200, goal: 40000, per_day: 1577, days_left: 14,
    by_category: [{ category: 'dining', amount: 5309 }], updated_at: now.toISOString() });
  const summary = json(await handle.summary('discord-1'));
  assert.equal(summary.embeds[0].fields[0].value, '฿17,926');
  assert.equal(summary.embeds[0].fields[2].value, '+฿13,274');
  const goal = json(await handle.goal('discord-1'));
  assert.equal(goal.embeds[0].title, '฿1,577 a day for 14 days');
});

test('Dates: now for today, midday Bangkok for earlier days, in words', () => {
  assert.equal(dateFor(0, now), now.toISOString());
  assert.equal(dateFor(2, now), '2026-10-16T05:00:00.000Z');
  assert.equal(sentence({ flow: 'moneyOut', items: [{ name: 'tea', amount: 30, category: 'dining' }], date: dateFor(1, now) }, now),
    'You spent ฿30.00 on tea (Food & Drinks) yesterday.');
});
