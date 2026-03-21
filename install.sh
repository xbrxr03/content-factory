#!/bin/bash
# content-factory — full installer
# Installs: system deps, Python packages, Piper TTS, ComfyUI, DreamShaper 8,
#           factory pipeline, skill for Claw Core + OpenClaw, then runs tests.
#
# Usage: bash install.sh
# Re-run safely: skips anything already installed.
set -euo pipefail

G="\033[38;5;84m"; R="\033[38;5;203m"; B="\033[38;5;75m"
Y="\033[38;5;220m"; D="\033[2m\033[38;5;245m"; RESET="\033[0m"; BOLD="\033[1m"

ok()     { echo -e "  ${G}✓${RESET}  $1"; }
step()   { echo -e "\n  ${B}${BOLD}──${RESET}  $1"; }
warn()   { echo -e "  ${Y}!${RESET}  $1"; }
info()   { echo -e "  ${D}·  $1${RESET}"; }
die()    { echo -e "\n  ${R}✗${RESET}  $1\n"; exit 1; }
confirm(){ echo -e "  ${B}?${RESET}  $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FACTORY_DIR="${FACTORY_DIR:-$HOME/factory}"
COMFYUI_DIR="${COMFYUI_DIR:-$HOME/ComfyUI}"
CLAW_SKILL_DIR="$HOME/.claw/skills/content-factory"
OC_SKILL_DIR="$HOME/.openclaw/skills/content-factory"
PIPER_MODEL_DIR="$HOME/.local/share/piper"
CHECKPOINT_NAME="dreamshaper_8.safetensors"
CHECKPOINT_URL="https://huggingface.co/Lykon/DreamShaper/resolve/main/DreamShaper_8_pruned.safetensors"

echo ""
echo -e "  ${B}${BOLD}🎬 Content Factory — Installer${RESET}"
echo -e "  ${D}────────────────────────────────────${RESET}"
echo ""
info "Factory dir:  $FACTORY_DIR"
info "ComfyUI dir:  $COMFYUI_DIR"
info "Checkpoint:   $CHECKPOINT_NAME (~2GB)"
echo ""

# ── 1. System packages ────────────────────────────────────────────────────────
step "System packages"
sudo apt-get update -qq 2>/dev/null || warn "apt update had errors — continuing"
sudo apt-get install -y -qq \
  ffmpeg python3-pip python3-dev \
  fonts-dejavu wget git curl \
  libsndfile1 \
  2>/dev/null || warn "Some system packages failed — continuing"
ok "System packages installed"

# ── 2. Python packages ────────────────────────────────────────────────────────
step "Python packages"
pip3 install -q \
  psutil pathvalidate \
  piper-tts \
  requests pillow \
  google-auth-oauthlib google-api-python-client \
  --break-system-packages 2>/dev/null \
|| pip3 install -q \
  psutil pathvalidate \
  piper-tts \
  requests pillow \
  google-auth-oauthlib google-api-python-client \
  --user 2>/dev/null \
|| warn "Some Python packages failed"
ok "psutil, pathvalidate, piper-tts, requests, pillow, google-auth installed"

# ── 3. Piper voice model ──────────────────────────────────────────────────────
step "Piper TTS voice model"
mkdir -p "$PIPER_MODEL_DIR"
PIPER_MODEL="$PIPER_MODEL_DIR/en_US-lessac-medium.onnx"

if [ ! -f "$PIPER_MODEL" ]; then
  info "Downloading voice model (~60MB)..."
  BASE="https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/lessac/medium"
  wget -q --show-progress "$BASE/en_US-lessac-medium.onnx" -O "$PIPER_MODEL" 2>&1 \
  || curl -L --progress-bar "$BASE/en_US-lessac-medium.onnx" -o "$PIPER_MODEL" \
  || die "Voice model download failed. Check internet connection."
  wget -q "$BASE/en_US-lessac-medium.onnx.json" -O "${PIPER_MODEL}.json" 2>/dev/null || true
  ok "Voice model downloaded"
else
  ok "Voice model already present"
fi

# Verify piper works
if echo "test" | piper --model "$PIPER_MODEL" --output_file /tmp/piper_verify.wav 2>/dev/null; then
  rm -f /tmp/piper_verify.wav
  ok "Piper TTS verified working"
else
  warn "Piper verification failed — check piper installation"
fi

# ── 4. ComfyUI ────────────────────────────────────────────────────────────────
step "ComfyUI (Stable Diffusion image generation)"

if [ -d "$COMFYUI_DIR" ] && [ -f "$COMFYUI_DIR/main.py" ]; then
  info "ComfyUI already installed at $COMFYUI_DIR"
  ok "ComfyUI present"
else
  info "Cloning ComfyUI (~500MB)..."
  git clone -q --depth 1 https://github.com/comfyanonymous/ComfyUI.git "$COMFYUI_DIR" \
    || die "ComfyUI clone failed. Check internet connection."
  ok "ComfyUI cloned to $COMFYUI_DIR"
fi

# Install ComfyUI Python requirements
info "Installing ComfyUI Python dependencies..."
pip3 install -q -r "$COMFYUI_DIR/requirements.txt" \
  --break-system-packages 2>/dev/null \
|| pip3 install -q -r "$COMFYUI_DIR/requirements.txt" \
  --user 2>/dev/null \
|| warn "Some ComfyUI deps failed — image generation may not work"
ok "ComfyUI dependencies installed"

# ── 5. DreamShaper 8 checkpoint ───────────────────────────────────────────────
step "DreamShaper 8 checkpoint (~2GB)"
CKPT_DIR="$COMFYUI_DIR/models/checkpoints"
mkdir -p "$CKPT_DIR"
CKPT_PATH="$CKPT_DIR/$CHECKPOINT_NAME"

if [ -f "$CKPT_PATH" ]; then
  CKPT_SIZE=$(stat -c%s "$CKPT_PATH" 2>/dev/null || echo 0)
  if [ "$CKPT_SIZE" -gt 1000000000 ]; then
    ok "DreamShaper 8 already downloaded ($(du -sh "$CKPT_PATH" | cut -f1))"
  else
    warn "Checkpoint file looks incomplete — re-downloading"
    rm -f "$CKPT_PATH"
  fi
fi

if [ ! -f "$CKPT_PATH" ]; then
  info "Downloading DreamShaper 8 (~2GB, this takes a few minutes)..."
  wget -q --show-progress "$CHECKPOINT_URL" -O "$CKPT_PATH" 2>&1 \
  || curl -L --progress-bar "$CHECKPOINT_URL" -o "$CKPT_PATH" \
  || die "Checkpoint download failed. Check internet and try again."
  ok "DreamShaper 8 downloaded ($(du -sh "$CKPT_PATH" | cut -f1))"
fi

# ── 6. Factory pipeline ───────────────────────────────────────────────────────
step "Factory pipeline"

if [ -d "$FACTORY_DIR" ]; then
  info "Updating factory at $FACTORY_DIR"
  cp -r "$SCRIPT_DIR/factory/." "$FACTORY_DIR/"
  ok "Factory updated"
else
  cp -r "$SCRIPT_DIR/factory" "$FACTORY_DIR"
  ok "Factory installed to $FACTORY_DIR"
fi

# Ensure all required dirs exist
mkdir -p \
  "$FACTORY_DIR/jobs/inbox"     "$FACTORY_DIR/jobs/active" \
  "$FACTORY_DIR/jobs/completed" "$FACTORY_DIR/jobs/failed" \
  "$FACTORY_DIR/artifacts"      "$FACTORY_DIR/logs" \
  "$FACTORY_DIR/state/agents"   "$FACTORY_DIR/state/events" \
  "$FACTORY_DIR/state/leases"   "$FACTORY_DIR/state/metrics" \
  "$FACTORY_DIR/assets/music"

chmod +x "$FACTORY_DIR/start.sh" "$FACTORY_DIR/stop.sh" \
         "$FACTORY_DIR/factoryctl" 2>/dev/null || true

# Write .env with all correct paths
cat > "$FACTORY_DIR/.env" << ENV
FACTORY_ROOT=$FACTORY_DIR
PYTHONPATH=$FACTORY_DIR
OLLAMA_MODEL=qwen2.5:7b
PIPER_BIN=piper
PIPER_MODEL_DIR=$PIPER_MODEL_DIR
PIPER_VOICE=en_US-lessac-medium.onnx
COMFYUI_DIR=$COMFYUI_DIR
COMFYUI_BASE=http://localhost:8188
COMFYUI_CHECKPOINT=$CHECKPOINT_NAME
VISUAL_IMAGE_WIDTH=512
VISUAL_IMAGE_HEIGHT=512
VISUAL_STEPS=20
COMFYUI_STARTUP_TIMEOUT=180
ENV

ok "Factory ready at $FACTORY_DIR"
info ".env written with all paths"

# ── 7. Skills ─────────────────────────────────────────────────────────────────
step "Installing skill"

mkdir -p "$CLAW_SKILL_DIR" "$OC_SKILL_DIR"

for dir in "$CLAW_SKILL_DIR" "$OC_SKILL_DIR"; do
  cp "$SCRIPT_DIR/SKILL.md"          "$dir/SKILL.md"
  cp "$SCRIPT_DIR/youtube_upload.py" "$dir/youtube_upload.py"
  cp "$SCRIPT_DIR/clawhub.json"      "$dir/clawhub.json"
  if [ ! -f "$dir/schedule.json" ]; then
    echo '{"upload_time": "09:00", "timezone": "local", "enabled": false}' > "$dir/schedule.json"
  fi
done

ok "Skill installed → ~/.claw/skills/content-factory/"
ok "Skill installed → ~/.openclaw/skills/content-factory/"

# ── 8. Background music dir ───────────────────────────────────────────────────
step "Assets"
mkdir -p "$FACTORY_DIR/assets/music"
info "Drop royalty-free .mp3 files in: $FACTORY_DIR/assets/music/"
info "Free music: pixabay.com/music"
ok "Assets directory ready"

# ── 9. Test suite ─────────────────────────────────────────────────────────────
step "Running tests"
if PYTHONPATH="$FACTORY_DIR" python3 "$SCRIPT_DIR/test_factory.py" --quick 2>&1; then
  ok "All tests passed"
else
  warn "Some tests failed — check output above before starting factory"
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "  ${G}${BOLD}✓  Content Factory installed!${RESET}"
echo ""
echo -e "  ${D}────────────────────────────────────${RESET}"
echo ""
echo -e "  ${BOLD}1. Start the factory:${RESET}"
echo -e "     ${B}bash ~/factory/start.sh${RESET}"
echo ""
echo -e "  ${BOLD}2. Submit a job:${RESET}"
echo -e "     ${B}cd ~/factory && python3 factoryctl.py new-job \"your topic\" --template documentary_video${RESET}"
echo ""
echo -e "  ${BOLD}3. Watch it run:${RESET}"
echo -e "     ${B}python3 factoryctl.py status${RESET}"
echo -e "     ${B}http://localhost:7000${RESET}  (dashboard)"
echo ""
echo -e "  ${BOLD}YouTube upload (optional):${RESET}"
echo -e "     ${D}Tell Jarvis: 'youtube setup'${RESET}"
echo ""
