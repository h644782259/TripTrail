-- Incremental, atomic migration: unify trips and footprints. Never run cloud-initialize.sql.
-- Keeps a complete pre-migration snapshot; legacy story tables are retained for recovery.
-- Old clients are rejected after this migration. Install both updated clients.
begin;
create table if not exists public.triptrail_unified_migration_backup (
 kind text not null, id uuid not null, payload jsonb not null, revision bigint not null,
 saved_at timestamptz not null default now(), primary key(kind,id)
);
insert into public.triptrail_unified_migration_backup(kind,id,payload,revision)
select kind,id,payload,revision from public.triptrail_cloud_records on conflict(kind,id) do nothing;
create table if not exists public.triptrail_journey_schema(version integer primary key, migrated_at timestamptz not null default now());
alter table public.triptrail_trips add column if not exists "journalSummary" text not null default '';
alter table public.triptrail_trips add column if not exists "coverMedia" jsonb;
alter table public.triptrail_trips add column if not exists "coverZoom" double precision not null default 1;
alter table public.triptrail_trips add column if not exists "coverOffsetX" double precision not null default 0;
alter table public.triptrail_trips add column if not exists "coverOffsetY" double precision not null default 0;
alter table public.triptrail_trip_days add column if not exists "journalNote" text not null default '';
alter table public.triptrail_trip_days add column if not exists "journalDetails" text not null default '';
alter table public.triptrail_trip_items add column if not exists "journalNote" text not null default '';
alter table public.triptrail_trip_items add column if not exists "journalSupplement" text not null default '';
create unique index if not exists trip_item_media_record_identity on public.triptrail_trip_item_media(root_id,id);
create unique index if not exists trip_item_vouchers_record_identity on public.triptrail_trip_item_vouchers(root_id,id);

