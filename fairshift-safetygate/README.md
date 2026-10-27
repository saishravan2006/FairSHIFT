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
- After a successful local save, the receipt provides spoken confirmation. Report details provide optional spoken status and playback for attached recordings. Supervisors can play recordings from the report and timeline.
- Voice may reveal identity even on an anonymous report. The worker sees this warning with a Listen button and can use text, structured answers, or assisted reporting instead.

For the construction sample, the worker could not safely approach exposed wiring, so no warning board was placed. For the hospital sample, a safety representative used a shared device after a warning sign was placed safely.

## Priority rules

The initial rule-based classification uses the selected hazard category. Exposed wiring, fall risk, and electrical hazards are **Critical**. Scaffolding, sharps, and slipping hazards are **High**. Missing protective equipment is **Medium**. Minor obstructions and nonurgent housekeeping concerns are **Low**. Other/unsure or a missing category is **Unknown — Needs Review**. Chemical spills default to High and become Critical when the description indicates a major or toxic release. Supervisors may escalate priority with a recorded reason. They cannot downgrade it in this demo. Priority is an initial triage cue, not a professional risk assessment.

## Persistence and security boundaries

This build runs in **local demo mode**. Reports, events, protection history, and image data URLs persist in browser localStorage. Audio persists as Blobs in browser IndexedDB and is referenced by ID from the report and event record. The app only shows a successful submission after all attached audio and the report have been saved locally. It has no database connection, private server-side audio storage, role authentication, cross-device synchronization, notifications, or tamper-resistant audit log. All three roles are simulated in one browser; reviewer identity is a demo entry, not authenticated. Anonymous mode omits the worker name from the stored report, but a voice can still identify someone and this is not a production anonymity guarantee. A shared browser exposes its local records and recordings to anyone who can use it. Photos are limited to 1 MB to reduce localStorage failures. The UI shows an error if storage fills. Reset demo data also clears locally stored audio.

The included [schema.sql](schema.sql) is a starting schema for a future Supabase-backed service. It is **not connected to this frontend**. It includes recording metadata and private storage paths. Row-level security is enabled and no public access policies are granted. Follow [SUPABASE_SETUP.md](SUPABASE_SETUP.md) for project, role, storage, and acceptance steps. Do not add a Supabase key to the frontend until authenticated roles, server-side transition rules, private evidence storage, and safe row policies are configured and tested. A production deployment also needs append-only event enforcement, privacy review, and site-specific inspection procedures before data access is enabled. Supabase project URL and publishable/anon key are pending from the project owner; never use a service-role key in the browser.

**Safety:** Reporting is not an emergency response system. Workers should move to safety and follow workplace emergency procedures. They should never approach a dangerous area to place a sign or take a photo. Images do not prove that a hazard has been removed. High-risk closure requires an authorized physical inspection in real deployments. The reviewer action here records a simulated decision only.

## Files

- src/main.jsx — report form, priority rules, role views, workflow, local persistence
- src/VoiceFeatures.jsx — speech prompts, MediaRecorder controls, saved recording playback
- src/audioStore.js — IndexedDB recording storage
- src/style.css — responsive presentation
- schema.sql — future server-side schema with RLS default-deny posture
- SUPABASE_SETUP.md — role, storage, and cloud deployment steps
- index.html — Vite entry point
