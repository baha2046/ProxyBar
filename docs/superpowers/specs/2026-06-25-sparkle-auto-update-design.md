# Sparkle Automatic Update Design

## Goal

Add secure Sparkle 2 updates to ProxyBar. The app will check for updates in the
background, download eligible updates automatically, install them when the app
quits when possible, and retain Sparkle's standard confirmation UI when user
interaction or authorization is required.

Users can also start an immediate check from a `Check for Updates…` item in the
ProxyBar application menu.

## Dependency and App Integration

Add the official `sparkle-project/Sparkle` Swift package and link the `Sparkle`
product to the `ProxyBar` executable target. Pin the package to the selected
Sparkle 2 release series so dependency resolution remains reproducible while
allowing compatible patch updates.

`AppDelegate` will own one `SPUStandardUpdaterController` for the lifetime of
the application. The controller starts with the application and uses Sparkle's
standard update UI and scheduler. ProxyBar will not implement a parallel
version checker, downloader, or installer.

`ApplicationMenu.install` will accept the updater controller and add `Check for
Updates…` to the application menu. Its target and action will be
`SPUStandardUpdaterController.checkForUpdates(_:)`, allowing Sparkle to manage
manual checks and menu-item validation.

## Update Behavior

The packaged application's `Info.plist` will contain:

- `SUFeedURL`, pointing to the stable GitHub Releases URL
  `https://github.com/baha2046/ProxyBar/releases/latest/download/appcast.xml`;
- `SUPublicEDKey`, supplied from the release environment and embedded in the
  app bundle;
- `SUEnableAutomaticChecks` set to `true`;
- `SUAutomaticallyUpdate` set to `true`.

Sparkle will use its default scheduled check interval of 24 hours. ProxyBar
will not force a check on every launch because that would interfere with
Sparkle's scheduler.

With automatic updates enabled, Sparkle may download and stage an update
silently. It installs the update when the app quits when possible. Sparkle may
show its standard UI when installation needs authorization, when the app has
remained open for an extended period, when an update cannot be installed
silently, or when the user invokes a manual check.

## Appcast and Update Security

Release archives will be protected by both Developer ID code signing and
Sparkle EdDSA signatures. The Sparkle private key remains in the release
operator's macOS Keychain and is never committed to the repository, printed by
scripts, or placed in the app bundle.

The release process will use Sparkle's `generate_appcast` tool to produce an
`appcast.xml` containing the release archive URL, archive size, version
metadata, minimum supported macOS version, and EdDSA signature. The generated
file will be uploaded as an asset on the same GitHub Release as the notarized
ProxyBar ZIP. The stable `releases/latest/download/appcast.xml` URL lets every
installed version discover the newest published release without requiring
GitHub Pages or another web host.

The public EdDSA key will be passed to packaging through
`SPARKLE_PUBLIC_ED_KEY`. Packaging must fail before creating a distributable
archive if this value is absent. Key generation remains an explicit one-time
release setup step using Sparkle's `generate_keys` utility.

## Packaging

The existing `scripts/package-app.sh` remains the release entry point.
Packaging will:

1. Resolve and build ProxyBar with the Sparkle dependency.
2. Copy `Sparkle.framework` into `ProxyBar.app/Contents/Frameworks` while
   preserving framework symlinks.
3. Write the Sparkle feed URL, public key, and automatic-update defaults into
   `Info.plist`.
4. Sign nested Sparkle components in the order required by Sparkle, then sign
   the application with the hardened runtime.
5. Verify the final app signature, notarize it, staple the ticket, and create
   the release ZIP as today.
6. Generate `dist/appcast.xml` from the finished release archive for upload to
   GitHub Releases.

The executable must have a runtime search path that resolves the embedded
framework from `Contents/Frameworks`. Packaging tests will verify the framework
location and executable linkage rather than relying only on a successful
compile.

`CFBundleVersion` remains the machine-readable update ordering value. The
packaging script will default it to the supplied release version when
`BUILD_NUMBER` is not provided, while preserving the environment override for
release operators who use monotonically increasing integer builds.

## Failure Handling

Packaging will stop without producing a final release archive or appcast when:

- `SPARKLE_PUBLIC_ED_KEY` is missing;
- the Sparkle framework or command-line tools cannot be located;
- framework embedding or nested signing fails;
- final signature verification, notarization, or stapling fails;
- appcast generation or archive signing fails.

Failures will identify the missing prerequisite or failed stage without
exposing signing material.

At runtime, Sparkle's standard UI and logging will handle unreachable feeds,
invalid appcasts, signature failures, incompatible macOS versions, and
installation authorization. Update failures must not stop ProxyBar's proxy
service or otherwise change its routing state.

## Verification

Implementation will follow test-first development.

Package and release tests will verify:

- the Sparkle package and executable dependency are declared;
- the framework is embedded under `Contents/Frameworks`;
- the executable has the expected framework runtime path;
- `Info.plist` contains the stable feed URL, supplied public key, and enabled
  automatic checking and updating;
- missing public-key configuration fails before release output;
- Sparkle nested components are signed before the outer app;
- the final app is still verified, notarized, stapled, and archived;
- appcast generation happens from the final archive and produces a release
  asset with an EdDSA signature;
- the bundle version defaults and overrides behave as specified.

App-level tests will isolate any small menu-construction decision that can be
tested without launching Sparkle's UI. A release smoke test will launch the
packaged app against a controlled test appcast and confirm that a manual check
reaches Sparkle's standard update flow.

## Documentation

Update the README with:

- automatic-update behavior and the manual menu command;
- one-time Sparkle key generation;
- the `SPARKLE_PUBLIC_ED_KEY` packaging requirement;
- the release artifacts that must be uploaded to GitHub;
- a concise release order that prevents publishing an unsigned or mismatched
  appcast.
