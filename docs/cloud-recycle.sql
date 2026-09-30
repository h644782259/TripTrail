-- 增量迁移：不清空现有数据。删除后 24 小时内可恢复。
begin;
create table if not exists public.triptrail_deleted_records (
 id uuid not null, kind text not null check(kind in ('trip','story','favorite')),
 title text not null, recoverable boolean not null default true, deleted_at_ms bigint not null default (extract(epoch from now())*1000)::bigint,
 expires_at_ms bigint not null default (extract(epoch from now()+interval '24 hours')*1000)::bigint,
 primary key(kind,id)
);
alter table public.triptrail_deleted_records add column if not exists recoverable boolean not null default true;
alter table public.triptrail_deleted_records enable row level security;
grant select,insert,update,delete on public.triptrail_deleted_records to anon,authenticated;
drop policy if exists shared_access on public.triptrail_deleted_records;
create policy shared_access on public.triptrail_deleted_records for all to anon,authenticated using(true) with check(true);
-- Retried requests must not delete an already restored record again.
create table if not exists public.triptrail_delete_operations(operation_id uuid primary key);
alter table public.triptrail_delete_operations enable row level security;
grant select,insert on public.triptrail_delete_operations to anon,authenticated;
drop policy if exists shared_access on public.triptrail_delete_operations;
create policy shared_access on public.triptrail_delete_operations for all to anon,authenticated using(true) with check(true);
create or replace view public.triptrail_cloud_records with (security_invoker=true) as
select t.id, 'trip'::text as kind, t.title, (to_jsonb(t) - 'revision' - 'updated_at' || jsonb_build_object('days', (select coalesce(jsonb_agg((to_jsonb(d) - 'root_id' || jsonb_build_object('items', (select coalesce(jsonb_agg((to_jsonb(i) - 'root_id' - 'parent_id' || jsonb_build_object('media', (select coalesce(jsonb_agg(to_jsonb(m) - 'root_id' - 'parent_id' order by m."sortOrder", m.id),'[]'::jsonb) from public.triptrail_trip_item_media m where m.root_id=i.root_id and m.parent_id=i.id), 'vouchers', (select coalesce(jsonb_agg(to_jsonb(v) - 'root_id' - 'parent_id' order by v.id),'[]'::jsonb) from public.triptrail_trip_item_vouchers v where v.root_id=i.root_id and v.parent_id=i.id))) order by i."sortOrder", i.id),'[]'::jsonb) from public.triptrail_trip_items i where i.root_id=d.root_id and i.parent_id=d.id))) order by d."sortOrder", d.id),'[]'::jsonb) from public.triptrail_trip_days d where d.root_id=t.id))) as payload, t.revision, t.updated_at from public.triptrail_trips t where not exists (select 1 from public.triptrail_deleted_records x where x.id=t.id and x.kind='trip')
union all
select t.id, 'story'::text as kind, t.title, (to_jsonb(t) - 'revision' - 'updated_at' || jsonb_build_object('days', (select coalesce(jsonb_agg(to_jsonb(d) - 'root_id' order by d."sortOrder", d.id),'[]'::jsonb) from public.triptrail_story_days d where d.root_id=t.id), 'entries', (select coalesce(jsonb_agg((to_jsonb(e) - 'root_id' || jsonb_build_object('media', (select coalesce(jsonb_agg(to_jsonb(m) - 'root_id' - 'parent_id' order by m."sortOrder", m.id),'[]'::jsonb) from public.triptrail_story_entry_media m where m.root_id=e.root_id and m.parent_id=e.id))) order by e."sortOrder", e.id),'[]'::jsonb) from public.triptrail_story_entries e where e.root_id=t.id), 'coverMedia', (select to_jsonb(m) - 'root_id' from public.triptrail_story_cover_media m where m.root_id=t.id limit 1))) as payload, t.revision, t.updated_at from public.triptrail_stories t where not exists (select 1 from public.triptrail_deleted_records x where x.id=t.id and x.kind='story')
union all
select t.id, 'favorite'::text as kind, t.title, (to_jsonb(t) - 'revision' - 'updated_at' || jsonb_build_object('media', (select coalesce(jsonb_agg(to_jsonb(m) - 'root_id' order by m."sortOrder", m.id),'[]'::jsonb) from public.triptrail_favorite_media m where m.root_id=t.id), 'vouchers', (select coalesce(jsonb_agg(to_jsonb(v) - 'root_id' order by v.id),'[]'::jsonb) from public.triptrail_favorite_vouchers v where v.root_id=t.id))) as payload, t.revision, t.updated_at from public.triptrail_favorites t where not exists (select 1 from public.triptrail_deleted_records x where x.id=t.id and x.kind='favorite');

