# SmartThings Gree Air Conditioner Driver

A Samsung SmartThings Edge driver for Gree air conditioners using the ME31-00/C7 WiFi dongle module.

## Features
- **Local control** without cloud dependencies
- **Auto-discovery** of Gree AC units on local network
- **Multi-split support** - Control multiple AC units independently
- **Version 1.0**: Basic ON/OFF control with Mode and Temperature display

## Supported Devices
- Gree air conditioners with ME31-00/C7 WiFi module
- Single and multi-split systems
- Tested with various Gree models

## Installation

### Prerequisites
- Samsung SmartThings Hub (with Edge driver support)
- Gree AC with WiFi module on same local network
- SmartThings CLI (for driver installation)

### Steps
1. Package the driver:
   ```bash
   tar -czf gree-driver.tar.gz src/ profiles/ config/ fingerprints.yml
   ```
2. Install via SmartThings CLI or Developer Workspace
3. Add device in SmartThings app
4. Configure device settings (see `CONFIG_TEMPLATE.md`)

## Configuration
All device-specific information (IP addresses, MAC addresses, encryption keys) is configured through SmartThings device settings. See `CONFIG_TEMPLATE.md` for detailed configuration guide.

## Version 1.0 Features
- ✅ Power ON/OFF control
- ✅ Display current Mode (Auto, Cool, Dry, Fan, Heat)
- ✅ Display set temperature and current temperature
- ✅ Multi-split system support with individual unit control

## Planned Features (Future Versions)
- Temperature setpoint control
- Mode selection
- Fan speed control
- Advanced features (Quiet mode, Turbo, Swing control)

## Security
⚠️ **Important**: Never commit encryption keys, IP addresses, or MAC addresses to git. All sensitive data is configured via SmartThings device settings and excluded from version control.

## Development
See `IMPLEMENTATION_SUMMARY.md` for comprehensive development guidance and protocol details.

## Protocol Documentation
Based on reverse-engineered Gree WiFi protocol:
- AES-128-ECB encryption
- UDP communication on port 7000
- Multi-split system support
- Protocol references:
  - [Gree HVAC Protocol](https://github.com/tomikaa87/gree-remote)
  - [Gree Protocol Reverse Engineering](https://github.com/bekmansurov/gree-hvac-protocol)
  - [SmartThings LAN Edge Driver Guide](https://developer.smartthings.com/docs/devices/hub-connected/lan/)

## License
[Your License Here]

## Contributing
Contributions welcome! Please ensure no sensitive data (keys, IPs, MACs) is included in pull requests.