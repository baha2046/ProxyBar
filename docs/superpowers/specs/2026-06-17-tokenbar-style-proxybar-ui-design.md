# TokenBar-Style ProxyBar UI Design

## Goal

Upgrade ProxyBar from a plain status menu into a compact custom popover inspired by TokenBar. The UI should make proxy state obvious at a glance, provide a real on/off switch, and explain startup failures such as busy ports 1080 or 1081 in user-friendly language.

## Scope

- Replace the current `NSMenu`-only status UI with a custom popover panel opened from the menu bar item.
- Keep the app a lightweight menu bar utility. The panel should be polished, not a full dashboard.
- Preserve existing domain management actions: add domain, apply now, open config, open at login, and quit.
- Add real proxy enable/disable behavior. Off means embedded proxy servers are stopped and macOS auto-proxy is disabled for the configured network service.
- Add clear visual states in both the panel and menu bar icon:
  - Green means proxy servers are running and macOS PAC settings were applied.
  - Red means the proxy is off or failed.
  - Amber means ProxyBar is starting, stopping, or applying settings.

## UI Design

The popover should use a dark rounded panel with a visual hierarchy similar to TokenBar:

- Header:
  - ProxyBar mark and title.
  - Glowing green/red status light.
  - Primary on/off switch.
- Main body:
  - A concise state message such as `Routing Enabled`, `Proxy Off`, or `Port Busy`.
  - SOCKS5 and PAC status cards showing host and bound ports.
  - A compact decorative activity strip to add motion and polish without implying precise traffic analytics.
  - Error card when needed, using focused recovery copy.
- Footer/actions:
  - Add Domain.
  - Apply Now.
  - Open Config.
  - Open at Login toggle.
  - Quit.

The panel should use native AppKit controls where practical, with custom views for the switch, status lights, cards, and activity strip. It should fit comfortably in a menu bar popover and avoid requiring a normal app window.

## Proxy State Behavior

Introduce an explicit UI state model in `AppDelegate` or a small helper owned by it:

- `starting`
- `running`
- `stopping`
- `off`
- `failed(message)`

Switching on:

1. Load config.
2. Start the embedded SOCKS5 and PAC servers.
3. Apply macOS PAC settings.
4. Show running state with bound ports.

Switching off:

1. Stop the embedded proxy servers.
2. Disable macOS auto-proxy for the configured network service.
3. Show off state.

Applying changes while on should reload the proxy server and reapply PAC settings. Applying changes while off should update the config/domain list without starting the proxy unless the user turns it on.

## Error Handling

Socket bind failures should be classified before reaching the UI:

- SOCKS5 bind failure:
  - Example: `SOCKS5 port 1080 is already in use. Quit the other app or change socks_port in config.toml.`
- PAC bind failure:
  - Example: `PAC port 1081 is already in use. Quit the other app or change pac_port in config.toml.`
- Other POSIX errors:
  - Include the requested role, port, and POSIX description.
- `networksetup` failure:
  - Explain that the proxy server may be running but macOS proxy settings could not be applied.
- Config parse fallback:
  - Existing config fallback can remain, but invalid explicit port values should continue surfacing clearly when a write/apply path encounters them.

On startup failure, stop any partially started server, return the switch to off, show a red state, and keep the app open so the user can fix the issue.

## Implementation Notes

- Add a small AppKit popover controller/view for the visual panel.
- Update `StatusIcon` so it can render green, red, and neutral/working variants instead of only a template icon.
- Add `SystemActions.disableAutoProxy()` for the switch-off path.
- Add typed bind errors in `ProxyBarCore` by wrapping `POSIXError` from `PACHTTPServer` and `SOCKS5Server` with server role and requested port.
- Keep all server lifecycle changes on the main actor from the UI, while existing server internals remain thread-safe.

## Verification

- Unit tests:
  - PAC occupied port reports a PAC-specific bind error.
  - SOCKS5 occupied port reports a SOCKS5-specific bind error.
  - `SystemActions.disableAutoProxy()` emits the expected `networksetup -setautoproxystate Wi-Fi off` command.
- Build/test:
  - `swift run ProxyBarCoreTests`
  - `swift build --product ProxyBar`
- Manual check:
  - Launch app.
  - Open popover.
  - Toggle proxy off and on.
  - Confirm green/red icon and panel states.
  - Start another listener on 1080 or 1081 and confirm the panel shows the targeted port-busy message.
