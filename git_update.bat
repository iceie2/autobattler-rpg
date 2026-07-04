@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"

echo ================================
echo   Git Update - autobattler-rpg
echo ================================
echo.

git rev-parse --is-inside-work-tree >nul 2>&1
if errorlevel 1 (
    echo This folder is not a git repository. Aborting.
    pause
    exit /b 1
)

echo Current branch:
git branch --show-current
echo.

echo Changed files:
git status --short
echo.

git diff --quiet --cached
set STAGED_EMPTY=%errorlevel%
git diff --quiet
set UNSTAGED_EMPTY=%errorlevel%
git ls-files --others --exclude-standard > "%TEMP%\gu_untracked.txt"
for %%A in ("%TEMP%\gu_untracked.txt") do set UNTRACKED_SIZE=%%~zA

if "%STAGED_EMPTY%%UNSTAGED_EMPTY%"=="10" if "%UNTRACKED_SIZE%"=="0" (
    echo Nothing to commit - working tree is clean.
    del "%TEMP%\gu_untracked.txt" >nul 2>&1
    pause
    exit /b 0
)
del "%TEMP%\gu_untracked.txt" >nul 2>&1

set /p MSG=Commit message (blank = "Manual update"):
if "%MSG%"=="" set MSG=Manual update

git add -A
git commit -m "%MSG%"
if errorlevel 1 (
    echo.
    echo Commit failed - see errors above.
    pause
    exit /b 1
)

echo.
echo Committed. Recent history:
git log --oneline -5
echo.

set /p PUSH=Push to origin now? [y/N]:
if /i "%PUSH%"=="y" (
    for /f "delims=" %%b in ('git branch --show-current') do set BR=%%b
    echo Pushing !BR! to origin...
    git push origin !BR!
) else (
    echo Skipped push. Your commit is saved locally.
)

echo.
pause
