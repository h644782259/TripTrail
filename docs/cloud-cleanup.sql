-- Apply AFTER cloud-initialize.sql and cloud-recycle.sql. Non-destructive, repeatable.
-- Physical files must be deleted through Storage API, never DELETE storage.objects.
begin;
create table if not exists public.triptrail_gc_objects (
 bucket text not null check(bucket in ('triptrail-media','triptrail-backups')),
 path text not null, first_seen timestamptz not null default now(), deleting boolean not null default false,
 primary key(bucket,path)
);
alter table public.triptrail_gc_objects enable row level security;
grant select,insert,update,delete on public.triptrail_gc_objects to anon,authenticated;
drop policy if exists shared_access on public.triptrail_gc_objects;
create policy shared_access on public.triptrail_gc_objects for all to anon,authenticated using(true) with check(true);

create or replace function public.triptrail_media_referenced(p text) returns boolean
language sql stable security invoker set search_path='' as $$
 select exists(select 1 from public.triptrail_trip_item_media where "cloudPath"=p)
 or exists(select 1 from public.triptrail_story_entry_media where "cloudPath"=p)
 or exists(select 1 from public.triptrail_story_cover_media where "cloudPath"=p)
 or exists(select 1 from public.triptrail_favorite_media where "cloudPath"=p)
$$;

-- Serialize reference creation with claiming. Claimed paths stay retired permanently:
-- an old/offline client cannot resurrect a reference while the Storage DELETE is in flight.
create or replace function public.triptrail_gc_guard() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
 perform pg_advisory_xact_lock(728349012);
 if TG_TABLE_NAME='triptrail_backups' then
  if exists(select 1 from public.triptrail_gc_objects where bucket='triptrail-backups' and deleting and (path=NEW.object_path or starts_with(path,NEW.object_path||'/'))) then
   raise exception 'TRIPTRAIL_MEDIA_RETIRED: create a new backup';
  end if;
 else
  if exists(select 1 from public.triptrail_gc_objects where bucket='triptrail-media' and path=NEW."cloudPath" and deleting) then
   raise exception 'TRIPTRAIL_MEDIA_RETIRED: upload media with a new path';
  end if;
 end if;
 return NEW;
end $$;
do $$ declare t text; begin
 foreach t in array array['triptrail_trip_item_media','triptrail_story_entry_media','triptrail_story_cover_media','triptrail_favorite_media','triptrail_backups'] loop
  execute format('drop trigger if exists triptrail_gc_guard on public.%I',t);
  execute format('create trigger triptrail_gc_guard before insert or update on public.%I for each row execute function public.triptrail_gc_guard()',t);
 end loop;
end $$;

create or replace function public.triptrail_media_available(media_path text) returns boolean
language sql stable security invoker set search_path='' as $$
 select exists(select 1 from storage.objects where bucket_id='triptrail-media' and name=media_path)
 and not exists(select 1 from public.triptrail_gc_objects where bucket='triptrail-media' and path=media_path and deleting)
$$;

create or replace function public.triptrail_cleanup_candidates()
returns table(bucket text,path text) language plpgsql security invoker set search_path='' as $$
begin
 perform pg_advisory_xact_lock(728349012);
 -- Every existing backup row protects its files, including incomplete/deleting versions.
 -- Recycle records retain their media rows until the recycle purge actually succeeds.
 delete from public.triptrail_gc_objects g where not g.deleting and (
  not exists(select 1 from storage.objects o where o.bucket_id=g.bucket and o.name=g.path and greatest(o.created_at,o.updated_at)<now()-interval '7 days')
  or (g.bucket='triptrail-media' and public.triptrail_media_referenced(g.path))
  or (g.bucket='triptrail-backups' and exists(select 1 from public.triptrail_backups b where g.path=b.object_path or starts_with(g.path,b.object_path||'/')))
 );
 insert into public.triptrail_gc_objects(bucket,path)
 select o.bucket_id,o.name from storage.objects o
 where o.bucket_id in ('triptrail-media','triptrail-backups')
 and greatest(o.created_at,o.updated_at)<now()-interval '7 days'
 and ((o.bucket_id='triptrail-media' and not public.triptrail_media_referenced(o.name))
 or (o.bucket_id='triptrail-backups' and not exists(select 1 from public.triptrail_backups b where o.name=b.object_path or starts_with(o.name,b.object_path||'/'))))
 on conflict do nothing;
 return query select g.bucket,g.path from public.triptrail_gc_objects g
 join storage.objects o on o.bucket_id=g.bucket and o.name=g.path
 where g.deleting or g.first_seen<=now()-interval '1 day'
 order by g.first_seen,g.bucket,g.path limit 100;
end $$;
-- Called only after user confirmation. Recheck under the same lock as reference writes.
create or replace function public.triptrail_cleanup_claim(files jsonb)
returns table(bucket text,path text) language plpgsql security invoker set search_path='' as $$
begin
 perform pg_advisory_xact_lock(728349012);
 update public.triptrail_gc_objects g set deleting=true
 where (g.deleting or g.first_seen<=now()-interval '1 day')
 and exists(select 1 from jsonb_to_recordset(files) as f(bucket text,path text) where f.bucket=g.bucket and f.path=g.path)
 and exists(select 1 from storage.objects o where o.bucket_id=g.bucket and o.name=g.path and greatest(o.created_at,o.updated_at)<now()-interval '7 days')
 and ((g.bucket='triptrail-media' and not public.triptrail_media_referenced(g.path))
 or (g.bucket='triptrail-backups' and not exists(select 1 from public.triptrail_backups b where g.path=b.object_path or starts_with(g.path,b.object_path||'/'))));
 return query select g.bucket,g.path from public.triptrail_gc_objects g
 where g.deleting and exists(select 1 from jsonb_to_recordset(files) as f(bucket text,path text) where f.bucket=g.bucket and f.path=g.path)
 order by g.bucket,g.path limit 100;
end $$;
revoke all on function public.triptrail_media_referenced(text),public.triptrail_gc_guard(),public.triptrail_media_available(text),public.triptrail_cleanup_candidates(),public.triptrail_cleanup_claim(jsonb) from public;
grant execute on function public.triptrail_media_referenced(text),public.triptrail_gc_guard(),public.triptrail_media_available(text),public.triptrail_cleanup_candidates(),public.triptrail_cleanup_claim(jsonb) to anon,authenticated;
commit;
