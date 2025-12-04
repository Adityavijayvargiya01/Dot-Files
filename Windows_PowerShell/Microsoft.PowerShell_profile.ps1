Import-Module -Name Terminal-Icons
Invoke-Expression (&starship init powershell)
fastfetch

#Folders
function home { cd ~ }
function projects { cd ~/Projects }

#Scoop
function list { scoop list }
function su { scoop update * && winget upgrade --all }
function cleanup { scoop cleanup * && scoop cache rm *  }

#powershell
function pro { code $PROFILE }
function pn { nvim $PROFILE}
function local { cd C:\Users\Aditya\AppData\Local }
function roaming { cd C:\Users\Aditya\AppData\Roaming }
function load { .$PROFILE }
function path { pwd | scb }
function newt { wezterm.exe }
function rd { rm -r -FORCE }

function edit {
    param([string]$FilePath)
    notepad++ $FilePath
}

function spt { spotify_player }
function ntp { ntop -s MEM }
function tvc {
    param (
        [Parameter(ValueFromRemainingArguments = $true)]
        [String[]]$Args
    )
    $selected = tv dirs @Args
    if ($selected) {
        cd $selected
    }
}

# Git
function gs { git status }
function gcm { git commit -m $args }
function lm { git checkout main; git pull }
function gp { git pull; git push }
function ulc { git reset --soft HEAD~1 }
function gst { git stash }
function pop { git stash pop }
function gstapp { git stash apply }

# npm
function nrd { npm run dev }
function nrb { npm run build }
function ni { npm install }
function nu { npm uninstall }
function nr { npm run $args }
function nrp { npm run prisma:studio }

# macOS (Replaced with Windows compatible)
function port { netstat -ano | findstr :$args }
function stop { Stop-Process -Id $args -Force }

# Bun
function bx { bunx }
function b { bun }
function ba { bun add $args }
function bi { bun install }
function br { bun run $args }
function bu { bun update }
function bre { bun remove $args }
function brd { bun run dev }
function brb { bun run build }
function bpm { bun pm }

#wsl
function wslshut { wsl --shutdown }
