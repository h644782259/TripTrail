-- FIRST DEVELOPMENT RESET: drops only the old TripTrail JSON records table and RPC.

-- Business fields are scalar columns. Dates ending Date/Time and createdAt are epoch milliseconds.

-- JSON is constructed only at the API boundary; no business JSON payload is persisted.

begin;

drop function if exists public.triptrail_save_record(uuid,text,text,jsonb,bigint);

drop table if exists public.triptrail_cloud_records;

create table public.triptrail_trips (
  "id" uuid not null,
  "title" text not null,
  "destination" text not null,
  "licensePlate" text,
  "startDate" double precision not null,
  "endDate" double precision not null,
  "note" text not null,
  "createdAt" double precision not null,
  primary key(id),
  revision bigint not null default 1,
  updated_at timestamptz not null default now()
);

alter table public.triptrail_trips enable row level security;

grant select, insert, update, delete on public.triptrail_trips to anon, authenticated;

create policy shared_access on public.triptrail_trips for all to anon, authenticated using(true) with check(true);

create table public.triptrail_trip_days (
  root_id uuid not null references public.triptrail_trips(id) on delete cascade,
  "id" uuid not null,
  "date" double precision not null,
  "title" text not null,
  "note" text not null,
  "city" text,
  "sortOrder" integer not null,
  primary key(root_id,id)
);

create index on public.triptrail_trip_days(root_id);

alter table public.triptrail_trip_days enable row level security;

grant select, insert, update, delete on public.triptrail_trip_days to anon, authenticated;

create policy shared_access on public.triptrail_trip_days for all to anon, authenticated using(true) with check(true);

create table public.triptrail_trip_items (
  root_id uuid not null references public.triptrail_trips(id) on delete cascade,
  parent_id uuid not null,
  "id" uuid not null,
  "title" text not null,
  "categoryRaw" text not null,
  "startTime" double precision not null,
  "endTime" double precision not null,
  "address" text not null,
  "note" text not null,
  "locationModeRaw" text,
  "placeName" text,
  "placeAddress" text,
  "originName" text,
  "originAddress" text,
  "destinationName" text,
  "destinationAddress" text,
  "transportRaw" text,
  "attractionTypeRaw" text,
  "distanceText" text,
  "playDurationMinutes" integer not null,
  "reservationInfo" text not null,
  "cost" double precision not null,
  "isCompleted" boolean not null,
  "executionStatusRaw" text,
  "isAutomaticCompletionOverridden" boolean,
  "isFixedTime" boolean,
  "isTimePending" boolean,
  "isFavorite" boolean,
  "favoriteCity" text,
  "favoriteCreatedAt" double precision,
  "sourceFavoriteID" uuid,
  "sortOrder" integer not null,
  primary key(root_id,id),
  foreign key(root_id,parent_id) references public.triptrail_trip_days(root_id,id) on delete cascade
);

create index on public.triptrail_trip_items(root_id,parent_id);

alter table public.triptrail_trip_items enable row level security;

grant select, insert, update, delete on public.triptrail_trip_items to anon, authenticated;

create policy shared_access on public.triptrail_trip_items for all to anon, authenticated using(true) with check(true);

create table public.triptrail_stories (
  "id" uuid not null,
  "title" text not null,
  "destination" text not null,
  "startDate" double precision not null,
  "endDate" double precision not null,
  "summary" text not null,
  "createdAt" double precision not null,
  "sourceTripID" uuid,
  "syncScopeRaw" text not null,
  "sourceSelectionIDsRaw" text not null,
  "coverZoom" double precision,
  "coverOffsetX" double precision,
  "coverOffsetY" double precision,
  primary key(id),
  revision bigint not null default 1,
  updated_at timestamptz not null default now()
);

alter table public.triptrail_stories enable row level security;

grant select, insert, update, delete on public.triptrail_stories to anon, authenticated;

