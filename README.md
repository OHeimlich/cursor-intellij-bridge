# Cursor → IntelliJ Bridge

Jump from Cursor edits directly to IntelliJ at the exact changed lines.

![macOS](https://img.shields.io/badge/platform-macOS-blue)
![Cursor 2.0+](https://img.shields.io/badge/Cursor-2.0%2B-green)
![IntelliJ IDEA](https://img.shields.io/badge/IntelliJ-Ultimate%20%7C%20CE-orange)

## The Problem

Using Cursor Agent for AI-assisted coding but still need IntelliJ for code review and navigation?

For languages like Scala (or anything with complex build systems like Bazel), IntelliJ's tooling is still unmatched. But context switching is painful — finishing an Agent session, then manually hunting for changed files in IntelliJ.

## The Solution

Press `⌘⇧J` → IntelliJ opens all files Cursor just edited, at the exact lines.

```
Cursor Agent edits files → Press ⌘⇧J → IntelliJ opens all files at changed lines
```

## Installation

```bash
curl -fsSL https://raw.githubusercontent.com/user/cursor-intellij-bridge/main/install.sh | bash
```

Or clone and run:

```bash
git clone https://github.com/user/cursor-intellij-bridge.git
cd cursor-intellij-bridge
bash install.sh
```

Then:
1. Restart your terminal (or run `source ~/.zshrc`)
2. Restart Cursor
3. Done!

## What Gets Installed

The script automatically:
- ✅ Installs `jq` (if needed)
- ✅ Adds IntelliJ CLI to your PATH
- ✅ Installs Cursor hooks
- ✅ Configures global task (works in all projects)
- ✅ Sets up `⌘⇧J` keyboard shortcut

## Requirements

- macOS
- Cursor 2.0+
- IntelliJ IDEA (Ultimate or CE) in `/Applications`
- Homebrew (for jq installation)

## How It Works

1. **Cursor hooks** (`afterFileEdit`) track every file the Agent edits
2. **Line detection** calculates the exact line number of each change
3. **On `⌘⇧J`**: brings IntelliJ to foreground, syncs files, opens each file at the right line

## Usage

1. Use Cursor Agent to edit files
2. Press `⌘⇧J`
3. IntelliJ opens all changed files at the exact lines

## Uninstall

```bash
rm -rf ~/.cursor/hooks ~/.cursor/hooks.json
```

Then manually remove:
- Keybindings from `~/Library/Application Support/Cursor/User/keybindings.json`
- PATH line from `~/.zshrc` or `~/.bashrc`

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Hooks not working | Restart Cursor |
| `⌘⇧J` doesn't work | Restart Cursor |
| `idea` not found | Restart terminal or run `source ~/.zshrc` |
| No notification | Check macOS Settings → Notifications → Cursor |

## License

MIT
