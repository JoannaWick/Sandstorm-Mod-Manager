@echo off
setlocal enabledelayedexpansion
title Move Sandstorm mod.io Directory

echo.
echo ==============================================
echo         Move mod.io Directory Wizard        
echo ==============================================
echo.

:: Make sure globalsettings.json exists

:: Define path to mod.io globalsettings.json

set "JSON_FILE=%LOCALAPPDATA%\mod.io\globalsettings.json"
set "JSON_BACKUP_FILE=%LOCALAPPDATA%\mod.io\globalsettings.backup"

:: Check if the file exists
if not exist "%JSON_FILE%" (
    echo Error: File not found at "%JSON_FILE%"
    pause
    exit /b
)

:: Make sure json directory path variable is in json format
:: Create a temporary file to hold the modified content

SET "TEMP_FILE=%TEMP%\settings_temp.json"

:: Read the file line by line and replace \ with /

(for /f "usebackq tokens=* delims=" %%a in ("%JSON_FILE%") do (
    SET "line=%%a"
    SET "line=!line:\=/!"
    echo(!line!
)) > "%TEMP_FILE%"

:: Replace the original file with the modified temporary file

move /y "%TEMP_FILE%" "%JSON_FILE%" >nul

:: Extract RootLocalStoragePath and set it to a Batch variable

for /f "delims=" %%i in ('powershell -NoProfile -Command "(Get-Content '%JSON_FILE%' | ConvertFrom-Json).RootLocalStoragePath"') do (
    set "RootLocalStoragePath=%%i"
)

echo.

:: Display the result

if defined RootLocalStoragePath (
    echo The RootLocalStoragePath is: %RootLocalStoragePath%
    set "RootLocalStoragePath=%RootLocalStoragePath:\\=\%"
) else (
    echo Error: Could not find RootLocalStoragePath in the JSON file.
    pause
    exit /b
)

echo.

:: Change / in directory path to Windows \

set "source_dir=!RootLocalStoragePath:/=\!"
echo The source_dir is: %source_dir%
echo.

:: Select Destination Folder using Windows GUI selector

:GetDestination

echo Selecting destination folder...
set "dest_cmd=(New-Object -ComObject Shell.Application).BrowseForFolder(0, 'Select the DESTINATION folder', 0, 0).Self.Path"
for /f "usebackq delims=" %%I in (`powershell -Command "%dest_cmd%"`) do set "dest_dir=%%I"

if not defined dest_dir (
    echo.
    echo No destination folder selected. Exiting.
    pause
    exit /b
)

set "lastchar=%dest_dir:~-1%"

if not "%lastchar%"=="\" (
    set "dest_dir=%dest_dir%\"
)

echo.
echo Destination: %dest_dir%
echo.

:: Test if Base Directory is Writable

set "TEMP_TEST_FILE=%dest_dir%.write_test.tmp"

copy /y NUL "%TEMP_TEST_FILE%" >nul 2>&1

if errorlevel 1 (
echo.
    echo [FAILURE] The directory is NOT writable: "%dest_dir%"
    echo.
    goto GetDestination
) else (
    echo [SUCCESS] The directory IS writable "%TEMP_TEST_FILE%" .

    del /f /q "%TEMP_TEST_FILE%" 
)

:: Clean up destination Directory path

set "dest_dir=%dest_dir%\mod.io\"
set "dest_dir=%dest_dir:\\=\%"

:: Create Target Directory

echo.
echo Creating target directory: "%dest_dir%"

if not exist "%dest_dir%" mkdir "%dest_dir%" >nul 2>&1

if errorlevel 1 (
    echo.
    echo [ERROR] Failed to create target directory "%dest_dir%".
    echo.
    goto GetDestination
) else (
    echo.
    echo [SUCCESS] The Target Directory IS created "%dest_dir%" .
    rmdir /s /q "%dest_dir%" >nul 2>&1
)

:: Show Disclaimer then Confirm Moving of Files to new location

echo.
echo ==============================================
echo        WARNING! Please Read WARNING!  
echo ==============================================
echo.

echo Source:      %source_dir%
echo Destination: %dest_dir%
echo.
echo This script will also move mod files for every game that uses 'RootLocalStoragePath'
echo in the globalsettings.json file for mod.io. The script will update the metadata
echo only for Sandstorm.  If any other games use metadata that points to the old location
echo it will not be updated.  If Sandstorm is the only game you have installed that uses
echo Mod.io then go ahead and use this script.  Any game that is installed after the mods
echo have been moved will use the new location for their mods.
echo.
echo DO NOT ABORT THIS SCRIPT AFTER ENTERING Y!!!
echo Stopping before completion can corrupt your mod files requiring you to delete your
echo mod.io directories and re-downloading all mods.
echo.

set /p "confirm=Are you sure you want to move all files? (Y/N): "

if /i "%confirm%"=="Y" (
    echo.
    echo Moving files...  robocopy "%source_dir%" "%dest_dir%" /E /MOVE
    robocopy %source_dir% %dest_dir% /E /MOVE
    echo.
) else (
    echo Operation cancelled.
    pause
    exit /b
)

:: Convert Destination Path to format used by mod.io
:: Note: mod.io prefers forward slashes in its paths

set "NEW_PATH=!dest_dir:\=/!"

:: Create a temporary file to rewrite the JSON

set "TEMP_FILE=%TEMP%\globalsettings_temp.json"
echo { > "%TEMP_FILE%"

echo "RootLocalStoragePath": "%NEW_PATH%" >> "%TEMP_FILE%"
echo } >> "%TEMP_FILE%"

:: Overwrite the original file with the new configuration

move /y "%TEMP_FILE%" "%JSON_FILE%" >nul

xcopy "%JSON_FILE%" "%JSON_BACKUP_FILE%" /Y

echo [SUCCESS] Mod storage path updated to %NEW_PATH%

:: Set variables for changing all path locations in the
:: 254\metadata\state.json file to point to the new location
:: If this file is not updated after moving it will still point
:: to the previous locations

set "filepath=%dest_dir%254\metadata\state.json"
set "search=%source_dir%254\mods\"
set "replace=%dest_dir%254\mods\"

:: Convert single \ to Double \\ used by the mod.io state.json file

set "search=%search:\=\\%"
set "replace=%replace:\=\\%"

echo.
echo Replacing %search%
echo With %replace%
echo Inside %filepath%
echo.

:: Perform update on state.json using Powershell

powershell -Command " (Get-Content -Path '%filepath%') -replace [regex]::Escape('%search%'), '%replace%' | Set-Content -Path '%filepath%' "

echo Metadata update inside %filepath% complete!
echo.
echo ==============================================
echo   Moving/Updating mod.io files is complete.        
echo ==============================================
echo.

pause