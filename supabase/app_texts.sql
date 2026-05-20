create table if not exists public.app_texts (
  key text not null,
  locale text not null,
  value text not null,
  updated_at timestamptz default now(),
  primary key (key, locale)
);

alter table public.app_texts enable row level security;

drop policy if exists "app_texts_read" on public.app_texts;
create policy "app_texts_read"
on public.app_texts for select
to anon, authenticated
using (true);

drop policy if exists "app_texts_write" on public.app_texts;
create policy "app_texts_write"
on public.app_texts for insert
to anon, authenticated
with check (true);

drop policy if exists "app_texts_update" on public.app_texts;
create policy "app_texts_update"
on public.app_texts for update
to anon, authenticated
using (true)
with check (true);
