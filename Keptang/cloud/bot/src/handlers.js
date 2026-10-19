// What the bot says and does, apart from Discord itself, so it can be tested with a fake store.
// Every handler takes the person's Discord id and returns a message payload (content, embeds, components).

import { ActionRowBuilder, ButtonBuilder, ButtonStyle, EmbedBuilder, StringSelectMenuBuilder } from 'discord.js';
import { readEntry, baht, bahtWhole, CATEGORY_NAMES, SELECTABLE, INCOME_NAMES } from './quickEntry.js';

export const PROVIDER = 'discord';
const GREEN = 0x00a86b;
const ORANGE = 0xff5a00;
const RED = 0xf23645;
const GREY = 0x8c8c8c;
const MAX_PHOTO_BYTES = 10 * 1024 * 1024;

const HOW_TO_LINK =
  'Your Discord isn’t linked to Snapceipt yet.\n' +
  '1. Open **Snapceipt → Settings → Chat bots → Connect Discord**.\n' +
  '2. Send me **/link** with the 6-digit code it shows, like `/link 482913`.';

export const HELP =
  '**Snapceipt bot**\n' +
  '• Type what you spent or got, in Thai or English: `Pop corn 60`, `ข้าวมันไก่ 50 เมื่อวาน`, `coffee 45, cake 80`, `เงินเดือน 30000`, `+500 sold old shoes`. ' +
  'I’ll show what I understood, you check it, and tap **Save**.\n' +
  '• Send a **photo of a receipt** and Snapceipt reads it on your phone the next time you open it.\n' +
  '• `/summary` this month · `/goal` your money goal · `/link` `/unlink` your account.';

/** The date a typed line means, as an ISO string: now for today, midday (Bangkok) for earlier days. */
export function dateFor(daysAgo, now = new Date()) {
  if (!daysAgo) return now.toISOString();
  const bangkok = new Date(now.getTime() + 7 * 3600_000);
  bangkok.setUTCDate(bangkok.getUTCDate() - daysAgo);
  bangkok.setUTCHours(12, 0, 0, 0);
  return new Date(bangkok.getTime() - 7 * 3600_000).toISOString();
}

function dayWords(iso, now = new Date()) {
  const days = Math.round((startOfBangkokDay(now) - startOfBangkokDay(new Date(iso))) / 86_400_000);
  if (days === 0) return 'today';
  if (days === 1) return 'yesterday';
  return new Date(iso).toLocaleDateString('en-GB', { weekday: 'long', day: 'numeric', month: 'long', timeZone: 'Asia/Bangkok' });
}

function startOfBangkokDay(date) {
  const b = new Date(date.getTime() + 7 * 3600_000);
  b.setUTCHours(0, 0, 0, 0);
  return b.getTime();
}

/** "You spent ฿60.00 on pop corn (Entertainment) today." — the reading in one sentence. */
export function sentence(parsed, now = new Date()) {
  const when = dayWords(parsed.date, now);
  const total = parsed.items.reduce((s, i) => s + i.amount, 0);
  if (parsed.flow === 'moneyIn') {
    const name = parsed.items[0]?.name;
    const extra = name && name !== INCOME_NAMES[parsed.source] ? ` (${name})` : '';
    return `You got ${baht(total)} from ${INCOME_NAMES[parsed.source].toLowerCase()}${extra} ${when}.`;
  }
  const things = parsed.items.map((i) => `${i.name || 'something'} (${CATEGORY_NAMES[i.category]})`);
  const list = things.length <= 1 ? (things[0] ?? 'something') : `${things.slice(0, -1).join(', ')} and ${things.at(-1)}`;
  return `You spent ${baht(total)} on ${list} ${when}.`;
}

