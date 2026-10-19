-- Snapceipt cloud: the meeting point between chat bots and the app.
-- Paste the whole file into Supabase → SQL Editor → Run. Safe to run again.
--
-- The phone keeps the real data. The cloud only holds:
--   • what people send through a bot, until the app imports it (inbox + photos)
--   • which Discord/LINE account belongs to which app user (linked_accounts)
--   • an optional, opt-in monthly summary so the bot can answer "how much this month?"

-- Who is linked to whom.
create table if not exists public.linked_accounts (
  provider    text not null check (provider in ('discord', 'line')),
  external_id text not null,
  user_id     uuid not null references auth.users on delete cascade,
  display_name text,
  linked_at   timestamptz not null default now(),
  primary key (provider, external_id)
);
create index if not exists linked_accounts_user on public.linked_accounts (user_id);

-- Short-lived 6-digit codes the app shows and the person types into the bot.
create table if not exists public.link_codes (
  code       text primary key,
  user_id    uuid not null references auth.users on delete cascade,
  expires_at timestamptz not null
);

-- Things sent through a bot, waiting for the app.
create table if not exists public.inbox (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users on delete cascade,
  origin     text not null check (origin in ('discord', 'line')),
  kind       text not null check (kind in ('text', 'photo')),
  raw_text   text,
  photo_path text,
  -- {flow: "moneyOut"|"moneyIn", items: [{name, amount, category}], source, date}
  parsed     jsonb,
  status     text not null default 'pending'
             check (status in ('pending', 'confirmed', 'imported', 'cancelled')),
  created_at timestamptz not null default now()
);
create index if not exists inbox_user_status on public.inbox (user_id, status);

-- Optional monthly totals the app shares so the bot can answer questions.
create table if not exists public.summaries (
  user_id     uuid primary key references auth.users on delete cascade,
  month       date not null,
  spent       numeric not null default 0,
  income      numeric not null default 0,
  goal        numeric not null default 0,
  per_day     numeric not null default 0,
  days_left   integer not null default 0,
  by_category jsonb not null default '[]',
  updated_at  timestamptz not null default now()
);

-- Row-level security: the app (signed in as the person) only ever sees its own rows.
-- The bot uses the service key, which skips these rules, and lives only on the bot's computer.
alter table public.linked_accounts enable row level security;
alter table public.link_codes enable row level security;
alter table public.inbox enable row level security;
alter table public.summaries enable row level security;

drop policy if exists "own links: read" on public.linked_accounts;
create policy "own links: read" on public.linked_accounts for select using (user_id = auth.uid());
drop policy if exists "own links: remove" on public.linked_accounts;
create policy "own links: remove" on public.linked_accounts for delete using (user_id = auth.uid());

drop policy if exists "own inbox: read" on public.inbox;
create policy "own inbox: read" on public.inbox for select using (user_id = auth.uid());
drop policy if exists "own inbox: mark" on public.inbox;
create policy "own inbox: mark" on public.inbox for update using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists "own inbox: remove" on public.inbox;
create policy "own inbox: remove" on public.inbox for delete using (user_id = auth.uid());

drop policy if exists "own summary: all" on public.summaries;
create policy "own summary: all" on public.summaries for all using (user_id = auth.uid()) with check (user_id = auth.uid());
-- link_codes has no policies: only the functions below and the bot touch it.

-- A fresh code for the signed-in person, valid for 10 minutes.
create or replace function public.create_link_code()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  new_code text;
begin
  if auth.uid() is null then
    raise exception 'not signed in';
  end if;
  delete from link_codes where user_id = auth.uid() or expires_at < now();
  loop
    new_code := lpad((floor(random() * 1000000))::int::text, 6, '0');
    exit when not exists (select 1 from link_codes where code = new_code);
  end loop;
  insert into link_codes (code, user_id, expires_at) values (new_code, auth.uid(), now() + interval '10 minutes');
  return new_code;
end;
$$;

-- Everything the cloud holds about the signed-in person, gone. Photos are removed by the app
-- through the storage API (same folder rule as below).
create or replace function public.delete_my_cloud_data()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'not signed in';
  end if;
  delete from inbox where user_id = auth.uid();
  delete from summaries where user_id = auth.uid();
  delete from linked_accounts where user_id = auth.uid();
  delete from link_codes where user_id = auth.uid();
end;
$$;

revoke all on function public.create_link_code() from public, anon;
grant execute on function public.create_link_code() to authenticated;
revoke all on function public.delete_my_cloud_data() from public, anon;
grant execute on function public.delete_my_cloud_data() to authenticated;

-- Private photo storage: receipts/<user id>/<inbox id>.jpg
insert into storage.buckets (id, name, public)
values ('receipts', 'receipts', false)
on conflict (id) do nothing;

drop policy if exists "own photos: read" on storage.objects;
create policy "own photos: read" on storage.objects for select
  using (bucket_id = 'receipts' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "own photos: remove" on storage.objects;
create policy "own photos: remove" on storage.objects for delete
  using (bucket_id = 'receipts' and (storage.foldername(name))[1] = auth.uid()::text);
