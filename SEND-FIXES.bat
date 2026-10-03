@echo off
REM ============================================================
REM   AIRCARD-iOS  -  SEND MY FIXES TO GITHUB
REM   After I fix a bug, double-click this to push it.
REM   Then go back to Codemagic and press "Start new build".
REM ============================================================
setlocal
cd /d "%~dp0"

echo.
echo   Sending fixes to GitHub...
echo.

git add -A
git diff --cached --quiet
if errorlevel 1 (
    git -c user.name="uzair" -c user.email="uzair.ahm014@gmail.com" commit -q -m "fixes"
    echo   Changes saved.
) else (
    echo   No changes to send.
)

git push -q origin main

echo.
if errorlevel 1 (
    echo   Could not push. See the message above.
) else (
    echo   SENT.
    echo.
    echo   NOW: go back to Codemagic and press "Start new build".
    echo.
)
pause