/** The checklist card: what was understood, with Save, In/Out, Cancel and a category menu per item. */
export function card(row, now = new Date()) {
  const p = row.parsed;
  const total = p.items.reduce((s, i) => s + i.amount, 0);
  const isIn = p.flow === 'moneyIn';
  const embed = new EmbedBuilder()
    .setColor(isIn ? GREEN : ORANGE)
    .setTitle(`${isIn ? '↙ Money in' : '↗ Money out'} · ${baht(total)}`)
    .setDescription(sentence(p, now))
    .addFields(
      ...p.items.slice(0, 10).map((i) => ({
        name: i.name || (isIn ? INCOME_NAMES[p.source] : 'Item'),
        value: `${baht(i.amount)} · ${isIn ? INCOME_NAMES[p.source] : CATEGORY_NAMES[i.category]}`,
        inline: true,
      })),
      { name: 'When', value: dayWords(p.date, now), inline: true },
    )
    .setFooter({ text: `Typed in ${p.language} · check it, change anything below, then Save` });

  const buttons = new ActionRowBuilder().addComponents(
    new ButtonBuilder().setCustomId(`save:${row.id}`).setLabel('Save').setEmoji('✅').setStyle(ButtonStyle.Success).setDisabled(total <= 0),
    new ButtonBuilder().setCustomId(`flip:${row.id}`).setLabel(isIn ? 'It’s money out' : 'It’s money in').setEmoji('🔁').setStyle(ButtonStyle.Secondary),
    new ButtonBuilder().setCustomId(`cancel:${row.id}`).setLabel('Cancel').setStyle(ButtonStyle.Danger),
  );
  const menus = isIn
    ? [new ActionRowBuilder().addComponents(
        new StringSelectMenuBuilder()
          .setCustomId(`src:${row.id}`)
          .setPlaceholder('Came from')
          .addOptions(Object.entries(INCOME_NAMES).map(([value, label]) => ({ label, value, default: value === p.source }))),
      )]
    : p.items.slice(0, 4).map((item, index) =>
        new ActionRowBuilder().addComponents(
          new StringSelectMenuBuilder()
            .setCustomId(`cat:${row.id}:${index}`)
            .setPlaceholder(`Category for ${item.name || 'item'}`.slice(0, 150))
            .addOptions(SELECTABLE.map((value) => ({
              label: `${item.name ? item.name.slice(0, 40) + ': ' : ''}${CATEGORY_NAMES[value]}`.slice(0, 100),
              value,
              default: value === item.category,
            }))),
        ),
      );
  return { embeds: [embed], components: [buttons, ...menus] };
}

function finished(row, title, colour, note, now) {
  const embed = new EmbedBuilder().setColor(colour).setTitle(title).setDescription(`${sentence(row.parsed, now)}\n\n${note}`);
  return { embeds: [embed], components: [] };
}

