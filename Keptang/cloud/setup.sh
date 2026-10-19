#!/bin/zsh
# Snapceipt bot setup: asks for the four keys (typed by you, hidden), saves them in bot/.env,
# registers the Discord commands and starts the bot. Run:  zsh ~/Documents/PROJECT/SwiftProject/Keptang/cloud/setup.sh
set -e
cd "${0:A:h}"
echo "1/3  Copying the database setup to your clipboard..."
pbcopy < supabase/setup.sql
echo "     → In Supabase: SQL Editor → New query → paste (⌘V) → Run."
echo "     → Then Authentication → Sign In / Providers → turn on 'Allow anonymous sign-ins'."
read "?     Press Return when that's done. "

echo "2/3  Your keys (they're only saved in bot/.env on this Mac):"
read "app_id?     Discord Application ID: "
read -s "token?     Discord bot token (hidden): "; echo
read "url?     Supabase Project URL (https://….supabase.co): "
read -s "service?     Supabase service_role key (hidden): "; echo
cat > bot/.env <<ENV
DISCORD_APPLICATION_ID=$app_id
DISCORD_TOKEN=$token
SUPABASE_URL=$url
SUPABASE_SERVICE_KEY=$service
ENV
chmod 600 bot/.env

echo "3/3  Registering the commands and starting the bot (keep this window open)..."
cd bot
npm install --silent
npm run register
echo
echo "     In Snapceipt: Settings → Chat bots → paste the Project URL and the anon public key → Connect Discord."
npm start
