-- Incremental migration. If the previous script failed inside a transaction,
-- first execute ROLLBACK in that SQL console, then run this whole file.
-- Uses caller permissions; does not require SECURITY DEFINER or elevated server settings.
begin;
create or replace function public.triptrail_storage_usage()
returns table(database_bytes bigint, object_bytes bigint, measured_at_ms bigint)
language sql security invoker set search_path = pg_catalog as $$
  select pg_database_size(current_database()),
    (select coalesce(sum(case when metadata->>'size' ~ '^[0-9]+$'
       then (metadata->>'size')::bigint else 0 end), 0)::bigint
     from storage.objects
     where bucket_id in ('triptrail-media', 'triptrail-backups')),
    (extract(epoch from now()) * 1000)::bigint;
$$;
revoke all on function public.triptrail_storage_usage() from public;
grant execute on function public.triptrail_storage_usage() to anon, authenticated;
commit;
-- Clients cache successful results for 24 hours. Storage RLS remains in force.
-- The old triptrail_storage_usage_cache table, if created, is unused and may remain.
