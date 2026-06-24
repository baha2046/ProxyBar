# Settings Update Button Design

## Goal

Move the manual `Check for Updates…` action out of the application menu and
into the Settings window beside the current version number.

## Layout

Replace the standalone version label at the bottom of Settings with a
full-width horizontal footer row:

- the existing subdued version label remains left-aligned;
- a small rounded `Check for Updates…` button is right-aligned;
- flexible space separates the label and button;
- the row keeps the existing 312-point content width and does not increase the
  Settings window height.

The update button is a secondary action, not the window's default button.

## Behavior and Wiring

`SettingsViewController` will expose an `onCheckForUpdates` callback and invoke
it when the button is pressed. `SettingsWindowController` will forward that
callback using the same pattern as its existing settings actions.

`AppDelegate` will assign the callback and call
`SPUStandardUpdaterController.checkForUpdates(_:)` on its existing updater
controller. This keeps Sparkle ownership in `AppDelegate` and avoids coupling
the Settings UI directly to Sparkle.

`ApplicationMenu` will return to its previous updater-independent interface.
The update item and its separator will be removed, leaving the Quit command in
the application menu.

## Failure Handling

Sparkle continues to own update-check progress, errors, and user-facing
dialogs. Pressing the button does not affect ProxyBar's proxy state or close
the Settings window.

## Verification

Test first with source-wiring assertions that require:

- `Check for Updates…` in `SettingsWindowController.swift`;
- no update item in `ApplicationMenu.swift`;
- an `onCheckForUpdates` callback path from Settings to `AppDelegate`;
- the existing Sparkle selector call in `AppDelegate`.

Then run the packaging tests, core tests, and a full app build. Visually verify
that the version label and button share one footer row without clipping.
