# Changelog

All notable changes to the BBR Optimization Script will be documented in this file.

## [1.1.0] - 2025-12-07
### Changed
- **Localization:** Updated interface, logs, and menu to Chinese.
- **Compatibility:** `uninstall.sh` now supports removing both English and Chinese configuration blocks.

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
