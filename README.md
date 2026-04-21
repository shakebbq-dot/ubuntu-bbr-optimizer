# Ubuntu BBR Optimization & Management Script (Ubuntu BBR 加速与优化脚本)

[English](#english) | [中文](#chinese)

<a name="english"></a>
## English Documentation

A comprehensive Bash script to manage TCP congestion control and system network optimizations across major Linux distributions (kernel 3.10+).

### Features
*   **Cross-Distro:** Ubuntu/Debian/CentOS/RHEL/Fedora/Arch/openSUSE (best-effort, kernel feature-gated).
*   **Smart CC Selection:** Auto-selects the best available congestion control (`bbr` → `cubic` → `reno`).
*   **Sysctl.d Based:** Writes to `/etc/sysctl.d/99-bbr-optimizer.conf` (idempotent, removable).
*   **Limits.d Based:** Writes to `/etc/security/limits.d/99-bbr-optimizer.conf` when available.
*   **RTT-Adaptive Buffers:** Optional RTT probe to adapt `rmem/wmem` sizing.
*   **Rollback:** `restore/uninstall` removes managed config files.

### Usage

1.  **Download & Permissions:**
    ```bash
    curl -fsSL "https://raw.githubusercontent.com/shakebbq-dot/ubuntu-bbr-optimizer/main/bbr_install.sh" -o bbr_install.sh && chmod +x bbr_install.sh && sudo ./bbr_install.sh
    ```
2.  **Interactive Mode:** Run without arguments to see the menu.
3.  **Batch Mode:**
    *   `./bbr_install.sh --enable-bbr` (Enable Standard BBR)
    *   `./bbr_install.sh --install-xanmod` (Install XanMod Kernel)
    *   `./bbr_install.sh --optimize` (Apply System Tweaks)
    *   `./bbr_install.sh enable --cc=auto --qdisc=auto --rtt-host=1.1.1.1` (Smart apply with RTT probe)
    *   `./bbr_install.sh restore` (Remove managed optimizations)

---

<a name="chinese"></a>
## 中文说明 (Chinese Documentation)

这是一个面向多种 Linux 发行版（内核 3.10+）的 TCP 拥塞控制管理与系统网络优化脚本。

### 主要功能
1.  **多发行版支持**：
    *   在不同发行版上按内核能力进行特性降级（例如没有 `bbr` 时自动切换到 `cubic/reno`）。
    *   **XanMod 内核**：仅在 Ubuntu/Debian 上提供安装入口（需重启）。
2.  **算法切换**：
    *   支持在 BBR、CUBIC（默认）、Reno 等算法间自由切换。
3.  **系统优化**：
    *   **网络参数**：写入 `/etc/sysctl.d/99-bbr-optimizer.conf`（幂等、可回滚）。
    *   **资源限制**：写入 `/etc/security/limits.d/99-bbr-optimizer.conf`（若系统支持）。
    *   **自适应**：可选 RTT 探测，根据延迟自动调整 `rmem/wmem` 上限。
4.  **安全保障**：
    *   使用独立配置文件，卸载时直接移除并重载 sysctl。
    *   提供 `restore/uninstall` 路径快速回滚。

### 使用方法

#### 1. 安装与运行
下载脚本后，赋予执行权限并运行：

```bash
curl -fsSL "https://raw.githubusercontent.com/shakebbq-dot/ubuntu-bbr-optimizer/main/bbr_install.sh" -o bbr_install.sh && chmod +x bbr_install.sh && sudo ./bbr_install.sh
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
*   智能应用（自动选择算法）: `./bbr_install.sh enable --cc=auto --qdisc=auto --rtt-host=1.1.1.1`
*   回滚卸载: `./bbr_install.sh restore` 或 `./uninstall.sh`

### 注意事项
*   本脚本需要 root 权限运行。
*   安装新内核需要重启服务器才能生效。
*   脚本会自动创建配置备份，但建议在生产环境中操作前自行备份重要数据。
