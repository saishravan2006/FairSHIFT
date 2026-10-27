-- Future Supabase/PostgreSQL schema. The current app uses browser localStorage only.
-- Run in a private Supabase project after designing authentication and server-side access.
-- RLS is enabled with no public policies, so anon/authenticated API roles have no access.

create extension if not exists pgcrypto;

-- Assign roles only from the Supabase SQL editor or a trusted server process.
-- Client sessions have no insert/update/delete policy on this table.
create table if not exists public.app_user_roles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('worker','supervisor','reviewer')),
  created_at timestamptz not null default now()
);

create table if not exists public.hazards (
  id uuid primary key default gen_random_uuid(),
  public_code text not null unique,
  tracking_code_hash text not null,
  industry text not null check (industry in ('construction','hospital')),
  location text not null,
  category text not null,
  description text not null default '',
  priority text not null check (priority in ('Critical','High','Medium','Low','Unknown — Needs Review')),
  status text not null check (status in ('Reported','Acknowledged','Action in Progress','Awaiting Verification','Verified Closed','Reopened')),
  physical_protection text not null default 'Unknown — Requires Review' check (physical_protection in ('Not Established','Verbal Warning Given','Warning Sign Placed','Area Isolated','Protection Verified','Unknown — Requires Review')),
  parent_hazard_id uuid references public.hazards(id),
  reporting_mode text not null check (reporting_mode in ('personal','assisted')),
  anonymous boolean not null default true,
  immediate_safety_action text not null,
  image_path text,
  containment text,
  assignment_note text,
  repair_method text,
  completion_note text,
  completed_at timestamptz,
  verified_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Identity is isolated from public hazard records and should be readable only
-- through a carefully authorized server endpoint.
create table if not exists public.hazard_private_identity (
  hazard_id uuid primary key references public.hazards(id) on delete cascade,
  worker_name text,
  representative_name text
);

create table if not exists public.hazard_events (
  id uuid primary key default gen_random_uuid(),
  hazard_id uuid not null references public.hazards(id) on delete cascade,
  event_type text not null,
  notes text not null default '',
  actor_role text not null,
  actor_id uuid,
  created_at timestamptz not null default now()
);

create table if not exists public.physical_protection_actions (
  id uuid primary key default gen_random_uuid(),
  hazard_id uuid not null references public.hazards(id) on delete cascade,
  protection_state text not null check (protection_state in ('Not Established','Verbal Warning Given','Warning Sign Placed','Area Isolated','Protection Verified','Unknown — Requires Review')),
  notes text not null,
  evidence_path text,
  actor_id uuid,
  created_at timestamptz not null default now()
);

create table if not exists public.corrective_actions (
  id uuid primary key default gen_random_uuid(),
  hazard_id uuid not null references public.hazards(id) on delete cascade,
  action_description text not null,
  evidence_path text,
  status text not null check (status in ('in_progress','completed')),
  completed_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.verifications (
  id uuid primary key default gen_random_uuid(),
  hazard_id uuid not null references public.hazards(id) on delete cascade,
  reviewer_id uuid not null,
  decision text not null check (decision in ('passed','rejected')),
  notes text not null,
  created_at timestamptz not null default now()
);

-- Recording objects belong in a private storage bucket. Store only private paths
-- here; a server must authorize playback and issue short-lived signed URLs.
create table if not exists public.hazard_audio (
  id uuid primary key default gen_random_uuid(),
  hazard_id uuid not null references public.hazards(id) on delete cascade,
  step text not null check (step in ('description','warning')),
  storage_path text not null,
  duration_seconds integer not null check (duration_seconds between 1 and 60),
  mime_type text not null,
  created_at timestamptz not null default now()
);

-- Generic private media inventory for photos, voice, and corrective evidence.
create table if not exists public.hazard_media (
  id uuid primary key default gen_random_uuid(),
  hazard_id uuid not null references public.hazards(id) on delete cascade,
  media_kind text not null check (media_kind in ('worker_photo','worker_voice_description','worker_voice_safety','protection_photo','corrective_photo')),
  storage_path text not null unique,
  mime_type text not null,
  duration_seconds integer check (duration_seconds between 1 and 60),
  uploaded_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create index if not exists hazards_status_priority_idx on public.hazards(status, priority, created_at desc);
create index if not exists hazard_events_hazard_time_idx on public.hazard_events(hazard_id, created_at desc);
create index if not exists physical_protection_actions_hazard_time_idx on public.physical_protection_actions(hazard_id, created_at desc);
create index if not exists corrective_actions_hazard_idx on public.corrective_actions(hazard_id);
create index if not exists verifications_hazard_idx on public.verifications(hazard_id);
create index if not exists hazard_audio_hazard_idx on public.hazard_audio(hazard_id);
create index if not exists hazard_media_hazard_idx on public.hazard_media(hazard_id);

alter table public.app_user_roles enable row level security;
alter table public.hazards enable row level security;
alter table public.hazard_private_identity enable row level security;
alter table public.hazard_events enable row level security;
alter table public.physical_protection_actions enable row level security;
alter table public.corrective_actions enable row level security;
alter table public.verifications enable row level security;
alter table public.hazard_audio enable row level security;
alter table public.hazard_media enable row level security;

-- No API policies or public storage bucket are intentionally created here.
-- A production API should validate role permissions and state transitions,
-- hash tracking codes, restrict evidence file access, and make events append-only.
