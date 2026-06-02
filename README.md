<div align="center">

# 🏭 Content Factory

### Fully automated faceless YouTube documentary pipeline

[![CI](https://github.com/xbrxr03/content-factory/actions/workflows/ci.yml/badge.svg)](https://github.com/xbrxr03/content-factory/actions/workflows/ci.yml)
[![Python](https://img.shields.io/badge/Python-3.10+-3776AB?logo=python&logoColor=white)](https://python.org/)
[![Ollama](https://img.shields.io/badge/Ollama-Local_AI-000000?logo=ollama&logoColor=white)](https://ollama.ai)
[![ComfyUI](https://img.shields.io/badge/ComfyUI-DreamShaper-6366F1)](https://github.com/comfyanonymous/ComfyUI)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

</div>

Send a topic. Get a published YouTube video. No cloud APIs, no recurring costs, no data leaving your machine. Content Factory runs a 6-stage agent pipeline entirely on your own hardware — from research and script writing through voice synthesis, image generation, video rendering, and optional scheduled upload.

## Pipeline

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌──────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│   Topic      │───▶│   Writer     │───▶│    Voice     │───▶│  Assembler   │───▶│   Visual    │───▶│   Render    │───▶│   Upload    │
│   Input      │    │   Agent      │    │    Agent     │    │   Agent      │    │   Agent      │    │   Agent     │    │   Agent     │
│              │    │  (Ollama)    │    │  (Piper TTS) │    │              │    │  (ComfyUI)   │    │  (ffmpeg)   │    │ (YouTube)   │
└─────────────┘    └─────────────┘    └─────────────┘    └──────────────┘    └─────────────┘    └─────────────┘    └─────────────┘
                         │                   │                   │                   │                   │                   │
                   script.txt           voice.wav          edit_plan.json     image_01..N.png     final_video.mp4   youtube_upload.json
                   metadata.json
                   shots.json
```

A **Foreman Agent** orchestrates scheduling — it issues time-limited leases to workers, detects stalls, retries failed jobs (up to 3×), and enforces resource limits so a heavy GPU task can't starve lighter phases. A **Monitor Agent** exposes an HTTP dashboard + API on port 7000.

## Tech Stack

| Layer | Tool | Notes |
|-------|------|-------|
| **Script writing** | [Ollama](https://ollama.ai) + local LLM | Default: `qwen2.5:7b`. Configurable via `OLLAMA_MODEL` env var |
| **Voice synthesis** | [Piper TTS](https://github.com/rhasspy/piper) | CPU-only, offline. Default voice: `en_US-lessac-medium` |
| **Image generation** | [ComfyUI](https://github.com/comfyanonymous/ComfyUI) + DreamShaper 8 | Auto-started/stopped to free RAM. KSampler + Euler scheduler |
| **Video rendering** | [ffmpeg](https://ffmpeg.org) | Ken Burns zoom, 1080p 30fps, caption overlay, optional background music |
| **Upload** | [YouTube Data API v3](https://developers.google.com/youtube/v3) | Opt-in. Scheduled publishing (default 9am). Auto-sets thumbnail |
| **Orchestration** | Python 3.10+ | File-based job queue, lease manager, resource guard, event log |

**Python packages:** `psutil`, `pathvalidate`, `piper-tts`, `requests`, `Pillow`, `google-auth-oauthlib`, `google-api-python-client`

## How It Works

### 1. Writer Agent → `script.txt`, `metadata.json`, `shots.json`

The writer calls Ollama with a prompt derived from your topic and template. It produces three artifacts in sequence:

- **`script.txt`** — the narration script (default ~400 words, configurable via template)
- **`metadata.json`** — title, description, tags, target audience, duration estimate
- **`shots.json`** — an array of visual shot objects, each with `image_prompt`, `negative_prompt`, `mood`, and dimensions

Each artifact is checked before generation, so the agent can safely resume after a crash.

### 2. Voice Agent → `voice.wav`

Reads `script.txt`, strips markdown formatting, and pipes the clean text to Piper TTS. The result is a WAV file of narrated audio.

### 3. Assembler Agent → `edit_plan.json`

Validates that `script.txt`, `shots.json`, and `voice.wav` all exist and are non-empty. Then builds a production manifest:

- **`timeline`** — an ordered list of scenes mapping shots to images, with computed start/end times based on word count (~150 WPM)
- **`assets`** — absolute paths to every artifact the render agent will need
- **`validation`** — checksum of what's present vs. what's required

### 4. Visual Agent → `image_01..N.png`, `thumbnail.png`

The heaviest phase. The visual agent:

1. **Stops all other agents** to free RAM (ComfyUI needs ~6GB VRAM)
2. **Starts ComfyUI** as a subprocess and waits for `/system_stats` to respond
3. **Submits each shot** as a KSampler workflow (DreamShaper 8 checkpoint, 20 steps, CFG 7.0)
4. **Polls `/history/{prompt_id}`** until the image is ready, then downloads it
5. **Generates a thumbnail** from the first shot's prompt
6. **Shuts down ComfyUI** and **restarts** the other agents

Images are generated individually with resume support — only missing files are produced.

### 5. Render Agent → `final_video.mp4`

Reads `edit_plan.json` and renders each scene as a short MP4 clip with:

- **Ken Burns effect** — alternating zoom-in / zoom-out via ffmpeg's `zoompan` filter
- **Caption overlay** — shot description as centered white text with black outline
- **Voiceover mix** — the narration track is mixed as the primary audio
- **Optional background music** — loops an MP3 from `assets/music/` at 8% volume, fading out 3 seconds before the end

Final output: **1920×1080, 30fps, H.264/AAC**.

### 6. Upload Agent → `youtube_upload.json` *(opt-in, disabled by default)*

If YouTube OAuth credentials are configured, the upload agent:

1. Waits until the scheduled publish time (default 09:00 local)
2. Uploads `final_video.mp4` with metadata from `metadata.json`
3. Sets the custom thumbnail from `thumbnail.png`
4. Records `youtube_upload.json` with `video_id`, `video_url`, and timestamp

Without credentials, it writes a skip marker and moves on.

## Templates

Pre-built pipeline configurations that control script tone, length, visual style, and shot count:

| Template | Duration | Shots | Style |
|----------|----------|-------|-------|
| `documentary_video` | 8-12 min | 12 | Cinematic, authoritative narrator |
| `educational_video` | 5-10 min | 8 | Clear, engaging explainer |
| `tutorial_video` | 5-8 min | 6 | Step-by-step instructional |
| `short_form_video` | 60-90 sec | 4 | Punchy, social-media vertical |

```bash
python3 factoryctl.py new-job "The rise and fall of Kodak" --template documentary_video
python3 factoryctl.py new-job "How HTTPS encryption works" --template educational_video
```

Each template ships its own `pipeline_config` — system prompts, word counts, negative prompts, image dimensions, and Piper voice selection.

## Architecture

```
~/factory/
├── jobs/
│   ├── inbox/          ← New jobs land here
│   ├── active/         ← Jobs currently being processed
│   ├── completed/      ← Finished jobs
│   └── failed/         ← Jobs that exceeded max retries
├── artifacts/          ← Output files per job (script, images, video, etc.)
├── state/
│   ├── agents/         ← Heartbeat JSON files (one per agent)
│   ├── leases/         ← Lease tokens (foreman → agent assignments)
│   ├── events/         ← Structured JSONL event log
│   └── metrics/        ← System resource snapshots
├── logs/               ← Per-agent log files
├── dashboard/          ← Static HTML inspector
└── assets/music/       ← Drop .mp3 files for background music
```

### Key design decisions

- **File-based job queue** — No database. Jobs are `job.json` files moved between directories. This makes the system inspectable, debuggable, and trivially resumable.
- **Lease-based scheduling** — The Foreman is the only process that writes leases. Agents poll for their lease token; if it expires (heavy: 2h, medium: 15min, light: 5min), the Foreman reclaims the job and retries (up to 3×) or marks it failed.
- **Resource isolation** — Only 1 heavy (visual) job runs at a time. The `ResourceGuard` enforces limits per class: `heavy: 1`, `medium: 1`, `light: ∞`. Anti-starvation scheduling guarantees each class gets at least 1 slot per tick.
- **Crash-safe resume** — Every agent checks `artifact_exists()` before generating anything. If an agent dies mid-pipeline, it picks up where it left off on restart.
- **Atomic writes** — All JSON state files use write-then-rename (`path.tmp → path`) to prevent partial reads.
- **Agent pause/resume** — Operators can send pause signals via `factoryctl pause-agent <id>` or the HTTP API. The foreman skips paused agents.

### Retry & failure handling

```
┌──────────┐     ┌──────────┐     ┌──────────┐
│  Lease   │────▶│  Retry   │────▶│  Mark    │
│  expires │     │  (up to  │     │  Failed  │
│          │     │   3×)    │     │          │
└──────────┘     └──────────┘     └──────────┘
      │                │
      │           Job resets to
      │           phase=created,
      │           re-enters inbox
      │
  Foreman detects
  on next tick (3s)
```

The Foreman scans for expired leases every 3 seconds. If retries < max (3), the job resets to `phase=created` and re-enters the inbox. After 3 failures, it's moved to `failed/`.

## Requirements

| | Minimum | Recommended |
|--|---------|-------------|
| RAM | 8 GB | 16 GB+ |
| GPU VRAM | — | 6 GB (GTX 1060 or better) |
| Disk | 10 GB | 20 GB+ |
| OS | Ubuntu 22.04+ | Ubuntu 24.04 |

Software installed automatically by `install.sh`: ComfyUI, DreamShaper 8, Piper TTS, ffmpeg, Python dependencies (~2.5 GB total model downloads).

## Install

```bash
git clone https://github.com/xbrxr03/content-factory
cd content-factory
bash install.sh
```

First run downloads ~2.5 GB of models. Re-runs are fast — skips anything already installed.

## Quick Start

```bash
# Start all agents
bash ~/factory/start.sh

# Submit a job
cd ~/factory
python3 factoryctl.py new-job "the rise and fall of Kodak" --template documentary_video

# Watch progress
python3 factoryctl.py status

# Dashboard
open http://localhost:7000
```

### Via ClawOS / Claw Core REPL

```
make a video about the history of NASA
```

### Via WhatsApp (OpenClaw gateway)

```
make a video about the rise and fall of Nokia
```

## CLI Reference

```bash
factoryctl new-job "Your topic" [--template TEMPLATE] [--priority 1-10]
factoryctl status [JOB_ID]
factoryctl agents                    # Agent health & heartbeat status
factoryctl logs [AGENT_ID] [--tail]  # View agent logs
factoryctl events [--tail N]         # Structured event stream
factoryctl metrics                   # System resource snapshot
factoryctl inspect JOB_ID            # Deep-inspect a job
factoryctl retry JOB_ID              # Re-queue a failed job
factoryctl cancel-job JOB_ID         # Cancel a pending/active job
factoryctl pause-job JOB_ID          # Pause a pending job
factoryctl resume-job JOB_ID         # Resume a paused job
factoryctl pause-agent AGENT_ID     # Pause an agent
factoryctl resume-agent AGENT_ID     # Resume an agent
factoryctl version                   # Show version
```

## HTTP API

The Monitor Agent serves a REST API on port 7000:

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/health` | System snapshot (CPU, RAM, disk, queue depth) |
| GET | `/agents` | Agent heartbeat status |
| GET | `/jobs` | All jobs across all queues |
| GET | `/jobs/<id>` | Single job detail + artifact list |
| GET | `/jobs/<id>/artifact/<name>` | Raw artifact file |
| GET | `/jobs/<id>/logs` | Agent log tail for a job |
| GET | `/events?tail=N` | Last N structured events |
| GET | `/metrics` | System resource metrics |
| POST | `/api/jobs` | Create job `{topic, priority, template}` |
| POST | `/api/jobs/<id>/retry` | Retry a failed job |
| POST | `/api/jobs/<id>/cancel` | Cancel a job |
| POST | `/api/jobs/<id>/pause` | Pause a job |
| POST | `/api/jobs/<id>/resume` | Resume a job |
| POST | `/api/agents/<id>/pause` | Pause an agent |
| POST | `/api/agents/<id>/resume` | Resume an agent |

## YouTube Upload (opt-in)

YouTube upload is **disabled by default**. To enable:

1. Go to [console.cloud.google.com](https://console.cloud.google.com)
2. Create project → Enable YouTube Data API v3
3. Credentials → OAuth 2.0 → Desktop app → Download JSON
4. Save as `~/.claw/skills/content-factory/youtube_credentials.json`
5. Test: `python3 youtube_upload.py --test`

Videos upload at 9am daily (configurable in `schedule.json`).

## Install as OpenClaw Skill

```bash
openclaw skills install content-factory
```

## Part of ClawOS

This skill ships with [ClawOS](https://github.com/xbrxr03/clawos) — the agent-native Linux OS.

## License

MIT