export function makeHandlers(store, { now = () => new Date(), fetchImage = defaultFetch } = {}) {
  async function linkedUser(discordId) {
    return store.userFor(PROVIDER, discordId);
  }

  return {
    help() {
      return { content: HELP };
    },

    async link(discordId, displayName, code) {
      const clean = String(code ?? '').replace(/\D/g, '');
      if (clean.length !== 6) return { content: 'The code is 6 digits, from **Snapceipt → Settings → Chat bots → Connect Discord**.' };
      const result = await store.redeem(clean, PROVIDER, discordId, displayName);
      if (!result.ok) return { content: 'That code didn’t work. It may have expired (codes last 10 minutes) — make a new one in Snapceipt and try again.' };
      return { content: '**Linked ✅** Now send me something like `Pop corn 60`, or a photo of a receipt.' };
    },

    async unlink(discordId) {
      await store.unlink(PROVIDER, discordId);
      return { content: 'Unlinked. Nothing more goes to your Snapceipt from this Discord account.' };
    },

    /** A typed line: read it, keep it as a pending inbox row, and show the checklist card. */
    async text(discordId, text) {
      const userId = await linkedUser(discordId);
      if (!userId) return { content: HOW_TO_LINK };
      const read = readEntry(text);
      if (!read.items.length || read.total <= 0) {
        return { content: 'I couldn’t find an amount in that. Try something like `Pop corn 60` or `เงินเดือน 30000`.\n\n' + HELP };
      }
      const parsed = {
        flow: read.flow,
        items: read.items,
        source: read.source,
        date: dateFor(read.daysAgo, now()),
        language: read.language,
      };
      const row = await store.addInbox({ user_id: userId, origin: PROVIDER, kind: 'text', raw_text: read.text, parsed, status: 'pending' });
      return card(row, now());
    },

    /** A tap on Save, In/Out or Cancel, or a choice in a menu. Returns the updated card. */
    async component(discordId, customId, values = []) {
      const [action, id, index] = customId.split(':');
      const userId = await linkedUser(discordId);
      const row = id ? await store.getInbox(id) : null;
      if (!row || !userId || row.user_id !== userId) return { content: 'That isn’t yours to change.', ephemeral: true };
      if (row.status !== 'pending') return { content: 'That one is already done.', ephemeral: true };
      const parsed = structuredClone(row.parsed);
      switch (action) {
        case 'save': {
          const saved = await store.updateInbox(id, { status: 'confirmed', parsed });
          return finished(saved, 'Saved ✅', GREEN, 'It’ll be in Snapceipt the next time you open it.', now());
        }
        case 'cancel': {
          const cancelled = await store.updateInbox(id, { status: 'cancelled' });
          return finished(cancelled, 'Cancelled', GREY, 'Nothing was saved.', now());
        }
        case 'flip': {
          if (parsed.flow === 'moneyIn') {
            parsed.flow = 'moneyOut';
            const fresh = readEntry(row.raw_text);
            parsed.items = fresh.flow === 'moneyOut' && fresh.total === parsed.items.reduce((s, i) => s + i.amount, 0)
              ? fresh.items
              : parsed.items.map((i) => ({ ...i, category: 'other' }));
          } else {
            parsed.flow = 'moneyIn';
            const total = parsed.items.reduce((s, i) => s + i.amount, 0);
            parsed.items = [{ name: parsed.items.map((i) => i.name).filter(Boolean).join(', '), amount: total, category: 'other' }];
          }
          break;
        }
        case 'cat': {
          const i = Number(index);
          if (parsed.items[i] && CATEGORY_NAMES[values[0]]) parsed.items[i].category = values[0];
          break;
        }
        case 'src': {
          if (INCOME_NAMES[values[0]]) parsed.source = values[0];
          break;
        }
        default:
          return { content: 'I don’t know that button.', ephemeral: true };
      }
      const updated = await store.updateInbox(id, { parsed });
      return card(updated, now());
    },

    /** A receipt photo: store it for the app, which reads it on the phone. */
    async photo(discordId, attachment, caption = '') {
      const userId = await linkedUser(discordId);
      if (!userId) return { content: HOW_TO_LINK };
      if (!String(attachment.contentType ?? '').startsWith('image/')) return { content: 'Send the receipt as a photo (JPG, PNG or HEIC).' };
      if ((attachment.size ?? 0) > MAX_PHOTO_BYTES) return { content: 'That photo is over 10 MB. Try a smaller one.' };
      // Discord's file links expire, so the photo is copied straight away.
      const bytes = await fetchImage(attachment.url);
      const row = await store.addPhoto({ userId, origin: PROVIDER, bytes, contentType: attachment.contentType, caption });
      const embed = new EmbedBuilder()
        .setColor(ORANGE)
        .setTitle('Got your receipt 📸')
        .setDescription('Open **Snapceipt → Add**. It’s waiting in the inbox — Snapceipt reads it on your phone and you check it before it’s saved.')
        .setFooter({ text: `Inbox item ${row.id.slice(0, 8)}` });
      return { embeds: [embed] };
    },

    async summary(discordId) {
      const userId = await linkedUser(discordId);
      if (!userId) return { content: HOW_TO_LINK };
      const s = await store.summary(userId);
      if (!s) return { content: 'Turn on **Share a monthly summary** in Snapceipt → Settings → Chat bots, then ask again.' };
      const month = new Date(s.month).toLocaleDateString('en-GB', { month: 'long', year: 'numeric', timeZone: 'Asia/Bangkok' });
      const net = s.income - s.spent;
      const top = (s.by_category ?? []).slice(0, 5).map((c) => `• ${CATEGORY_NAMES[c.category] ?? c.category}: ${bahtWhole(c.amount)}`).join('\n');
      const embed = new EmbedBuilder()
        .setColor(ORANGE)
        .setTitle(`${month}`)
        .addFields(
          { name: 'Spent', value: bahtWhole(s.spent), inline: true },
          { name: 'Money in', value: bahtWhole(s.income), inline: true },
          { name: 'Net', value: `${net >= 0 ? '+' : '−'}${bahtWhole(Math.abs(net))}`, inline: true },
        )
        .setDescription(top ? `**Where it went**\n${top}` : 'Nothing spent yet.')
        .setFooter({ text: `Updated ${new Date(s.updated_at).toLocaleString('en-GB', { timeZone: 'Asia/Bangkok' })}` });
      return { embeds: [embed] };
    },

    async goal(discordId) {
      const userId = await linkedUser(discordId);
      if (!userId) return { content: HOW_TO_LINK };
      const s = await store.summary(userId);
      if (!s) return { content: 'Turn on **Share a monthly summary** in Snapceipt → Settings → Chat bots, then ask again.' };
      if (!s.goal) return { content: 'No money goal set. Set one at the top of Overview in Snapceipt.' };
      const over = s.spent > s.goal;
      const pct = Math.round((s.spent / s.goal) * 1000) / 10;
      const embed = new EmbedBuilder()
        .setColor(over ? RED : GREEN)
        .setTitle(over ? `Over the goal by ${bahtWhole(s.spent - s.goal)}` : `${bahtWhole(s.per_day)} a day for ${s.days_left} day${s.days_left === 1 ? '' : 's'}`)
        .setDescription(`${bahtWhole(s.spent)} of ${bahtWhole(s.goal)} · ${pct}%${over ? '' : ` · ${bahtWhole(s.goal - s.spent)} left`}`);
      return { embeds: [embed] };
    },
  };
}

async function defaultFetch(url) {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`Couldn’t download the photo (${response.status})`);
  return Buffer.from(await response.arrayBuffer());
}
