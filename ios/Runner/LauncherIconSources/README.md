# Alternate launcher icons

The default P mark uses the app's blue palette. Eight earlier color variants
remain for compatibility. The `*.svg` files are vector sources; their opaque
RGB raster outputs live in `../Assets.xcassets/AppIcon*.appiconset/`.

Regenerate with the existing browser QA tooling (no runtime dependency):

```sh
PLAYWRIGHT_MODULE=/path/to/playwright node ios/Runner/LauncherIconSources/generate.cjs --default-only
python3 assets/launcher/generate_floor_icons.py
python3 ios/Runner/LauncherIconSources/check.py
```

The default generator also updates the Android default raster and web icons.
Omit `--default-only` only when intentionally regenerating the compatibility
variants. The floor generator owns F1–F5/B1–B6 assets for both mobile platforms.

Xcode's `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` is configured in all three
Runner configurations. Xcode generates `CFBundleIcons` and iPad entries; those
keys are deliberately not maintained manually in Info.plist.

The app applies the icon for the server-confirmed parking floor when active.
Logging out, having no parking record or using an unsupported floor restores
the default icon. No manual color picker is shown. iOS may display its system
icon-change notice; changes made by family members are applied on the next
app activation. See `docs/DECISIONS.md` for the current behavior contract.

References checked 2026-11-02:

- [Apple alternate icon configuration](https://developer.apple.com/documentation/xcode/configuring-your-app-to-use-alternate-app-icons)
- [Apple setAlternateIconName](https://developer.apple.com/documentation/uikit/uiapplication/setalternateiconname(_:completionhandler:))

Local validation covers the bridge and complete RGB asset catalog.
Xcode compilation and actual SpringBoard icon changes must also be validated on
macOS/iOS; local Linux tests do not prove those system behaviors.
