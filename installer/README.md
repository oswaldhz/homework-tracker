# Homework Tracker - Windows Installer

This directory contains the Inno Setup script to create a professional Windows installer for the Homework Tracker application.

## Prerequisites

Before creating the installer, you need to install:

1. **Flutter** (if not already installed)
   - Download from: https://flutter.dev/docs/get-started/install
   - Make sure Flutter is in your system PATH

2. **Inno Setup 6**
   - Download from: https://jrsoftware.org/isdl.php
   - Install Inno Setup
   - Add to PATH: `C:\Program Files (x86)\Inno Setup 6`
   - Or run the build script from the Inno Setup directory

## Quick Build (Automated)

If you have both Flutter and Inno Setup installed and in your PATH, simply run:

```batch
build_installer.bat
```

This will:
1. Build the Flutter Windows release
2. Create the installer using Inno Setup
3. Output the installer to `installer\installer_output\`

## Manual Build

### Step 1: Build Flutter App

```batch
cd frontend
flutter build windows --release
```

This creates the executable at: `frontend\build\windows\x64\runner\Release\homework_tracker.exe`

### Step 2: Create Installer

1. Open `installer\installer.iss` in Inno Setup Compiler
2. Click **Build** → **Compile** (or press F9)
3. The installer will be created at: `installer\installer_output\HomeworkTracker_Setup_v1.0.0.exe`

## Installer Features

The installer includes:
- ✅ Professional installation wizard
- ✅ Desktop shortcut (optional)
- ✅ Start menu entry
- ✅ Uninstaller
- ✅ Multi-language support (English & Spanish)
- ✅ 64-bit Windows support
- ✅ No admin privileges required
- ✅ LZMA compression for small installer size

> **Note:** This installer packages the Flutter desktop app only. The Python
> backend in `backend/` is not required for the current version.

## Customizing the Installer

Edit `installer.iss` to customize:

- **App Name**: Change `#define MyAppName`
- **Version**: Change `#define MyAppVersion`
- **Publisher**: Change `#define MyAppPublisher`
- **Icon**: Change `SetupIconFile` path
- **Output Directory**: Change `OutputDir`

## Distribution

After building the installer, you can:
- Distribute `HomeworkTracker_Setup_v1.0.0.exe` to users
- Upload to GitHub Releases
- Share via cloud storage

## Troubleshooting

### "Flutter is not installed or not in PATH"
- Install Flutter from https://flutter.dev
- Add `C:\flutter\bin` to your system PATH
- Restart your command prompt

### "Inno Setup is not installed or not in PATH"
- Install Inno Setup from https://jrsoftware.org/isdl.php
- Add `C:\Program Files (x86)\Inno Setup 6` to your system PATH
- Or run the script from the Inno Setup directory

### "Flutter build failed"
- Run `flutter doctor` to check your Flutter installation
- Make sure all dependencies are installed
- Check the error message for specific issues

### "Inno Setup compilation failed"
- Check the Inno Setup compiler output for errors
- Make sure all paths in `installer.iss` are correct
- Verify the Flutter build output exists

## File Structure

```
installer/
├── installer.iss          # Inno Setup script
├── installer_output/      # Generated installer (after build)
│   └── HomeworkTracker_Setup_v1.0.0.exe
└── README.md              # This file
```

## Support

For issues or questions:
- GitHub Issues: https://github.com/yourusername/homework-tracker/issues
- Documentation: See main README.md
