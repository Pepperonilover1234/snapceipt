// Snapceipt's Discord bot. Start it with `npm start` (reads .env).
import { Client, Events, GatewayIntentBits, Partials, ChannelType, MessageFlags } from 'discord.js';
import { makeHandlers } from './handlers.js';
import { supabaseStore, memoryStore } from './store.js';

const { DISCORD_TOKEN, SUPABASE_URL, SUPABASE_SERVICE_KEY } = process.env;
if (!DISCORD_TOKEN) {
  console.error('Set DISCORD_TOKEN in .env first (see README.md).');
  process.exit(1);
}
const store = SUPABASE_URL && SUPABASE_SERVICE_KEY
  ? supabaseStore({ url: SUPABASE_URL, serviceKey: SUPABASE_SERVICE_KEY })
  : (console.warn('No Supabase settings in .env: keeping everything in memory (nothing reaches the app).'), memoryStore());
const handle = makeHandlers(store);

const client = new Client({
  intents: [GatewayIntentBits.Guilds, GatewayIntentBits.DirectMessages],
  partials: [Partials.Channel], // needed to receive DMs
});

client.once(Events.ClientReady, (c) => console.log(`Snapceipt bot is online as ${c.user.tag}`));

/** In a server, replies about money are only shown to the person who asked. */
const privately = (interaction, payload) => {
  const { ephemeral, ...rest } = payload;
  return interaction.inGuild() || ephemeral ? { ...rest, flags: MessageFlags.Ephemeral } : rest;
};

client.on(Events.InteractionCreate, async (interaction) => {
  const user = interaction.user;
  try {
    if (interaction.isChatInputCommand()) {
      let payload;
      switch (interaction.commandName) {
        case 'link': payload = await handle.link(user.id, user.username, interaction.options.getString('code', true)); break;
        case 'unlink': payload = await handle.unlink(user.id); break;
        case 'add': payload = await handle.text(user.id, interaction.options.getString('text', true)); break;
        case 'receipt': {
          await interaction.deferReply(interaction.inGuild() ? { flags: MessageFlags.Ephemeral } : {});
          const photo = interaction.options.getAttachment('photo', true);
          await interaction.editReply(await handle.photo(user.id, photo));
          return;
        }
        case 'summary': payload = await handle.summary(user.id); break;
        case 'goal': payload = await handle.goal(user.id); break;
        default: payload = handle.help();
      }
      await interaction.reply(privately(interaction, payload));
    } else if (interaction.isButton() || interaction.isStringSelectMenu()) {
      const payload = await handle.component(user.id, interaction.customId, interaction.values ?? []);
      if (payload.ephemeral) await interaction.reply({ content: payload.content, flags: MessageFlags.Ephemeral });
      else await interaction.update(payload);
    }
  } catch (error) {
    console.error(error);
    const message = { content: 'Something went wrong on my side. Try again in a moment.', flags: MessageFlags.Ephemeral };
    if (interaction.deferred || interaction.replied) await interaction.followUp(message).catch(() => {});
    else if (interaction.isRepliable()) await interaction.reply(message).catch(() => {});
  }
});

// Plain DMs: a photo goes to the inbox, a line of text gets the checklist card.
client.on(Events.MessageCreate, async (message) => {
  if (message.author.bot || message.channel.type !== ChannelType.DM) return;
  try {
    const photo = message.attachments.find((a) => String(a.contentType ?? '').startsWith('image/'));
    if (photo) {
      await message.reply(await handle.photo(message.author.id, photo, message.content));
    } else if (message.content.trim()) {
      const text = message.content.trim();
      await message.reply(/^(help|\?|ช่วย)/i.test(text) ? handle.help() : await handle.text(message.author.id, text));
    }
  } catch (error) {
    console.error(error);
    await message.reply('Something went wrong on my side. Try again in a moment.').catch(() => {});
  }
});

client.login(DISCORD_TOKEN);
