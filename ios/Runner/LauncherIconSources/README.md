# Alternate launcher icons

The default icon is the 차자리 pin (design direction A, 2026-11-10): brand blue
`#2563EB` background, a white map pin holding the car silhouette, and a deeper
blue `#1D4ED8` ground shadow. The eleven floor icons F1–F5/B1–B6 use the same
pin with the floor label inside the pin head, so the launcher icon reads as
"the car is here, on B2" after a parking record is saved. Eight earlier color
variants (the old P mark) remain for compatibility only. `Default.svg` and
`assets/launcher/*.svg` are generated vector sources; the opaque RGB rasters
live in `../Assets.xcassets/AppIcon*.appiconset/`.

Regenerate with the existing browser QA tooling (no runtime dependency; the
bundled NotoSansKR Bold renders the floor labels):

```sh
PLAYWRIGHT_MODULE=/path/to/playwright node ios/Runner/LauncherIconSources/generate.cjs
python3 ios/Runner/LauncherIconSources/check.py
```

One run writes the default pin (iPhone/iPad sets, Android legacy raster, web
icons) and all floor pins (iPhone/iPad sets, Android legacy raster, transparent
adaptive foreground layers, Android 13+ monochrome layers with the label knocked
out of the pin, and the `mipmap-anydpi-v33` XML that references them). The
generated `*.svg` sources name the Noto font without embedding it, so view the
PNGs rather than the SVGs for the final look. Add `--legacy` only when intentionally
regenerating the compatibility variants. The Android default adaptive
foreground is the hand-maintained vector
`android/app/src/main/res/drawable/ic_launcher_foreground.xml` with the same
pin geometry. The in-app `PinMark` widget (`lib/shared/components.dart`) draws
the identical geometry so the home header follows the launcher icon.

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
