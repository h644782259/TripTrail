-- Incremental migration: run on the existing cloud database; no data reset.
begin;
alter table public.triptrail_trip_items add column if not exists "attractionTypeRaw" text;
alter table public.triptrail_favorites add column if not exists "attractionTypeRaw" text;
alter table public.triptrail_story_entries add column if not exists "attractionTypeRaw" text;

alter table public.triptrail_trip_days add column if not exists city text;
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
insert into public.triptrail_trip_days ("root_id","id","date","title","note","city","sortOrder") select record_id,r."id",r."date",r."title",r."note",r."city",r."sortOrder" from jsonb_populate_record(null::public.triptrail_trip_days, d) r;
 for i in select value from jsonb_array_elements(d->'items') loop
insert into public.triptrail_trip_items ("root_id","parent_id","id","title","categoryRaw","startTime","endTime","address","note","locationModeRaw","placeName","placeAddress","originName","originAddress","destinationName","destinationAddress","transportRaw","attractionTypeRaw","distanceText","playDurationMinutes","reservationInfo","cost","isCompleted","executionStatusRaw","isAutomaticCompletionOverridden","isFixedTime","isTimePending","isFavorite","favoriteCity","favoriteCreatedAt","sourceFavoriteID","sortOrder") select record_id,(d->>'id')::uuid,r."id",r."title",r."categoryRaw",r."startTime",r."endTime",r."address",r."note",r."locationModeRaw",r."placeName",r."placeAddress",r."originName",r."originAddress",r."destinationName",r."destinationAddress",r."transportRaw",r."attractionTypeRaw",r."distanceText",r."playDurationMinutes",r."reservationInfo",r."cost",r."isCompleted",r."executionStatusRaw",r."isAutomaticCompletionOverridden",r."isFixedTime",r."isTimePending",r."isFavorite",r."favoriteCity",r."favoriteCreatedAt",r."sourceFavoriteID",r."sortOrder" from jsonb_populate_record(null::public.triptrail_trip_items, i) r;for m in select value from jsonb_array_elements(coalesce(nullif(i->'media','null'::jsonb),'[]'::jsonb)) loop
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
insert into public.triptrail_story_entries ("root_id","id","title","categoryRaw","startTime","endTime","timeLabel","address","supplementalInfo","note","locationModeRaw","placeName","placeAddress","originName","originAddress","destinationName","destinationAddress","transportRaw","attractionTypeRaw","routeInfo","cost","didPrefillSourceMemory","sourceMemoryPrefill","sortOrder","sourceItemID","storyDayID") select record_id,r."id",r."title",r."categoryRaw",r."startTime",r."endTime",r."timeLabel",r."address",r."supplementalInfo",r."note",r."locationModeRaw",r."placeName",r."placeAddress",r."originName",r."originAddress",r."destinationName",r."destinationAddress",r."transportRaw",r."attractionTypeRaw",r."routeInfo",r."cost",r."didPrefillSourceMemory",r."sourceMemoryPrefill",r."sortOrder",r."sourceItemID",r."storyDayID" from jsonb_populate_record(null::public.triptrail_story_entries, i) r;for m in select value from jsonb_array_elements(coalesce(nullif(i->'media','null'::jsonb),'[]'::jsonb)) loop
 insert into public.triptrail_story_entry_media ("root_id","parent_id","id","localIdentifier","kindRaw","caption","createdAt","sortOrder","cloudPath") select record_id,(i->>'id')::uuid,r."id",r."localIdentifier",r."kindRaw",r."caption",r."createdAt",r."sortOrder",r."cloudPath" from jsonb_populate_record(null::public.triptrail_story_entry_media, m) r;
end loop;
end loop;
if jsonb_typeof(record_payload->'coverMedia')='object' then
insert into public.triptrail_story_cover_media ("root_id","id","localIdentifier","kindRaw","caption","createdAt","sortOrder","cloudPath") select record_id,r."id",r."localIdentifier",r."kindRaw",r."caption",r."createdAt",r."sortOrder",r."cloudPath" from jsonb_populate_record(null::public.triptrail_story_cover_media, record_payload->'coverMedia') r;
end if;
else
if expected_revision = 0 then
        insert into public.triptrail_favorites ("id","title","categoryRaw","startTime","endTime","address","note","locationModeRaw","placeName","placeAddress","originName","originAddress","destinationName","destinationAddress","transportRaw","attractionTypeRaw","distanceText","playDurationMinutes","reservationInfo","cost","isCompleted","executionStatusRaw","isAutomaticCompletionOverridden","isFixedTime","isTimePending","isFavorite","favoriteCity","favoriteCreatedAt","sourceFavoriteID","sortOrder") select r."id",r."title",r."categoryRaw",r."startTime",r."endTime",r."address",r."note",r."locationModeRaw",r."placeName",r."placeAddress",r."originName",r."originAddress",r."destinationName",r."destinationAddress",r."transportRaw",r."attractionTypeRaw",r."distanceText",r."playDurationMinutes",r."reservationInfo",r."cost",r."isCompleted",r."executionStatusRaw",r."isAutomaticCompletionOverridden",r."isFixedTime",r."isTimePending",r."isFavorite",r."favoriteCity",r."favoriteCreatedAt",r."sourceFavoriteID",r."sortOrder" from jsonb_populate_record(null::public.triptrail_favorites, record_payload) r on conflict(id) do nothing;
        if not found then raise sqlstate 'PT409' using message='Cloud revision conflict'; end if;
    else
        update public.triptrail_favorites t set ("id","title","categoryRaw","startTime","endTime","address","note","locationModeRaw","placeName","placeAddress","originName","originAddress","destinationName","destinationAddress","transportRaw","attractionTypeRaw","distanceText","playDurationMinutes","reservationInfo","cost","isCompleted","executionStatusRaw","isAutomaticCompletionOverridden","isFixedTime","isTimePending","isFavorite","favoriteCity","favoriteCreatedAt","sourceFavoriteID","sortOrder") = (select r."id",r."title",r."categoryRaw",r."startTime",r."endTime",r."address",r."note",r."locationModeRaw",r."placeName",r."placeAddress",r."originName",r."originAddress",r."destinationName",r."destinationAddress",r."transportRaw",r."attractionTypeRaw",r."distanceText",r."playDurationMinutes",r."reservationInfo",r."cost",r."isCompleted",r."executionStatusRaw",r."isAutomaticCompletionOverridden",r."isFixedTime",r."isTimePending",r."isFavorite",r."favoriteCity",r."favoriteCreatedAt",r."sourceFavoriteID",r."sortOrder" from jsonb_populate_record(null::public.triptrail_favorites,record_payload) r),
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
NOTIFY pgrst, 'reload schema';
commit;