create policy shared_access on public.triptrail_stories for all to anon, authenticated using(true) with check(true);

create table public.triptrail_story_days (
  root_id uuid not null references public.triptrail_stories(id) on delete cascade,
  "id" uuid not null,
  "date" double precision not null,
  "title" text not null,
  "note" text not null,
  "details" text not null,
  "didMigrateInlineSummary" boolean not null,
  "sortOrder" integer not null,
  "sourceDayID" uuid,
  primary key(root_id,id)
);

create index on public.triptrail_story_days(root_id);

alter table public.triptrail_story_days enable row level security;

grant select, insert, update, delete on public.triptrail_story_days to anon, authenticated;

create policy shared_access on public.triptrail_story_days for all to anon, authenticated using(true) with check(true);

create table public.triptrail_story_entries (
  root_id uuid not null references public.triptrail_stories(id) on delete cascade,
  "id" uuid not null,
  "title" text not null,
  "categoryRaw" text not null,
  "startTime" double precision,
  "endTime" double precision,
  "timeLabel" text not null,
  "address" text not null,
  "supplementalInfo" text,
  "note" text not null,
  "locationModeRaw" text,
  "placeName" text,
  "placeAddress" text,
  "originName" text,
  "originAddress" text,
  "destinationName" text,
  "destinationAddress" text,
  "transportRaw" text,
  "attractionTypeRaw" text,
  "routeInfo" text,
  "cost" double precision,
  "didPrefillSourceMemory" boolean,
  "sourceMemoryPrefill" text,
  "sortOrder" integer not null,
  "sourceItemID" uuid,
  "storyDayID" uuid,
  primary key(root_id,id),
  foreign key(root_id,"storyDayID") references public.triptrail_story_days(root_id,id) deferrable initially deferred
);

create index on public.triptrail_story_entries(root_id);

alter table public.triptrail_story_entries enable row level security;

grant select, insert, update, delete on public.triptrail_story_entries to anon, authenticated;

create policy shared_access on public.triptrail_story_entries for all to anon, authenticated using(true) with check(true);

create table public.triptrail_favorites (
  "id" uuid not null,
  "title" text not null,
  "categoryRaw" text not null,
  "startTime" double precision not null,
  "endTime" double precision not null,
  "address" text not null,
  "note" text not null,
  "locationModeRaw" text,
  "placeName" text,
  "placeAddress" text,
  "originName" text,
  "originAddress" text,
  "destinationName" text,
  "destinationAddress" text,
  "transportRaw" text,
  "attractionTypeRaw" text,
  "distanceText" text,
  "playDurationMinutes" integer not null,
  "reservationInfo" text not null,
  "cost" double precision not null,
  "isCompleted" boolean not null,
  "executionStatusRaw" text,
  "isAutomaticCompletionOverridden" boolean,
  "isFixedTime" boolean,
  "isTimePending" boolean,
  "isFavorite" boolean,
  "favoriteCity" text,
  "favoriteCreatedAt" double precision,
  "sourceFavoriteID" uuid,
  "sortOrder" integer not null,
  primary key(id),
  revision bigint not null default 1,
  updated_at timestamptz not null default now()
);

alter table public.triptrail_favorites enable row level security;

grant select, insert, update, delete on public.triptrail_favorites to anon, authenticated;

create policy shared_access on public.triptrail_favorites for all to anon, authenticated using(true) with check(true);

create table public.triptrail_trip_item_media (
  root_id uuid not null references public.triptrail_trips(id) on delete cascade,
  parent_id uuid not null,
  "id" uuid not null,
  "localIdentifier" text not null,
  "kindRaw" text not null,
  "caption" text not null,
  "createdAt" double precision not null,
  "sortOrder" integer not null,
  "cloudPath" text not null,
  foreign key(root_id,parent_id) references public.triptrail_trip_items(root_id,id) on delete cascade
);

