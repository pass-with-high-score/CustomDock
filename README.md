# CustomDock

A powerful iOS dock customization tweak for jailbroken devices.

## Features

### Dock Background
- **Transparent Dock** — Remove the dock background entirely
- **Hide Dock** — Hide the dock completely
- **Custom Color** — Set any color via hex code with adjustable opacity
- **Blur Intensity** — Control the blur level behind the dock (0–100%)
- **Corner Radius** — Adjust the dock's corner radius

### Icons
- **Icon Scale** — Resize dock icons (50%–150%)
- **Hide Labels** — Remove icon labels from dock apps

### Behavior
- **Disable Bounce** — Remove the bounce animation when launching apps
- **Hide in Landscape** — Automatically hide the dock in landscape orientation

### Settings
- Live preview with your actual dock apps
- All changes apply instantly (no respring needed for most settings)
- Respring button built-in

## Compatibility

- **iOS**: 14.0+
- **Jailbreak**: Dopamine (rootless)
- **Architecture**: arm64, arm64e

## Installation

### From .deb
1. Download the latest `.deb` from [Releases](https://github.com/pass-with-high-score/CustomDock/releases)
2. Install via Sileo or Filza
3. Respring

### Build from source
```bash
git clone https://github.com/pass-with-high-score/CustomDock.git
cd CustomDock
make clean && make package
```

To build release:
```bash
make clean && make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless
```

## Dependencies

- **PreferenceLoader** (>= 2.2.3)
- **MobileSubstrate**

## License

MIT
