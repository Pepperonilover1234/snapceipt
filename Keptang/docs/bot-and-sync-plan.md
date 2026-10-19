# Snapceipt: chat bot (Discord, later LINE) and cloud plan

Status: plan only. Nothing here is built yet.

## 1. What we want

A person can send a receipt photo or a line like "Pop corn 60" to a Snapceipt bot in Discord (later LINE).
The bot answers with what it understood, the person confirms, and the entry shows up in the app.
The bot can also answer questions like "how much did I spend this month?".

## 2. The problem to solve first

Today everything lives only on the phone (SwiftData). A Discord bot runs on a server, and a server can't
reach into someone's phone. So we need a small cloud piece in the middle that both sides can talk to.

Apple's iCloud (CloudKit) can't do this job: the app could sync to the person's private iCloud, but our
bot server isn't allowed to write into anyone's private iCloud database.

## 3. Recommended architecture: local first + a small cloud

```
 Discord user ──DM / slash command──► Discord
                                        │  (gateway events)
                                        ▼
                               Snapceipt bot  (Node.js discord.js, hosted 24/7)
                                        │  service key (server only)
                                        ▼
                     Supabase  (Postgres database + Auth + Storage for photos)
                                        ▲
                                        │  user's own login (Sign in with Apple)
                                        │
                              Snapceipt iOS app  (SwiftData stays the main copy)
```

- **The phone stays the main copy.** The app keeps working offline exactly as now.
- **Supabase is the meeting point**: a Postgres database, user login, private photo storage and small
  server functions, with a free tier that's enough for the hackathon.
  - Firebase could do the same job; Supabase is plain SQL with row-level security, so I'd pick it.
  - Free projects pause after a week with no activity, so wake it before the demo.
- **The bot** is a small Node.js program that listens to Discord and writes to Supabase.

### Two ways to do the "cloud" part (pick one)

| | A. Inbox only (recommended for the hackathon) | B. Full sync |
|---|---|---|
| What goes to the cloud | Only things sent through the bot, until the app picks them up | Every receipt and income, both ways |
| Work | ~1–2 days | ~4–6 days (conflicts, deletes, photos, migration) |
| Privacy | Almost everything stays on the phone | All money data on our server |
| Bot can answer "how much this month?" | Only if the app uploads a monthly summary | Yes, from the database |

**Recommendation:** start with A, and have the app upload a small, opt-in monthly summary (totals per
category, goal progress) so the bot can answer questions. Move to B later if needed.

## 4. Where the "reading" happens

| | On the phone (recommended) | On the server |
|---|---|---|
| How | Bot stores the photo/text; app reads it with what we already have (Vision OCR, QuickEntry rules, Create ML, Apple Intelligence) | Server calls an AI API (e.g. Claude with vision) to read the photo |
| Instant answer in Discord | Text: yes (port the QuickEntry rules to the bot). Photos: "got it, open the app to check" | Yes, for both |
| Cost | Free | Pay per receipt |
| Privacy | Photo only passes through our storage | Photo also goes to the AI provider |

**Recommendation:**
- Typed lines are read on the bot with a JavaScript copy of `QuickEntryRules` (the same tests in both).
- Photos are read on the phone. The checklist runs in the app for those.
- Server reading can be added later as an option.

## 5. The flow, step by step

### Linking the Discord account (once)
1. In the app: Settings → Connect Discord. The app signs in to Supabase (Sign in with Apple) and gets a
   6-digit code that's valid for 10 minutes.
2. In Discord: `/link 482913`. The bot checks the code and saves "this Discord user = this Snapceipt user".
3. The bot replies "Linked ✅". `/unlink` and a button in the app undo it.

### Sending a typed entry
1. DM the bot `Pop corn 60` (or `/add Pop corn 60`).
2. The bot reads it with the ported rules and replies with a card, which acts as the checklist in Discord:
   "Money out · ฿60 · pop corn · Entertainment · today", with buttons:
   - ✅ Save
   - 🔁 In/Out
   - 🏷 Category (dropdown)
   - ❌ Cancel
3. On ✅ the bot writes a row to `inbox` with status `confirmed`.
4. Next time the app opens (or on a push), it pulls the row, saves it into SwiftData and marks it `imported`.

### Sending a photo
1. DM the bot a photo (or `/receipt` with an attachment).
2. The bot downloads it **right away**: Discord's file links expire, so they can't be kept as links. It
   then uploads the photo to the private Supabase bucket `receipts/<user_id>/<id>.jpg` and adds an
   `inbox` row with status `pending`.
3. The bot replies "Got your receipt 📸, open Snapceipt to check it".
4. The app downloads the photo, runs the normal scan reader, shows the usual review and checklist, then
   saves it and marks the row `imported`. The photo is then deleted from the cloud.

### Asking questions (needs the opt-in summary)
- `/summary`: this month's spending, money in, net and the top categories.
- `/goal`: ฿ per day left and days to go.
- The app uploads a small `summaries` row whenever it changes (no single receipts).

## 6. Database tables (Supabase / Postgres)

