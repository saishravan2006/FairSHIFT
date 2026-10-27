-- Run schema.sql first. This migration enables the authenticated pilot cloud mode.
-- One Supabase project represents one workplace pilot; do not mix organizations here.
create schema if not exists private;
alter table public.hazards add column if not exists reporter_id uuid references auth.users(id);
alter table public.hazards add column if not exists payload jsonb not null default '{}'::jsonb;
alter table public.corrective_actions add column if not exists responsible_actor uuid references auth.users(id);
create index if not exists hazards_reporter_idx on public.hazards(reporter_id);

-- Remove direct writes. All writes go through validated functions below.
revoke all on public.app_user_roles, public.hazards, public.hazard_private_identity,
  public.hazard_events, public.corrective_actions, public.verifications,
  public.hazard_audio, public.hazard_media, public.physical_protection_actions
  from anon, authenticated;
-- Reporter UUID is used by RLS but is not exposed through the Data API.
grant select (id, payload, public_code, status, priority, physical_protection, updated_at)
  on public.hazards to authenticated;
grant select on public.hazard_media to authenticated;

create or replace function private.fairshift_role()
returns text language sql stable security definer set search_path = ''
as $$ select role from public.app_user_roles where user_id = (select auth.uid()) $$;
revoke all on function private.fairshift_role() from public;
grant usage on schema private to authenticated;
grant execute on function private.fairshift_role() to authenticated;

create or replace function public.my_fairshift_role()
returns text language sql stable security invoker set search_path = ''
as $$ select private.fairshift_role() $$;
revoke all on function public.my_fairshift_role() from public;
grant execute on function public.my_fairshift_role() to authenticated;

drop policy if exists fairshift_hazards_read on public.hazards;
create policy fairshift_hazards_read on public.hazards
  for select to authenticated
  using ((select auth.uid()) = reporter_id
    or (select private.fairshift_role()) in ('supervisor','reviewer'));
drop policy if exists fairshift_hazard_media_read on public.hazard_media;
create policy fairshift_hazard_media_read on public.hazard_media
  for select to authenticated
  using (exists (select 1 from public.hazards h where h.id = hazard_id));