-- A single pass merges legacy narrative fields and media, without replacing existing itinerary facts.
do $$
declare s record; d record; e record; m record; target uuid; target_day uuid; target_item uuid; extra_order integer; orphan_day uuid;
begin
 if exists(select 1 from public.triptrail_journey_schema where version=1) then return; end if;
 for s in select * from public.triptrail_stories t where not exists(select 1 from public.triptrail_deleted_records x where x.kind='story' and x.id=t.id) order by "createdAt",id loop
  select id into target from public.triptrail_trips t where t.id=coalesce(s."sourceTripID",s.id)
   and not exists(select 1 from public.triptrail_deleted_records x where x.kind='trip' and x.id=t.id);
  if target is null then
   target := s.id;
   if exists(select 1 from public.triptrail_deleted_records where kind='trip' and id=target) then continue; end if;
   insert into public.triptrail_trips(id,title,destination,"licensePlate","startDate","endDate",note,"createdAt")
   values(target,s.title,s.destination,'',s."startDate",s."endDate",'',s."createdAt") on conflict(id) do nothing;
  end if;
  update public.triptrail_trips set "journalSummary"=case when "journalSummary"='' then coalesce(s.summary,'') when coalesce(s.summary,'')='' or "journalSummary"=s.summary then "journalSummary" else "journalSummary"||E'\n\n'||s.summary end,
   "coverMedia"=coalesce("coverMedia",(select to_jsonb(c)-'root_id' from public.triptrail_story_cover_media c where c.root_id=s.id limit 1)),
   "coverZoom"=case when "coverMedia" is null then coalesce(s."coverZoom",1) else "coverZoom" end,
   "coverOffsetX"=case when "coverMedia" is null then coalesce(s."coverOffsetX",0) else "coverOffsetX" end,
   "coverOffsetY"=case when "coverMedia" is null then coalesce(s."coverOffsetY",0) else "coverOffsetY" end,
   revision=revision+1,updated_at=now() where id=target;
  -- Older footprints can have records without a day. Preserve those in a real migration day.
  if exists(select 1 from public.triptrail_story_entries orphan_entry where orphan_entry.root_id=s.id and
    not exists(select 1 from public.triptrail_story_days orphan_day_row where orphan_day_row.root_id=s.id and orphan_day_row.id=orphan_entry."storyDayID")) then
   orphan_day := gen_random_uuid();
   insert into public.triptrail_story_days(root_id,id,date,title,note,details,"didMigrateInlineSummary","sortOrder")
    values(s.id,orphan_day,s."startDate",'', '', '',true,0);
   update public.triptrail_story_entries orphan_entry set "storyDayID"=orphan_day where orphan_entry.root_id=s.id and
    not exists(select 1 from public.triptrail_story_days orphan_day_row where orphan_day_row.root_id=s.id and orphan_day_row.id=orphan_entry."storyDayID");
  end if;
  for d in select * from public.triptrail_story_days where root_id=s.id order by "sortOrder",id loop
   select id into target_day from public.triptrail_trip_days where root_id=target and (id=coalesce(d."sourceDayID",d.id) or date=d.date)
    order by (id=coalesce(d."sourceDayID",d.id)) desc limit 1;
   if target_day is null then
    target_day := coalesce(d."sourceDayID",d.id);
    insert into public.triptrail_trip_days(root_id,id,date,title,note,city,"sortOrder") values(target,target_day,d.date,d.title,'','',d."sortOrder");
   end if;
   update public.triptrail_trip_days set "journalNote"=case when "journalNote"='' then coalesce(d.note,'') when coalesce(d.note,'')='' or "journalNote"=d.note then "journalNote" else "journalNote"||E'\n\n'||d.note end,
    "journalDetails"=case when "journalDetails"='' then coalesce(d.details,'') when coalesce(d.details,'')='' or "journalDetails"=d.details then "journalDetails" else "journalDetails"||E'\n\n'||d.details end where root_id=target and id=target_day;
   for e in select * from public.triptrail_story_entries where root_id=s.id and "storyDayID"=d.id order by "sortOrder",id loop
    target_item := coalesce(e."sourceItemID",e.id);
    if not exists(select 1 from public.triptrail_trip_items where root_id=target and id=target_item) then
     insert into public.triptrail_trip_items(root_id,parent_id,id,title,"categoryRaw","startTime","endTime",address,note,"locationModeRaw","placeName","placeAddress","originName","originAddress","destinationName","destinationAddress","transportRaw","attractionTypeRaw","distanceText","playDurationMinutes","reservationInfo",cost,"isCompleted","executionStatusRaw","isAutomaticCompletionOverridden","isFixedTime","isTimePending","isFavorite","favoriteCity","favoriteCreatedAt","sortOrder")
     values(target,target_day,target_item,e.title,e."categoryRaw",coalesce(e."startTime",d.date),coalesce(e."endTime",d.date+3600000),coalesce(e.address,''),'',e."locationModeRaw",e."placeName",e."placeAddress",e."originName",e."originAddress",e."destinationName",e."destinationAddress",e."transportRaw",e."attractionTypeRaw",e."routeInfo",60,'',coalesce(e.cost,0),false,'未开始',false,false,e."startTime" is null,false,'',d.date,e."sortOrder");
    end if;
    update public.triptrail_trip_items set "journalNote"=case when "journalNote"='' then coalesce(e.note,'') when coalesce(e.note,'')='' or "journalNote"=e.note then "journalNote" else "journalNote"||E'\n\n'||e.note end,
     "journalSupplement"=case when "journalSupplement"='' then coalesce(e."supplementalInfo",'') when coalesce(e."supplementalInfo",'')='' or "journalSupplement"=e."supplementalInfo" then "journalSupplement" else "journalSupplement"||E'\n\n'||e."supplementalInfo" end where root_id=target and id=target_item;
    select coalesce(max("sortOrder"),-1)+1 into extra_order from public.triptrail_trip_item_media where root_id=target and parent_id=target_item;
    for m in select * from public.triptrail_story_entry_media where root_id=s.id and parent_id=e.id order by "sortOrder",id loop
     insert into public.triptrail_trip_item_media(root_id,parent_id,id,"localIdentifier","kindRaw",caption,"createdAt","sortOrder","cloudPath")
      values(target,target_item,m.id,m."localIdentifier",m."kindRaw",m.caption,m."createdAt",extra_order,m."cloudPath") on conflict(root_id,id) do nothing;
     if found then extra_order := extra_order+1; end if;
    end loop;
   end loop;
  end loop;
 end loop;
 insert into public.triptrail_journey_schema(version) values(1);
