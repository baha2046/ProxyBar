# Developer ID Notarized Release Design

## Goal

Make `scripts/package-app.sh` produce a Developer ID-signed, Apple-notarized,
stapled release archive that is ready for GitHub Releases and Homebrew.

## Release Flow

The existing packaging script remains the single release entry point. It will:

1. Build the release executable and assemble `ProxyBar.app`.
2. Select the signing identity from `SIGNING_IDENTITY` when provided; otherwise,
   select the first valid `Developer ID Application` identity reported by the
   login keychain.
3. Sign the app with the hardened runtime enabled.
4. Verify the signature before contacting Apple's notarization service.
5. Create a temporary zip containing the signed app.
6. Submit that zip with `xcrun notarytool` using the keychain profile named by
   `NOTARY_PROFILE`, which defaults to `develop`, and wait for completion.
7. Staple the notarization ticket to the app and validate the staple.
8. Create the final versioned release zip from the stapled app and print its
   SHA-256 checksum.

The final zip is not created until notarization and stapling succeed. The
temporary notarization zip is removed automatically on successful completion.

## Configuration

- `SIGNING_IDENTITY`: optional exact Developer ID identity override.
- `NOTARY_PROFILE`: optional keychain-profile override; defaults to `develop`.
- `BUILD_NUMBER`: existing optional bundle build number; defaults to `1`.

The script never reads or prints notarization credentials. Those remain in the
Keychain item previously created with `xcrun notarytool store-credentials`.

## Failure Handling

The script exits before publishing a final archive when:

- no Developer ID Application identity can be found;
- signing or signature verification fails;
- the `develop` keychain profile is missing or rejected;
- notarization is rejected or times out;
- stapling or staple validation fails.

Error messages identify the failed stage and explain which environment variable
can override the relevant default. Existing release archives are removed before
the flow starts so a failed run cannot leave a stale archive looking current.

## Verification

Add a shell-based test harness that runs the packaging script with mocked
macOS and Swift commands. Tests will first fail against the current script, then
verify:

- automatic Developer ID identity selection;
- explicit `SIGNING_IDENTITY` override;
- hardened-runtime signing and signature verification;
- notarization with keychain profile `develop`;
- stapling and validation before final archive creation;
- failure when no Developer ID identity is available.

Also run Bash syntax validation. Tests do not submit real artifacts to Apple or
access credentials.

## Documentation

Update the README build instructions to state that release packaging requires a
Developer ID Application certificate and a `notarytool` keychain profile named
`develop`, and document the supported environment-variable overrides.
