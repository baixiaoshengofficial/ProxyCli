English [中文](https://github.com/baixiaoshengofficial/ProxyCli/blob/main/README_CN.md)
# Proxy Management Script

A lightweight proxy manager for Bash and Zsh. Manage HTTP and SOCKS5 proxy environment variables in the current shell.

## Features

- 🚀 Start, stop, or toggle proxy variables in the current shell
- 🔍 Auto-detect HTTP and SOCKS5 proxies from local listeners
- 📊 Show proxy variables and check connectivity
- ⚙️ Configure proxy addresses and scan ports with `pset`

## Installation 

### One-line Install 

```bash
bash <(curl -sSL baixiaosheng.de/proxycli) && source "$HOME/.proxycli/src/proxy-setup.sh"
```

The installer updates Bash startup files for both regular and SSH login shells, or the Zsh startup file. The `source` step loads the installed or updated commands into the current shell; new terminals load them automatically.

GitHub Raw fallback:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/baixiaoshengofficial/ProxyCli/main/install.sh) && source "$HOME/.proxycli/src/proxy-setup.sh"
```

### One-line Uninstall 

```bash
bash <(curl -sSL baixiaosheng.de/proxycli) --uninstall
```

### Manual Install 

1. Clone repository:  

   ```bash
   git clone https://github.com/baixiaoshengofficial/ProxyCli.git
   cd ProxyCli
   ```

2. Run installer:  

   ```bash
   bash install.sh
   ```

3. Load the commands in the current shell:

   ```bash
   source "$HOME/.proxycli/src/proxy-setup.sh"
   ```

## Usage 

| Command  | Description| Example |
|----------------|-------------------|---------------|
| `pstart`       | Enable proxy variables in this shell | `pstart` |
| `pscan`        | Scan local proxies and enable the result | `pscan` |
| `pstop`        | Restore this shell's previous proxy environment | `pstop` |
| `ptoggle`      | Start or stop ProxyCli | `ptoggle` |
| `pstatus`      | Show shell proxy variables and test connectivity | `pstatus` |
| `pset`         | Show current settings | `pset` |
| `pset --address host:port` | Set a shared HTTP/SOCKS5 endpoint | `pset --address localhost:7890` |
| `pset --address HTTP SOCKS` | Set HTTP and SOCKS5 endpoints separately | `pset --address localhost:7890 localhost:1080` |
| `pset --address auto` | Return to automatic detection | `pset --address auto` |
| `pset --ports` | Show scan ports | `pset --ports` |
| `pset --ports port ...` | Replace scan ports | `pset --ports 7890 1080 8080` |
| `pset --ports --reset` | Restore default scan ports | `pset --ports --reset` |
| `phelp`        | Show help | `phelp` |

## Proxy Detection

`pstart` uses a manually configured address, a cached local proxy whose ports are still listening, or existing proxy environment variables. It scans when no reusable proxy is available. `pscan` always performs a fresh local scan and enables the result; a successful scan switches the address setting to automatic detection.

Scans try cached ports first, followed by common proxy process ports, configured ports, and other local listeners. Progress shows the candidates, current port, protocols, and results. A failed scan keeps the previous address and shell environment.

`pstart` confirms that proxy variables were set. Run `pstatus` to test connectivity to `PROXYCLI_TEST_URL` (default: `https://example.com/`). It checks the actual shell variables, including externally configured proxies. `ACTIVE` / `INACTIVE` describes whether ProxyCli is managing the shell; the connection results are reported separately.

`pstart` and `pscan` export `http_proxy`, `https_proxy`, `all_proxy`, and their uppercase variants in the current shell. Programs launched from that shell inherit these variables and can use them if they support proxy environment variables. `pstop` restores the previous shell environment. Other terminals, already running programs, and independently launched services keep their own environment.

Sourcing the runtime loads the commands; it does not automatically enable a proxy. Address and scan-port settings apply to the current shell session and survive reloading the runtime. `pset --address host:port` sets the address for `pstart`; if ProxyCli is active, it updates the proxy variables immediately. `pset --address auto` rescans immediately when active. Run `pset` to view the settings.

Addresses require a host and a port from `1` to `65535`. Use brackets around IPv6 hosts, for example `'[::1]:7890'`. HTTP addresses accept `http://` or `https://`; a separate SOCKS address accepts `socks5://` or `socks5h://`. Proxy credentials are hidden in command output.

The defaults are `7890 7891 7892 7893 7897 8888 8080`. Change them for the current shell when needed:

```bash
pset --ports 7890 1080 8080
```

Run `pset --ports` to show the current list or `pset --ports --reset` to restore the defaults. Use `pset --address host:port` to bypass detection, or `pset --address auto` to return to automatic mode.

## Uninstallation 

```bash
bash install.sh uninstall
```

## Supported Environments

- ✔️ macOS (Terminal, iTerm2)
- ✔️ Linux (Ubuntu, Debian, CentOS, etc.)
- ✔️ Windows Subsystem for Linux (WSL)

## Project Structure

```
ProxyCli/
├── LICENSE                 # MIT License
├── README.md               # English documentation
├── README_CN.md            # Chinese documentation (中文文档)
├── install.sh              # Installation script
├── src/
│   └── proxy-setup.sh      # Core proxy management
└── tests/
    └── test_proxy_setup.sh # Offline shell regression tests
```

## Contributing 

Contributions are welcome! Please open an issue or submit a pull request.  


[View on GitHub](https://github.com/baixiaoshengofficial/ProxyCli)

## License 

This project is licensed under the MIT License.  

See [LICENSE](LICENSE) for more information.  