end $$;
create or replace view public.triptrail_cloud_records with (security_invoker=true) as
select t.id, 'trip'::text as kind, t.title, (to_jsonb(t) - 'revision' - 'updated_at' || jsonb_build_object('days', (select coalesce(jsonb_agg((to_jsonb(d) - 'root_id' || jsonb_build_object('items', (select coalesce(jsonb_agg((to_jsonb(i) - 'root_id' - 'parent_id' || jsonb_build_object('media', (select coalesce(jsonb_agg(to_jsonb(m) - 'root_id' - 'parent_id' order by m."sortOrder", m.id),'[]'::jsonb) from public.triptrail_trip_item_media m where m.root_id=i.root_id and m.parent_id=i.id), 'vouchers', (select coalesce(jsonb_agg(to_jsonb(v) - 'root_id' - 'parent_id' order by v.id),'[]'::jsonb) from public.triptrail_trip_item_vouchers v where v.root_id=i.root_id and v.parent_id=i.id))) order by i."sortOrder", i.id),'[]'::jsonb) from public.triptrail_trip_items i where i.root_id=d.root_id and i.parent_id=d.id))) order by d."sortOrder", d.id),'[]'::jsonb) from public.triptrail_trip_days d where d.root_id=t.id))) as payload, t.revision, t.updated_at from public.triptrail_trips t where not exists (select 1 from public.triptrail_deleted_records x where x.id=t.id and x.kind='trip')
union all
select t.id, 'favorite'::text as kind, t.title, (to_jsonb(t) - 'revision' - 'updated_at' || jsonb_build_object('media', (select coalesce(jsonb_agg(to_jsonb(m) - 'root_id' order by m."sortOrder", m.id),'[]'::jsonb) from public.triptrail_favorite_media m where m.root_id=t.id), 'vouchers', (select coalesce(jsonb_agg(to_jsonb(v) - 'root_id' order by v.id),'[]'::jsonb) from public.triptrail_favorite_vouchers v where v.root_id=t.id))) as payload, t.revision, t.updated_at from public.triptrail_favorites t where not exists (select 1 from public.triptrail_deleted_records x where x.id=t.id and x.kind='favorite');
create or replace function public.triptrail_patch_record(record_id uuid,record_kind text,record_title text,record_payload jsonb,expected_revision bigint,record_base_payload jsonb)
returns public.triptrail_cloud_records language plpgsql security invoker set search_path='' as $$
declare d jsonb; i jsonb; m jsonb; result public.triptrail_cloud_records;
begin
 perform pg_advisory_xact_lock(hashtextextended(record_kind||':'||record_id::text,0));
 if exists(select 1 from public.triptrail_deleted_records where id=record_id and kind=record_kind) then raise sqlstate 'PT410' using message='Record is in recycle bin or expired'; end if;
 if record_kind not in ('trip','favorite') then raise sqlstate 'PT426' using message='Update app: footprints are trip views'; end if;
 if jsonb_typeof(record_payload)<>'object' or (record_payload->>'id')::uuid is distinct from record_id or record_title is distinct from record_payload->>'title' or expected_revision<0 then raise exception 'Invalid cloud record'; end if;
 if record_kind='trip' then
  if not(record_payload ? 'journalSummary') or exists(select 1 from jsonb_array_elements(record_payload->'days') x where not(x ? 'journalNote'))
   or exists(select 1 from jsonb_path_query(record_payload,'$.days[*].items[*]') x where not(x ? 'journalNote')) then
   raise sqlstate 'PT426' using message='Update app: unified journey fields required';
  end if;
  if expected_revision=0 then
   insert into public.triptrail_trips ("id","title","destination","licensePlate","startDate","endDate","note","createdAt","journalSummary","coverMedia","coverZoom","coverOffsetX","coverOffsetY") select r."id",r."title",r."destination",r."licensePlate",r."startDate",r."endDate",r."note",r."createdAt",r."journalSummary",r."coverMedia",r."coverZoom",r."coverOffsetX",r."coverOffsetY" from jsonb_populate_record(null::public.triptrail_trips,record_payload) r on conflict(id) do nothing;
   if not found then raise sqlstate 'PT409' using message='Cloud revision conflict'; end if;
  else
   update public.triptrail_trips set ("id","title","destination","licensePlate","startDate","endDate","note","createdAt","journalSummary","coverMedia","coverZoom","coverOffsetX","coverOffsetY")=(select r."id",r."title",r."destination",r."licensePlate",r."startDate",r."endDate",r."note",r."createdAt",r."journalSummary",r."coverMedia",r."coverZoom",r."coverOffsetX",r."coverOffsetY" from jsonb_populate_record(null::public.triptrail_trips,record_payload) r), revision=revision+1,updated_at=now() where id=record_id and revision=expected_revision;
   if not found then raise sqlstate 'PT409' using message='Cloud revision conflict'; end if;
  end if;
  -- Remove only deleted identities; the whole operation is atomic with the CAS above.
  delete from public.triptrail_trip_items where root_id=record_id and not(jsonb_path_query_array(record_payload,'$.days[*].items[*].id') ? id::text);
  delete from public.triptrail_trip_item_media where root_id=record_id and not(jsonb_path_query_array(record_payload,'$.days[*].items[*].media[*].id') ? id::text);
  delete from public.triptrail_trip_item_vouchers where root_id=record_id and not(jsonb_path_query_array(record_payload,'$.days[*].items[*].vouchers[*].id') ? id::text);
  delete from public.triptrail_trip_days where root_id=record_id and not(jsonb_path_query_array(record_payload,'$.days[*].id') ? id::text);
  for d in select value from jsonb_array_elements(record_payload->'days') loop
