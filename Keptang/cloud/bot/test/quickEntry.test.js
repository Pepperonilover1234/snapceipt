// The same cases as the app's QuickEntryTests, so the bot and the app agree.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readEntry, chunks, incomeSource } from '../src/quickEntry.js';

test('“Pop corn 60” is ฿60 spent on entertainment today', () => {
  const e = readEntry('Pop corn 60');
  assert.equal(e.flow, 'moneyOut');
  assert.equal(e.items.length, 1);
  assert.equal(e.items[0].name, 'pop corn');
  assert.equal(e.items[0].amount, 60);
  assert.equal(e.items[0].category, 'entertainment');
  assert.equal(e.daysAgo, 0);
  assert.equal(e.language, 'English');
});

test('Thai works the same way', () => {
  const e = readEntry('ป๊อปคอร์น 60 บาท');
  assert.equal(e.flow, 'moneyOut');
  assert.equal(e.items[0].name, 'ป๊อปคอร์น');
  assert.equal(e.items[0].amount, 60);
  assert.equal(e.items[0].category, 'entertainment');
  assert.equal(e.language, 'Thai');
  const rice = readEntry('ข้าวมันไก่ 50 เมื่อวาน');
  assert.equal(rice.items[0].category, 'dining');
  assert.equal(rice.daysAgo, 1);
});

test('Income words and a plus sign mean money in', () => {
  const pay = readEntry('เงินเดือน 30000');
  assert.equal(pay.flow, 'moneyIn');
  assert.equal(pay.source, 'salary');
  assert.equal(pay.total, 30000);
  const sold = readEntry('+500 sold old shoes');
  assert.equal(sold.flow, 'moneyIn');
  assert.equal(sold.source, 'sales');
  assert.equal(sold.total, 500);
  assert.equal(readEntry('refund 250').source, 'refund');
  assert.equal(readEntry('salary 45k').total, 45000);
});

test('A pharmacy is a shop, not a sale', () => {
  assert.equal(readEntry('ร้านขายยา 120').flow, 'moneyOut');
  assert.equal(incomeSource('ร้านขายยา'), null);
});

test('Several things, split at commas and “and” when each has a price', () => {
  const two = readEntry('coffee 45, cake 80');
  assert.deepEqual(two.items.map((i) => i.amount), [45, 80]);
  assert.deepEqual(two.items.map((i) => i.category), ['dining', 'dining']);
  assert.equal(two.total, 125);
  const joined = readEntry('coffee and cake 125');
  assert.equal(joined.items.length, 1);
  assert.equal(joined.items[0].amount, 125);
  const anded = readEntry('grab 120 and popcorn 60 yesterday');
  assert.deepEqual(anded.items.map((i) => i.amount), [120, 60]);
  assert.deepEqual(anded.items.map((i) => i.category), ['transport', 'entertainment']);
  assert.equal(anded.daysAgo, 1);
});

test('Amounts with commas, decimals and k', () => {
  assert.equal(readEntry('shoes 1,290').total, 1290);
  assert.equal(readEntry('latte 65.50').total, 65.5);
  assert.equal(readEntry('iphone 1.5k').total, 1500);
  assert.equal(readEntry('7-eleven 45').total, 45);
  assert.equal(readEntry('lunch').total, 0);
  assert.deepEqual(chunks('shoes 1,290'), ['shoes 1290']);
});
