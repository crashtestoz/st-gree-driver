# Configuration Template for SmartThings Gree AC Driver

## Device Discovery (Automatic)
The driver will automatically discover Gree AC devices on your local network via UDP broadcast.

## Required Settings (Set in SmartThings App)

### After Device Discovery
When a device is discovered, you'll need to configure:

1. **Device IP Address** (auto-detected but can be manually set)
   - Example: `10.0.0.164`
   - Used for: Direct UDP communication

2. **Main MAC Address** (auto-detected from discovery)
   - Example: `c039379a2dc9`
   - Used for: Device identification and binding

3. **Encryption Key** (obtained automatically during binding)
   - Format: 16-character string
   - Example: `5Gh8Jk1Mn4Pq7St0`
   - Note: Automatically saved after successful binding
   - Can be manually entered if device is already bound to Gree+ app

### For Multi-Split Systems

4. **Sub-Unit MAC** (for each AC unit)
   - Living AC Example: `e137811d0000000`
   - Bedroom AC Example: `8f917e1d0000000`
   - Note: Discovered automatically, but can check in Gree+ app

### Optional Settings

5. **Polling Interval** (seconds)
   - Default: `30`
   - Range: `10-300`
   - Used for: Status update frequency

6. **Temperature Unit**
   - Options: `Celsius` or `Fahrenheit`
   - Default: `Celsius`

## Getting Your Encryption Key

### Option 1: Automatic Binding (Recommended)
1. Remove device from Gree+ app (if previously bound)
2. Add device in SmartThings
3. Driver automatically binds and saves encryption key

### Option 2: Manual Entry (If Already Bound)
If your device is already bound to Gree+ app:
1. Keep device in Gree+ app
2. Extract key from Gree cloud API (requires OAuth - see documentation)
3. Manually enter key in device settings

### Option 3: From Gree+ App
Check device details in Gree+ mobile app:
- Open device settings
- Look for MAC address (shows format: `<sub-id>@<main-mac>`)
- Sub-unit MAC is the prefix before `@`

## Security Notes

⚠️ **IMPORTANT**: Never share your encryption key publicly
- The key allows full control of your AC unit
- Store securely if backing up configuration
- Regenerate by re-binding if compromised

## Example Configuration

```yaml
# This is what SmartThings will store (not in git)
device:
  main_mac: "c039379a2dc9"
  ip_address: "10.0.0.164"
  encryption_key: "5Gh8Jk1Mn4Pq7St0"  # AUTO-GENERATED - DO NOT SHARE
  
  # For multi-split systems
  sub_units:
    - name: "Living AC"
      sub_mac: "e137811d0000000"
    - name: "Bedroom AC"
      sub_mac: "8f917e1d0000000"
  
  # Optional settings
  polling_interval: 30
  temperature_unit: "celsius"
```

## DO NOT COMMIT
- Any files containing actual encryption keys
- Device-specific IP addresses
- MAC addresses of your devices
- Test scripts with hardcoded credentials