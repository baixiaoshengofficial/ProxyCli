中文 [English](README.md)
# 代理管理脚本

适用于 Bash 和 Zsh 的轻量级代理管理脚本，通过命令管理当前 shell 的 HTTP 和 SOCKS5 代理环境变量。

## 功能

- 🚀 一键启动、停止或切换当前 shell 的代理变量
- 🔍 从本地监听端口自动识别 HTTP 和 SOCKS5 代理
- 📊 查看代理变量并检查连接
- ⚙️ 通过 `pset` 统一设置代理地址和扫描端口

## 安装方法

### 一行命令安装

```bash
bash <(curl -sSL baixiaosheng.de/proxycli) && source "$HOME/.proxycli/src/proxy-setup.sh"
```

安装脚本会配置 Bash 的普通终端与 SSH 登录配置文件，或 Zsh 的启动文件。`source` 用于将安装或更新后的命令立即加载到当前 shell；新终端会自动加载。

GitHub Raw 备用方式：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/baixiaoshengofficial/ProxyCli/main/install.sh) && source "$HOME/.proxycli/src/proxy-setup.sh"
```

### 一行命令卸载

```bash
bash <(curl -sSL baixiaosheng.de/proxycli) --uninstall
```

### 手动安装

1. 克隆仓库:
   ```bash
   git clone https://github.com/baixiaoshengofficial/ProxyCli.git
   cd ProxyCli
   ```

2. 运行安装脚本:
   ```bash
   bash install.sh
   ```

3. 将命令加载到当前 shell:
   ```bash
   source "$HOME/.proxycli/src/proxy-setup.sh"
   ```

## 使用方法

| 命令 | 说明 |
|------|------|
| `pstart` | 启用当前 shell 的代理变量 |
| `pscan` | 扫描本地代理并启用结果 |
| `pstop` | 恢复当前 shell 原有代理环境 |
| `ptoggle` | 启动或停止 ProxyCli |
| `pstatus` | 查看 shell 代理变量并检查连接 |
| `pset` | 查看当前设置 |
| `phelp` | 查看帮助 |

## 设置

`pset` 保存当前 shell 会话的设置，执行 `pstart` 后生效。代理已启动时，应用新设置前会继续使用原有环境。

### 代理地址

```bash
pset --address 127.0.0.1:7890  # 设置代理地址
pset --address auto            # 使用自动识别
```

执行 `pset --address` 查看地址设置。

按需替换主机和端口。一个地址同时用于 HTTP 和 SOCKS5。如果两者地址不同，先写 HTTP，再写 SOCKS5：

```bash
pset --address 127.0.0.1:7890 127.0.0.1:1080
```

地址必须包含主机和端口，端口范围为 `1–65535`。IPv6 主机需要方括号，例如 `'[::1]:7890'`。HTTP 地址可带 `http://` 或 `https://`；单独指定的 SOCKS 地址可带 `socks5://` 或 `socks5h://`。命令输出会隐藏代理认证信息。

### 扫描端口

```bash
pset --ports 7890 1080  # 设置扫描端口
pset --ports auto      # 恢复默认端口
```

执行 `pset --ports` 查看扫描端口，执行 `pset` 查看全部设置。默认端口为 `7890 7891 7892 7893 7897 8888 8080`。

## 代理识别

`pstart` 优先应用待生效的设置：手动地址直接启用，自动模式重新扫描。没有待应用设置时，会复用仍在监听的本地代理缓存或已有的代理环境变量，必要时扫描。`pscan` 每次都会重新扫描本地代理并启用结果；扫描成功后，地址设置切换为自动识别。

扫描顺序为缓存端口、常见代理进程端口、配置的候选端口、其他本地监听端口。进度会显示候选列表、当前端口、协议和结果。扫描失败时保留原有地址和 shell 环境。

`pstart` 成功表示代理变量已设置。执行 `pstatus` 可检查到 `PROXYCLI_TEST_URL` 的连接（默认 `https://example.com/`）。它检测当前 shell 的实际变量，也会显示外部设置的代理。`ACTIVE` / `INACTIVE` 表示 ProxyCli 是否正在管理当前 shell，连接是否可用会单独显示。

`pstart` 和 `pscan` 会在当前 shell 中导出 `http_proxy`、`https_proxy`、`all_proxy` 及其大写变量。从该 shell 启动的程序会继承这些变量，支持代理环境变量的程序可据此使用代理。`pstop` 恢复当前 shell 原有的环境。其他终端、已经运行的程序和独立启动的服务保留各自的环境。

加载运行脚本只会提供命令，不会自动启用代理。同一 shell 会话内重新加载脚本，会保留设置和待应用的更改。`pstatus` 显示正在使用的环境，并提示是否有待应用设置。应用失败时保留当前环境，新设置保持待应用状态，可再次尝试。执行 `pset` 查看已配置的设置。

## 卸载方法

```bash
bash install.sh uninstall
```

## 支持环境

- ✔️ macOS (Terminal, iTerm2)
- ✔️ Linux (Ubuntu, Debian, CentOS 等)
- ✔️ Windows Subsystem for Linux (WSL)

## 项目结构

```
ProxyCli/
├── LICENSE                 # MIT 许可证
├── README.md               # 英文文档
├── README_CN.md            # 中文文档
├── install.sh               # 安装脚本
├── src/
│   └── proxy-setup.sh      # 核心代理管理脚本
└── tests/
    └── test_proxy_setup.sh # 离线 shell 回归测试
```

## 贡献

欢迎提交 issue 或 pull request 来改进本项目。

[在 GitHub 上查看](https://github.com/baixiaoshengofficial/ProxyCli)

## 许可证

本项目基于 MIT 许可证。查看 [LICENSE](LICENSE) 文件了解更多信息。