create or replace function public.triptrail_save_record(record_id uuid,record_kind text,record_title text,record_payload jsonb,expected_revision bigint)
returns public.triptrail_cloud_records language plpgsql security invoker set search_path='' as $$
declare d jsonb; i jsonb; m jsonb; result public.triptrail_cloud_records;
begin
perform pg_advisory_xact_lock(hashtextextended(record_kind || ':' || record_id::text,0));
if exists(select 1 from public.triptrail_deleted_records where id=record_id and kind=record_kind) then raise sqlstate 'PT410' using message='Record is in recycle bin or expired'; end if;
if record_kind not in ('trip','story','favorite') or jsonb_typeof(record_payload) <> 'object'
   or (record_payload->>'id')::uuid is distinct from record_id or expected_revision < 0
   or record_title is distinct from record_payload->>'title' then
 raise exception 'Invalid cloud record';
end if;
if record_kind='trip' then
if expected_revision = 0 then
        insert into public.triptrail_trips ("id","title","destination","licensePlate","startDate","endDate","note","createdAt") select r."id",r."title",r."destination",r."licensePlate",r."startDate",r."endDate",r."note",r."createdAt" from jsonb_populate_record(null::public.triptrail_trips, record_payload) r on conflict(id) do nothing;
        if not found then raise sqlstate 'PT409' using message='Cloud revision conflict'; end if;
    else
        update public.triptrail_trips t set ("id","title","destination","licensePlate","startDate","endDate","note","createdAt") = (select r."id",r."title",r."destination",r."licensePlate",r."startDate",r."endDate",r."note",r."createdAt" from jsonb_populate_record(null::public.triptrail_trips,record_payload) r),
            revision=t.revision+1, updated_at=now()
        where t.id=record_id and t.revision=expected_revision;
        if not found then raise sqlstate 'PT409' using message='Cloud revision conflict'; end if;
    end if;
delete from public.triptrail_trip_days where root_id=record_id;
for d in select value from jsonb_array_elements(record_payload->'days') loop
insert into public.triptrail_trip_days ("root_id","id","date","title","note","sortOrder") select record_id,r."id",r."date",r."title",r."note",r."sortOrder" from jsonb_populate_record(null::public.triptrail_trip_days, d) r;
 for i in select value from jsonb_array_elements(d->'items') loop
insert into public.triptrail_trip_items ("root_id","parent_id","id","title","categoryRaw","startTime","endTime","address","note","locationModeRaw","placeName","placeAddress","originName","originAddress","destinationName","destinationAddress","transportRaw","distanceText","playDurationMinutes","reservationInfo","cost","isCompleted","executionStatusRaw","isAutomaticCompletionOverridden","isFixedTime","isTimePending","isFavorite","favoriteCity","favoriteCreatedAt","sourceFavoriteID","sortOrder") select record_id,(d->>'id')::uuid,r."id",r."title",r."categoryRaw",r."startTime",r."endTime",r."address",r."note",r."locationModeRaw",r."placeName",r."placeAddress",r."originName",r."originAddress",r."destinationName",r."destinationAddress",r."transportRaw",r."distanceText",r."playDurationMinutes",r."reservationInfo",r."cost",r."isCompleted",r."executionStatusRaw",r."isAutomaticCompletionOverridden",r."isFixedTime",r."isTimePending",r."isFavorite",r."favoriteCity",r."favoriteCreatedAt",r."sourceFavoriteID",r."sortOrder" from jsonb_populate_record(null::public.triptrail_trip_items, i) r;for m in select value from jsonb_array_elements(coalesce(nullif(i->'media','null'::jsonb),'[]'::jsonb)) loop
 insert into public.triptrail_trip_item_media ("root_id","parent_id","id","localIdentifier","kindRaw","caption","createdAt","sortOrder","cloudPath") select record_id,(i->>'id')::uuid,r."id",r."localIdentifier",r."kindRaw",r."caption",r."createdAt",r."sortOrder",r."cloudPath" from jsonb_populate_record(null::public.triptrail_trip_item_media, m) r;