```sql
-- people are Supabase auth users (auth.users), created by Sign in with Apple
create table linked_accounts (
  user_id     uuid references auth.users not null,
  provider    text check (provider in ('discord','line')) not null,
  external_id text not null,                    -- Discord user id / LINE user id
  linked_at   timestamptz default now(),
  primary key (provider, external_id)
);

create table link_codes (
  code        text primary key,                 -- 6 digits
  user_id     uuid references auth.users not null,
  expires_at  timestamptz not null
);

create table inbox (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid references auth.users not null,
  origin      text not null,                    -- 'discord' | 'line'
  kind        text not null,                    -- 'text' | 'photo'
  raw_text    text,
  photo_path  text,                             -- storage path, private bucket
  parsed      jsonb,                            -- {flow, items:[{name,amount,category}], source, date}
  status      text not null default 'pending',  -- pending | confirmed | imported | cancelled
  created_at  timestamptz default now()
);

create table summaries (                        -- optional, opt-in
  user_id     uuid primary key references auth.users,
  month       date not null,
  spent       numeric, income numeric, goal numeric,
  by_category jsonb,
  updated_at  timestamptz default now()
);
```

- **Row-level security** is on for every table: the app can only see rows where `user_id = auth.uid()`.
- The bot uses the **service key**, which lives only on the bot server and is never put in the app or in git.
- **Photos:** a private bucket, deleted after import.
- **Thailand's PDPA (data protection law):**
  - Ask for consent when connecting.
  - A "delete my cloud data" button.
  - Keep data only as long as it's needed.

## 7. Changes in the iOS app

1. Add the `supabase-swift` package. Add Sign in with Apple, which appears only when connecting, never to use the app.
2. Settings → "Chat bots" section:
   - Connect Discord (shows the 6-digit code)
   - Status
   - Disconnect
   - "Share monthly summary with the bot" toggle
   - Delete cloud data
3. `InboxSync`, which runs:
   - on launch and on pull-to-refresh: fetch `confirmed` and `pending` rows;
   - for confirmed text: save directly (it was already checked in Discord);
   - for photos: show them in an "Inbox (2)" badge on the Add tab, then run the normal review;
   - mark each row `imported`.
4. Optional: push notifications ("1 receipt from Discord") through APNs, sent from a Supabase function. That needs
   the Push capability and an APNs key in the Apple developer account.

## 8. What you have to do for the Discord bot

1. **Create the app.** Go to <https://discord.com/developers/applications> → New Application → name it "Snapceipt".
2. **Bot tab**:
   - Reset Token and copy it somewhere safe. This is the password of the bot: never paste it in chat, the app or git.
   - Turn on **Message Content Intent**. It's only needed if the bot will read normal messages in servers; in DMs with the bot it can read them anyway.
3. **Installation tab**:
   - Turn on both **User Install** and **Guild Install**. User Install lets people add the bot to their own account and DM it without a server.
   - Scopes: `applications.commands` and `bot`.
   - Permissions: Send Messages, Read Message History, Attach Files, Embed Links.
4. **Test server:** make a private Discord server for testing and invite the bot with the install link.
5. **Supabase:** make an account at supabase.com → New project (region: Singapore, closest to Thailand). I'll write the SQL above. You give me the project URL and anon key for the app. The service key goes only into the bot host's settings; you type it in yourself.
6. **Hosting the bot.** It must run 24/7 to receive DMs. Easiest: **Railway** or **Render** (free/low-cost tiers, about $0–5 a month). You:
   - make the account;
   - connect the GitHub repo, or I give you a folder to upload;
   - paste the three secrets as environment variables: `DISCORD_TOKEN`, `SUPABASE_URL`, `SUPABASE_SERVICE_KEY`.
   - For the hackathon demo it can just run on your Mac (`npm start`).
7. **Bot commands I'd build**:
   - `/link`, `/unlink`
   - `/add <text>` (plain DMs work too)
   - `/receipt <photo>` (or just DM a photo)
   - `/summary`, `/goal`
   - `/help`
8. **Apple side:** Sign in with Apple capability on the app ID, and Push Notifications if we do pushes.

## 9. LINE (phase 2, very useful in Thailand)

Same backend, different door:
- LINE Developers → Messaging API channel → get the Channel secret and Channel access token.
- Set the webhook URL to a Supabase Edge Function. LINE calls us; nothing needs to run 24/7.
- Use the same `/link`-style code and the same `inbox` table.
- Replies to a user's message are free. Pushing messages first is limited on the free plan.

## 10. Order of work and rough time

| Step | What | Time |
|---|---|---|
| 1 | Supabase project, tables, security rules, storage bucket | 0.5 day |
| 2 | Bot skeleton: login, `/help`, `/link`, DM listener | 0.5 day |
| 3 | Port QuickEntry rules to JS and share the test cases; Discord checklist card with buttons | 1 day |
| 4 | Photos: download, upload to storage, inbox row | 0.5 day |
| 5 | App: Sign in with Apple, Connect Discord screen, InboxSync, Add-tab inbox badge | 1–1.5 days |
| 6 | Opt-in summary upload + `/summary` `/goal` | 0.5 day |
| 7 | Push notifications (optional) | 0.5 day |
| 8 | LINE (phase 2) | 1 day |

## 11. Decisions needed from you

1. **Cloud:** Supabase (recommended) or Firebase?
2. **Cloud scope:** inbox only plus an opt-in summary (recommended), or full sync of everything?
3. **Photo reading:** on the phone (free, private; recommended), or on the server with an AI API (instant replies, costs money)?
4. **Hosting the bot:** Railway/Render, or just your Mac for the demo?
5. **Discord first and LINE later, or both now?**
