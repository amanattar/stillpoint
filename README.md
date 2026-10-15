# Stillpoint

A free, open-source task manager for macOS (iPhone and iPad later), with optional sync through your own Supabase project.

Status: early development. Licensed under GPL-3.0.

## Development

Requires Xcode 27 (macOS 26 SDK or later) and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

    xcodegen generate              # creates Stillpoint.xcodeproj (not committed)
    open Stillpoint.xcodeproj

Tests:

    (cd Packages/StillpointModel && swift test)
    (cd Packages/StillpointUI && swift test)
    (cd Packages/StillpointFeatures && swift test)
    xcodebuild -project Stillpoint.xcodeproj -scheme Stillpoint -destination 'platform=macOS' -derivedDataPath .build/xcode test

Snapshot tests record reference images on their first run (that run fails) and compare against them afterwards.

Try the app with sample data, kept in a separate folder from your real database:

    open .build/xcode/Build/Products/Debug/Stillpoint.app --args -dataFolderName Demo -seedDemoData YES
