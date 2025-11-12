# SmartThings Gree Air Conditioner Driver - AI Coding Instructions

## Project Overview
This is a Samsung SmartThings Edge driver for Gree air conditioners using the ME31-00/C7 WiFi dongle module. The driver enables local control of Gree AC units through SmartThings without cloud dependencies.

## References
- **Gree WiFi Protocol Reverse Engineering**: https://github.com/bekmansurov/gree-hvac-protocol
  *(Use for protocol implementation, message formats, and encryption details)*
- **Gree App and Universal Wifi Installation**: https://www.greecomfort.com/assets/documents/resource-materials/wifi-info/gree-wifi-app-installation-and-operation.pdf?utm_source=chatgpt.com
  *(Reference for device capabilities and expected behavior)*
- **SmartThings LAN Edge Driver Guide**: https://developer.smartthings.com/docs/devices/hub-connected/lan/?utm_source=chatgpt.com
  *(Essential for Edge driver patterns and SmartThings integration)*
- **Forum Discussion**: https://community.home-assistant.io/t/open-source-gree-wifi-module-replacement/896581/46?page=3
  *(Real-world implementation insights and troubleshooting)*
- Gree HVAC API Communitity Documentation: https://qwici.github.io/gree-hvac-api/docs/client/connecting
- Gree API Community Reverse Engineer: https://github.com/tomikaa87/gree-remote


## Architecture & Key Components

### Driver Structure
- **`src/init.lua`** - Main driver entry point, device lifecycle management
- **`src/gree_protocol.lua`** - Gree WiFi protocol implementation (UDP communication)
- **`src/device_handler.lua`** - SmartThings device command handlers and capability mappings
- **`profiles/`** - Device profiles defining capabilities and metadata
- **`config/`** - Driver configuration and device fingerprints

### Protocol Implementation
- **Communication**: UDP broadcasts on port 7000 for discovery, port 7001 for commands
- **Encryption**: AES-128-ECB with PKCS7 padding, then Base64 encoding
  - **Generic Key**: `a3K8Bx%2r8Y7#xDh` (used for discovery responses and bind requests)
  - **Device Key**: Unique per device, obtained from bind response
- **Message Format**: JSON payloads with `t` (type), `i` (device info), `uid`, `cid`, `tcid`, `pack` fields
- **Device Binding**: CRITICAL - Bind requests must be sent as encrypted pack messages, not plain JSON
  - Device may already be bound to Gree+ app (common scenario)
  - If already bound, device will reject new bind requests
  - Solution: Either unbind from app first, or extract key from Gree cloud API

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
- **Device Scan**: Broadcast `{"t":"scan"}` to discover units (response is encrypted with generic key)
- **Binding**: Must send encrypted pack with `{"mac":"<mac>","t":"bind","uid":0}` inside
  - Wrap in pack structure: `{"cid":"app","i":1,"pack":"<encrypted>","t":"pack","tcid":"<mac>","uid":0}`
  - Encrypt inner JSON with generic key before sending
  - Device responds with encrypted pack containing unique device key
  - **IMPORTANT**: Device will ignore bind if already bound to Gree+ app
- **Status Query**: `{"cols":["Pow","Mod","SetTem","WdSpd"],"mac":"<mac>","t":"status"}`
- **Commands**: Pack values array corresponds to cols array indices
- **Multi-Split Systems**: Discovery response includes `subCnt` field for number of sub-units
  - Each sub-unit has unique MAC in format: `<sub_id>@<main_mac>` (e.g., `e137811d0000000@c039379a2dc9`)
  - **CRITICAL**: Use only the prefix (before @) in "sub" field: `{"opt":["Pow"],"p":[1],"sub":"e137811d0000000","t":"cmd"}`
  - Without sub field, commands may fail or control wrong unit
  - Each sub-unit must be treated as separate device in SmartThings

### Handling Already-Bound Devices
If device is bound to Gree+ app (common scenario):
1. **Option A**: Unbind from app (user must remove device from Gree+ app first)
2. **Option B**: Extract key from Gree cloud API (requires OAuth authentication)
3. **Option C**: User manually provides encryption key (advanced users only)

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

## Security & Configuration
- **NEVER hardcode**: IP addresses, MAC addresses, or encryption keys in source code
- **Use device preferences**: All device-specific data must be configurable via SmartThings device settings
- **Gitignore protection**: Test files and personal data are excluded from git
- **Encryption keys**: Generated during binding, stored in device state, never committed to repo
- **Configuration template**: See `CONFIG_TEMPLATE.md` for user-facing setup guide

## External Dependencies
- **LuaSocket** for UDP networking (available in ST Edge runtime)
- **lua-cjson** for JSON encoding/decoding
- Custom AES implementation (Gree uses non-standard padding)