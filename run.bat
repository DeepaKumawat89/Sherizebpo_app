@echo off
REM ===================================================================
REM   Human BPO - Flutter Project Runner
REM ===================================================================

title Human BPO - Flutter Runner
cd /d "%~dp0"

echo.
echo ==================================================
echo    Human BPO - Flutter Project Runner
echo ==================================================
echo.

REM --- Check Flutter installation ---
where flutter >nul 2>&1
if errorlevel 1 goto noflutter

REM --- Parse MODE ---
set "MODE=%~1"
if "%MODE%"=="" set "MODE=chrome"

if /i "%MODE%"=="clean" goto doclean
if /i "%MODE%"=="build" goto dobuild
if /i "%MODE%"=="chrome" goto dochrome
if /i "%MODE%"=="android" goto doandroid

echo Unknown command: %MODE%
echo Available: chrome, android, build, clean
pause
exit /b 1

:noflutter
echo ERROR: Flutter is not installed.
pause
exit /b 1

:doclean
echo Cleaning build cache
flutter clean
echo Getting dependencies
flutter pub get
pause
exit /b 0

:dobuild
echo Building Android APK
flutter pub get
flutter build apk --release
if errorlevel 1 echo Build failed
if not errorlevel 1 echo Build successful
pause
exit /b 0

:dochrome
echo Launching on Chrome
flutter run -d chrome
exit /b 0

:doandroid
echo Launching on your phone (c716503b2ef6)
flutter run -d c716503b2ef6
exit /b 0
