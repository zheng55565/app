@echo off
REM ============================================================
REM  Build HuanYouYu (Tuanjie) as standard WebGL and deploy to
REM  server\public\games\  — run AFTER Tuanjie editor + WebGL
REM  module are installed (see STARTUP.md / unity-webgl-bridge.md)
REM  Usage: build-games.bat [TuanjieEditorDir]
REM ============================================================
setlocal

set "EDITOR_DIR=%~1"
if "%EDITOR_DIR%"=="" set "EDITOR_DIR=D:\dev\tuanjie"
set "EDITOR=%EDITOR_DIR%\Editor\Tuanjie.exe"
if not exist "%EDITOR%" (
  echo [error] Tuanjie.exe not found at %EDITOR%
  echo         pass the editor install dir as the first argument
  exit /b 1
)

set "PROJECT=D:\new-api-app\huanyouyu\HuanYouYu-main"
set "OUTPUT=D:\new-api-app\huanyouyu\Builds\WebGL"
set "DEPLOY=D:\new-api-app\server\public\games"
set "LOG=D:\new-api-app\huanyouyu\build-webgl.log"

echo [1/3] Building WebGL (10-30 min on first run) ...
"%EDITOR%" -batchmode -quit -projectPath "%PROJECT%" -buildTarget WebGL ^
  -executeMethod CIBuildWebGL.BuildWebGL -customBuildPath "%OUTPUT%" -logFile "%LOG%"
if errorlevel 1 (
  echo [error] build failed - tail of log:
  powershell -Command "Get-Content -Tail 40 '%LOG%'"
  exit /b 1
)

echo [2/3] Deploying to %DEPLOY% ...
if exist "%DEPLOY%" rd /s /q "%DEPLOY%"
xcopy /e /i /q "%OUTPUT%" "%DEPLOY%" >nul

echo [3/3] Done. Open the app's mini-game entry to verify.
echo        log: %LOG%
endlocal