insert into public.triptrail_trip_days ("root_id","id","date","title","note","city","sortOrder","journalNote","journalDetails") select record_id,r."id",r."date",r."title",r."note",r."city",r."sortOrder",r."journalNote",r."journalDetails" from jsonb_populate_record(null::public.triptrail_trip_days, d) r on conflict(root_id,id) do update set "date"=excluded."date","title"=excluded."title","note"=excluded."note","city"=excluded."city","sortOrder"=excluded."sortOrder","journalNote"=excluded."journalNote","journalDetails"=excluded."journalDetails" where (triptrail_trip_days."date",triptrail_trip_days."title",triptrail_trip_days."note",triptrail_trip_days."city",triptrail_trip_days."sortOrder",triptrail_trip_days."journalNote",triptrail_trip_days."journalDetails") is distinct from (excluded."date",excluded."title",excluded."note",excluded."city",excluded."sortOrder",excluded."journalNote",excluded."journalDetails");
 for i in select value from jsonb_array_elements(d->'items') loop
insert into public.triptrail_trip_items ("root_id","parent_id","id","title","categoryRaw","startTime","endTime","address","note","locationModeRaw","placeName","placeAddress","originName","originAddress","destinationName","destinationAddress","transportRaw","attractionTypeRaw","distanceText","playDurationMinutes","reservationInfo","cost","isCompleted","executionStatusRaw","isAutomaticCompletionOverridden","isFixedTime","isTimePending","isFavorite","favoriteCity","favoriteCreatedAt","sourceFavoriteID","sortOrder","journalNote","journalSupplement") select record_id,(d->>'id')::uuid,r."id",r."title",r."categoryRaw",r."startTime",r."endTime",r."address",r."note",r."locationModeRaw",r."placeName",r."placeAddress",r."originName",r."originAddress",r."destinationName",r."destinationAddress",r."transportRaw",r."attractionTypeRaw",r."distanceText",r."playDurationMinutes",r."reservationInfo",r."cost",r."isCompleted",r."executionStatusRaw",r."isAutomaticCompletionOverridden",r."isFixedTime",r."isTimePending",r."isFavorite",r."favoriteCity",r."favoriteCreatedAt",r."sourceFavoriteID",r."sortOrder",r."journalNote",r."journalSupplement" from jsonb_populate_record(null::public.triptrail_trip_items, i) r on conflict(root_id,id) do update set "parent_id"=excluded."parent_id","title"=excluded."title","categoryRaw"=excluded."categoryRaw","startTime"=excluded."startTime","endTime"=excluded."endTime","address"=excluded."address","note"=excluded."note","locationModeRaw"=excluded."locationModeRaw","placeName"=excluded."placeName","placeAddress"=excluded."placeAddress","originName"=excluded."originName","originAddress"=excluded."originAddress","destinationName"=excluded."destinationName","destinationAddress"=excluded."destinationAddress","transportRaw"=excluded."transportRaw","attractionTypeRaw"=excluded."attractionTypeRaw","distanceText"=excluded."distanceText","playDurationMinutes"=excluded."playDurationMinutes","reservationInfo"=excluded."reservationInfo","cost"=excluded."cost","isCompleted"=excluded."isCompleted","executionStatusRaw"=excluded."executionStatusRaw","isAutomaticCompletionOverridden"=excluded."isAutomaticCompletionOverridden","isFixedTime"=excluded."isFixedTime","isTimePending"=excluded."isTimePending","isFavorite"=excluded."isFavorite","favoriteCity"=excluded."favoriteCity","favoriteCreatedAt"=excluded."favoriteCreatedAt","sourceFavoriteID"=excluded."sourceFavoriteID","sortOrder"=excluded."sortOrder","journalNote"=excluded."journalNote","journalSupplement"=excluded."journalSupplement" where (triptrail_trip_items."parent_id",triptrail_trip_items."title",triptrail_trip_items."categoryRaw",triptrail_trip_items."startTime",triptrail_trip_items."endTime",triptrail_trip_items."address",triptrail_trip_items."note",triptrail_trip_items."locationModeRaw",triptrail_trip_items."placeName",triptrail_trip_items."placeAddress",triptrail_trip_items."originName",triptrail_trip_items."originAddress",triptrail_trip_items."destinationName",triptrail_trip_items."destinationAddress",triptrail_trip_items."transportRaw",triptrail_trip_items."attractionTypeRaw",triptrail_trip_items."distanceText",triptrail_trip_items."playDurationMinutes",triptrail_trip_items."reservationInfo",triptrail_trip_items."cost",triptrail_trip_items."isCompleted",triptrail_trip_items."executionStatusRaw",triptrail_trip_items."isAutomaticCompletionOverridden",triptrail_trip_items."isFixedTime",triptrail_trip_items."isTimePending",triptrail_trip_items."isFavorite",triptrail_trip_items."favoriteCity",triptrail_trip_items."favoriteCreatedAt",triptrail_trip_items."sourceFavoriteID",triptrail_trip_items."sortOrder",triptrail_trip_items."journalNote",triptrail_trip_items."journalSupplement") is distinct from (excluded."parent_id",excluded."title",excluded."categoryRaw",excluded."startTime",excluded."endTime",excluded."address",excluded."note",excluded."locationModeRaw",excluded."placeName",excluded."placeAddress",excluded."originName",excluded."originAddress",excluded."destinationName",excluded."destinationAddress",excluded."transportRaw",excluded."attractionTypeRaw",excluded."distanceText",excluded."playDurationMinutes",excluded."reservationInfo",excluded."cost",excluded."isCompleted",excluded."executionStatusRaw",excluded."isAutomaticCompletionOverridden",excluded."isFixedTime",excluded."isTimePending",excluded."isFavorite",excluded."favoriteCity",excluded."favoriteCreatedAt",excluded."sourceFavoriteID",excluded."sortOrder",excluded."journalNote",excluded."journalSupplement");
for m in select value from jsonb_array_elements(coalesce(nullif(i->'media','null'::jsonb),'[]'::jsonb)) loop
insert into public.triptrail_trip_item_media ("root_id","parent_id","id","localIdentifier","kindRaw","caption","createdAt","sortOrder","cloudPath") select record_id,(i->>'id')::uuid,r."id",r."localIdentifier",r."kindRaw",r."caption",r."createdAt",r."sortOrder",r."cloudPath" from jsonb_populate_record(null::public.triptrail_trip_item_media, m) r on conflict(root_id,id) do update set "parent_id"=excluded."parent_id","localIdentifier"=excluded."localIdentifier","kindRaw"=excluded."kindRaw","caption"=excluded."caption","createdAt"=excluded."createdAt","sortOrder"=excluded."sortOrder","cloudPath"=excluded."cloudPath" where (triptrail_trip_item_media."parent_id",triptrail_trip_item_media."localIdentifier",triptrail_trip_item_media."kindRaw",triptrail_trip_item_media."caption",triptrail_trip_item_media."createdAt",triptrail_trip_item_media."sortOrder",triptrail_trip_item_media."cloudPath") is distinct from (excluded."parent_id",excluded."localIdentifier",excluded."kindRaw",excluded."caption",excluded."createdAt",excluded."sortOrder",excluded."cloudPath");
end loop;
for m in select value from jsonb_array_elements(coalesce(nullif(i->'vouchers','null'::jsonb),'[]'::jsonb)) loop
insert into public.triptrail_trip_item_vouchers ("root_id","parent_id","id","name","mimeType","dataBase64") select record_id,(i->>'id')::uuid,r."id",r."name",r."mimeType",r."dataBase64" from jsonb_populate_record(null::public.triptrail_trip_item_vouchers, m) r on conflict(root_id,id) do update set "parent_id"=excluded."parent_id","name"=excluded."name","mimeType"=excluded."mimeType","dataBase64"=excluded."dataBase64" where (triptrail_trip_item_vouchers."parent_id",triptrail_trip_item_vouchers."name",triptrail_trip_item_vouchers."mimeType",triptrail_trip_item_vouchers."dataBase64") is distinct from (excluded."parent_id",excluded."name",excluded."mimeType",excluded."dataBase64");
end loop;
end loop; end loop;
 elsif record_kind='favorite' then
