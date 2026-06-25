@echo off
REM Build Homework Tracker Windows Installer
REM This script builds the Flutter app and creates a Windows installer using Inno Setup

echo ========================================
echo Homework Tracker - Windows Installer Builder
echo ========================================
echo.

REM Check if Flutter is installed
where flutter >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Flutter is not installed or not in PATH
    echo Please install Flutter from: https://flutter.dev/docs/get-started/install
    pause
    exit /b 1
)

REM Check if Inno Setup is installed
where iscc >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Inno Setup is not installed or not in PATH
    echo Please install Inno Setup from: https://jrsoftware.org/isdl.php
    echo.
    echo After installing Inno Setup, add it to your PATH or run this script from:
    echo C:\Program Files (x86)\Inno Setup 6
    pause
    exit /b 1
)

echo Step 1: Building Flutter Windows release...
echo.
cd frontend
call flutter build windows --release
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Flutter build failed
    pause
    exit /b 1
)
cd ..

echo.
echo Step 2: Creating Windows installer...
echo.
cd installer
iscc installer.iss
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Inno Setup compilation failed
    pause
    exit /b 1
)
cd ..

echo.
echo ========================================
echo SUCCESS!
echo ========================================
echo.
echo Installer created at: installer\installer_output\HomeworkTracker_Setup_v1.0.0.exe
echo.
echo You can now distribute this installer to users.
echo.
pause
