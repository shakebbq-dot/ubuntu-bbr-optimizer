# Changelog

All notable changes to the BBR Optimization Script will be documented in this file.

## [1.1.0] - 2025-12-07
### Changed
- **Localization:** Updated interface, logs, and menu to Chinese.
- **Compatibility:** `uninstall.sh` now supports removing both English and Chinese configuration blocks.

## [2.0.0] - 2026-04-21
### Changed
- **Cross-distro:** Refactored to feature-gated tuning (kernel 3.10+) and sysctl.d/limits.d based config.
- **Idempotency & rollback:** Writes managed config files and supports clean restore/uninstall.
- **Security:** Removed insecure download guidance and switched XanMod repo URL to HTTPS.
### Added
- **Smart selection:** Auto congestion control selection (`bbr → cubic → reno`).
- **Adaptive tuning:** Optional RTT probe and `autotune` loop.
- **Observability:** Basic status monitoring and logrotate integration.
- **Tests & docs:** Added unit/stress scripts and deployment guide; added remediation and compatibility reports.

## [1.0.0] - 2025-12-07

### Added
- **Core Functionality:**
    - Interactive menu interface.
    - Standard BBR enablement for Kernel 4.9+.
    - XanMod Kernel installation support (Stable branch).
    - Switcher for CUBIC and Reno algorithms.
- **System Optimization:**
    - `sysctl.conf` tuning for high-throughput/low-latency.
    - File descriptor and connection limit increases.
    - Timezone configuration and NTP sync.
- **Safety:**
    - Automatic backup of `sysctl.conf` before edits.
    - Restore function to revert changes.
    - OS detection (Ubuntu 18.04/20.04/22.04).
- **Documentation:**
    - Comprehensive README with usage examples.
    - Uninstall script for clean removal.
