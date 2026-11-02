# Alternate launcher icons

Eight local iOS/iPadOS icon options use the app's P mark and shared vehicle palette.
The `*.svg` files are vector sources; their opaque RGB raster outputs live in
`../Assets.xcassets/AppIcon*.appiconset/`. The primary `AppIcon` remains unchanged.

Regenerate with the existing browser QA tooling (no runtime dependency):

```sh
PLAYWRIGHT_MODULE=/path/to/playwright node ios/Runner/LauncherIconSources/generate.cjs
python3 ios/Runner/LauncherIconSources/check.py
```

Xcode's `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` is configured in all three
Runner configurations. Xcode generates `CFBundleIcons` and iPad entries; those
keys are deliberately not maintained manually in Info.plist.

The app calls `UIApplication.setAlternateIconName` only after the user chooses
Apply. Passing nil restores the primary icon. Sharing a vehicle color, logging
out, or switching vehicles does not automatically change this device preference.

References checked 2026-11-02:

- [Apple alternate icon configuration](https://developer.apple.com/documentation/xcode/configuring-your-app-to-use-alternate-app-icons)
- [Apple setAlternateIconName](https://developer.apple.com/documentation/uikit/uiapplication/setalternateiconname(_:completionhandler:))

Local validation covers the bridge, opt-in UI and complete RGB asset catalog.
Xcode compilation and actual SpringBoard icon changes must also be validated on
macOS/iOS; local Linux tests do not prove those system behaviors.