create index on public.triptrail_trip_item_media(root_id,parent_id);

alter table public.triptrail_trip_item_media enable row level security;

grant select, insert, update, delete on public.triptrail_trip_item_media to anon, authenticated;

create policy shared_access on public.triptrail_trip_item_media for all to anon, authenticated using(true) with check(true);

create table public.triptrail_story_entry_media (
  root_id uuid not null references public.triptrail_stories(id) on delete cascade,
  parent_id uuid not null,
  "id" uuid not null,
  "localIdentifier" text not null,
  "kindRaw" text not null,
  "caption" text not null,
  "createdAt" double precision not null,
  "sortOrder" integer not null,
  "cloudPath" text not null,
  foreign key(root_id,parent_id) references public.triptrail_story_entries(root_id,id) on delete cascade
);

create index on public.triptrail_story_entry_media(root_id,parent_id);

alter table public.triptrail_story_entry_media enable row level security;

grant select, insert, update, delete on public.triptrail_story_entry_media to anon, authenticated;

create policy shared_access on public.triptrail_story_entry_media for all to anon, authenticated using(true) with check(true);

create table public.triptrail_story_cover_media (
  root_id uuid not null references public.triptrail_stories(id) on delete cascade,
  "id" uuid not null,
  "localIdentifier" text not null,
  "kindRaw" text not null,
  "caption" text not null,
  "createdAt" double precision not null,
  "sortOrder" integer not null,
  "cloudPath" text not null
);

create index on public.triptrail_story_cover_media(root_id);

alter table public.triptrail_story_cover_media enable row level security;

grant select, insert, update, delete on public.triptrail_story_cover_media to anon, authenticated;

create policy shared_access on public.triptrail_story_cover_media for all to anon, authenticated using(true) with check(true);

create table public.triptrail_favorite_media (
  root_id uuid not null references public.triptrail_favorites(id) on delete cascade,
  "id" uuid not null,
  "localIdentifier" text not null,
  "kindRaw" text not null,
  "caption" text not null,
  "createdAt" double precision not null,
  "sortOrder" integer not null,
  "cloudPath" text not null
);

create index on public.triptrail_favorite_media(root_id);

alter table public.triptrail_favorite_media enable row level security;

grant select, insert, update, delete on public.triptrail_favorite_media to anon, authenticated;

create policy shared_access on public.triptrail_favorite_media for all to anon, authenticated using(true) with check(true);

create table public.triptrail_trip_item_vouchers (
  root_id uuid not null references public.triptrail_trips(id) on delete cascade,
  parent_id uuid not null,
  "id" text not null,
  "name" text not null,
  "mimeType" text not null,
  "dataBase64" text not null,
  foreign key(root_id,parent_id) references public.triptrail_trip_items(root_id,id) on delete cascade
);

create index on public.triptrail_trip_item_vouchers(root_id,parent_id);

alter table public.triptrail_trip_item_vouchers enable row level security;

grant select, insert, update, delete on public.triptrail_trip_item_vouchers to anon, authenticated;

create policy shared_access on public.triptrail_trip_item_vouchers for all to anon, authenticated using(true) with check(true);

create table public.triptrail_favorite_vouchers (
  root_id uuid not null references public.triptrail_favorites(id) on delete cascade,
  "id" text not null,
  "name" text not null,
  "mimeType" text not null,
  "dataBase64" text not null
);

create index on public.triptrail_favorite_vouchers(root_id);

alter table public.triptrail_favorite_vouchers enable row level security;

grant select, insert, update, delete on public.triptrail_favorite_vouchers to anon, authenticated;

create policy shared_access on public.triptrail_favorite_vouchers for all to anon, authenticated using(true) with check(true);