if expected_revision = 0 then
        insert into public.triptrail_favorites ("id","title","categoryRaw","startTime","endTime","address","note","locationModeRaw","placeName","placeAddress","originName","originAddress","destinationName","destinationAddress","transportRaw","attractionTypeRaw","distanceText","playDurationMinutes","reservationInfo","cost","isCompleted","executionStatusRaw","isAutomaticCompletionOverridden","isFixedTime","isTimePending","isFavorite","favoriteCity","favoriteCreatedAt","sourceFavoriteID","sortOrder") select r."id",r."title",r."categoryRaw",r."startTime",r."endTime",r."address",r."note",r."locationModeRaw",r."placeName",r."placeAddress",r."originName",r."originAddress",r."destinationName",r."destinationAddress",r."transportRaw",r."attractionTypeRaw",r."distanceText",r."playDurationMinutes",r."reservationInfo",r."cost",r."isCompleted",r."executionStatusRaw",r."isAutomaticCompletionOverridden",r."isFixedTime",r."isTimePending",r."isFavorite",r."favoriteCity",r."favoriteCreatedAt",r."sourceFavoriteID",r."sortOrder" from jsonb_populate_record(null::public.triptrail_favorites, record_payload) r on conflict(id) do nothing;
        if not found then raise sqlstate 'PT409' using message='Cloud revision conflict'; end if;
    else
        update public.triptrail_favorites t set ("id","title","categoryRaw","startTime","endTime","address","note","locationModeRaw","placeName","placeAddress","originName","originAddress","destinationName","destinationAddress","transportRaw","attractionTypeRaw","distanceText","playDurationMinutes","reservationInfo","cost","isCompleted","executionStatusRaw","isAutomaticCompletionOverridden","isFixedTime","isTimePending","isFavorite","favoriteCity","favoriteCreatedAt","sourceFavoriteID","sortOrder") = (select r."id",r."title",r."categoryRaw",r."startTime",r."endTime",r."address",r."note",r."locationModeRaw",r."placeName",r."placeAddress",r."originName",r."originAddress",r."destinationName",r."destinationAddress",r."transportRaw",r."attractionTypeRaw",r."distanceText",r."playDurationMinutes",r."reservationInfo",r."cost",r."isCompleted",r."executionStatusRaw",r."isAutomaticCompletionOverridden",r."isFixedTime",r."isTimePending",r."isFavorite",r."favoriteCity",r."favoriteCreatedAt",r."sourceFavoriteID",r."sortOrder" from jsonb_populate_record(null::public.triptrail_favorites,record_payload) r),
            revision=t.revision+1, updated_at=now()
        where t.id=record_id and t.revision=expected_revision;
        if not found then raise sqlstate 'PT409' using message='Cloud revision conflict'; end if;
    end if;
