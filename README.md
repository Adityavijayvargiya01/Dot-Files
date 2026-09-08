# Dot-Files

**Terminal & Shell**
- PowerShell Profile (aliases, git/npm/bun shortcuts)
- Starship Prompt
- Fastfetch (with dragon ASCII art)
- Terminal Icons
- Herdr (terminal workspace manager)
- OMP Agent Config
- Pi Agent (settings, MCP, extensions, themes)

**Editor**
- Neovim (LazyVim)

**Media**
- Spotify Player (terminal client)

**Browser**
- Nightab Configuration

**Omarchy**
- Custom menu plugin (`aditya.menu` — cloned from `omarchy.menu` with custom layout/rows)
- Herdr status plugin (`aditya.herdr` — traffic-light bar widget for Herdr agents)
- Shell config (`shell.json` — bottom bar, custom clock format, idle/lock timings)
- Shell tweaks (`shell.toml` — font size, spacing)

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
cp ./omarchy/shell.json ./omarchy/shell.toml ~/.config/omarchy/ -f
cp -r ./omarchy/plugins/aditya.menu ./omarchy/plugins/aditya.herdr ~/.config/omarchy/plugins/ -f
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
