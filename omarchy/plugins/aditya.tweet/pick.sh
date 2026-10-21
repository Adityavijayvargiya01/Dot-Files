#!/usr/bin/env bash
set -euo pipefail
# Desktop FileChooser portal — Flea, Nautilus, or whatever is configured as
# org.freedesktop.impl.portal.FileChooser. Do not call zenity/kdialog by name.
exec omarchy file select \
  --title "Attach to post" \
  --multiple \
  --extensions "png jpg jpeg webp gif bmp heic mp4 mov webm mkv m4v"
