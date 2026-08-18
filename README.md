# FSA App — Flutter rebuild

Greenfield rebuild of the Food Safety Agency inspector application.
First screen: the login page, reproduced from the legacy Xamarin.Forms
`LoginPage.xaml` / `LoginPage.xaml.cs`.

## Prerequisites

Neither Flutter nor the Android SDK is installed on this machine yet.

1. **Flutter SDK** — https://docs.flutter.dev/get-started/install/windows
   Extract to `C:\src\flutter` and add `C:\src\flutter\bin` to PATH.
2. **Android Studio** (bundles the Android SDK, platform-tools and a JDK).
3. Verify: `flutter doctor`

## Generating the platform folders

The Dart source, assets and `pubspec.yaml` are committed. The `android/`,
`ios/`, `web/` folders are generated boilerplate — create them in place:

```bash
cd fsa_app
flutter create . --project-name fsa_app --org za.co.eclick --platforms android,ios
flutter pub get
flutter run
```

`flutter create .` on an existing directory adds the missing platform folders
and leaves `lib/`, `assets/` and `pubspec.yaml` untouched.

## Layout

```
lib/
  core/
    config/app_config.dart          runtime config (replaces Constants.cs #if blocks)
    services/connectivity_service.dart
    services/device_service.dart    device id + masking
    theme/app_theme.dart            colours and font sizes from the legacy app
  features/auth/
    domain/auth_service.dart        sign-in boundary + stub implementation
    presentation/login_page.dart    the screen
assets/images/                      1x / 2x / 3x / 4x from the legacy drawables
```

## Behaviour carried over

| Legacy | Here |
|---|---|
| `Constants.BackgroundColour` white | `AppColors.background` |
| `MainButtonBackGroundColour` #0D8BB5 | field labels |
| `LabelBackGroundColour` #4F0FFF | banner, buttons, version footer |
| `Regex.Replace(text, @"\s", "")` | `_stripWhitespace` on both fields |
| Login Name <kbd>Enter</kbd> → password | `onSubmitted` → `_passwordFocus` |
| Password <kbd>Enter</kbd> → sign in | `onSubmitted` → `_signIn` |
| `HidePass.png` / `ShowPass.png` toggle | `IconButton` suffix on the password field |
| `App.StartCheckIfInternet(...)` | `ConnectivityService` stream → offline banner |
| `OnIdiom` phone/tablet padding | `MediaQuery.shortestSide >= 600` |

## Deliberate fixes

- **Device ID masking** — the original did
  `Substring(0, Length - 17)` and threw on identifiers shorter than 18
  characters. Now length-safe.
- **Sign-in branches** — the legacy `else if (!GetUserIsDisabledStatus...)`
  and `else if (GetUserActiveStatus...)` conditions were inverted, making the
  suspended/inactive messages unreachable. Replaced with an exhaustive
  `AuthOutcome` switch.
- **Colours** — XAML declared `Red`, `Init()` overwrote it with `#4F0FFF` at
  runtime. The runtime value is used directly instead of being set twice.
- **Config** — no compile-time `#if` environment switching, and no cleartext
  HTTP endpoints.

## Not yet wired

`LocalStubAuthService` accepts any non-empty credentials. Replace it with the
Drift-backed local store plus server token exchange when the data layer lands.
Device registration (`deviceNotRegistered`) is modelled but not enforced.
