# Developer ID Notarized Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `scripts/package-app.sh` produce a Developer ID-signed, notarized, stapled release zip using the `develop` notarytool keychain profile by default.

**Architecture:** Keep one release entry point and extract no new production components. Add a shell test harness that replaces external build, signing, archive, and Apple tooling with deterministic mocks, then update the packaging script and README from those behavioral tests.

**Tech Stack:** Bash, Swift Package Manager, macOS `security`, `codesign`, `ditto`, `xcrun notarytool`, and `xcrun stapler`.

---

## File Structure

- Create `Tests/PackageAppTests/package-app-tests.sh`: isolated behavioral tests for release command order, defaults, overrides, and failure handling.
- Modify `scripts/package-app.sh`: Developer ID discovery, hardened-runtime signing, verification, notarization, stapling, validation, and final archive creation.
- Modify `README.md`: release prerequisites, credential profile setup, and environment overrides.

### Task 1: Add failing packaging-flow tests

**Files:**
- Create: `Tests/PackageAppTests/package-app-tests.sh`
- Test: `scripts/package-app.sh`

- [ ] **Step 1: Create a mocked-command test harness**

The harness must copy `scripts/package-app.sh` into a temporary project, put mock
commands first on `PATH`, run the copied script, and record every external
command. It must assert:

```text
security find-identity -v -p codesigning
codesign --force --deep --options runtime --timestamp --sign Developer ID Application: Example (TEAMID)
codesign --verify --deep --strict --verbose=2
xcrun notarytool submit ... --keychain-profile develop --wait
xcrun stapler staple ...
xcrun stapler validate ...
```

It must also assert that stapler validation precedes creation of the final
`ProxyBar-<version>.zip`, that `SIGNING_IDENTITY` bypasses discovery, and that a
missing identity exits nonzero without creating a final zip.

- [ ] **Step 2: Run the tests and verify RED**

Run:

```bash
bash Tests/PackageAppTests/package-app-tests.sh
```

Expected: FAIL because the current script defaults to ad-hoc signing and does
not invoke notarization or stapling.

- [ ] **Step 3: Validate test syntax**

Run:

```bash
bash -n Tests/PackageAppTests/package-app-tests.sh
```

Expected: exit code `0`.

### Task 2: Implement the notarized release flow

**Files:**
- Modify: `scripts/package-app.sh`
- Test: `Tests/PackageAppTests/package-app-tests.sh`

- [ ] **Step 1: Add release configuration and identity discovery**

Use:

```bash
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-develop}"
NOTARY_ZIP_PATH="$DIST_DIR/ProxyBar-$VERSION-notary.zip"
```

When `SIGNING_IDENTITY` is empty, parse the first quoted identity containing
`Developer ID Application` from:

```bash
/usr/bin/security find-identity -v -p codesigning
```

Exit with a clear error if no identity is found.

- [ ] **Step 2: Sign and verify before notarization**

Sign and verify with:

```bash
/usr/bin/codesign --force --deep --options runtime --timestamp \
  --sign "$SIGNING_IDENTITY" "$APP_DIR"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_DIR"
```

- [ ] **Step 3: Submit, staple, validate, and create the final archive**

Create only the temporary submission archive before notarization:

```bash
/usr/bin/ditto -c -k --norsrc --keepParent "$APP_DIR" "$NOTARY_ZIP_PATH"
/usr/bin/xcrun notarytool submit "$NOTARY_ZIP_PATH" \
  --keychain-profile "$NOTARY_PROFILE" --wait
/usr/bin/xcrun stapler staple "$APP_DIR"
/usr/bin/xcrun stapler validate "$APP_DIR"
rm -f "$NOTARY_ZIP_PATH"
/usr/bin/ditto -c -k --norsrc --keepParent "$APP_DIR" "$ZIP_PATH"
```

- [ ] **Step 4: Run focused tests and verify GREEN**

Run:

```bash
bash Tests/PackageAppTests/package-app-tests.sh
bash -n scripts/package-app.sh
```

Expected: all packaging tests pass and Bash syntax validation exits `0`.

### Task 3: Document signed release prerequisites

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add credential setup and release behavior**

Document that `scripts/package-app.sh` requires:

```bash
xcrun notarytool store-credentials develop
```

and a valid Developer ID Application certificate. Explain that
`SIGNING_IDENTITY`, `NOTARY_PROFILE`, and `BUILD_NUMBER` override defaults.

- [ ] **Step 2: Run documentation and regression checks**

Run:

```bash
git diff --check
swift test
bash Tests/PackageAppTests/package-app-tests.sh
```

Expected: no whitespace errors and all tests pass.

### Task 4: Final release-script verification

**Files:**
- Verify: `scripts/package-app.sh`
- Verify: `Tests/PackageAppTests/package-app-tests.sh`
- Verify: `README.md`

- [ ] **Step 1: Inspect the final diff**

Run:

```bash
git diff -- scripts/package-app.sh Tests/PackageAppTests/package-app-tests.sh README.md
```

Expected: only the approved signing, notarization, stapling, tests, and
documentation changes appear.

- [ ] **Step 2: Re-run the complete verification set**

Run:

```bash
bash -n scripts/package-app.sh
bash -n Tests/PackageAppTests/package-app-tests.sh
bash Tests/PackageAppTests/package-app-tests.sh
swift test
git diff --check
```

Expected: every command exits `0`.
