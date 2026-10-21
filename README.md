# Dot-Files

**Terminal & Shell**
- PowerShell Profile (aliases, git/npm/bun shortcuts)
- Starship Prompt
- Fastfetch (with dragon ASCII art)
- Terminal Icons
- Herdr (terminal workspace manager)
- OMP Agent (config, Mire theme, Herdr extension)
- Pi Agent (settings, MCP, extensions, themes)

**Editor**
- Neovim (LazyVim)

**Media**
- Spotify Player (terminal client)

**Browser**
- Nightab Configuration

**Omarchy**
- Custom menu plugin (`aditya.menu` — cloned from `omarchy.menu` with custom layout/rows)
- Traffic plugin (`aditya.traffic` — traffic-light bar widget for Pi, OpenCode, OMP, and other Herdr agents)
- Bar widgets (`aditya.grayscale`, `aditya.opacity`, `aditya.ram`)
- Compose overlay (`aditya.tweet` — draft and post tweets)
- Menu extension (`omarchy-menu.jsonc` — grayscale toggle), wallpaper rotation script, and macOS dock pins
- Shell config (`shell.json` — top bar, custom clock format, idle/lock timings)
- Shell tweaks (`shell.toml` — font size, spacing, bar height)
- Requires third-party plugins: `macos.dock` and `io.github.adityavijayvargiya01.coverglow`

**Extras**
- Curated Wallpapers
- StartAllBack Bypass

## Quick Install

```powershell
# PowerShell Profile
Copy-Item .\Windows_Powershell\Microsoft.PowerShell_profile.ps1 $PROFILE -Force

# Starship
Copy-Item .\Starship\starship.toml $env:USERPROFILE\.config\starship.toml -Force

# Fastfetch
Copy-Item .\Fastfetch\* $env:USERPROFILE\.config\fastfetch\ -Recurse -Force

# Neovim
Copy-Item .\nvim\* $env:LOCALAPPDATA\nvim\ -Recurse -Force

# OMP Agent
Copy-Item .\omp\* $env:USERPROFILE\.omp\ -Recurse -Force

# Herdr
Copy-Item .\herdr\* $env:USERPROFILE\.config\herdr\ -Recurse -Force

# Pi Agent
Copy-Item .\pi\* $env:USERPROFILE\.pi\ -Recurse -Force
```

```bash
# Omarchy (Linux)
cp ./omarchy/shell.json ./omarchy/shell.toml ./omarchy/dock-pinned-macos.json ~/.config/omarchy/ -f
cp -r ./omarchy/plugins/aditya.* ~/.config/omarchy/plugins/ -f
cp -r ./omarchy/extensions/. ~/.config/omarchy/extensions/
cp -r ./omarchy/scripts/. ~/.config/omarchy/scripts/
mkdir -p ~/.config/omarchy/defaults
cp ./omarchy/defaults/agent ~/.config/omarchy/defaults/agent

# Agent themes and Herdr harness symlinks
cp ./omp/agent/themes/mire.json ~/.omp/agent/themes/

# Compose overlay dependencies (virtualenv is not tracked)
python -m venv ~/.config/omarchy/plugins/aditya.tweet/.venv
~/.config/omarchy/plugins/aditya.tweet/.venv/bin/pip install -r ~/.config/omarchy/plugins/aditya.tweet/requirements.txt

mkdir -p ~/.omp/agent/extensions ~/.pi/agent/extensions
ln -sfn ~/.config/omarchy/plugins/aditya.traffic/harness/omp.ts ~/.omp/agent/extensions/traffic-herdr.ts
ln -sfn ~/.config/omarchy/plugins/aditya.traffic/harness/pi.ts ~/.pi/agent/extensions/traffic-herdr.ts

omarchy restart shell
```

## Softwares & Libs

Obsidian
Helium Browser 
Zed 
Perplexity
localsend
neovim 
notepad++
obs-studio 
picotorrent
starship 
terminal-icons
vlc 
Fold Money
MyMind

## Windows Must Have Apps

Everything
windirstat
