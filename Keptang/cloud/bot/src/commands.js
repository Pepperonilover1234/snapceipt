// The slash commands. Usable in servers, in DMs with the bot, and anywhere once someone adds the
// bot to their own account (user install).

const everywhere = { integration_types: [0, 1], contexts: [0, 1, 2] };

export const commands = [
  { name: 'link', description: 'Link this Discord account to Snapceipt with the 6-digit code from the app', ...everywhere,
    options: [{ type: 3, name: 'code', description: 'The code from Snapceipt → Settings → Chat bots', required: true, min_length: 6, max_length: 7 }] },
  { name: 'unlink', description: 'Stop sending things to Snapceipt from this Discord account', ...everywhere },
  { name: 'add', description: 'Add money in or out, like “Pop corn 60” or “เงินเดือน 30000”', ...everywhere,
    options: [{ type: 3, name: 'text', description: 'What you spent or got, in Thai or English', required: true, max_length: 300 }] },
  { name: 'receipt', description: 'Send a receipt photo to Snapceipt', ...everywhere,
    options: [{ type: 11, name: 'photo', description: 'A photo of the receipt', required: true }] },
  { name: 'summary', description: 'This month: spent, money in and where it went', ...everywhere },
  { name: 'goal', description: 'Your money goal: per day and what’s left', ...everywhere },
  { name: 'help', description: 'How to use the Snapceipt bot', ...everywhere },
];
