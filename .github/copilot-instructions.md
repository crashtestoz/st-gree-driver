# SmartThings Gree Air Conditioner Driver - AI Coding Instructions

## Project Overview
This is a Samsung SmartThings Edge driver for Gree air conditioners using the ME31-00/C7 WiFi dongle module. The driver enables local control of Gree AC units through SmartThings without cloud dependencies.

## References
- Gree WiFi Protocol Reverse Engineering: https://github.com/bekmansurov/gree-hvac-protocol
- Gree App and Universal Wifi Installation: https://www.greecomfort.com/assets/documents/resource-materials/wifi-info/gree-wifi-app-installation-and-operation.pdf?utm_source=chatgpt.com
- SmartThings LAN Edge Driver Guide: https://developer.smartthings.com/docs/devices/hub-connected/lan/?utm_source=chatgpt.com
- Forum: https://community.home-assistant.io/t/open-source-gree-wifi-module-replacement/896581/46?page=3

## Architecture & Key Components

### Driver Structure
- **`src/init.lua`** - Main driver entry point, device lifecycle management
- **`src/gree_protocol.lua`** - Gree WiFi protocol implementation (UDP communication)
- **`src/device_handler.lua`** - SmartThings device command handlers and capability mappings
- **`profiles/`** - Device profiles defining capabilities and metadata
- **`config/`** - Driver configuration and device fingerprints

### Protocol Implementation
- **Communication**: UDP broadcasts on port 7000 for discovery, port 7001 for commands
- **Encryption**: AES encryption with device-specific keys (extracted from bind response)
- **Message Format**: JSON payloads with `t` (type), `i` (device info), `uid`, `cid`, `tcid`, `pack` fields
- **Device Binding**: Required handshake process before control commands

## SmartThings Edge Driver Patterns

### Capability Mapping
```lua
-- Use standard ST capabilities for AC functions
capabilities.thermostatCoolingSetpoint
capabilities.thermostatMode
capabilities.fanSpeed
capabilities.switch
```

### Device Lifecycle
1. **Discovery** - UDP broadcast scan for Gree devices
2. **Fingerprinting** - Match device via manufacturer/model in fingerprints
3. **Initialization** - Bind with device, establish encryption
4. **Command Handling** - Translate ST commands to Gree protocol
5. **Status Updates** - Poll device state and update ST capabilities

### Error Handling Conventions
- Use `log.error()` for protocol failures and network issues
- Implement retry logic for UDP packet loss (common with WiFi modules)
- Handle encryption key mismatches gracefully with re-binding

## Critical Implementation Details

### Gree Protocol Specifics
- **Device Scan**: Broadcast `{"t":"scan"}` to discover units
- **Binding**: Send `{"mac":"<mac>","t":"bind","uid":0}` to get encryption key
- **Status Query**: `{"cols":["Pow","Mod","SetTem","WdSpd"],"mac":"<mac>","t":"status"}`
- **Commands**: Pack values array corresponds to cols array indices

### WiFi Module Quirks (ME31-00/C7)
- Responds inconsistently to rapid commands - implement 500ms delays
- May drop UDP packets under poor WiFi conditions
- Requires periodic re-binding if idle for extended periods

### SmartThings Integration Points
- **Device Addition**: Handle both manual addition and automatic discovery
- **Health Monitoring**: Implement regular connectivity checks via status polling
- **Preferences**: Expose polling intervals, temperature units via device preferences

## Development Workflow

### Testing Commands
```bash
# Package driver for testing
tar -czf gree-driver.tar.gz src/ profiles/ config/ fingerprints.yml
# Install via SmartThings CLI or Developer Workspace
```

### Debugging
- Use `log.debug()` extensively for UDP packet tracing
- Test with multiple AC units to verify multi-device support
- Validate encryption/decryption with known Gree mobile app packets

### Key Files to Reference
- **`profiles/gree-ac.yml`** - Complete capability definitions and UI layout
- **`fingerprints.yml`** - Device identification patterns for auto-discovery
- **`src/crypto.lua`** - AES implementation for Gree protocol encryption

## Common Pitfalls
- Don't assume immediate UDP responses - implement proper timeouts
- Gree temperature values are in Celsius internally, convert for display preferences  
- Status polling frequency affects battery life of SmartThings hub - balance responsiveness vs efficiency
- Handle MAC address formats consistently (uppercase, no separators for Gree protocol)

## External Dependencies
- **LuaSocket** for UDP networking (available in ST Edge runtime)
- **lua-cjson** for JSON encoding/decoding
- Custom AES implementation (Gree uses non-standard padding)