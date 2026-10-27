# Supabase setup for FairShift

The current frontend runs in **Local Demo** mode. Its role buttons are simulated and its reports are stored in the browser. The SQL schema is a secure starting point for cloud development; applying it does not connect the current frontend or enable cross-device sync. Do not use demo role switching as authorization for real records.

## Project and keys

1. Create a private Supabase project intended for this app.
2. In the Supabase SQL editor, run [schema.sql](schema.sql). It enables row-level security (RLS) and grants no report or media policies. Confirm that querying `hazards`, `hazard_events`, and `hazard_media` through the publishable key returns no rows.
3. Obtain the Project URL and **publishable/anon** key from Project Settings → API Keys. Keep the service-role/secret key off the frontend and out of Git. The project owner will provide the URL and publishable key separately.
4. When a cloud client with authenticated policies is implemented, use a local `.env.local` file for `VITE_SUPABASE_URL` and `VITE_SUPABASE_PUBLISHABLE_KEY`. Add `.env.local` to `.gitignore`. Vite variables are exposed to browser users, so these variables must never contain a service-role/secret key.

## Authentication and roles

1. In Supabase Authentication, create or invite separate test users for worker, supervisor, and safety reviewer. Give each a unique login. Disable public signups for the pilot unless the organization has an approved onboarding process.
2. In Authentication → Users, copy each user's UUID. From the **SQL editor**, insert role assignments, substituting real UUIDs:

   ```sql
   insert into public.app_user_roles (user_id, role) values
     ('WORKER_AUTH_UUID', 'worker'),
     ('SUPERVISOR_AUTH_UUID', 'supervisor'),
     ('REVIEWER_AUTH_UUID', 'reviewer');
   ```

3. Keep `app_user_roles` writable only by trusted administrators. Do not create a policy that lets users assign or change their own role. A production deployment also needs a site or organization membership model before reports from different workplaces are stored in one project.
4. Implement server-side functions or constrained database RPCs for `acknowledge`, `start_action`, `complete_action`, `record_protection`, `verify`, and `raise_concern`. Each operation must check `auth.uid()`, the role, workplace membership, current status, required fields, and expected version in one transaction. Only the reviewer operation may set `Verified Closed`; it must reject the same user who performed the corrective action.
5. Give workers access to only reports they submitted or know through a separate secure tracking flow. An anonymous report must not reveal identity through table joins, logs, or media paths. The demo tracking code is not suitable as a production bearer credential; store a hash, rate-limit lookup, and scope the response.

## Private evidence storage

1. Create a Supabase Storage bucket such as `hazard-evidence` with **Public bucket** turned off and file-size/type limits for photos and audio.
2. Keep `hazard_media.storage_path` private. Restrict upload/download policies by authenticated role, workplace membership, and report ownership. Use short-lived signed URLs for authorized playback and images. Never expose a public bucket URL for worker audio or photos.
3. Store media metadata in `hazard_media` only after the private object upload succeeds; if metadata creation fails, remove the orphaned object through a trusted cleanup process. Do not show a success receipt until the report and all required media are committed.

## Realtime and acceptance gate

After authenticated RLS and transitions are implemented, subscribe only to records visible to the current user. Add manual refresh for reconnects, and show explicit write or subscription failures. Test worker phone → supervisor laptop → reviewer device → worker phone with separate accounts and a fresh private browser. Confirm that an unauthenticated or wrong-role session cannot list reports, access media, change protection, or close a hazard. Keep Local Demo mode available until this entire gate passes.
