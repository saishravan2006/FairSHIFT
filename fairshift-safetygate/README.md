# FairShift — Hazard Beacon

**Spot it. Warn others. Report it. Verify it's fixed.** A responsive React/Vite hackathon MVP for Prompt Wars 2026 × SRM ACM Student Chapter and SDG 8.

## Run locally

Requires Node.js 18+.

~~~bash
npm install
npm run dev
~~~

Open the URL printed by Vite, usually http://localhost:5173/. To check a production build:

~~~bash
npm run build
npm run preview
~~~

## Modes

**Local Demo** uses browser-local data and simulated role buttons. **Cloud** requires the [Supabase setup](SUPABASE_SETUP.md), a worker/supervisor/reviewer Auth account, and the publishable key in ignored `.env.local`. Use **Connect cloud** to sign in. Cloud reports stay separate from local samples. Realtime updates and a 30-second fallback refresh keep signed-in views current; the header also has **Refresh**. A failed cloud write shows an error and never creates a local success receipt.

## Demo workflow

The role buttons simulate three roles in one browser. The home screen includes two sample reports.

1. **Worker:** Report a construction or hospital hazard. Choose an immediate safety action, personal or assisted reporting, and optional anonymity. A photo is optional. Save the tracking code shown after submission.
2. **Supervisor:** Use the single Hazard Action Panel to record immediate containment and the separate physical protection state. Add an assignment note, then record what was fixed, how, and optional evidence. Completion sends the report to **Awaiting Verification**. Protection updates can be recorded separately with notes and optional photos; they do not change resolution status.
3. **Safety Reviewer:** Open the verification queue. Enter reviewer name or ID, inspection outcome, and a note. Passing sets **Verified Closed** and records verified physical protection; rejection sets **Reopened** for more corrective work.
4. **Worker:** Follow both resolution and physical protection status with the tracking code. On a closed report, **Problem Still Exists** creates a new linked concern for review and preserves the original closure record.
5. Try the English/Tamil toggle, filters, anonymous tracking code, and page reload. Records persist in the same browser. The supervisor dashboard counts protection that has not reached Area Isolated or Protection Verified.

## Voice-first worker reporting

- Every worker report question has a Listen button. Hazard, workplace, warning, and selected location answers can also be played. Playback uses the browser's speech synthesis voice matching the selected language. When no Tamil voice is installed, the app states that limitation and does not substitute English speech.
- The description and safety-warning steps have separate, large microphone controls. Permission is requested only when Start recording is tapped. A worker can stop, replay, delete, and re-record. Recording stops automatically at 60 seconds. The browser chooses a supported format, preferring low-bitrate Opus.
- A spoken safety answer without a selected option is saved as **Requires review**. The app does not infer a structured answer from speech.
- After a successful save, the receipt provides spoken confirmation. Report details provide optional spoken status and playback for attached recordings. In cloud mode, recordings use private Storage and authorized signed URLs.
- Voice may reveal identity even on an anonymous report. The worker sees this warning with a Listen button and can use text, structured answers, or assisted reporting instead.

For the construction sample, the worker could not safely approach exposed wiring, so no warning board was placed. For the hospital sample, a safety representative used a shared device after a warning sign was placed safely.

## Priority rules

The initial rule-based classification uses the selected hazard category. Exposed wiring, fall risk, and electrical hazards are **Critical**. Scaffolding, sharps, and slipping hazards are **High**. Missing protective equipment is **Medium**. Minor obstructions and nonurgent housekeeping concerns are **Low**. Other/unsure or a missing category is **Unknown — Needs Review**. Chemical spills default to High and become Critical when the description indicates a major or toxic release. Supervisors may escalate priority with a recorded reason. They cannot downgrade it in this demo. Priority is an initial triage cue, not a professional risk assessment.

## Persistence and security boundaries

In **Local Demo**, reports, events, protection history, and image data URLs persist in browser localStorage. Audio persists as Blobs in IndexedDB. All three roles are simulated in one browser; a shared browser exposes its local records and recordings to anyone who can use it. Reset demo data clears locally stored audio.

In **Cloud**, Supabase Auth fixes the user's role. Postgres RLS restricts reads; server-side functions validate transitions and write history. Photos and voice use a private bucket. The project owner must run [schema.sql](schema.sql) and [cloud_setup.sql](cloud_setup.sql) and assign Auth roles before this can be tested live. The secret key is never used by the frontend. Anonymous mode hides the worker name in reports, but a voice can still identify someone. This pilot is for one workplace and is not a production anonymity guarantee. A production deployment needs organizational scoping, privacy review, retention rules, and site-specific inspection procedures.

**Safety:** Reporting is not an emergency response system. Workers should move to safety and follow workplace emergency procedures. They should never approach a dangerous area to place a sign or take a photo. Images do not prove that a hazard has been removed. High-risk closure requires an authorized physical inspection in real deployments. The reviewer action here records a simulated decision only.

## Files

- src/main.jsx — report form, priority rules, role views, workflow, local persistence
- src/VoiceFeatures.jsx — speech prompts, MediaRecorder controls, saved recording playback
- src/audioStore.js — IndexedDB recording storage
- src/cloud.js — authenticated Supabase client, private uploads, signed media, refresh
- src/style.css — responsive presentation
- schema.sql — base tables with RLS default-deny posture
- cloud_setup.sql — pilot RLS policies, guarded actions, private bucket, Realtime
- SUPABASE_SETUP.md — role, storage, and cloud deployment steps
- index.html — Vite entry point
