@echo off
REM ============================================================
REM  AirCard-iOS  -  send to GitHub  (just double-click this file)
REM  No typing needed until the last step.
REM ============================================================
setlocal

cd /d "%~dp0"

echo.
echo ============================================================
echo   STEP 1 of 3 :  preparing files
echo ============================================================
echo.

REM Find the real repo root: it must contain codemagic.yaml
if exist "codemagic.yaml" goto ROOT_OK
if exist "AirCard-iOS\codemagic.yaml" (
    echo   Found the inner folder, using that one.
    cd /d "AirCard-iOS"
    goto ROOT_OK
)
echo   ERROR: could not find codemagic.yaml in this folder.
echo   Expected to find it in:
echo     %~dp0
echo.
pause
exit /b 1

:ROOT_OK
echo   Folder: %CD%
echo.

where git >nul 2>&1
if errorlevel 1 (
    echo   ERROR: git is not on your PATH.
    echo   Install it from: https://git-scm.com/download/win
    echo.
    pause
    exit /b 1
)

if not exist ".git" (
    echo   Creating the repository...
    git init -q
    git branch -M main
)

git add -A >nul 2>&1
git diff --cached --quiet
if errorlevel 1 (
    echo   Saving your files...
    git -c user.name="uzair" -c user.email="uzair.ahm014@gmail.com" commit -q -m "AirCard-iOS source"
)

echo   Files ready: 
git ls-files | find /c /v "" 

echo.
echo ============================================================
echo   STEP 2 of 3 :  your GitHub repo
echo ============================================================
echo.
echo   Opening github.com/new in your browser.
echo.
echo   On the page:
echo     1. Repository name:  AirCard-iOS
echo     2. Tick  "Add a README file"
echo     3. Click the green  "Create repository"
echo.
echo   Then come back here and press any key.
echo.

start https://github.com/new
pause

echo.
echo ============================================================
echo   STEP 3 of 3 :  uploading
echo ============================================================
echo.
set /p REPOURL=Paste your repo address here (like https://github.com/uzair/AirCard-iOS.git) and press Enter: 

if "%REPOURL%"=="" (
    echo   No address given - nothing uploaded. That is fine, run this file again.
    pause
    exit /b 1
)

echo.
echo   Connecting to your repo...
git remote remove origin >nul 2>&1
git remote add origin %REPOURL%
echo   Uploading. This can take a few minutes for 127 MB...
echo.

git push -u origin main

echo.
echo ============================================================
if errorlevel 1 (
    echo   Upload did not finish.
    echo.
    echo   Common reasons:
    echo     - Wrong address pasted
    echo     - GitHub asked for a Personal Access Token, not your password
    echo       Create one at: https://github.com/settings/tokens
    echo       then tick  repo  and run this file again
    echo.
) else (
    echo   UPLOADED.
    echo.
    echo   Next: go to https://codemagic.io
    echo     1. Sign in with GitHub
    echo     2. Add new application  -  pick AirCard-iOS
    echo     3. Press  "Start new build"
    echo     4. When it finishes:  Artifacts tab  -  download the .ipa
    echo.
    echo   Then sideload that .ipa the way you already know how.
    echo.
)
echo ============================================================
echo.
pause