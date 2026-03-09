#!/bin/bash
# Runs at container start via linuxserver s6-overlay custom-cont-init.d
# Installs extensions once (marker file prevents re-running on every restart)

MARKER="/config/.extensions-installed"
EXTENSIONS_DIR="/config/extensions"
USER_DATA_DIR="/config/data"

if [ ! -f "$MARKER" ]; then
    echo "[init] Installing code-server extensions..."
    /app/code-server/bin/code-server \
        --extensions-dir "$EXTENSIONS_DIR" \
        --user-data-dir "$USER_DATA_DIR" \
        --install-extension continue.continue \
    && touch "$MARKER" \
    && echo "[init] Extensions installed." \
    || echo "[init] Extension install failed — will retry on next start."
else
    echo "[init] Extensions already installed, skipping."
fi

# Seed settings.json on first run (won't overwrite after initial write)
SETTINGS_DST="$USER_DATA_DIR/User/settings.json"
if [ ! -f "$SETTINGS_DST" ] && [ -f "/defaults/settings.json" ]; then
    mkdir -p "$USER_DATA_DIR/User"
    cp /defaults/settings.json "$SETTINGS_DST"
    echo "[init] settings.json seeded."
fi