delete from public.triptrail_favorite_media where root_id=record_id and not (jsonb_path_query_array(record_payload, '$.media[*].id') ? id::text);
delete from public.triptrail_favorite_vouchers where root_id=record_id and not (jsonb_path_query_array(record_payload, '$.vouchers[*].id') ? id::text);
for m in select value from jsonb_array_elements(coalesce(nullif(record_payload->'media','null'::jsonb),'[]'::jsonb)) loop
 insert into public.triptrail_favorite_media ("root_id","id","localIdentifier","kindRaw","caption","createdAt","sortOrder","cloudPath") select record_id,r."id",r."localIdentifier",r."kindRaw",r."caption",r."createdAt",r."sortOrder",r."cloudPath" from jsonb_populate_record(null::public.triptrail_favorite_media, m) r on conflict(root_id,id) do update set "localIdentifier"=excluded."localIdentifier","kindRaw"=excluded."kindRaw","caption"=excluded."caption","createdAt"=excluded."createdAt","sortOrder"=excluded."sortOrder","cloudPath"=excluded."cloudPath" where (triptrail_favorite_media."localIdentifier",triptrail_favorite_media."kindRaw",triptrail_favorite_media."caption",triptrail_favorite_media."createdAt",triptrail_favorite_media."sortOrder",triptrail_favorite_media."cloudPath") is distinct from (excluded."localIdentifier",excluded."kindRaw",excluded."caption",excluded."createdAt",excluded."sortOrder",excluded."cloudPath");
