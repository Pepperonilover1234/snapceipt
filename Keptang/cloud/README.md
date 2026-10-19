# Snapceipt chat bot: setup

Send a Discord bot `Pop corn 60` or a photo of a receipt, and it shows up in Snapceipt.

The code is all written. These steps are the parts that need **your own accounts and keys**, which
only you can create and type in. Never paste the secret keys in a chat, the app or GitHub.

Folders:
- `supabase/setup.sql`: the database (tables, security rules, photo storage).
- `bot/`: the Discord bot (Node.js). It has 14 tests: `npm test`.
- The app side is in `Keptang/Cloud/` and `Keptang/Views/ChatBotsView.swift`.

---

## 1. Supabase, the cloud (about 5 minutes)

1. Go to <https://supabase.com>, sign up (GitHub sign-in is fine), then **New project**.
   - Name: `snapceipt`.
   - Region: **Southeast Asia (Singapore)**.
   - Database password: let it generate one and keep it in your password manager.
2. When the project is ready, open **SQL Editor** → **New query**. Paste all of `supabase/setup.sql` and
   press **Run**. It should say "Success. No rows returned".
3. Go to **Authentication** → **Sign In / Providers** and turn on **Allow anonymous sign-ins**. The app signs in
   by itself with no email or password.
4. Go to **Project Settings** → **API** (or **API Keys**) and keep this page open. You'll need:
   - the **Project URL**, like `https://abcd1234.supabase.co`;
   - the **anon / public** key, which goes in the app;
   - the **service_role / secret** key, which goes **only** in the bot's `.env` file on your Mac.

> The free plan pauses a project after about a week with no use. Open the dashboard and press
> **Restore** before a demo if it's paused.

## 2. Discord, the bot (about 5 minutes)

1. Go to <https://discord.com/developers/applications> → **New Application** → name it `Snapceipt` →
   Create.
2. On **General Information**, copy the **Application ID**.
3. On the **Bot** tab:
   - Press **Reset Token**, then copy the token. It's shown once and is the bot's password.
   - Optionally, upload the app icon.
4. On the **Installation** tab:
   - Turn on **User Install** and **Guild Install**.
   - Under Default Install Settings → Guild Install: scopes `applications.commands` + `bot`, and
     permissions **Send Messages, Read Message History, Attach Files, Embed Links**.
   - Under User Install: scope `applications.commands`.
   - Copy the **Install Link** at the top. Open it to add the bot to your account ("Add to My Apps") or to a test
     server.

## 3. The keys on your Mac (2 minutes)

In Terminal:

```bash
cd ~/Documents/PROJECT/SwiftProject/Keptang/cloud/bot
cp .env.example .env
open -e .env
```

Fill in the four lines (Application ID, bot token, Project URL, service_role key), then save. `.env` is
ignored by git.

## 4. Start the bot

```bash
cd ~/Documents/PROJECT/SwiftProject/Keptang/cloud/bot
npm run register   # once, and again if the commands change
npm start          # keep this window open; "Snapceipt bot is online as Snapceipt#1234"
```

For the demo the bot runs on your Mac. To keep it running all the time, put the `bot` folder on Railway
or Render, set the same four values as environment variables there, and set the start command to
`npm start`.

## 5. Connect the app

1. In Snapceipt: **Settings** → **Chat bots**. Paste the **Project URL** and the **anon** key, then Save.
2. Tap **Connect Discord**. You get a code like `/link 482913`, which lasts 10 minutes.
3. In Discord, DM the bot (or use any channel it's in) and send `/link 482913`. It replies **Linked ✅**.
4. Back in the app, tap **I've sent it, check again**. It should say "Linked as …".

## 6. Try it

- DM the bot `Pop corn 60`. You get a card with what it understood. Change the category if you want, then tap **Save ✅**.
  Open Snapceipt (or pull down on Add) and it's in Receipts.
- `เงินเดือน 30000` is saved as money in.
- Send a **photo of a receipt**. In Snapceipt, **Add** shows it under *Inbox · from the chat*, with a badge on the
  tab. Tap **Read** to scan it, check it, and Save. The cloud copy is then deleted.
- Turn on **Share a monthly summary** in Chat bots, then try `/summary` and `/goal`.
- `/help` lists everything.

## Privacy

- Receipts stay on the phone. The cloud only holds:
  - what you send through the bot, until the app takes it;
  - which Discord account is yours;
  - the monthly totals, if you turn sharing on.
- Each person can only read their own rows (row-level security). The service key that can read everything
  is only in the bot's `.env`.
- **Settings → Chat bots → Delete my cloud data** removes everything in the cloud: photos, inbox, summary and links.
