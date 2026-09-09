@echo off
rem ============================================================
rem  set-apikey.bat - save your TMDb API key
rem
rem  Double-click this file, paste the API key, press Enter.
rem  It checks the key against TMDb and writes config.local.json.
rem
rem  ASCII-only on purpose: .bat files are read with the console
rem  code page, so Japanese text here can break. All Japanese
rem  messages live in set-apikey.ps1.
rem ============================================================

cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\set-apikey.ps1"
