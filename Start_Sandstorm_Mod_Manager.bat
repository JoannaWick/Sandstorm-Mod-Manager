@echo off
:: Launch the script and wait for it to finish

Powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Sandstorm_Mod_Manager.ps1" -batchLaunch "1"

:: Finished