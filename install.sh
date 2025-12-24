#!/bin/bash
#
# Cursor → IntelliJ Bridge
# =======================
# Seamlessly jump from Cursor AI edits to IntelliJ at the exact changed lines.
#
# Usage: bash install-cursor-intellij-bridge.sh
#
set -e

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║         Cursor → IntelliJ Bridge Installer                ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Check macOS
if [[ "$(uname)" != "Darwin" ]]; then
  echo "❌ Error: This tool only supports macOS"
  exit 1
fi

# Detect shell config file
detect_shell_config() {
  if [[ "$SHELL" == *"zsh"* ]]; then
    echo "$HOME/.zshrc"
  else
    echo "$HOME/.bashrc"
  fi
}
SHELL_CONFIG=$(detect_shell_config)

# Check for jq
echo "[1/6] Checking dependencies..."
if ! command -v jq &> /dev/null; then
  echo "      Installing jq..."
  brew install jq
fi
echo "      ✓ jq installed"

# Setup IntelliJ in PATH
echo "[2/6] Configuring IntelliJ CLI..."
INTELLIJ_PATH=""
if [[ -d "/Applications/IntelliJ IDEA.app/Contents/MacOS" ]]; then
  INTELLIJ_PATH="/Applications/IntelliJ IDEA.app/Contents/MacOS"
elif [[ -d "/Applications/IntelliJ IDEA CE.app/Contents/MacOS" ]]; then
  INTELLIJ_PATH="/Applications/IntelliJ IDEA CE.app/Contents/MacOS"
fi

if [[ -n "$INTELLIJ_PATH" ]]; then
  # Check if already in PATH
  if ! grep -q "$INTELLIJ_PATH" "$SHELL_CONFIG" 2>/dev/null; then
    echo "" >> "$SHELL_CONFIG"
    echo "# IntelliJ IDEA CLI (added by cursor-intellij-bridge)" >> "$SHELL_CONFIG"
    echo "export PATH=\"\$PATH:$INTELLIJ_PATH\"" >> "$SHELL_CONFIG"
    echo "      ✓ Added IntelliJ to PATH in $SHELL_CONFIG"
  else
    echo "      ✓ IntelliJ already in PATH"
  fi
  # Export for current session
  export PATH="$PATH:$INTELLIJ_PATH"
else
  echo "      ⚠️  IntelliJ not found in /Applications"
  echo "      Please install IntelliJ IDEA first"
fi

# Create hooks directory
echo "[3/6] Installing Cursor hooks..."
mkdir -p ~/.cursor/hooks

#------------------------------------------
# hooks.json
#------------------------------------------
cat > ~/.cursor/hooks.json << 'EOF'
{
  "version": 1,
  "hooks": {
    "afterFileEdit": [
      {
        "command": "~/.cursor/hooks/track-edit.sh"
      }
    ],
    "stop": [
      {
        "command": "~/.cursor/hooks/on-stop.sh"
      }
    ]
  }
}
EOF

#------------------------------------------
# track-edit.sh
#------------------------------------------
cat > ~/.cursor/hooks/track-edit.sh << 'EOF'
#!/bin/bash
# Tracks files edited by Cursor AI with line numbers
TRACKING_FILE="/tmp/cursor-changed-files.txt"

payload=$(cat)
file_path=$(echo "$payload" | jq -r '.file_path')
workspace=$(echo "$payload" | jq -r '.workspace_roots[0]')