end loop;for m in select value from jsonb_array_elements(coalesce(nullif(i->'vouchers','null'::jsonb),'[]'::jsonb)) loop
 insert into public.triptrail_trip_item_vouchers ("root_id","parent_id","id","name","mimeType","dataBase64") select record_id,(i->>'id')::uuid,r."id",r."name",r."mimeType",r."dataBase64" from jsonb_populate_record(null::public.triptrail_trip_item_vouchers, m) r;
end loop;
 end loop;
end loop;
elsif record_kind='story' then
if expected_revision = 0 then
        insert into public.triptrail_stories ("id","title","destination","startDate","endDate","summary","createdAt","sourceTripID","syncScopeRaw","sourceSelectionIDsRaw","coverZoom","coverOffsetX","coverOffsetY") select r."id",r."title",r."destination",r."startDate",r."endDate",r."summary",r."createdAt",r."sourceTripID",r."syncScopeRaw",r."sourceSelectionIDsRaw",r."coverZoom",r."coverOffsetX",r."coverOffsetY" from jsonb_populate_record(null::public.triptrail_stories, record_payload) r on conflict(id) do nothing;
        if not found then raise sqlstate 'PT409' using message='Cloud revision conflict'; end if;
    else
        update public.triptrail_stories t set ("id","title","destination","startDate","endDate","summary","createdAt","sourceTripID","syncScopeRaw","sourceSelectionIDsRaw","coverZoom","coverOffsetX","coverOffsetY") = (select r."id",r."title",r."destination",r."startDate",r."endDate",r."summary",r."createdAt",r."sourceTripID",r."syncScopeRaw",r."sourceSelectionIDsRaw",r."coverZoom",r."coverOffsetX",r."coverOffsetY" from jsonb_populate_record(null::public.triptrail_stories,record_payload) r),
            revision=t.revision+1, updated_at=now()
        where t.id=record_id and t.revision=expected_revision;
        if not found then raise sqlstate 'PT409' using message='Cloud revision conflict'; end if;
    end if;
delete from public.triptrail_story_entries where root_id=record_id;
delete from public.triptrail_story_days where root_id=record_id;
delete from public.triptrail_story_cover_media where root_id=record_id;
for d in select value from jsonb_array_elements(record_payload->'days') loop
insert into public.triptrail_story_days ("root_id","id","date","title","note","details","didMigrateInlineSummary","sortOrder","sourceDayID") select record_id,r."id",r."date",r."title",r."note",r."details",r."didMigrateInlineSummary",r."sortOrder",r."sourceDayID" from jsonb_populate_record(null::public.triptrail_story_days, d) r;
end loop;
for i in select value from jsonb_array_elements(record_payload->'entries') loop
insert into public.triptrail_story_entries ("root_id","id","title","categoryRaw","startTime","endTime","timeLabel","address","supplementalInfo","note","locationModeRaw","placeName","placeAddress","originName","originAddress","destinationName","destinationAddress","transportRaw","routeInfo","cost","didPrefillSourceMemory","sourceMemoryPrefill","sortOrder","sourceItemID","storyDayID") select record_id,r."id",r."title",r."categoryRaw",r."startTime",r."endTime",r."timeLabel",r."address",r."supplementalInfo",r."note",r."locationModeRaw",r."placeName",r."placeAddress",r."originName",r."originAddress",r."destinationName",r."destinationAddress",r."transportRaw",r."routeInfo",r."cost",r."didPrefillSourceMemory",r."sourceMemoryPrefill",r."sortOrder",r."sourceItemID",r."storyDayID" from jsonb_populate_record(null::public.triptrail_story_entries, i) r;for m in select value from jsonb_array_elements(coalesce(nullif(i->'media','null'::jsonb),'[]'::jsonb)) loop
 insert into public.triptrail_story_entry_media ("root_id","parent_id","id","localIdentifier","kindRaw","caption","createdAt","sortOrder","cloudPath") select record_id,(i->>'id')::uuid,r."id",r."localIdentifier",r."kindRaw",r."caption",r."createdAt",r."sortOrder",r."cloudPath" from jsonb_populate_record(null::public.triptrail_story_entry_media, m) r;
