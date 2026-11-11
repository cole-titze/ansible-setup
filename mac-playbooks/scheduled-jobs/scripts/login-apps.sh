#!/bin/bash
# Runs once at login (launchd RunAtLoad). Starts Ollama, which the nhl-odds assistant calls over the
# network. Claude Code Remote Control runs on the backup Pi now (claude-rc.service), not here: no
# automatic agents run on the Mac.
set -u

open -a Ollama
