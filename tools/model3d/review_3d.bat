@echo off
REM ---------------------------------------------------------------------------
REM Open a 3D character in Blender, ready to review. See blender_review.py.
REM
REM   review_3d.bat                 -> bouncer, idle
REM   review_3d.bat bouncer         -> bouncer, idle
REM   review_3d.bat bouncer attack  -> bouncer, starting on the attack clip
REM
REM Resolves assets/3d pipeline/hero/<name>/<name>.glb, so the character's name
REM is the ONLY thing you type. Set BLENDER_EXE to override the Blender path.
REM ---------------------------------------------------------------------------
setlocal

if not defined BLENDER_EXE set "BLENDER_EXE=C:\Program Files\Blender Foundation\Blender 5.2\blender.exe"

set "NAME=%~1"
if "%NAME%"=="" set "NAME=bouncer"
set "CLIP=%~2"

set "ROOT=%~dp0..\.."
set "MODEL=%ROOT%\assets\3d pipeline\hero\%NAME%\%NAME%.glb"

if not exist "%MODEL%" (
    echo.
    echo   No model at: %MODEL%
    echo.
    echo   Characters available:
    for /d %%D in ("%ROOT%\assets\3d pipeline\hero\*") do echo       %%~nxD
    echo.
    echo   Merge one first ^(see 3D_PIPELINE.md stage 3^):
    echo       py -3 tools\model3d\glb_merge_anims.py "assets\3d pipeline\hero\NAME\raw" "assets\3d pipeline\hero\NAME\NAME.glb" --tex 1024 --harden-bones RightHand,LeftHand
    echo.
    exit /b 1
)

if not exist "%BLENDER_EXE%" (
    echo   Blender not found at: %BLENDER_EXE%
    echo   Set BLENDER_EXE to your install and re-run.
    exit /b 1
)

echo   Opening %NAME% ...
REM Blender is handed a .blend purely so it does not show its splash screen
REM (whose "New File > General" button would reset the file and discard the
REM import). It opens a THROWAWAY COPY, never review_base.blend itself: the
REM reviewer's Ctrl+S has to land somewhere harmless. Saving over the real
REM scaffold makes every later launch import on top of the saved scene and
REM duplicate every clip as idle/idle.001.
set "SESSION=%TEMP%\review_%NAME%.blend"
copy /Y "%~dp0review_base.blend" "%SESSION%" >nul

"%BLENDER_EXE%" "%SESSION%" --python "%~dp0blender_review.py" -- "%MODEL%" %CLIP%

endlocal
