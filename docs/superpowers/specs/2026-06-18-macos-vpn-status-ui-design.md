# macOS VPN Status UI Design

## Goal

Show the current macOS VPN connection status in the ProxyBar popover using data from `scutil --nc list`. The status should update as the VPN changes and make the connected or disconnected state obvious at a glance.

## Scope

- Add a VPN status indicator to the existing AppKit popover.
- Treat `scutil --nc list` as the source of truth.
- Show a green indicator and VPN service name when any VPN service is connected.
- Show a red indicator and `Not connected` when no VPN service is connected.
- Refresh the status on launch, whenever the popover opens, and periodically while the app is running.
- Keep the implementation lightweight and testable, with parsing logic in `ProxyBarCore`.

## Architecture

Add a small `VPNStatus` model and parser in `ProxyBarCore`. A monitor owned by `AppDelegate` will call `/usr/sbin/scutil --nc list`, parse the output, store the latest status, and trigger `updateUI()` on the main actor.

The parser will understand the status marker and service name from rows in `scutil --nc list`. If any row is connected, the first connected service name becomes the displayed VPN name. If no row is connected, the state is disconnected. If the command fails, the UI can show the disconnected state rather than blocking proxy controls.

## UI

Add a compact VPN status row or card near the existing SOCKS5, PAC, and Domains cards. It should match the current dark TokenBar-style panel:

- Label: `VPN`
- Connected value: VPN service name
- Disconnected value: `Not connected`
- Green light for connected
- Red light for disconnected

The VPN status is independent from ProxyBar's own proxy state. A disconnected VPN should not disable ProxyBar controls.

## Data Flow

1. App launches and starts a timer-backed VPN monitor.
2. Monitor runs `scutil --nc list`.
3. Parser returns connected name or disconnected.
4. `AppDelegate` stores the latest VPN status and rebuilds the popover view model.
5. Popover displays the status card.
6. Opening the popover forces a refresh so the displayed value is current.

## Error Handling

If `scutil` fails or returns unexpected output, the monitor should avoid surfacing a disruptive proxy error. The UI should fall back to `Not connected`, keeping ProxyBar usable. Parser tests should cover ordinary connected and disconnected output.

## Testing

- Unit test parsing connected `scutil --nc list` output.
- Unit test parsing disconnected output.
- Unit test choosing the first connected VPN when multiple services are present.
- Run `swift run ProxyBarCoreTests`.
- Run `swift build --product ProxyBar`.
