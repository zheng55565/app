@echo off
setlocal enabledelayedexpansion
REM ============================================================
REM  new-api-app one-click dev startup
REM  Starts: embedded PostgreSQL (5433) + API server (3001)
REM          + Android emulator (AVD dev_phone) + installs the app
REM  Usage:
REM    start-dev.bat            start everything, install existing debug APK
REM    start-dev.bat build      rebuild APK first: flutter build apk --debug
REM    start-dev.bat nodeploy   start services + emulator only, skip APK
REM  Idempotent: safe to re-run, already-running components are skipped.
REM  Details and troubleshooting: STARTUP.md
REM ============================================================

set "ROOT=D:\new-api-app"
set "SERVER_DIR=%ROOT%\server"
set "APP_DIR=%ROOT%\app"
set "ADB=D:\dev\android-sdk\platform-tools\adb.exe"
set "EMU=D:\dev\android-sdk\emulator\emulator.exe"
set "FLUTTER=D:\dev\flutter\bin\flutter.bat"
set "AVD=dev_phone"
set "APK=%APP_DIR%\build\app\outputs\flutter-apk\app-debug.apk"
set "PKG=com.gongyiapp.gongyi_app"
set "EMU_PROXY=10.0.2.2:7897"

echo.
echo [1/6] Embedded PostgreSQL - port 5433
netstat -ano | findstr ":5433 " | findstr "LISTENING" >nul
if errorlevel 1 (
  start "dev-db" cmd /k "cd /d %SERVER_DIR% & node scripts\dev-db.js"
  echo        launching in window "dev-db" ...
) else (
  echo        already running - skipped
)
set /a TRIES=0
:wait_db
netstat -ano | findstr ":5433 " | findstr "LISTENING" >nul
if errorlevel 1 (
  set /a TRIES+=1
  if !TRIES! geq 20 (
    echo        ERROR: database not listening after 60s - check window "dev-db"
    exit /b 1
  )
  ping -n 4 127.0.0.1 >nul
  goto wait_db
)
echo        database is up

echo.
echo [2/6] API server - port 3001 - NODE_USE_ENV_PROXY=1
netstat -ano | findstr ":3001 " | findstr "LISTENING" >nul
if errorlevel 1 (
  start "api-server" cmd /k "cd /d %SERVER_DIR% & set NODE_USE_ENV_PROXY=1& set NO_PROXY=localhost,127.0.0.1& npm run dev"
  echo        launching in window "api-server" ...
) else (
  echo        already running - skipped
)
set /a TRIES=0
:wait_api
curl --noproxy * -s -m 2 http://127.0.0.1:3001/healthz 2>nul | findstr "ok" >nul
if errorlevel 1 (
  set /a TRIES+=1
  if !TRIES! geq 20 (
    echo        ERROR: /healthz not responding after 60s - check window "api-server"
    exit /b 1
  )
  ping -n 4 127.0.0.1 >nul
  goto wait_api
)
echo        API is up - http://127.0.0.1:3001/healthz OK

echo.
echo [3/6] Android emulator - AVD %AVD%
"%ADB%" devices | findstr "emulator-" >nul
if errorlevel 1 (
  start "emulator" cmd /k "set HTTP_PROXY=& set HTTPS_PROXY=& set ALL_PROXY=& set NO_PROXY=& %EMU% -avd %AVD% -gpu swiftshader_indirect"
  echo        launching in window "emulator" - proxy env cleared, software GPU
) else (
  echo        already running - skipped
)

echo.
echo [4/6] Waiting for emulator boot - can take 1-3 min
set /a TRIES=0
:wait_boot
"%ADB%" shell getprop sys.boot_completed 2>nul | findstr "1" >nul
if errorlevel 1 (
  set /a TRIES+=1
  if !TRIES! geq 60 (
    echo        ERROR: emulator not booted after 5 min - check window "emulator"
    exit /b 1
  )
  ping -n 6 127.0.0.1 >nul
  goto wait_boot
)
echo        emulator booted

echo.
echo [5/6] Emulator network config - REQUIRED after every emulator restart
"%ADB%" shell settings put global http_proxy %EMU_PROXY%
"%ADB%" reverse tcp:3001 tcp:3001
echo        global http_proxy = %EMU_PROXY%  - in-emulator browser reaches linux.do
echo        adb reverse tcp:3001             - OAuth callback localhost:3001 works

if /i "%~1"=="nodeploy" (
  echo.
  echo [6/6] APK install skipped - nodeploy
  goto summary
)
if /i "%~1"=="build" (
  echo.
  echo [6/6] Building debug APK first ...
  pushd "%APP_DIR%"
  call "%FLUTTER%" build apk --debug
  if errorlevel 1 (
    popd
    echo        ERROR: flutter build failed
    exit /b 1
  )
  popd
)
if not exist "%APK%" (
  echo        ERROR: APK not found - run: start-dev.bat build
  exit /b 1
)
echo.
echo [6/6] Installing and launching app
"%ADB%" install -r "%APK%" >nul
if errorlevel 1 (
  echo        ERROR: adb install failed
  exit /b 1
)
"%ADB%" shell am start -n %PKG%/.MainActivity >nul
echo        app launched - %PKG%

:summary
echo.
echo ============================================================
echo   ALL UP
echo   DB        postgres://postgres:postgres@localhost:5433/linuxdo_ad_reward
echo   API       http://localhost:3001   health: /healthz
echo   Emulator  %AVD%   app reaches API via http://10.0.2.2:3001
echo   NOTE  if the emulator is restarted, re-run this script or redo step 5
echo ============================================================
endlocal