end loop;
end loop;
if jsonb_typeof(record_payload->'coverMedia')='object' then
insert into public.triptrail_story_cover_media ("root_id","id","localIdentifier","kindRaw","caption","createdAt","sortOrder","cloudPath") select record_id,r."id",r."localIdentifier",r."kindRaw",r."caption",r."createdAt",r."sortOrder",r."cloudPath" from jsonb_populate_record(null::public.triptrail_story_cover_media, record_payload->'coverMedia') r;
end if;
else
if expected_revision = 0 then
        insert into public.triptrail_favorites ("id","title","categoryRaw","startTime","endTime","address","note","locationModeRaw","placeName","placeAddress","originName","originAddress","destinationName","destinationAddress","transportRaw","distanceText","playDurationMinutes","reservationInfo","cost","isCompleted","executionStatusRaw","isAutomaticCompletionOverridden","isFixedTime","isTimePending","isFavorite","favoriteCity","favoriteCreatedAt","sourceFavoriteID","sortOrder") select r."id",r."title",r."categoryRaw",r."startTime",r."endTime",r."address",r."note",r."locationModeRaw",r."placeName",r."placeAddress",r."originName",r."originAddress",r."destinationName",r."destinationAddress",r."transportRaw",r."distanceText",r."playDurationMinutes",r."reservationInfo",r."cost",r."isCompleted",r."executionStatusRaw",r."isAutomaticCompletionOverridden",r."isFixedTime",r."isTimePending",r."isFavorite",r."favoriteCity",r."favoriteCreatedAt",r."sourceFavoriteID",r."sortOrder" from jsonb_populate_record(null::public.triptrail_favorites, record_payload) r on conflict(id) do nothing;
        if not found then raise sqlstate 'PT409' using message='Cloud revision conflict'; end if;
    else
        update public.triptrail_favorites t set ("id","title","categoryRaw","startTime","endTime","address","note","locationModeRaw","placeName","placeAddress","originName","originAddress","destinationName","destinationAddress","transportRaw","distanceText","playDurationMinutes","reservationInfo","cost","isCompleted","executionStatusRaw","isAutomaticCompletionOverridden","isFixedTime","isTimePending","isFavorite","favoriteCity","favoriteCreatedAt","sourceFavoriteID","sortOrder") = (select r."id",r."title",r."categoryRaw",r."startTime",r."endTime",r."address",r."note",r."locationModeRaw",r."placeName",r."placeAddress",r."originName",r."originAddress",r."destinationName",r."destinationAddress",r."transportRaw",r."distanceText",r."playDurationMinutes",r."reservationInfo",r."cost",r."isCompleted",r."executionStatusRaw",r."isAutomaticCompletionOverridden",r."isFixedTime",r."isTimePending",r."isFavorite",r."favoriteCity",r."favoriteCreatedAt",r."sourceFavoriteID",r."sortOrder" from jsonb_populate_record(null::public.triptrail_favorites,record_payload) r),
            revision=t.revision+1, updated_at=now()
        where t.id=record_id and t.revision=expected_revision;
        if not found then raise sqlstate 'PT409' using message='Cloud revision conflict'; end if;
    end if;
delete from public.triptrail_favorite_media where root_id=record_id;
delete from public.triptrail_favorite_vouchers where root_id=record_id;
for m in select value from jsonb_array_elements(coalesce(nullif(record_payload->'media','null'::jsonb),'[]'::jsonb)) loop
 insert into public.triptrail_favorite_media ("root_id","id","localIdentifier","kindRaw","caption","createdAt","sortOrder","cloudPath") select record_id,r."id",r."localIdentifier",r."kindRaw",r."caption",r."createdAt",r."sortOrder",r."cloudPath" from jsonb_populate_record(null::public.triptrail_favorite_media, m) r;
