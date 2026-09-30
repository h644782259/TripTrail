"""Generate the first-release relational cloud schema from the portable Swift wire contract."""
from pathlib import Path
import re
source = Path("TripTrail/Services/DataBackupService.swift").read_text()
def fields(name):
    body = source.split("private struct " + name + ": Codable {",1)[1].split("\n    init",1)[0].split("\n    var ",1)[0]
    result=[]
    for name, type_ in re.findall(r"    let (\w+): ([^\n]+)",body):
        if type_.startswith("[") or type_ == "MediaRecord?": continue
        optional=type_.endswith("?"); t=type_.rstrip("?")
        result.append((name,{"UUID":"uuid","String":"text","Int":"integer","Double":"double precision","Date":"double precision","Bool":"boolean"}[t],optional))
    return result
defs={}
def table(name,record,parent=None,relation=None):
    defs[name]=(fields(record) if record else [],parent,relation)
table("trips","TripRecord")
table("trip_days","TripDayRecord","trips")
table("trip_items","ItineraryItemRecord","trips","trip_days")
table("stories","StoryRecord")
table("story_days","StoryDayRecord","stories")
table("story_entries","StoryEntryRecord","stories")
table("favorites","ItineraryItemRecord")
for name,parent,rel in [("trip_item_media","trips","trip_items"),("story_entry_media","stories","story_entries"),("story_cover_media","stories",None),("favorite_media","favorites",None)]:
    table(name,"MediaRecord",parent,rel);defs[name][0].append(("cloudPath","text",False))
for name,parent,rel in [("trip_item_vouchers","trips","trip_items"),("favorite_vouchers","favorites",None)]:
    table(name,None,parent,rel);defs[name][0].extend([("id","text",False),("name","text",False),("mimeType","text",False),("dataBase64","text",False)])
def full(n): return "public.triptrail_"+n
def cols(n): return [x[0] for x in defs[n][0]]
def q(x):return '"'+x+'"'
out=["-- FIRST DEVELOPMENT RESET: drops only the old TripTrail JSON records table and RPC.",
     "-- Business fields are scalar columns. Dates ending Date/Time and createdAt are epoch milliseconds.",
     "-- JSON is constructed only at the API boundary; no business JSON payload is persisted.",
     "begin;","drop function if exists public.triptrail_save_record(uuid,text,text,jsonb,bigint);",
     "drop table if exists public.triptrail_cloud_records;",
     # repeated installs use new schema file only once, to avoid accidental destruction
]
for n,(fs,parent,relation) in defs.items():
    leaf="media" in n or "vouchers" in n
    lines=[]
    if parent:lines.append("root_id uuid not null references "+full(parent)+"(id) on delete cascade")
    if relation:lines.append("parent_id uuid not null")
    for field,typ,opt in fs:lines.append(q(field)+" "+typ+("" if opt else " not null"))
    if parent:
        if not leaf: lines.append('primary key(root_id,id)')
    else:lines+=["primary key(id)","revision bigint not null default 1","updated_at timestamptz not null default now()"]
    if relation:lines.append("foreign key(root_id,parent_id) references "+full(relation)+"(root_id,id) on delete cascade")
    if n=="story_entries":lines.append('foreign key(root_id,"storyDayID") references public.triptrail_story_days(root_id,id) deferrable initially deferred')
    out.append("create table "+full(n)+" (\n  "+",\n  ".join(lines)+"\n);")
    if parent:out.append("create index on "+full(n)+"(root_id"+(",parent_id" if relation else "")+");")
    out += [f"alter table {full(n)} enable row level security;",
            f"grant select, insert, update, delete on {full(n)} to anon, authenticated;",
            f"create policy shared_access on {full(n)} for all to anon, authenticated using(true) with check(true);"]

# Construct recursive payloads directly from scalar rows.
def base(alias,parent=False,rel=False,root=False):
    remove=["root_id"] if parent else []
    if rel:remove+=["parent_id"]
    if root:remove+=["revision","updated_at"]
    return "to_jsonb("+alias+")"+''.join(" - '"+x+"'" for x in remove)
def arr(n,alias,condition,expr=None,order=True):
    expr=expr or base(alias,True,defs[n][2] is not None)
    return f"(select coalesce(jsonb_agg({expr}"+(f' order by {alias}."sortOrder", {alias}.id' if order else f' order by {alias}.id')+f"),'[]'::jsonb) from {full(n)} {alias} where {condition})"
def obj(b,**kw):
    return "("+b+" || jsonb_build_object("+", ".join("'"+k+"', "+v for k,v in kw.items())+"))"