-- Private bucket and upload path: <uploader auth UID>/<hazard UUID>/<file>.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('hazard-evidence','hazard-evidence',false,10485760,
  array['image/jpeg','image/png','image/webp','audio/webm','audio/mp4','audio/ogg'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create or replace function private.can_read_media(p_path text)
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.hazard_media m
    join public.hazards h on h.id = m.hazard_id
    where m.storage_path = p_path and
      (h.reporter_id = (select auth.uid())
       or (select private.fairshift_role()) in ('supervisor','reviewer'))
  )
$$;
revoke all on function private.can_read_media(text) from public;
grant execute on function private.can_read_media(text) to authenticated;
drop policy if exists fairshift_media_upload on storage.objects;
create policy fairshift_media_upload on storage.objects for insert to authenticated
  with check (bucket_id = 'hazard-evidence'
    and (storage.foldername(name))[1] = (select auth.uid())::text);
drop policy if exists fairshift_media_read on storage.objects;
create policy fairshift_media_read on storage.objects for select to authenticated
  using (bucket_id = 'hazard-evidence' and private.can_read_media(name));
drop policy if exists fairshift_media_pending_read on storage.objects;
create policy fairshift_media_pending_read on storage.objects for select to authenticated
  using (bucket_id = 'hazard-evidence'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and not exists (select 1 from public.hazard_media m where m.storage_path = name));
drop policy if exists fairshift_media_cleanup on storage.objects;
create policy fairshift_media_cleanup on storage.objects for delete to authenticated
  using (bucket_id = 'hazard-evidence'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and not exists (select 1 from public.hazard_media m where m.storage_path = name));

-- Register only objects that were actually uploaded by the signed-in actor.
create or replace function private.register_fairshift_media(p_hazard uuid, p_media jsonb)
returns void language plpgsql security definer set search_path = ''
as $$
declare m jsonb; path text; kind text; mime text; seconds integer;
begin
  if p_media is null then return; end if;
  if jsonb_typeof(p_media) <> 'array' or jsonb_array_length(p_media) > 5 then
    raise exception 'Invalid media list';
  end if;
  for m in select value from jsonb_array_elements(p_media) loop
    path := m->>'path'; kind := m->>'kind'; mime := m->>'mimeType';
    seconds := nullif(m->>'duration','')::integer;
    if path is null or path not like (auth.uid()::text || '/' || p_hazard::text || '/%')
      or kind not in ('worker_photo','worker_voice_description','worker_voice_safety','protection_photo','corrective_photo')
      or mime not in ('image/jpeg','image/png','image/webp','audio/webm','audio/mp4','audio/ogg')
      or not exists (select 1 from storage.objects where bucket_id = 'hazard-evidence' and name = path)
    then raise exception 'Invalid private media object'; end if;
    insert into public.hazard_media(hazard_id,media_kind,storage_path,mime_type,duration_seconds,uploaded_by)
    values (p_hazard,kind,path,mime,seconds,auth.uid());
  end loop;
end;
$$;
revoke all on function private.register_fairshift_media(uuid,jsonb) from public;

create or replace function private.create_fairshift_hazard(p_id uuid, p_record jsonb, p_media jsonb)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare uid uuid := auth.uid(); ts timestamptz := now(); r jsonb; ev jsonb;
  ind text := p_record->>'industry'; cat text := p_record->>'category';
  warning text := p_record->>'warning'; priority text; protection text;
  anonymous_report boolean := coalesce((p_record->>'anonymous')::boolean,true);
  public_id text := p_record->>'id'; tracking text := p_record->>'trackingCode';
begin
  if uid is null or private.fairshift_role() is distinct from 'worker' then raise exception 'Worker sign-in required'; end if;
  if ind not in ('construction','hospital') or coalesce(length(p_record->>'location'),0) not between 1 and 120
    or coalesce(length(cat),0) not between 1 and 80
    or warning not in ('sign','isolated','verbal','unsafe','unavailable','review')
    or coalesce(length(p_record->>'description'),0) > 4000
    or coalesce(length(public_id),0) not between 8 and 40
    or coalesce(length(tracking),0) not between 12 and 80
    or (p_record->>'reportingMode') not in ('personal','assisted')
  then raise exception 'Invalid hazard report'; end if;
  priority := case
    when cat in ('wiring','fall','electrical') then 'Critical'
    when cat = 'chemical' and coalesce(p_record->>'description','') ~* '(major|large|toxic|fume|acid|பெரிய|நச்சு)' then 'Critical'
    when cat in ('objects','scaffold','slippery','sharps','wet','chemical') then 'High'
    when cat in ('ppe') then 'Medium'
    when cat in ('obstruction','housekeeping') then 'Low'
    else 'Unknown — Needs Review' end;
  protection := case warning when 'sign' then 'Warning Sign Placed'
    when 'isolated' then 'Area Isolated' when 'verbal' then 'Verbal Warning Given'
    when 'review' then 'Unknown — Requires Review' else 'Not Established' end;
  ev := jsonb_build_object('id',gen_random_uuid()::text,'at',ts,'type','reported',
    'actorRole','worker','actorName',case when anonymous_report then 'Anonymous worker'
      else coalesce(nullif(p_record->>'workerName',''),'Worker') end,
    'note','Safety action: ' || warning);
  r := jsonb_build_object('id',public_id,'trackingCode',tracking,'industry',ind,
    'location',p_record->>'location','category',cat,'description',coalesce(p_record->>'description',''),
    'priority',priority,'status','Reported','physicalProtection',protection,'warning',warning,
    'reportingMode',p_record->>'reportingMode','anonymous',anonymous_report,
    'workerName',case when anonymous_report then '' else coalesce(p_record->>'workerName','') end,
    'representativeName',coalesce(p_record->>'representativeName',''),
    'createdAt',ts,'updatedAt',ts,'containment','','assignment','','corrective','',
    'repairMethod','','completionNote','','protectionActions','[]'::jsonb,
    'events',jsonb_build_array(ev),'audioRefs',coalesce(p_record->'audioRefs','[]'::jsonb),
    'imagePath',p_record->>'imagePath');
  insert into public.hazards(id,public_code,tracking_code_hash,industry,location,category,
    description,priority,status,physical_protection,reporting_mode,anonymous,
    immediate_safety_action,image_path,reporter_id,payload,created_at,updated_at)
  values (p_id,public_id,encode(pg_catalog.sha256(pg_catalog.convert_to(tracking,'UTF8')),'hex'),ind,p_record->>'location',cat,
    coalesce(p_record->>'description',''),priority,'Reported',protection,p_record->>'reportingMode',
    anonymous_report,warning,p_record->>'imagePath',uid,r,ts,ts);
  perform private.register_fairshift_media(p_id,p_media);
  insert into public.hazard_events(hazard_id,event_type,notes,actor_role,actor_id,created_at)
  values(p_id,'reported',ev->>'note','worker',uid,ts);
  return r;
end;
$$;
revoke all on function private.create_fairshift_hazard(uuid,jsonb,jsonb) from public;
grant execute on function private.create_fairshift_hazard(uuid,jsonb,jsonb) to authenticated;
create or replace function public.create_fairshift_hazard(p_id uuid,p_record jsonb,p_media jsonb)
returns jsonb language sql security invoker set search_path = ''
as $$ select private.create_fairshift_hazard(p_id,p_record,p_media) $$;
revoke all on function public.create_fairshift_hazard(uuid,jsonb,jsonb) from public;
grant execute on function public.create_fairshift_hazard(uuid,jsonb,jsonb) to authenticated;

create or replace function private.act_on_fairshift_hazard(
  p_id uuid,p_expected text,p_kind text,p_data jsonb,p_media jsonb)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare h public.hazards%rowtype; uid uuid := auth.uid(); role_name text := private.fairshift_role();
  ts timestamptz := now(); r jsonb; ev jsonb; new_status text; note text;
  protection text; action jsonb; actor text;
begin
  if uid is null then raise exception 'Sign-in required'; end if;
  select * into h from public.hazards where id = p_id for update;
  if not found then raise exception 'Report not found'; end if;
  if h.status is distinct from p_expected then raise exception 'Report changed. Refresh and retry'; end if;
  r := h.payload; new_status := h.status;
  actor := case role_name when 'reviewer' then 'Safety reviewer' else 'Supervisor' end;
  if p_kind = 'acknowledge' and role_name = 'supervisor' and h.status = 'Reported' then
    note := trim(coalesce(p_data->>'containment',''));
    protection := p_data->>'physicalProtection';
    if note = '' or protection is null or protection not in ('Not Established','Verbal Warning Given','Warning Sign Placed','Area Isolated','Unknown — Requires Review')
      then raise exception 'Containment and protection state required'; end if;
    new_status := 'Acknowledged';
    action := jsonb_build_object('at',ts,'status',protection,'note',coalesce(nullif(trim(p_data->>'protectionNote'),''),note),
      'imagePath',p_data->>'protectionImagePath','actor',actor);
    r := r || jsonb_build_object('containment',note,'physicalProtection',protection,
      'protectionActions',coalesce(r->'protectionActions','[]'::jsonb)||jsonb_build_array(action));
  elsif p_kind in ('start','resume') and role_name = 'supervisor'
    and h.status = (case when p_kind='start' then 'Acknowledged' else 'Reopened' end) then
    note := trim(coalesce(p_data->>'assignment',''));
    if note = '' then raise exception 'Assignment note required'; end if;
    new_status := 'Action in Progress'; r := r || jsonb_build_object('assignment',note);
  elsif p_kind = 'complete' and role_name = 'supervisor' and h.status = 'Action in Progress' then
    note := trim(coalesce(p_data->>'corrective',''));
    if note = '' or trim(coalesce(p_data->>'repairMethod','')) = '' then raise exception 'What and how are required'; end if;
    new_status := 'Awaiting Verification';
    r := r || jsonb_build_object('corrective',note,'repairMethod',trim(p_data->>'repairMethod'),
      'completionNote',coalesce(p_data->>'completionNote',''),'correctiveImagePath',
      p_data->>'correctiveImagePath','completedAt',ts);
  elsif p_kind = 'protection' and role_name = 'supervisor' and h.status <> 'Verified Closed' then
    protection := p_data->>'physicalProtection'; note := trim(coalesce(p_data->>'protectionNote',''));
    if note = '' or protection is null or protection not in ('Not Established','Verbal Warning Given','Warning Sign Placed','Area Isolated','Unknown — Requires Review')
      then raise exception 'Protection state and note required'; end if;
    action := jsonb_build_object('at',ts,'status',protection,'note',note,'imagePath',
      p_data->>'protectionImagePath','actor',actor);
    r := r || jsonb_build_object('physicalProtection',protection,
      'protectionActions',coalesce(r->'protectionActions','[]'::jsonb)||jsonb_build_array(action));
  elsif p_kind in ('verify_pass','verify_reject') and role_name = 'reviewer'
    and h.status = 'Awaiting Verification' then
    note := trim(coalesce(p_data->>'verifyNote',''));
    if note = '' or trim(coalesce(p_data->>'reviewerName','')) = ''
      or (p_kind='verify_pass' and p_data->>'reviewOutcome' is distinct from 'passed')
      or (p_kind='verify_reject' and p_data->>'reviewOutcome' is distinct from 'remaining')
      then raise exception 'Reviewer, outcome, and inspection note required'; end if;
    if exists (select 1 from public.corrective_actions where hazard_id=p_id and completed_at is not null and
      responsible_actor = uid) then raise exception 'Corrective actor cannot verify own work'; end if;
    actor := trim(p_data->>'reviewerName');
    new_status := case when p_kind='verify_pass' then 'Verified Closed' else 'Reopened' end;
    r := r || jsonb_build_object('verificationOutcome',p_data->>'reviewOutcome',
      'verifiedBy',actor,'verifiedAt',case when p_kind='verify_pass' then to_jsonb(ts) else 'null'::jsonb end);
    insert into public.verifications(hazard_id,reviewer_id,decision,notes,created_at)
    values (p_id,uid,case when p_kind='verify_pass' then 'passed' else 'rejected' end,note,ts);
    if p_kind='verify_pass' then
      protection := 'Protection Verified';
      action := jsonb_build_object('at',ts,'status',protection,'note',note,'actor',actor);
      r := r || jsonb_build_object('physicalProtection',protection,
        'protectionActions',coalesce(r->'protectionActions','[]'::jsonb)||jsonb_build_array(action));
    end if;
  elsif p_kind = 'escalate' and role_name = 'supervisor' and h.status <> 'Verified Closed' then
    note := trim(coalesce(p_data->>'reason',''));
    if note = '' or p_data->>'priority' is null or array_position(array['Unknown — Needs Review','Low','Medium','High','Critical'],p_data->>'priority') is null
      or array_position(array['Unknown — Needs Review','Low','Medium','High','Critical'],p_data->>'priority')
      <= array_position(array['Unknown — Needs Review','Low','Medium','High','Critical'],h.priority)
      then raise exception 'Higher priority and reason required'; end if;
    r := r || jsonb_build_object('priority',p_data->>'priority');
  else raise exception 'Action not allowed for role or status'; end if;
  ev := jsonb_build_object('id',gen_random_uuid()::text,'at',ts,'type',p_kind,
    'actorRole',role_name,'actorName',actor,'note',coalesce(note,protection,''));
  r := r || jsonb_build_object('status',new_status,'updatedAt',ts,
    'events',coalesce(r->'events','[]'::jsonb)||jsonb_build_array(ev));
  update public.hazards set status=new_status,physical_protection=coalesce(protection,h.physical_protection),
    priority=coalesce(r->>'priority',h.priority),payload=r,updated_at=ts,
    containment=r->>'containment',repair_method=r->>'repairMethod',
    completion_note=r->>'completionNote',completed_at=nullif(r->>'completedAt','')::timestamptz,
    verified_at=nullif(r->>'verifiedAt','')::timestamptz
  where id=p_id;
  perform private.register_fairshift_media(p_id,p_media);
  insert into public.hazard_events(hazard_id,event_type,notes,actor_role,actor_id,created_at)
  values(p_id,p_kind,ev->>'note',role_name,uid,ts);
  if p_kind in ('start','resume','complete') then
    insert into public.corrective_actions(hazard_id,action_description,status,completed_at,created_at,responsible_actor)
    values(p_id,coalesce(note,r->>'corrective'),case when p_kind='complete' then 'completed' else 'in_progress' end,
      case when p_kind='complete' then ts else null end,ts,uid);
  end if;
  if p_kind in ('acknowledge','protection','verify_pass') then
    insert into public.physical_protection_actions(hazard_id,protection_state,notes,evidence_path,actor_id,created_at)
    values(p_id,protection,coalesce(action->>'note',note,p_data->>'protectionNote',''),
      p_data->>'protectionImagePath',uid,ts);
  end if;
  return r;
end;
$$;
revoke all on function private.act_on_fairshift_hazard(uuid,text,text,jsonb,jsonb) from public;
grant execute on function private.act_on_fairshift_hazard(uuid,text,text,jsonb,jsonb) to authenticated;
create or replace function public.act_on_fairshift_hazard(
  p_id uuid,p_expected text,p_kind text,p_data jsonb,p_media jsonb)
returns jsonb language sql security invoker set search_path = ''
as $$ select private.act_on_fairshift_hazard(p_id,p_expected,p_kind,p_data,p_media) $$;
revoke all on function public.act_on_fairshift_hazard(uuid,text,text,jsonb,jsonb) from public;
grant execute on function public.act_on_fairshift_hazard(uuid,text,text,jsonb,jsonb) to authenticated;

create or replace function private.create_fairshift_concern(
  p_parent uuid,p_id uuid,p_public_code text,p_tracking_code text,p_note text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare h public.hazards%rowtype; ts timestamptz := now(); r jsonb; ev jsonb;
begin
  if auth.uid() is null or private.fairshift_role() is distinct from 'worker' then
    raise exception 'Worker sign-in required'; end if;
  select * into h from public.hazards where id=p_parent and reporter_id=auth.uid()
    and status='Verified Closed' for share;
  if not found then raise exception 'Closed report not found'; end if;
  if length(trim(coalesce(p_note,''))) not between 1 and 4000
    or length(coalesce(p_public_code,'')) not between 8 and 40
    or length(coalesce(p_tracking_code,'')) not between 12 and 80
  then raise exception 'Invalid concern'; end if;
  ev := jsonb_build_object('id',gen_random_uuid()::text,'at',ts,'type','worker_concern',
    'actorRole','worker','actorName','Anonymous worker',
    'note','New concern linked to '||h.public_code||': '||trim(p_note));
  r := jsonb_build_object('id',p_public_code,'trackingCode',p_tracking_code,
    'parentHazardId',h.public_code,'industry',h.industry,'location',h.location,
    'category',h.category,'description',trim(p_note),'priority',h.priority,
    'status','Reported','physicalProtection','Unknown — Requires Review',
    'warning','review','reportingMode','personal','anonymous',true,
    'workerName','','representativeName','','createdAt',ts,'updatedAt',ts,
    'containment','','assignment','','corrective','','repairMethod','',
    'completionNote','','protectionActions','[]'::jsonb,'audioRefs','[]'::jsonb,
    'events',jsonb_build_array(ev));
  insert into public.hazards(id,public_code,tracking_code_hash,industry,location,category,
    description,priority,status,physical_protection,parent_hazard_id,reporting_mode,
    anonymous,immediate_safety_action,reporter_id,payload,created_at,updated_at)
  values(p_id,p_public_code,encode(pg_catalog.sha256(pg_catalog.convert_to(p_tracking_code,'UTF8')),'hex'),h.industry,
    h.location,h.category,trim(p_note),h.priority,'Reported','Unknown — Requires Review',
    p_parent,'personal',true,'review',auth.uid(),r,ts,ts);
  insert into public.hazard_events(hazard_id,event_type,notes,actor_role,actor_id,created_at)
  values(p_id,'worker_concern',ev->>'note','worker',auth.uid(),ts);
  return r;
end;
$$;
revoke all on function private.create_fairshift_concern(uuid,uuid,text,text,text) from public;
grant execute on function private.create_fairshift_concern(uuid,uuid,text,text,text) to authenticated;
create or replace function public.create_fairshift_concern(
  p_parent uuid,p_id uuid,p_public_code text,p_tracking_code text,p_note text)
returns jsonb language sql security invoker set search_path = ''
as $$ select private.create_fairshift_concern(p_parent,p_id,p_public_code,p_tracking_code,p_note) $$;
revoke all on function public.create_fairshift_concern(uuid,uuid,text,text,text) from public;
grant execute on function public.create_fairshift_concern(uuid,uuid,text,text,text) to authenticated;

-- Realtime publishes row changes; RLS still controls which rows each user sees.
do $$ begin
  if not exists (select 1 from pg_publication_tables
    where pubname='supabase_realtime' and schemaname='public' and tablename='hazards')
  then alter publication supabase_realtime add table public.hazards; end if;
end;
$$;
