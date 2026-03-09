#!/bin/bash
# ============================================================
# transkribieren.sh — Whisper-Transkription für macOS Shortcuts
# ANTIFRAGIL: Absolute Pfade, Anti-Halluzination, sauberer Output
# ============================================================

set -euo pipefail

# --- Absolute Pfade ---
FFMPEG="/opt/homebrew/bin/ffmpeg"
WHISPER="/opt/homebrew/bin/whisper-cli"
MODEL="/Users/eriktaichi/D ObsidianProject/ggml-large-v3.bin"
# ↑ ANPASSEN falls 'find' einen anderen Pfad zeigt!

# Whisper-Parameter (M4 Max optimiert)
LANG="de"
THREADS=8
BEAM_SIZE=5
ENTROPY_THRESH=2.4       # Runter von 2.8 → aggressiver gegen Halluzinationen
MAX_CONTEXT=64
MAX_SEGMENT_LEN=0        # 0 = automatisch, begrenzt Segmentlänge

# --- Anti-Halluzination: Max Wiederholungen eines Segments ---
MAX_REPEAT=3

# --- Preflight ---
MISSING=0
for BIN in "$FFMPEG" "$WHISPER"; do
    if [[ ! -x "$BIN" ]]; then
        echo "FEHLER: Binary nicht gefunden: $BIN" >&2
        MISSING=1
    fi
done
if [[ ! -f "$MODEL" ]]; then
    echo "FEHLER: Modell nicht gefunden: $MODEL" >&2
    FOUND=$(find /opt/homebrew /Users/eriktaichi -name "ggml-large-v3.bin" 2>/dev/null | head -1)
    if [[ -n "$FOUND" ]]; then
        echo "GEFUNDEN: $FOUND — bitte MODEL= anpassen." >&2
    fi
    MISSING=1
fi
[[ $MISSING -eq 1 ]] && exit 2

# --- Input prüfen ---
if [[ $# -lt 1 ]] || [[ ! -f "$1" ]]; then
    echo "Fehler: Gültige Audiodatei als Argument erwartet." >&2
    exit 1
fi
INPUT="$1"

# --- Nur Audiodateien verarbeiten (skip .waveform etc.) ---
case "$INPUT" in
    *.m4a|*.mp3|*.wav|*.aiff|*.ogg|*.flac) ;;
    *) exit 0 ;;
esac

# --- Temp-Datei mit Cleanup ---
TEMP_WAV=$(mktemp /tmp/whisper_XXXXXX.wav)
trap 'rm -f "$TEMP_WAV"' EXIT

# --- Konvertierung ---
if ! "$FFMPEG" -i "$INPUT" -ar 16000 -ac 1 -c:a pcm_s16le "$TEMP_WAV" -y -loglevel error 2>/dev/null; then
    echo "Fehler: ffmpeg-Konvertierung fehlgeschlagen: $INPUT" >&2
    exit 3
fi

# --- Transkription ---
RAW=$("$WHISPER" \
    -m "$MODEL" \
    -l "$LANG" \
    -f "$TEMP_WAV" \
    -t "$THREADS" \
    -et "$ENTROPY_THRESH" \
    -mc "$MAX_CONTEXT" \
    -bs "$BEAM_SIZE" \
    -nt \
    2>/dev/null) || true

if [[ -z "$RAW" ]]; then
    echo "Fehler: Transkription leer." >&2
    exit 4
fi

# --- Anti-Halluzinations-Filter ---
# Entfernt Zeilen die sich mehr als MAX_REPEAT mal am Stück wiederholen.
# Typisches Muster: Whisper halluziniert in Stille denselben Satz.
CLEANED=$(echo "$RAW" | awk -v max="$MAX_REPEAT" '
{
    line = $0
    # Whitespace trimmen für Vergleich
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
    if (line == "") { next }
    if (line == prev) {
        count++
    } else {
        count = 1
        prev = line
    }
    if (count <= max) {
        print $0
    }
}')

# Falls nach Filter nichts mehr übrig
if [[ -z "$CLEANED" ]]; then
    echo "Fehler: Nach Halluzinations-Filter ist kein Text übrig." >&2
    exit 4
fi

# --- Output ---
echo "$CLEANED" | sed 's/[[:space:]]*$//'
