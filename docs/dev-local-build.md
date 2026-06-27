# Local Development Builds

Use the dev installer when validating local macOS behavior that depends on app identity. It produces a separate app from the release bundle, so LaunchServices, Accessibility permissions, Microphone permissions, and Sparkle updates do not get mixed together.

## Which Command Should I Use?

Use `swift build`, `swift test`, and Prompt Lab for normal code and prompt checks. These commands do not need code signing.

Use `swift run Douvo` for quick local development only. It runs the executable directly, so macOS may attribute permissions to Terminal, your shell, or Xcode instead of a stable Douvo app identity.

Use `scripts/install-dev-app.sh` when testing the real menu bar app, global shortcuts, Accessibility, Microphone permissions, LaunchServices registration, or Sparkle behavior. This path needs a stable local code-signing identity.

## App Identity

- Release source identity: `Douvo` / `local.douvo`
- Local dev identity: `Douvo Dev` / `local.douvo.dev`
- Local dev path: `/Applications/Douvo Dev.app`

The source `Info.plist` stays on the release identity. The dev installer patches the copied app bundle after `scripts/build-app.sh` finishes, then signs the patched bundle.

## Signing

Local builds must use a stable signing identity. Ad-hoc signing changes the app's code requirement enough that macOS privacy permissions can appear to reset or point at stale entries.

Preferred local identity name:

```bash
Douvo Local Code Signing
```

`scripts/build-app.sh` and `scripts/install-dev-app.sh` both auto-detect this identity. If it is missing, create it explicitly:

```bash
scripts/ensure-local-code-signing-identity.sh
```

That script creates a self-signed code-signing certificate in a Douvo-specific local keychain at:

```bash
~/Library/Application Support/Douvo/CodeSigning/douvo-local-code-signing.keychain-db
```

It stores a generated keychain password beside it with user-only file permissions. Creating or trusting the identity can trigger macOS security authentication the first time. After that, `scripts/build-app.sh` and `scripts/install-dev-app.sh` reuse the same local keychain and should not ask for the login keychain password again.

If macOS asks every time, remove the stale local signing keychain and create it once again:

```bash
rm -rf "$HOME/Library/Application Support/Douvo/CodeSigning"
scripts/ensure-local-code-signing-identity.sh
```

You can override the identity with:

```bash
CODESIGN_IDENTITY="Developer ID Application: Example" scripts/install-dev-app.sh
```

If no identity is found, the scripts fail instead of producing an ad-hoc signed app.

External contributors do not need the maintainer's certificate or an Apple Developer account.

Verify it:

```bash
LOCAL_CODESIGN_KEYCHAIN="$HOME/Library/Application Support/Douvo/CodeSigning/douvo-local-code-signing.keychain-db"
security find-identity -v -p codesigning "$LOCAL_CODESIGN_KEYCHAIN" | rg "Douvo Local Code Signing"
```

## Install And Open

```bash
scripts/install-dev-app.sh
```

The installer:

- builds the release product
- copies `.build/release/Douvo.app` to `/Applications/Douvo Dev.app`
- patches `CFBundleDisplayName`, `CFBundleName`, and `CFBundleIdentifier`
- disables Sparkle automatic checks for the dev bundle
- removes quarantine metadata when present
- signs and verifies the copied app
- registers it with LaunchServices
- opens the dev app by default

Set `DOUVO_DEV_OPEN=0` to install without opening the app:

```bash
DOUVO_DEV_OPEN=0 scripts/install-dev-app.sh
```

## Permission Notes

macOS permissions are keyed by the app identity and signing requirement. The dev bundle intentionally keeps `local.douvo.dev` stable so repeated local installs can reuse the same Accessibility and Microphone permission rows.

If permissions look stale after changing the bundle ID or signing identity, reset the affected service for the dev bundle and grant it again in System Settings.

```bash
tccutil reset Accessibility local.douvo.dev
tccutil reset Microphone local.douvo.dev
```

Prefer keeping the bundle ID and signing identity stable over resetting permissions during normal development.

## Verification

After installation, these commands should identify the dev app:

```bash
plutil -p "/Applications/Douvo Dev.app/Contents/Info.plist" | rg "CFBundleIdentifier|CFBundleDisplayName|SUAutomaticallyUpdate|SUEnableAutomaticChecks"
codesign --verify --deep --strict "/Applications/Douvo Dev.app"
```
