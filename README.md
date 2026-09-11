English [中文](https://github.com/baixiaoshengofficial/ProxyCli/blob/main/README_CN.md)
# Proxy Management Script

A lightweight, powerful proxy management script for Bash and Zsh, onekey config  http_proxy,https_proxy,socks5_proxy,all_proxy by cli.

## Features

- 🚀 Start/stop/toggle proxy settings with single commands  
- 🔍 Auto-detect HTTP and SOCKS5 proxies from local listeners
- 📊 Detailed proxy status information  
- 🌐 Test internet and proxy connections  
- ⚙️ Set custom proxy address  
- 🔄 Toggle proxy status  

## Installation 

### One-line Install 

```bash
bash <(curl -sSL baixiaosheng.de/proxycli) && source "$HOME/.proxycli/src/proxy-setup.sh"
```

The `source` step loads the installed or updated commands into the current shell. Without it, an existing terminal continues using the previously loaded functions until restarted.

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

3. Reload your shell:  

   ```bash
   source ~/.zshrc  # or source ~/.bashrc
   ```

## Usage 

| Command  | Description| Example |
|----------------|-------------------|---------------|
| `pstart`       | Enable proxy<br> | `pstart` |
| `pscan`        | Force a new proxy scan and enable it<br> | `pscan` |
| `pstop`        | Disable proxy<br> | `pstop` |
| `ptoggle`      | Toggle proxy<br> | `ptoggle` |
| `pstatus`      | Show proxy status<br> | `pstatus` |
| `pset`         | Set a custom HTTP/SOCKS proxy<br> | `pset username:password@server:port` |
| `pset --auto`  | Return to automatic detection<br> | `pset --auto` |
| `pports`       | Show or change scan ports<br> | `pports 7890 1080 8080` |
| `phelp`        | Show help<br> | `phelp` |

## Proxy Detection

`pstart` is passive: it reports and checks each cached local endpoint, then reuses it when valid. If the cached or default ports are unavailable, it automatically scans again. `pscan` is active: it always performs a fresh scan and enables the result. Scan progress shows the candidate list, current port, pending protocols, and detected results. A scan prioritizes common proxy processes, checks the configured candidate ports, and finally checks other local listeners. Run `pstatus` separately for full connectivity checks.

The defaults are `7890 7891 7892 7893 7897 8888 8080`. Change them for the current shell when needed:

```bash
pports 7890 1080 8080
```

Run `pports` to show the current list or `pports --reset` to restore the defaults. Use `pset host:port` to bypass detection, or `pset --auto` to return to automatic mode.

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
