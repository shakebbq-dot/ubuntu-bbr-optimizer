# Ubuntu BBR Optimization & Management Script (Ubuntu BBR 加速与优化脚本)

[English](#english) | [中文](#chinese)

<a name="english"></a>
## English Documentation

A comprehensive Bash script to manage TCP BBR congestion control and system network optimizations on Ubuntu 18.04, 20.04, and 22.04 LTS.

### Features
*   **Multi-Version Support:** Standard BBR (Native) and XanMod Kernel (Advanced BBR/CAKE).
*   **Algorithm Switching:** Easily switch between BBR, CUBIC, and Reno.
*   **System Optimization:** Auto-tune `sysctl`, file limits, and memory settings.
*   **Safety:** Auto-backups and easy uninstallation.

### Usage

1.  **Download & Permissions:**
    ```bash
    wget -N --no-check-certificate "https://raw.githubusercontent.com/shakebbq-dot/ubuntu-bbr-optimizer/main/bbr_install.sh" && chmod +x bbr_install.sh && sudo ./bbr_install.sh
    ```
2.  **Interactive Mode:** Run without arguments to see the menu.
3.  **Batch Mode:**
    *   `./bbr_install.sh --enable-bbr` (Enable Standard BBR)
    *   `./bbr_install.sh --install-xanmod` (Install XanMod Kernel)
    *   `./bbr_install.sh --optimize` (Apply System Tweaks)

---

<a name="chinese"></a>
## 中文说明 (Chinese Documentation)

这是一个专为 Ubuntu 18.04/20.04/22.04 LTS 设计的 TCP BBR 拥塞控制管理与系统网络优化脚本。

### 主要功能
1.  **多版本支持**：
    *   **标准版 BBR**：在现有内核（4.9+）上启用原生 BBR。
    *   **XanMod 内核**：自动安装高性能 XanMod 内核（支持更高级的 BBRv2/CAKE 算法，替代不稳定的魔改版内核）。
2.  **算法切换**：
    *   支持在 BBR、CUBIC（默认）、Reno 等算法间自由切换。
3.  **系统全方位优化**：
    *   **网络参数**：自动优化 `sysctl.conf`，提升高并发下的吞吐量。
    *   **资源限制**：提高文件描述符（`ulimit`）和最大连接数限制。
    *   **基础配置**：包含时区设置与时间同步。
4.  **安全保障**：
    *   修改配置前自动备份 `/etc/sysctl.conf`。
    *   提供独立卸载脚本，一键回滚。

### 使用方法

#### 1. 安装与运行
下载脚本后，赋予执行权限并运行：

```bash
wget -N --no-check-certificate "https://raw.githubusercontent.com/shakebbq-dot/ubuntu-bbr-optimizer/main/bbr_install.sh" && chmod +x bbr_install.sh && sudo ./bbr_install.sh
```

#### 2. 菜单功能说明
运行脚本后将显示以下菜单：
*   **1. Enable Standard BBR**: 启用标准 BBR 加速（推荐大多数用户使用）。
*   **2. Install XanMod Kernel**: 安装 XanMod 高性能内核（适合追求极致性能的用户，需重启）。
*   **3/4. Switch to CUBIC/Reno**: 切换回传统的拥塞控制算法。
*   **5. Apply System Optimizations**: 应用网络参数与系统资源优化。
*   **6. Configure Timezone**: 设置时区并同步时间。
*   **7. Restore/Uninstall**: 恢复默认设置。

#### 3. 常用命令（静默模式）
适用于自动化部署：
*   启用 BBR: `./bbr_install.sh --enable-bbr`
*   安装内核: `./bbr_install.sh --install-xanmod`
*   系统优化: `./bbr_install.sh --optimize`

### 注意事项
*   本脚本需要 root 权限运行。
*   安装新内核需要重启服务器才能生效。
*   脚本会自动创建配置备份，但建议在生产环境中操作前自行备份重要数据。