end loop;for m in select value from jsonb_array_elements(coalesce(nullif(record_payload->'vouchers','null'::jsonb),'[]'::jsonb)) loop
 insert into public.triptrail_favorite_vouchers ("root_id","id","name","mimeType","dataBase64") select record_id,r."id",r."name",r."mimeType",r."dataBase64" from jsonb_populate_record(null::public.triptrail_favorite_vouchers, m) r on conflict(root_id,id) do update set "name"=excluded."name","mimeType"=excluded."mimeType","dataBase64"=excluded."dataBase64" where (triptrail_favorite_vouchers."name",triptrail_favorite_vouchers."mimeType",triptrail_favorite_vouchers."dataBase64") is distinct from (excluded."name",excluded."mimeType",excluded."dataBase64");
end loop;
 end if;
 select * into result from public.triptrail_cloud_records where id=record_id and kind=record_kind;
 return result;
end $$;
create or replace function public.triptrail_save_record(record_id uuid,record_kind text,record_title text,record_payload jsonb,expected_revision bigint)
returns public.triptrail_cloud_records language plpgsql security invoker set search_path='' as $$
begin
 if expected_revision<>0 then raise sqlstate 'PT426' using message='Update app: use atomic item save'; end if;
 return public.triptrail_patch_record(record_id,record_kind,record_title,record_payload,0,null);
end $$;
revoke all on function public.triptrail_patch_record(uuid,text,text,jsonb,bigint,jsonb),public.triptrail_save_record(uuid,text,text,jsonb,bigint) from public;
grant execute on function public.triptrail_patch_record(uuid,text,text,jsonb,bigint,jsonb),public.triptrail_save_record(uuid,text,text,jsonb,bigint) to anon,authenticated;
create or replace function public.triptrail_media_referenced(p text) returns boolean
language sql stable security invoker set search_path='' as $$
 select exists(select 1 from public.triptrail_trip_item_media where "cloudPath"=p)
 or exists(select 1 from public.triptrail_story_entry_media where "cloudPath"=p)
 or exists(select 1 from public.triptrail_story_cover_media where "cloudPath"=p)
 or exists(select 1 from public.triptrail_favorite_media where "cloudPath"=p)
 or exists(select 1 from public.triptrail_trips where "coverMedia"->>'cloudPath'=p)
$$;
create or replace function public.triptrail_journey_cover_guard() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
 perform pg_advisory_xact_lock(728349012);
 if NEW."coverMedia"->>'cloudPath' is not null and to_regclass('public.triptrail_gc_objects') is not null then
  if exists(select 1 from public.triptrail_gc_objects where bucket='triptrail-media' and path=NEW."coverMedia"->>'cloudPath' and deleting) then
   raise exception 'TRIPTRAIL_MEDIA_RETIRED: upload media with a new path';
  end if;
 end if;
 return NEW;
end $$;
drop trigger if exists triptrail_journey_cover_guard on public.triptrail_trips;
create trigger triptrail_journey_cover_guard before insert or update on public.triptrail_trips for each row execute function public.triptrail_journey_cover_guard();
commit;
