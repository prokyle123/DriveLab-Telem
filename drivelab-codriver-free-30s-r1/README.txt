DRIVELAB 2.2.2 — AUTO CO-DRIVER FREE PREVIEW
================================================

PURPOSE
-------
Changes only the Free Edition Auto Co-Driver preview from 60 seconds to 30 seconds.
Full Edition remains unlimited.

WHAT THE INSTALLER DOES
-----------------------
- Finds the current DriveLab 2.2.1 Android project automatically.
- Confirms the package is com.auroramediagroup.drivelab.
- Locates the actual Auto Co-Driver and pace-note source.
- Changes the Free preview timing and matching on-screen wording.
- Bumps the app to version 2.2.2 and increments versionCode.
- Updates the in-app What's New section, CHANGELOG.md, and update release notes.
- Creates a timestamped source backup before editing.
- Runs unit tests, release lint, and the release build.
- Confirms the permanent signing configuration is present.
- Verifies the APK signature when Android build tools are available.
- Installs the signed test APK when exactly one Android device is connected.
- Creates a Free/Full test checklist.
- Automatically restores the source backup if patching or building fails.

IMPORTANT
---------
This package DOES NOT publish anything. It does not update customers, the Pi server,
GitHub Releases, or the marketing website. Publishing happens only after the test build
passes and both the Free and Full behavior have been checked.

RUN
---
1. Extract the downloaded GitHub archive.
2. Open the drivelab-codriver-free-30s-r1 folder.
3. Double-click RUN-DRIVELAB-CODRIVER-30S.bat.
4. Keep the phone connected by USB if you want the signed test APK installed automatically.
5. Follow DRIVELAB-2.2.2-TEST-CHECKLIST.txt in the main DriveLab project.

EXPECTED APK
------------
C:\Users\<you>\OneDrive\Desktop\DriveLabTelem-v1.8.0-online-check-purchase\release-output\DriveLab-Telem-v2.2.2.apk

Do not run the existing publisher until the Free and Full tests pass.