create view public.triptrail_cloud_records with (security_invoker=true) as
select t.id, 'trip'::text as kind, t.title, (to_jsonb(t) - 'revision' - 'updated_at' || jsonb_build_object('days', (select coalesce(jsonb_agg((to_jsonb(d) - 'root_id' || jsonb_build_object('items', (select coalesce(jsonb_agg((to_jsonb(i) - 'root_id' - 'parent_id' || jsonb_build_object('media', (select coalesce(jsonb_agg(to_jsonb(m) - 'root_id' - 'parent_id' order by m."sortOrder", m.id),'[]'::jsonb) from public.triptrail_trip_item_media m where m.root_id=i.root_id and m.parent_id=i.id), 'vouchers', (select coalesce(jsonb_agg(to_jsonb(v) - 'root_id' - 'parent_id' order by v.id),'[]'::jsonb) from public.triptrail_trip_item_vouchers v where v.root_id=i.root_id and v.parent_id=i.id))) order by i."sortOrder", i.id),'[]'::jsonb) from public.triptrail_trip_items i where i.root_id=d.root_id and i.parent_id=d.id))) order by d."sortOrder", d.id),'[]'::jsonb) from public.triptrail_trip_days d where d.root_id=t.id))) as payload, t.revision, t.updated_at from public.triptrail_trips t
union all
select t.id, 'story'::text as kind, t.title, (to_jsonb(t) - 'revision' - 'updated_at' || jsonb_build_object('days', (select coalesce(jsonb_agg(to_jsonb(d) - 'root_id' order by d."sortOrder", d.id),'[]'::jsonb) from public.triptrail_story_days d where d.root_id=t.id), 'entries', (select coalesce(jsonb_agg((to_jsonb(e) - 'root_id' || jsonb_build_object('media', (select coalesce(jsonb_agg(to_jsonb(m) - 'root_id' - 'parent_id' order by m."sortOrder", m.id),'[]'::jsonb) from public.triptrail_story_entry_media m where m.root_id=e.root_id and m.parent_id=e.id))) order by e."sortOrder", e.id),'[]'::jsonb) from public.triptrail_story_entries e where e.root_id=t.id), 'coverMedia', (select to_jsonb(m) - 'root_id' from public.triptrail_story_cover_media m where m.root_id=t.id limit 1))) as payload, t.revision, t.updated_at from public.triptrail_stories t
union all
select t.id, 'favorite'::text as kind, t.title, (to_jsonb(t) - 'revision' - 'updated_at' || jsonb_build_object('media', (select coalesce(jsonb_agg(to_jsonb(m) - 'root_id' order by m."sortOrder", m.id),'[]'::jsonb) from public.triptrail_favorite_media m where m.root_id=t.id), 'vouchers', (select coalesce(jsonb_agg(to_jsonb(v) - 'root_id' order by v.id),'[]'::jsonb) from public.triptrail_favorite_vouchers v where v.root_id=t.id))) as payload, t.revision, t.updated_at from public.triptrail_favorites t;

grant select on public.triptrail_cloud_records to anon, authenticated;

create function public.triptrail_save_record(record_id uuid,record_kind text,record_title text,record_payload jsonb,expected_revision bigint)
returns public.triptrail_cloud_records language plpgsql security invoker set search_path='' as $$
declare d jsonb; i jsonb; m jsonb; result public.triptrail_cloud_records;
begin
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
revoke all on function public.triptrail_save_record(uuid,text,text,jsonb,bigint) from public;
grant execute on function public.triptrail_save_record(uuid,text,text,jsonb,bigint) to anon,authenticated;


insert into storage.buckets(id,name,public) values('triptrail-media','triptrail-media',true) on conflict(id) do nothing;
drop policy if exists triptrail_media_read on storage.objects;
create policy triptrail_media_read on storage.objects for select to anon,authenticated using(bucket_id='triptrail-media');
drop policy if exists triptrail_media_insert on storage.objects;
create policy triptrail_media_insert on storage.objects for insert to anon,authenticated with check(bucket_id='triptrail-media');
notify pgrst,'reload schema';
commit;
