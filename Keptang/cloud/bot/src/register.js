// Registers the slash commands with Discord. Run once, and again whenever commands change:
//   npm run register
import { REST, Routes } from 'discord.js';
import { commands } from './commands.js';

const token = process.env.DISCORD_TOKEN;
const appId = process.env.DISCORD_APPLICATION_ID;
if (!token || !appId) {
  console.error('Set DISCORD_TOKEN and DISCORD_APPLICATION_ID in .env first (see README.md).');
  process.exit(1);
}

const rest = new REST().setToken(token);
await rest.put(Routes.applicationCommands(appId), { body: commands });
console.log(`Registered ${commands.length} commands: ${commands.map((c) => '/' + c.name).join(' ')}`);
