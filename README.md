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

| Command | Description |
|---------|-------------|
| `pstart` | Enable proxy variables in this shell |
| `pscan` | Scan local proxies and enable the result |
| `pstop` | Restore this shell's previous proxy environment |
| `ptoggle` | Start or stop ProxyCli |
| `pstatus` | Show shell proxy variables and test connectivity |
| `pset` | Show current settings |
| `phelp` | Show help |

### Prompt indicator

After `pstart` or a successful `pscan`, a rocket appears before the existing prompt:

```text
🚀 root@host:~#
```

`pstop` removes the rocket. `ptoggle` shows or removes it as the proxy starts or stops. The icon means ProxyCli's proxy variables are active in this shell; run `pstatus` to check connectivity. Saving settings with `pset` keeps the current indicator until you apply them.

## Settings

`pset` saves settings for the current shell session. Run `pstart` to apply them. An active proxy keeps its current environment until you apply the new settings.

### Proxy address

```bash
pset --address 127.0.0.1:7890  # Set proxy address
pset --address auto            # Use automatic detection
```

Run `pset --address` to show the address setting.

Replace the host and port as needed. One address is used for both HTTP and SOCKS5. If they use separate addresses, put HTTP first and SOCKS5 second:

```bash
pset --address 127.0.0.1:7890 127.0.0.1:1080
```

Addresses require a host and a port from `1` to `65535`. Use brackets around IPv6 hosts, for example `'[::1]:7890'`. HTTP addresses accept `http://` or `https://`; a separate SOCKS address accepts `socks5://` or `socks5h://`. Proxy credentials are hidden in command output.

### Scan ports

```bash
pset --ports 7890 1080  # Set scan ports
pset --ports auto      # Restore default ports
```

Run `pset --ports` to show scan ports, or `pset` to show all settings. The defaults are `7890 7891 7892 7893 7897 8888 8080`.

## Proxy Detection

`pstart` applies pending settings first: a manual address is used directly; automatic mode runs a new scan. With no pending settings, it reuses a cached local proxy whose ports are still listening or existing proxy environment variables, and scans when needed. `pscan` always performs a fresh local scan and enables the result; a successful scan switches the address setting to automatic detection.

Scans try cached ports first, followed by common proxy process ports, configured ports, and other local listeners. Progress shows the candidates, current port, protocols, and results. A failed scan keeps the previous address and shell environment.

`pstart` confirms that proxy variables were set. Run `pstatus` to test connectivity to `PROXYCLI_TEST_URL` (default: `https://example.com/`). It checks the actual shell variables, including externally configured proxies. `ACTIVE` / `INACTIVE` describes whether ProxyCli is managing the shell; the connection results are reported separately.

`pstart` and `pscan` export `http_proxy`, `https_proxy`, `all_proxy`, and their uppercase variants in the current shell. Programs launched from that shell inherit these variables and can use them if they support proxy environment variables. `pstop` restores the previous shell environment. Other terminals, already running programs, and independently launched services keep their own environment.

Sourcing the runtime loads the commands; it does not automatically enable a proxy. Settings and pending changes survive reloading the runtime in the same shell session. `pstatus` shows the active environment and a reminder when settings are pending. A failed application keeps the active environment and leaves the new settings pending for another attempt. Run `pset` to view the configured settings.

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
