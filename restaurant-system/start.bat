@echo off
chcp 65001 >nul
title Restaurant Orders System
cd /d "%~dp0"

where node >nul 2>nul
if errorlevel 1 (
  echo.
  echo  [!] Node.js is not installed.
  echo      Download it from https://nodejs.org  (version 22 LTS or newer^)
  echo.
  start https://nodejs.org
  pause
  exit /b 1
)

if not exist node_modules (
  echo Installing packages, please wait...
  call npm install --omit=dev
)

start "" http://localhost:3000
call npm start
pause
