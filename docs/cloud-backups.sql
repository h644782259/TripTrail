-- Run once in Supabase SQL editor / DataGrip. Independent of live record syncing.
begin;
create table if not exists public.triptrail_backups (
  id uuid primary key,
  created_at timestamptz not null default now(),
  object_path text not null unique,
  bytes bigint not null check (bytes > 0),
  format_version integer not null default 1 check (format_version = 1),
  chunk_count integer not null check (chunk_count > 0 and chunk_count = (bytes + 8388607) / 8388608),
  ready boolean not null default false,
  sha256 text not null check (sha256 ~ '^[0-9a-f]{64}$'),
  deleting boolean not null default false,
  check (object_path = id::text || '.triptrailbackup')
);
alter table public.triptrail_backups enable row level security;
grant select, insert, update, delete on public.triptrail_backups to anon, authenticated;
drop policy if exists triptrail_backups_public on public.triptrail_backups;
create policy triptrail_backups_public on public.triptrail_backups for all to anon, authenticated using(true) with check(true);
insert into storage.buckets(id,name,public,file_size_limit)
values('triptrail-backups','triptrail-backups',false,52428800)
on conflict(id) do nothing;
drop policy if exists triptrail_backups_read on storage.objects;
create policy triptrail_backups_read on storage.objects for select to anon, authenticated using(bucket_id='triptrail-backups');
drop policy if exists triptrail_backups_insert on storage.objects;
create policy triptrail_backups_insert on storage.objects for insert to anon, authenticated with check(bucket_id='triptrail-backups');
drop policy if exists triptrail_backups_delete on storage.objects;
create policy triptrail_backups_delete on storage.objects for delete to anon, authenticated using(bucket_id='triptrail-backups');
notify pgrst, 'reload schema';
commit;
