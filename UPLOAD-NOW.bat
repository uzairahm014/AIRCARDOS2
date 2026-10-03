@echo off
REM ============================================================
REM   AIRCARD-iOS  -  UPLOAD TO GITHUB
REM   Everything is already prepared. Just double-click.
REM ============================================================
setlocal
cd /d "%~dp0"

echo.
echo ============================================================
echo   Uploading AirCard-iOS to github.com/uzairahm014/AIRCARDOS2
echo ============================================================
echo.
echo   252 files, about 127 MB. This takes a few minutes.
echo   Keep this window open.
echo.

where git >nul 2>&1
if errorlevel 1 (
    echo   ERROR: git is not installed.
    echo   Install from https://git-scm.com/download/win then run this again.
    pause
    exit /b 1
)

git push -u origin main

echo.
echo ============================================================
if errorlevel 1 (
    echo   PUSH DID NOT COMPLETE.
    echo.
    echo   If it asked for a password, that is why.
    echo   GitHub wants a Personal Access Token instead:
    echo.
    echo     1. Go to  https://github.com/settings/tokens
    echo     2. "Generate new token (classic)"
    echo     3. Tick the  repo  box
    echo     4. Generate, then COPY the token it shows
    echo     5. Run this file again and paste the token
    echo        when it asks for a password
    echo.
    echo   Your username is:  uzairahm014
    echo.
) else (
    echo   UPLOADED.
    echo.
    echo   NEXT:
    echo     1. Go to https://codemagic.io
    echo     2. Sign in with GitHub
    echo     3. "Add new application"  -  pick AIRCARDOS2
    echo     4. Press  "Start new build"
    echo     5. Wait about 10-15 minutes
    echo     6. Open the build  -  "Artifacts" tab  -  download the .ipa
    echo.
    echo   If the build FAILS, open it, click "Raw log",
    echo   find the first line starting with "error:", and send it to me.
    echo.
)
echo ============================================================
echo.
pause