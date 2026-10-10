@echo off
cd /d "%~dp0.."
if errorlevel 1 (
  echo start_claude.bat: cannot cd to the workspace root 1>&2
  exit /b 1
)
claude --dangerously-skip-permissions
