# ProxyCli

[中文](README_CN.md)

A lightweight HTTP/SOCKS5 proxy manager for Bash and Zsh on macOS, Linux, and WSL.

## Install or update

```bash
bash <(curl -fsSL baixiaosheng.de/proxycli) && source "$HOME/.proxycli/src/proxy-setup.sh"
```

Requires `curl`. The installer configures Bash startup files (including SSH login shells) or Zsh's startup file. `source` loads the installed version into the current shell; new terminals load it automatically. Loading commands does not start the proxy.

<details>
<summary>GitHub fallback and manual installation</summary>

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/baixiaoshengofficial/ProxyCli/main/install.sh) && source "$HOME/.proxycli/src/proxy-setup.sh"
```

Or clone and install:

```bash
git clone https://github.com/baixiaoshengofficial/ProxyCli.git
cd ProxyCli
bash install.sh
source "$HOME/.proxycli/src/proxy-setup.sh"
```

</details>

## Quick start

```bash
pstart   # Enable the proxy (automatic detection by default)
pstatus  # Check state and connectivity
pstop    # Restore the previous proxy environment
```

While ProxyCli is active, the prompt shows an icon (default: 🚀). `pstop` removes it:

```text
🚀 root@host:~#
```

| Command | Action |
| --- | --- |
| `pstart` | Enable this shell's proxy |
| `pscan` | Rescan local proxies and enable the result |
| `pstop` | Restore the previous proxy environment |
| `ptoggle` | Start or stop ProxyCli |
| `pstatus` | Show proxy state and check connectivity |
| `pset` | Show all settings |
| `phelp` | Show help |

## Settings

`pset` saves settings for the **current shell session**. Run `pstart` to apply them; until then, the active proxy and icon stay as they are.

| Setting | Set a value | Restore the default |
| --- | --- | --- |
| Address | `pset --address 127.0.0.1:7890` | `pset --address auto` |
| Scan ports | `pset --ports 7890 1080` | `pset --ports auto` |
| Prompt icon | `pset --indicator 🌐` | `pset --indicator auto` |

Omit the value to view one setting: `pset --address`, `pset --ports`, or `pset --indicator`.

One address is used for both HTTP and SOCKS5. For separate endpoints, put HTTP first and SOCKS5 second:

```bash
pset --address 127.0.0.1:7890 127.0.0.1:1080
pstart
```

- Addresses require `host:port`, with ports from `1` to `65535`. Quote IPv6 addresses: `'[::1]:7890'`. HTTP accepts `http://` or `https://`; a separate SOCKS endpoint accepts `socks5://` or `socks5h://`. Output hides proxy credentials.
- Default scan ports: `7890 7891 7892 7893 7897 8888 8080`.
- Icons accept a literal emoji or symbol without spaces or prompt escapes, including combined emoji such as `👩‍💻`. Quotes are optional for emoji. The default is 🚀; changing only the icon does not force a new proxy scan.

Settings survive reloading the runtime in the same session. They are not saved across terminals or shell restarts.

## How it works

### Start and scan

`pstart` uses a manual address directly. In automatic mode, pending address or scan-port changes trigger a scan; otherwise, it reuses a detected proxy whose ports are still listening, or existing proxy environment variables, before scanning.

`pscan` always scans and enables the result, then switches the address setting to automatic detection. Scans try cached ports, proxy process ports, configured ports, and other local listeners, in that order. A failed scan keeps the active environment and leaves pending settings available for retry.

### State and connectivity

The icon and `ACTIVE` / `INACTIVE` indicate whether ProxyCli is managing this shell. `pstatus` checks the actual proxy variables, including externally configured ones, and reports direct, HTTP, and SOCKS5 connectivity separately. The test URL defaults to `https://example.com/`; set `PROXYCLI_TEST_URL` to change it. Pending settings appear as a reminder to run `pstart`.

### Scope

`pstart` and `pscan` export `http_proxy`, `https_proxy`, `all_proxy`, and their uppercase variants. Programs started from this shell inherit them and use the proxy if they support these variables. Other terminals, already running programs, and independently started services keep their own environment. `pstop` restores the proxy and `no_proxy` variables that existed before ProxyCli started.

## Uninstall

```bash
bash <(curl -fsSL baixiaosheng.de/proxycli) --uninstall
```

From a local checkout, run `bash install.sh uninstall`. Restart the shell afterward to remove the loaded commands.

## Development

Runtime code lives in `src/proxy-setup.sh`; installation and shell startup integration live in `install.sh`. Validate changes with:

```bash
bash -n install.sh
bash -n src/proxy-setup.sh
bash tests/test_proxy_setup.sh
bash install.sh --help
```

Tests run offline. Contributions are welcome; keep both guides aligned with command behavior.

[MIT License](LICENSE) · [GitHub](https://github.com/baixiaoshengofficial/ProxyCli)
