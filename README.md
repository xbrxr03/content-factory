<div align="center">

# 🎬 content-factory

### Fully automated faceless YouTube documentary pipeline

[![Python](https://img.shields.io/badge/Python-3.10+-3776AB?logo=python&logoColor=white)](https://python.org/)
[![Ollama](https://img.shields.io/badge/Ollama-Local_AI-000000?logo=ollama&logoColor=white)](https://ollama.ai)
[![ComfyUI](https://img.shields.io/badge/ComfyUI-DreamShaper-6366F1)](https://github.com/comfyanonymous/ComfyUI)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

</div>

Fully automated faceless YouTube documentary pipeline. Send a topic via WhatsApp or chat, wake up to a published video. Runs 100% offline on your own hardware.

```
"make a video about the rise and fall of Kodak"
      ↓
  script.txt   (Ollama qwen2.5:7b,   ~2 min)
  voice.wav    (Piper TTS,            ~1 min)
  image_01-08  (ComfyUI DreamShaper,  ~5 min)
  final.mp4    (ffmpeg Ken Burns,     ~5 min)
  youtube      (scheduled 9am — opt-in)
```

## Requirements

| | Minimum | Recommended |
|--|---------|-------------|
| RAM | 8GB | 16GB+ |
| GPU VRAM | — | 6GB (GTX 1060 or better) |
| Disk | 10GB | 20GB+ |
| OS | Ubuntu 22.04+ | Ubuntu 24.04 |

Software installed automatically: ComfyUI, DreamShaper 8, Piper TTS, ffmpeg

## Install

```bash
git clone https://github.com/xbrxr03/content-factory
cd content-factory
bash install.sh
```

First run downloads ~2.5GB of models. Re-runs are fast — skips anything already installed.

## Quick start

```bash
# Start the pipeline
bash ~/factory/start.sh

# Submit a job
cd ~/factory
python3 factoryctl.py new-job "the rise and fall of Kodak" --template documentary_video

# Watch progress
python3 factoryctl.py status

# Dashboard
open http://localhost:7000
```

## Via ClawOS / Claw Core REPL

```
make a video about the history of NASA
```

## Via WhatsApp (OpenClaw gateway)

```
make a video about the rise and fall of Nokia
```

## Pipeline stages

| Phase | Agent | Output | Time |
|-------|-------|--------|------|
| Writing | writer_agent | script.txt, shots.json | ~2 min |
| Voice | voice_agent | voice.wav | ~1 min |
| Assembly | assembler_agent | edit_plan.json | ~30s |
| Visual | visual_agent | image_01..N.png | ~5 min (GPU) |
| Render | render_agent | final_video.mp4 | ~5 min |
| Upload | upload_agent | youtube_upload.json | scheduled, opt-in |

## Templates

```bash
--template documentary_video   # 8-12 min, cinematic narrator
--template educational_video   # 5-10 min, explainer style
--template short_form_video    # 60-90 sec, social media
--template tutorial_video      # 5-8 min, step by step
```

## YouTube upload (opt-in)

YouTube upload is disabled by default. To enable:

1. Go to [console.cloud.google.com](https://console.cloud.google.com)
2. Create project → Enable YouTube Data API v3
3. Credentials → OAuth 2.0 → Desktop app → Download JSON
4. Save as `~/.claw/skills/content-factory/youtube_credentials.json`
5. Test: `python3 youtube_upload.py --test`

Videos will upload at 9am daily (configurable in `schedule.json`).

## Install as OpenClaw skill

```bash
openclaw skills install content-factory
```

## Part of ClawOS

This skill ships with [ClawOS](https://github.com/xbrxr03/clawos) — the agent-native Linux OS.

## License

MIT
