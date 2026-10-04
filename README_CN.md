# ProxyCli

[English](README.md)

适用于 macOS、Linux 和 WSL 的轻量级 Bash/Zsh HTTP/SOCKS5 代理管理工具。

## 安装或更新

```bash
bash <(curl -fsSL baixiaosheng.de/proxycli) && source "$HOME/.proxycli/src/proxy-setup.sh"
```

需要 `curl`。安装脚本会配置 Bash 启动文件（包含 SSH 登录终端）或 Zsh 启动文件。`source` 将安装后的版本加载到当前 shell，新终端会自动加载。加载命令不会启动代理。

<details>
<summary>GitHub 备用方式和手动安装</summary>

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/baixiaoshengofficial/ProxyCli/main/install.sh) && source "$HOME/.proxycli/src/proxy-setup.sh"
```

也可以克隆仓库后安装：

```bash
git clone https://github.com/baixiaoshengofficial/ProxyCli.git
cd ProxyCli
bash install.sh
source "$HOME/.proxycli/src/proxy-setup.sh"
```

</details>

## 快速使用

```bash
pstart   # 启用代理（默认自动识别）
pstatus  # 检查状态和连接
pstop    # 恢复原有代理环境
```

ProxyCli 启动后，提示符前会显示图标，默认为 🚀；`pstop` 会移除图标：

```text
🚀 root@host:~#
```

| 命令 | 作用 |
| --- | --- |
| `pstart` | 启用当前 shell 的代理 |
| `pscan` | 重新扫描本地代理并启用结果 |
| `pstop` | 恢复原有代理环境 |
| `ptoggle` | 启动或停止 ProxyCli |
| `pstatus` | 查看代理状态并检查连接 |
| `pset` | 查看全部设置 |
| `phelp` | 查看帮助 |

## 设置

`pset` 保存**当前 shell 会话**的设置，执行 `pstart` 后生效。应用之前，正在使用的代理和图标保持原样。

| 设置 | 设置值 | 恢复默认 |
| --- | --- | --- |
| 代理地址 | `pset --address 127.0.0.1:7890` | `pset --address auto` |
| 扫描端口 | `pset --ports 7890 1080` | `pset --ports auto` |
| 提示符图标 | `pset --indicator 🌐` | `pset --indicator auto` |

省略值可查看对应设置：`pset --address`、`pset --ports`、`pset --indicator`。

一个地址同时用于 HTTP 和 SOCKS5。两者地址不同时，先写 HTTP，再写 SOCKS5：

```bash
pset --address 127.0.0.1:7890 127.0.0.1:1080
pstart
```

- 地址格式为 `host:port`，端口范围为 `1–65535`。IPv6 地址需要引号和方括号：`'[::1]:7890'`。HTTP 可带 `http://` 或 `https://`；单独指定的 SOCKS 地址可带 `socks5://` 或 `socks5h://`。输出会隐藏代理认证信息。
- 默认扫描端口：`7890 7891 7892 7893 7897 8888 8080`。
- 图标支持不含空格或提示符转义的 emoji 或符号，包括 `👩‍💻` 等组合 emoji。emoji 无需加引号，默认图标为 🚀。仅修改图标不会强制重新扫描代理。

同一会话内重新加载脚本会保留设置；设置不会跨终端或 shell 重启保存。

## 工作方式

### 启动与扫描

`pstart` 直接使用手动地址。自动模式下，待应用的地址或扫描端口设置会触发扫描；否则，优先复用端口仍在监听的已识别代理，或已有代理环境变量，必要时再扫描。

`pscan` 每次都会扫描并启用结果，然后将地址设置切换为自动识别。扫描顺序为缓存端口、代理进程端口、配置端口、其他本地监听端口。扫描失败时保留正在使用的环境，待应用设置可再次尝试。

### 状态与连接

图标和 `ACTIVE` / `INACTIVE` 表示 ProxyCli 是否正在管理当前 shell。`pstatus` 检查实际代理变量，包括外部设置的代理，并分别报告直连、HTTP 和 SOCKS5 的连接结果。测试地址默认为 `https://example.com/`，可通过 `PROXYCLI_TEST_URL` 更改。有待应用设置时会提示执行 `pstart`。

### 生效范围

`pstart` 和 `pscan` 导出 `http_proxy`、`https_proxy`、`all_proxy` 及其大写变量。从当前 shell 启动的程序会继承这些变量，支持它们的程序可据此使用代理。其他终端、已运行的程序和独立启动的服务保留各自的环境。`pstop` 恢复 ProxyCli 启动前的代理与 `no_proxy` 变量。

## 卸载

```bash
bash <(curl -fsSL baixiaosheng.de/proxycli) --uninstall
```

在本地仓库中也可执行 `bash install.sh uninstall`。卸载后重启 shell，移除已加载的命令。

## 开发

运行逻辑位于 `src/proxy-setup.sh`，安装和 shell 启动配置位于 `install.sh`。修改后执行：

```bash
bash -n install.sh
bash -n src/proxy-setup.sh
bash tests/test_proxy_setup.sh
bash install.sh --help
```

测试无需联网。欢迎提交改进，请保持两份文档与命令行为一致。

[MIT 许可证](LICENSE) · [GitHub](https://github.com/baixiaoshengofficial/ProxyCli)