end loop;for m in select value from jsonb_array_elements(coalesce(nullif(record_payload->'vouchers','null'::jsonb),'[]'::jsonb)) loop
 insert into public.triptrail_favorite_vouchers ("root_id","id","name","mimeType","dataBase64") select record_id,r."id",r."name",r."mimeType",r."dataBase64" from jsonb_populate_record(null::public.triptrail_favorite_vouchers, m) r;
end loop;
end if;
select * into result from public.triptrail_cloud_records where id=record_id and kind=record_kind;
return result;
end $$;
revoke all on function public.triptrail_save_record(uuid,text,text,jsonb,bigint) from public;
grant execute on function public.triptrail_save_record(uuid,text,text,jsonb,bigint) to anon,authenticated;



drop function if exists public.triptrail_trash_record(uuid,text);
create or replace function public.triptrail_trash_record(record_id uuid,record_kind text,operation_id uuid default null)
returns void language plpgsql security invoker set search_path='' as $$
declare record_title text; root_table text;
begin
 if record_kind not in ('trip','story','favorite') then raise exception 'Invalid kind'; end if;
 perform pg_advisory_xact_lock(hashtextextended(record_kind || ':' || record_id::text,0));
 if operation_id is not null then
  insert into public.triptrail_delete_operations values(operation_id) on conflict do nothing;
  if not found then return; end if;
 end if;
 root_table := case record_kind when 'trip' then 'triptrail_trips' when 'story' then 'triptrail_stories' else 'triptrail_favorites' end;
 execute format('select title from public.%I where id=$1',root_table) into record_title using record_id;
 -- Keep an intent even if this device deleted before its first upload.
 insert into public.triptrail_deleted_records(id,kind,title,recoverable) values(record_id,record_kind,coalesce(record_title,'未上传内容'),record_title is not null) on conflict(kind,id) do nothing;
end $$;
create or replace function public.triptrail_restore_record(record_id uuid,record_kind text)
returns void language plpgsql security invoker set search_path='' as $$
declare expiry bigint; root_table text;
begin
 perform pg_advisory_xact_lock(hashtextextended(record_kind || ':' || record_id::text,0));
 select expires_at_ms into expiry from public.triptrail_deleted_records where id=record_id and kind=record_kind for update;
 if not found then return; end if;
 if expiry <= (extract(epoch from now())*1000)::bigint then raise sqlstate 'PT410' using message='Recycle entry expired'; end if;
 root_table := case record_kind when 'trip' then 'triptrail_trips' when 'story' then 'triptrail_stories' when 'favorite' then 'triptrail_favorites' end;
 execute format('update public.%I set revision=revision+1,updated_at=now() where id=$1',root_table) using record_id;
 delete from public.triptrail_deleted_records where id=record_id and kind=record_kind;
end $$;
-- Purge payloads on sync/recycle access. Permanent small tombstones block stale offline uploads.
create or replace function public.triptrail_purge_recycle()
returns void language plpgsql security invoker set search_path='' as $$
declare r record; root_table text;
begin
 for r in select id,kind from public.triptrail_deleted_records where expires_at_ms <= (extract(epoch from now())*1000)::bigint order by kind,id loop
  perform pg_advisory_xact_lock(hashtextextended(r.kind || ':' || r.id::text,0));
  if exists(select 1 from public.triptrail_deleted_records where id=r.id and kind=r.kind and expires_at_ms <= (extract(epoch from now())*1000)::bigint) then
   root_table := case r.kind when 'trip' then 'triptrail_trips' when 'story' then 'triptrail_stories' else 'triptrail_favorites' end;
   execute format('delete from public.%I where id=$1',root_table) using r.id;
  end if;
 end loop;
end $$;
revoke all on function public.triptrail_trash_record(uuid,text,uuid),public.triptrail_restore_record(uuid,text),public.triptrail_purge_recycle() from public;
grant execute on function public.triptrail_trash_record(uuid,text,uuid),public.triptrail_restore_record(uuid,text),public.triptrail_purge_recycle() to anon,authenticated;
notify pgrst,'reload schema';
commit;
