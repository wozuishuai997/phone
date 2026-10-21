# FullScreenContentPop (LCSing / app-side dylib)

Objective-C dynamic library intended for injection into a normally signed iOS app. It does not use Theos, Logos, Substrate, or private UIKit navigation-transition methods.

## Build

A macOS GitHub Actions workflow builds an arm64 iOS dynamic library using the installed iPhoneOS SDK. It checks that the output is a Mach-O dynamic library and arm64, calculates a SHA-256 checksum, and uploads the output as the `FullScreenContentPop-iOS-arm64` workflow artifact.

Workflow: [Build FullScreenContentPop dylib](../../actions/workflows/build-dylib.yml)

## Behavior and limitations

- Looks up `UINavigationController.interactiveContentPopGestureRecognizer` dynamically and enables it only when that selector is available at runtime.
- Re-checks visible navigation controllers when the app becomes active and when a navigation controller appears.
- Does not install a custom competing pan gesture as a fallback. If the selector is unavailable, normal edge-swipe behavior remains unchanged.
- Applies only to UIKit navigation stacks that expose and support the selector. It cannot guarantee behavior in SwiftUI custom navigation, web-only screens, games, or apps with custom routing/gesture handling.
- A successful build validates the binary format and architecture only; it does not prove compatibility or behavior on iOS 27. Test with a non-critical app first.

## Use with LCSing

The artifact is an unsigned dylib. Inject it into a test IPA using your normal LCSing workflow and re-sign the resulting app. Do not use first on a critical app; if the app crashes or gestures behave incorrectly, remove the injection and inspect the crash log.

## Build locally on macOS

```sh
cd FullScreenContentPop-LCSing
chmod +x build.sh
./build.sh
```

Output: `build/FullScreenContentPop.dylib`.
