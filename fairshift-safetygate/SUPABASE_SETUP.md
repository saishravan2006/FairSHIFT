# FairShift cloud pilot setup

FairShift starts in **Local Demo** mode. Cloud mode appears after a user signs in with an assigned Supabase Auth account. Local reports are never copied to the cloud automatically. Use a fresh, single-workplace pilot project; this schema does not yet isolate multiple organizations.

## 1. Database and private storage

In your Supabase project's **SQL Editor**, run these files in order, using their complete contents:

1. [schema.sql](schema.sql) creates the base tables and enables row-level security (RLS) with no public policies.
2. [cloud_setup.sql](cloud_setup.sql) adds authenticated read rules, role-checked write functions, private media policies, and the Realtime publication. It creates the private `hazard-evidence` bucket with a 10 MB object limit.

The SQL Editor runs as an administrator. Do not add broad anonymous or authenticated write policies to these tables. The frontend calls only the guarded functions for changes; direct table writes are revoked. `hazard_events`, `corrective_actions`, `verifications`, and `physical_protection_actions` remain inaccessible for direct client mutation.

## 2. Create pilot users and assign roles

In **Authentication → Users**, create or invite three distinct test users: one worker, one supervisor, and one safety reviewer. Give each a unique login. Confirm each user can sign in. Public signup should remain disabled unless you have an approved onboarding process.

Copy each user's UUID and run this in the SQL Editor, replacing the placeholders:

~~~sql
insert into public.app_user_roles (user_id, role) values
  ('WORKER_AUTH_UUID', 'worker'),
  ('SUPERVISOR_AUTH_UUID', 'supervisor'),
  ('REVIEWER_AUTH_UUID', 'reviewer')
on conflict (user_id) do update set role = excluded.role;
~~~

Only the SQL Editor or a trusted administrator should assign roles. No browser policy lets users change their role. Do not send passwords or secret/service-role keys in chat.

## 3. Frontend environment

The local `.env.local` file contains the project URL and **publishable** key and is ignored by Git. For another machine, create the same file beside `package.json`:

~~~text
VITE_SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co
VITE_SUPABASE_PUBLISHABLE_KEY=sb_publishable_YOUR_KEY
~~~

Restart Vite after changing environment variables. These `VITE_` values are sent to the browser. Never put a secret/service-role key in them. The secret key previously shared in chat should be deleted or rotated in Supabase Settings → API Keys before using real data.

## 4. Test the cloud workflow

1. Run `npm install` and `npm run dev`. Click **Connect cloud** and sign in as the worker. Submit a report. The receipt must appear only after the private uploads and database call succeed.
2. On another browser or device, sign in as the supervisor. The report should appear through Realtime or within the 30-second fallback refresh. **Refresh** is available in the header. Record containment, physical protection, corrective work, and completion.
3. On a third browser or device, sign in as the reviewer. Record a simulated inspection outcome. Only this role can close or reject the report.
4. Refresh the worker device and confirm status, history, and private audio playback. Test **Problem Still Exists** on a closed report.
5. Sign in with each role and attempt the other roles' actions. They must fail. An unauthenticated browser must not list reports or private media. Verify the Storage bucket remains private.

Cloud write errors are shown and do not fall back to local success. The local demo remains available through the header switch. The app is a single-workplace pilot; production use still requires site membership, formal reviewer authorization, anonymity review, retention policy, and authorized on-site inspection procedures.
