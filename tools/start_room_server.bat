@echo off
title Ephemeral Jeopardy Room Server (Walls + Floor Sync)
cd /d "%~dp0\.."
python tools\serve_room.py --port 8080
pause
