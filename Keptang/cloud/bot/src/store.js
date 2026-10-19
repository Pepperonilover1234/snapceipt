// The bot's side of Supabase. Uses the service key, which skips row-level security, so it must
// only ever live on the bot's own computer (in .env), never in the app or in git.

import { createClient } from '@supabase/supabase-js';
import { randomUUID } from 'node:crypto';

/** "https://supabase.com/dashboard/project/abcd" (the dashboard page) → "https://abcd.supabase.co" (the API). */
export function apiURL(url) {
  const dashboard = String(url).match(/supabase\.com\/dashboard\/project\/([a-z0-9]+)/);
  return dashboard ? `https://${dashboard[1]}.supabase.co` : String(url).replace(/\/+$/, '');
}

export function supabaseStore({ url, serviceKey }) {
  const db = createClient(apiURL(url), serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });

  const must = ({ data, error }) => {
    if (error) throw new Error(error.message);
    return data;
  };

  return {
    async userFor(provider, externalId) {
      const rows = must(await db.from('linked_accounts').select('user_id').eq('provider', provider).eq('external_id', externalId).limit(1));
      return rows[0]?.user_id ?? null;
    },

    async redeem(code, provider, externalId, displayName) {
      const rows = must(await db.from('link_codes').select('user_id, expires_at').eq('code', code).limit(1));
      const found = rows[0];
      if (!found || new Date(found.expires_at) < new Date()) return { ok: false };
      must(await db.from('linked_accounts').upsert({ provider, external_id: externalId, user_id: found.user_id, display_name: displayName ?? null }));
      must(await db.from('link_codes').delete().eq('code', code));
      return { ok: true, userId: found.user_id };
    },

    async unlink(provider, externalId) {
      must(await db.from('linked_accounts').delete().eq('provider', provider).eq('external_id', externalId));
    },

    async addInbox(row) {
      return must(await db.from('inbox').insert(row).select().single());
    },

    async getInbox(id) {
      const rows = must(await db.from('inbox').select('*').eq('id', id).limit(1));
      return rows[0] ?? null;
    },

    async updateInbox(id, patch) {
      return must(await db.from('inbox').update(patch).eq('id', id).select().single());
    },

    async addPhoto({ userId, origin, bytes, contentType, caption }) {
      const id = randomUUID();
      const extension = contentType === 'image/png' ? 'png' : contentType === 'image/heic' ? 'heic' : 'jpg';
      const path = `${userId}/${id}.${extension}`;
      must(await db.storage.from('receipts').upload(path, bytes, { contentType, upsert: false }));
      return must(await db.from('inbox').insert({
        id, user_id: userId, origin, kind: 'photo', raw_text: caption || null, photo_path: path, status: 'pending',
      }).select().single());
    },

    async summary(userId) {
      const rows = must(await db.from('summaries').select('*').eq('user_id', userId).limit(1));
      return rows[0] ?? null;
    },
  };
}

/** The same store kept in memory, for tests and for trying the bot without Supabase. */
export function memoryStore() {
  const links = new Map();
  const codes = new Map();
  const inbox = new Map();
  const photos = new Map();
  const summaries = new Map();
  return {
    links, codes, inbox, photos, summaries,
    async userFor(provider, externalId) { return links.get(`${provider}:${externalId}`) ?? null; },
    async redeem(code, provider, externalId) {
      const found = codes.get(code);
      if (!found || found.expires < Date.now()) return { ok: false };
      links.set(`${provider}:${externalId}`, found.userId);
      codes.delete(code);
      return { ok: true, userId: found.userId };
    },
    async unlink(provider, externalId) { links.delete(`${provider}:${externalId}`); },
    async addInbox(row) { const r = { id: randomUUID(), created_at: new Date().toISOString(), ...structuredClone(row) }; inbox.set(r.id, r); return structuredClone(r); },
    async getInbox(id) { return inbox.has(id) ? structuredClone(inbox.get(id)) : null; },
    async updateInbox(id, patch) { const r = { ...inbox.get(id), ...structuredClone(patch) }; inbox.set(id, r); return structuredClone(r); },
    async addPhoto({ userId, origin, bytes, contentType, caption }) {
      const id = randomUUID();
      const path = `${userId}/${id}.jpg`;
      photos.set(path, { bytes, contentType });
      return this.addInbox({ id, user_id: userId, origin, kind: 'photo', raw_text: caption || null, photo_path: path, status: 'pending' });
    },
    async summary(userId) { return summaries.get(userId) ?? null; },
  };
}