item=obj(base("i",True,True),media=arr("trip_item_media","m","m.root_id=i.root_id and m.parent_id=i.id"),vouchers=arr("trip_item_vouchers","v","v.root_id=i.root_id and v.parent_id=i.id",order=False))
day=obj(base("d",True),items=arr("trip_items","i","i.root_id=d.root_id and i.parent_id=d.id",item))
trip=obj(base("t",root=True),days=arr("trip_days","d","d.root_id=t.id",day))
entry=obj(base("e",True),media=arr("story_entry_media","m","m.root_id=e.root_id and m.parent_id=e.id"))
cover="(select "+base("m",True)+" from "+full("story_cover_media")+" m where m.root_id=t.id limit 1)"
story=obj(base("t",root=True),days=arr("story_days","d","d.root_id=t.id"),entries=arr("story_entries","e","e.root_id=t.id",entry),coverMedia=cover)
fav=obj(base("t",root=True),media=arr("favorite_media","m","m.root_id=t.id"),vouchers=arr("favorite_vouchers","v","v.root_id=t.id",order=False))
out.append("create view public.triptrail_cloud_records with (security_invoker=true) as\n"+"\nunion all\n".join(f"select t.id, '{kind}'::text as kind, t.title, {expr} as payload, t.revision, t.updated_at from {full(n)} t" for n,kind,expr in [("trips","trip",trip),("stories","story",story),("favorites","favorite",fav)])+";")
out.append("grant select on public.triptrail_cloud_records to anon, authenticated;")

def insert(n,val,relation=None):
    fs=cols(n);parent=defs[n][1];rel=defs[n][2]
    columns=(["root_id"] if parent else [])+(["parent_id"] if rel else [])+fs
    values=(["record_id"] if parent else [])+([relation] if rel else [])+[f"r.{q(x)}" for x in fs]
    return f"insert into {full(n)} ({','.join(map(q,columns))}) select {','.join(values)} from jsonb_populate_record(null::{full(n)}, {val}) r;"
def root_save(n):
    cs=cols(n)
    return f"""if expected_revision = 0 then
        {insert(n,"record_payload")[:-1]} on conflict(id) do nothing;
        if not found then raise sqlstate 'PT409' using message='Cloud revision conflict'; end if;
    else
        update {full(n)} t set ({','.join(map(q,cs))}) = (select {','.join('r.'+q(x) for x in cs)} from jsonb_populate_record(null::{full(n)},record_payload) r),
            revision=t.revision+1, updated_at=now()
        where t.id=record_id and t.revision=expected_revision;
        if not found then raise sqlstate 'PT409' using message='Cloud revision conflict'; end if;
    end if;"""
def leaves(n,payload,rel=None,field="media"):
    return f"for m in select value from jsonb_array_elements(coalesce(nullif({payload}->'{field}','null'::jsonb),'[]'::jsonb)) loop\n {insert(n,'m',rel)}\nend loop;"
out.append("""create function public.triptrail_save_record(record_id uuid,record_kind text,record_title text,record_payload jsonb,expected_revision bigint)
returns public.triptrail_cloud_records language plpgsql security invoker set search_path='' as $$
declare d jsonb; i jsonb; m jsonb; result public.triptrail_cloud_records;
begin
if record_kind not in ('trip','story','favorite') or jsonb_typeof(record_payload) <> 'object'
   or (record_payload->>'id')::uuid is distinct from record_id or expected_revision < 0
   or record_title is distinct from record_payload->>'title' then
 raise exception 'Invalid cloud record';
end if;
if record_kind='trip' then
"""+root_save("trips")+"""
delete from public.triptrail_trip_days where root_id=record_id;
for d in select value from jsonb_array_elements(record_payload->'days') loop
"""+insert("trip_days","d")+"""
 for i in select value from jsonb_array_elements(d->'items') loop
"""+insert("trip_items","i","(d->>'id')::uuid")+leaves("trip_item_media","i","(i->>'id')::uuid")+leaves("trip_item_vouchers","i","(i->>'id')::uuid","vouchers")+"""
 end loop;
end loop;
elsif record_kind='story' then
"""+root_save("stories")+"""
delete from public.triptrail_story_entries where root_id=record_id;
delete from public.triptrail_story_days where root_id=record_id;
delete from public.triptrail_story_cover_media where root_id=record_id;
for d in select value from jsonb_array_elements(record_payload->'days') loop
"""+insert("story_days","d")+"""
end loop;
for i in select value from jsonb_array_elements(record_payload->'entries') loop
"""+insert("story_entries","i")+leaves("story_entry_media","i","(i->>'id')::uuid")+"""
end loop;
if jsonb_typeof(record_payload->'coverMedia')='object' then
"""+insert("story_cover_media","record_payload->'coverMedia'")+"""
end if;
else
"""+root_save("favorites")+"""
delete from public.triptrail_favorite_media where root_id=record_id;
delete from public.triptrail_favorite_vouchers where root_id=record_id;
"""+leaves("favorite_media","record_payload")+leaves("favorite_vouchers","record_payload",field="vouchers")+"""
end if;
select * into result from public.triptrail_cloud_records where id=record_id and kind=record_kind;
return result;
end $$;
revoke all on function public.triptrail_save_record(uuid,text,text,jsonb,bigint) from public;
grant execute on function public.triptrail_save_record(uuid,text,text,jsonb,bigint) to anon,authenticated;
""")
out += ["""insert into storage.buckets(id,name,public) values('triptrail-media','triptrail-media',true) on conflict(id) do nothing;
drop policy if exists triptrail_media_read on storage.objects;
create policy triptrail_media_read on storage.objects for select to anon,authenticated using(bucket_id='triptrail-media');
drop policy if exists triptrail_media_insert on storage.objects;
create policy triptrail_media_insert on storage.objects for insert to anon,authenticated with check(bucket_id='triptrail-media');
notify pgrst,'reload schema';
commit;"""]
Path("docs/cloud-schema.sql").write_text("\n\n".join(out)+"\n")
