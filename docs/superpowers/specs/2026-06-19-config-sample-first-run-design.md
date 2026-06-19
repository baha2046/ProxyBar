# Config Sample First Run Design

## Goal

ProxyBar should ship a sample crabbyproxy config and create the user's
`~/.config/crabbyproxy/config.toml` from that sample the first time the file is
needed.

## Design

Add `config.sample.toml` at the project root. Its content mirrors
`ProxySettings.crabbyDefaults`: SOCKS5 port `1080`, PAC port `1081`, the default
domain rules, and the default DoH servers.

Keep first-run behavior in `ConfigStore`, because that is the existing boundary
for reading and writing the config file. Before loading the document, create the
parent directory and write sample config text if `configURL` does not exist.
Existing config files are never overwritten.

Runtime parsing keeps its current tolerant behavior: if a config is missing or
malformed when loading `ProxySettings`, ProxyBar still falls back to built-in
defaults. The new file creation path is for the editable config document used by
domain management and first-run setup.

## Testing

Add a core test that points `ConfigStore` at a missing temporary config path,
calls `loadDomains()`, and verifies that the config directory and file are
created with parseable default domains.
