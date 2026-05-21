# StockSense — Deployment Guide (Demo to Judges)

This guide explains how to host StockSense so judges can use the demo without any local setup. You deploy the backend once to a free cloud host, build an APK pointing at that backend, and ship the APK.

---

## Architecture for the demo

```
Judge's phone (Android)          Cloud (Render / Railway / Fly.io)
┌──────────────────────┐         ┌─────────────────────────────┐
│  StockSense APK      │ HTTPS   │  FastAPI backend            │
│  (baked API URL)     │────────▶│  + Gemini API key           │
└──────────────────────┘   SSE   │  + scenario fixtures        │
                                 └─────────────────────────────┘
```

- **GEMINI_API_KEY never ships with the app.** It only lives in the server's environment.
- **No `credentials.json`** — the code does not use one. `.env` (with `GEMINI_API_KEY=...`) is the only secret the backend needs.
- The app is hardcoded at build time to point to the hosted URL, so the judge does not need to open Settings.

---

## Recommended host: Render.com (free tier)

Render gives you HTTPS, a public URL, and free-tier hosting that wakes on first request. It's the simplest option.

### Step 1 — Push the repo to GitHub (private OK)

Make sure these files are NOT committed:
- `backend/.env`
- `backend/credentials.json` (already deleted; gitignored)
- `backend/stocksense.db*`

`.gitignore` already handles all of these.

### Step 2 — Create a Render Web Service

1. Go to [https://render.com](https://render.com) → New → Web Service → connect your repo.
2. Settings:
   - **Root directory:** `stock_sense/backend`
   - **Runtime:** Python 3
   - **Build command:** `pip install -r requirements.txt`
   - **Start command:** `uvicorn main:app --host 0.0.0.0 --port $PORT`
   - **Plan:** Free
3. Environment variables (Render's "Environment" tab):
   - `GEMINI_API_KEY` = your real key
   - `API_KEY` = (optional) a shared secret if you want to gate the backend; leave empty for an open demo
   - `CORS_ORIGINS` = `*`
   - `OFFLINE_MODE` = `false`
   - `LIVE_CACHE` = `true` (so repeated demo runs cost ~$0 after the first)
4. Click **Create**. Render will build and give you a URL like `https://stocksense-api.onrender.com`.

> **Free tier cold-start:** the service sleeps after 15 min idle. First request takes ~30 s to wake up. For the live demo, hit the URL once just before the recording.

### Step 3 — Bake the URL into the APK

Build the release APK with the hosted URL baked in (no Settings tweak required):

```bash
cd stock_sense
flutter build apk --release \
  --dart-define=API_BASE_URL=https://stocksense-api.onrender.com
```

If you set `API_KEY` on the server, also pass:

```bash
  --dart-define=API_KEY=<the_same_key>
```

The APK lands at `build/app/outputs/flutter-apk/app-release.apk`. Rename to `stocksense-demo.apk`.

### Step 4 — Ship to judges

Three options, ordered by ease:

1. **Google Drive link** with "anyone with the link can view" — simplest. Judges download and sideload.
2. **Firebase App Distribution** — invite judges by email; they install via Firebase tester app. More polished.
3. **GitHub Releases** — attach the APK to a release tag; share the release URL.

Include a one-liner in your submission: *"Install the APK, open the app — no configuration needed. The backend is hosted at <URL>."*

---

## Alternative: Railway, Fly.io, Google Cloud Run

Any host that supports Python + a single port works. Notes:

- **Railway** — same flow as Render; UI is cleaner; free tier is ~$5/month credit.
- **Fly.io** — needs a `fly.toml`; better cold-start behaviour; small free allowance.
- **Cloud Run** — most production-grade. Build a Docker image (we already ship a `Dockerfile` in `backend/`), push to Artifact Registry, deploy. Best if you expect any real load.

For a hackathon judging window, Render free tier is enough.

---

## What "live" means in the demo

The hosted backend gives judges:
- A real `https://` URL they can hit from any device.
- Real Gemini calls (your key, your spend — cap usage with the `LIVE_CACHE` flag).
- The same agentic pipeline they'd see locally — no mocks beyond the scenario fixtures.

Judges never see your `.env`, your API key, or any `credentials.json`. The only thing in the APK is the public backend URL.

---

## Cost note for judging week

- Each scenario run: ~1,200 tokens × $0.15 / 1M tokens = **~$0.0002 per run** (Gemini 2.5 Flash blended).
- With `LIVE_CACHE=true`, identical re-runs of S1/S2/S3 are free after the first.
- Render free tier: $0/month.
- **Realistic worst case:** 50 judge runs × $0.0003 = **$0.015 total.** No meaningful spend.

---

## Killing the demo cleanly

After judging:
1. Render → service → Settings → Suspend (or Delete).
2. Rotate the Gemini key from Google AI Studio.
3. Revoke the GitHub repo's deploy hook if you used one.
