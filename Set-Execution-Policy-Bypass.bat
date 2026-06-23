@echo off
setlocal enabledelayedexpansion

echo Setting PowerShell Execution Policy...

:: Run PowerShell to change the policy. 
:: -Force suppresses confirmation prompts.
powershell.exe -NoProfile -Command "Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force"

:: Check the exit status of the previous command
if %ERRORLEVEL% EQU 0 (
    echo SUCCESS: The Execution Policy was updated successfully.
) else (
    echo FAIL: Failed to change the Execution Policy. 
    echo Ensure you are running this batch file as an Administrator.
)

pause
endlocal