# ProxyBar

ProxyBar is a macOS menu bar app for editing crabbyproxy domain exclusions and
running a crabbyproxy-compatible local proxy.

It reads `~/.config/crabbyproxy/config.toml`, starts embedded loopback servers,
and refreshes Wi-Fi's automatic proxy URL to:

```text
http://127.0.0.1:1081/proxy.pac
```

By default it listens on:

```text
socks5://127.0.0.1:1080
http://127.0.0.1:1081/proxy.pac
```

If `[proxy].socks_port` or `[proxy].pac_port` are set in `config.toml`,
ProxyBar uses those ports instead.

## Build

Run the core behavior tests:

```sh
swift run ProxyBarCoreTests
```

Build the release binary:

```sh
swift build -c release --product ProxyBar
```

Create the app bundle:

```sh
scripts/package-app.sh
```

The app bundle is written to:

```text
.build/ProxyBar.app
```

## Use

Open `.build/ProxyBar.app`. It appears in the macOS menu bar as `ProxyBar`.

- `Add Domain...` accepts a domain or URL.
- Adding `example.com` writes both `example.com` and `*.example.com`.
- Removing either entry removes both the apex and wildcard pair.
- `localhost` remains exact-only.
- `Apply Now` reloads the embedded PAC/SOCKS5 server and refreshes macOS's PAC
  setting.
- Each config write creates a timestamped backup beside `config.toml`.

ProxyBar is intentionally unsandboxed because it needs to edit your home config
file, bind local proxy ports, and run `networksetup`.
