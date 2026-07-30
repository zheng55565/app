@echo off
REM ============================================================
REM  new-api-app one-click dev shutdown
REM  Stops emulator, API server and embedded PostgreSQL windows
REM  started by start-dev.bat.
REM  Note: DB is force-killed. PostgreSQL is crash-safe; if it ever
REM  refuses to start afterwards, delete server\.pgdata\postmaster.pid
REM ============================================================

set "ADB=D:\dev\android-sdk\platform-tools\adb.exe"

echo Stopping emulator gracefully ...
"%ADB%" emu kill >nul 2>&1
ping -n 4 127.0.0.1 >nul

echo Closing dev windows ...
taskkill /fi "WINDOWTITLE eq emulator*"   /t /f >nul 2>&1
taskkill /fi "WINDOWTITLE eq api-server*" /t /f >nul 2>&1
taskkill /fi "WINDOWTITLE eq dev-db*"     /t /f >nul 2>&1

echo Killing any leftover listeners on ports 3001 / 5433 ...
for /f "tokens=5" %%p in ('netstat -ano ^| findstr ":3001 " ^| findstr "LISTENING"') do taskkill /f /pid %%p >nul 2>&1
for /f "tokens=5" %%p in ('netstat -ano ^| findstr ":5433 " ^| findstr "LISTENING"') do taskkill /f /pid %%p >nul 2>&1

echo Done.