[[ "$file_path" != /* ]] && file_path="$workspace/$file_path"

old_string=$(echo "$payload" | jq -r '.edits[0].old_string // empty')
new_string=$(echo "$payload" | jq -r '.edits[0].new_string // empty')

line_number=1
diff_offset=0

if [[ -n "$old_string" && -n "$new_string" ]]; then
  while IFS= read -r old_line <&3 && IFS= read -r new_line <&4; do
    diff_offset=$((diff_offset + 1))
    [[ "$old_line" != "$new_line" ]] && break
  done 3< <(echo "$old_string") 4< <(echo "$new_string")
  
  old_count=$(echo "$old_string" | wc -l)
  new_count=$(echo "$new_string" | wc -l)
  [[ $diff_offset -gt $old_count || $diff_offset -gt $new_count ]] && \
    diff_offset=$(( old_count < new_count ? old_count : new_count ))
fi

if [[ -f "$file_path" && -n "$old_string" ]]; then
  first_old_line=$(echo "$old_string" | head -1)
  if [[ -n "$first_old_line" ]]; then
    block_start=$(grep -n -F "$first_old_line" "$file_path" 2>/dev/null | head -1 | cut -d: -f1)
    [[ -n "$block_start" && "$block_start" =~ ^[0-9]+$ ]] && \
      line_number=$((block_start + diff_offset - 1))
  fi
fi

entry="$file_path:$line_number"
if grep -q "^$file_path:" "$TRACKING_FILE" 2>/dev/null; then
  sed -i '' "s|^$file_path:.*|$entry|" "$TRACKING_FILE"
else
  echo "$entry" >> "$TRACKING_FILE"
fi
EOF

#------------------------------------------
# on-stop.sh
#------------------------------------------
cat > ~/.cursor/hooks/on-stop.sh << 'EOF'
#!/bin/bash
# Shows notification when Cursor AI agent completes
TRACKING_FILE="/tmp/cursor-changed-files.txt"

[[ ! -f "$TRACKING_FILE" || ! -s "$TRACKING_FILE" ]] && exit 0

file_count=$(wc -l < "$TRACKING_FILE" | tr -d ' ')
filenames=$(while IFS=: read -r filepath line; do
  basename "$filepath"
done < "$TRACKING_FILE" | tr '\n' ', ' | sed 's/,$//' | cut -c1-50)

osascript <<APPLESCRIPT
display notification "$file_count file(s): $filenames" ¬
  with title "Cursor → IntelliJ" ¬
  subtitle "Press ⌘⇧J to open" ¬
  sound name "Pop"
APPLESCRIPT
EOF

#------------------------------------------
# open-in-intellij.sh
#------------------------------------------
cat > ~/.cursor/hooks/open-in-intellij.sh << 'EOF'
#!/bin/bash
# Opens tracked files in IntelliJ at specific lines
TRACKING_FILE="/tmp/cursor-changed-files.txt"

# Ensure IntelliJ is in PATH
[[ -d "/Applications/IntelliJ IDEA.app/Contents/MacOS" ]] && \
  export PATH="$PATH:/Applications/IntelliJ IDEA.app/Contents/MacOS"
[[ -d "/Applications/IntelliJ IDEA CE.app/Contents/MacOS" ]] && \
  export PATH="$PATH:/Applications/IntelliJ IDEA CE.app/Contents/MacOS"

if [[ ! -f "$TRACKING_FILE" || ! -s "$TRACKING_FILE" ]]; then
  osascript -e 'display notification "No recent Cursor changes to open" with title "Cursor → IntelliJ"'
  exit 0
fi

start_time=$(perl -MTime::HiRes=time -e 'printf "%.0f", time * 1000' 2>/dev/null || echo $(($(date +%s) * 1000)))

# Detect IntelliJ variant
detect_intellij_app() {
  if pgrep -f "IntelliJ IDEA.app" > /dev/null 2>&1; then
    echo "IntelliJ IDEA"
  elif pgrep -f "IntelliJ IDEA CE.app" > /dev/null 2>&1; then
    echo "IntelliJ IDEA CE"
  elif [[ -d "/Applications/IntelliJ IDEA.app" ]]; then
    echo "IntelliJ IDEA"
  elif [[ -d "/Applications/IntelliJ IDEA CE.app" ]]; then
    echo "IntelliJ IDEA CE"
  else
    echo "IntelliJ IDEA"
  fi
}

INTELLIJ_APP=$(detect_intellij_app)

# Activate IntelliJ
osascript -e "tell application \"$INTELLIJ_APP\" to activate"
sleep 0.3

# Sync files (Cmd+Alt+Y)
osascript <<APPLESCRIPT
tell application "System Events"
  tell process "$INTELLIJ_APP"
    keystroke "y" using {command down, option down}
  end tell
end tell
APPLESCRIPT
sleep 0.3

file_count=$(wc -l < "$TRACKING_FILE" | tr -d ' ')

# Open each file at its line
while IFS=: read -r filepath line_number; do
  [[ -f "$filepath" ]] && idea --line "${line_number:-1}" "$filepath" &
  sleep 0.15
done < "$TRACKING_FILE"

rm -f "$TRACKING_FILE"
wait

end_time=$(perl -MTime::HiRes=time -e 'printf "%.0f", time * 1000' 2>/dev/null || echo $(($(date +%s) * 1000)))
duration_ms=$((end_time - start_time))
duration_sec=$(echo "scale=2; $duration_ms / 1000" | bc)

osascript -e "display notification \"Opened $file_count file(s) in ${duration_sec}s\" with title \"✓ Cursor → IntelliJ\""
EOF

chmod +x ~/.cursor/hooks/*.sh
echo "      ✓ Hooks installed"

# Setup global VSCode/Cursor tasks
echo "[4/6] Configuring global tasks..."
CURSOR_USER_DIR="$HOME/Library/Application Support/Cursor/User"
mkdir -p "$CURSOR_USER_DIR"

# Create or update global tasks.json
TASKS_FILE="$CURSOR_USER_DIR/tasks.json"
cat > "$TASKS_FILE" << 'EOF'
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "Open in IntelliJ",
      "type": "shell",
      "command": "~/.cursor/hooks/open-in-intellij.sh",
      "presentation": {
        "reveal": "silent",
        "close": true
      },
      "problemMatcher": []
    }
  ]
}
EOF
echo "      ✓ Global tasks configured"

# Setup keybindings
echo "[5/6] Configuring keyboard shortcuts..."
KEYBINDINGS_FILE="$CURSOR_USER_DIR/keybindings.json"

# Create new keybindings or merge with existing
NEW_KEYBINDINGS='[
  {
    "key": "cmd+shift+j",
    "command": "workbench.action.terminal.sendSequence",
    "args": { "text": "~/.cursor/hooks/open-in-intellij.sh\n" },
    "when": "terminalIsOpen"
  },
  {
    "key": "cmd+shift+j",
    "command": "workbench.action.tasks.runTask",
    "args": "Open in IntelliJ",
    "when": "!terminalIsOpen"
  }
]'

if [[ -f "$KEYBINDINGS_FILE" ]]; then
  # Check if our keybinding already exists
  if grep -q "Open in IntelliJ" "$KEYBINDINGS_FILE" 2>/dev/null; then
    echo "      ✓ Keybindings already configured"
  else
    # Merge with existing keybindings
    existing=$(cat "$KEYBINDINGS_FILE")
    if [[ "$existing" == "[]" || -z "$existing" ]]; then
      echo "$NEW_KEYBINDINGS" > "$KEYBINDINGS_FILE"
    else
      # Remove trailing ] and add new keybindings
      sed -i '' '$ s/]$/,/' "$KEYBINDINGS_FILE"
      cat >> "$KEYBINDINGS_FILE" << 'EOF'
  {
    "key": "cmd+shift+j",
    "command": "workbench.action.terminal.sendSequence",
    "args": { "text": "~/.cursor/hooks/open-in-intellij.sh\n" },
    "when": "terminalIsOpen"
  },
  {
    "key": "cmd+shift+j",
    "command": "workbench.action.tasks.runTask",
    "args": "Open in IntelliJ",
    "when": "!terminalIsOpen"
  }
]
EOF
    fi
    echo "      ✓ Keybindings added"
  fi
else
  echo "$NEW_KEYBINDINGS" > "$KEYBINDINGS_FILE"
  echo "      ✓ Keybindings created"
fi

# Final instructions
echo "[6/6] Finalizing..."
echo "      ✓ Installation complete"

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║              ✓ Installation Complete!                     ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "WHAT WAS INSTALLED:"
echo "  • Cursor hooks in ~/.cursor/hooks/"
echo "  • Global task 'Open in IntelliJ'"
echo "  • Keyboard shortcut ⌘⇧J"
echo "  • IntelliJ CLI added to PATH in $SHELL_CONFIG"
echo ""
echo "NEXT STEPS:"
echo ""
echo "  1. Restart your terminal (or run: source $SHELL_CONFIG)"
echo "  2. Restart Cursor"
echo "  3. Done! Use ⌘⇧J to jump to IntelliJ"
echo ""
echo "USAGE:"
echo "  • Use Cursor AI Agent to edit files"
echo "  • When agent completes → notification appears"
echo "  • Press ⌘⇧J → files open in IntelliJ at exact lines"
echo ""
echo "TEST:"
echo "  ~/.cursor/hooks/open-in-intellij.sh"
echo ""
echo "UNINSTALL:"
echo "  rm -rf ~/.cursor/hooks ~/.cursor/hooks.json"
echo "  # Remove keybindings manually from Cursor settings"
echo "  # Remove PATH line from $SHELL_CONFIG"
echo ""
