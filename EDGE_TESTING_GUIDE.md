# SmartThings Edge Driver Testing Guide for Gree AC Driver

Based on: https://developer.smartthings.com/docs/devices/hub-connected/test-your-driver

## Testing Approach

The Gree AC driver uses **LAN (UDP) communication** which is different from Zigbee/Z-Wave devices. SmartThings integration testing framework is primarily designed for Zigbee/Z-Wave, but we can adapt the principles for LAN drivers.

### Testing Strategy

1. **Unit Tests** (Protocol Level) - Test Gree protocol functions directly
2. **Manual Testing** (Real Device) - Test on actual SmartThings Hub with real AC units  
3. **Integration Tests** (Optional) - Use SmartThings test framework if applicable to LAN drivers

## Current Status: Unit Testing Complete ✓

We've already performed extensive unit testing with real hardware:
- ✅ Discovery protocol tested
- ✅ Encryption/decryption validated
- ✅ Binding working
- ✅ ON/OFF commands working on both sub-units
- ✅ Multi-split addressing verified

## Next: Deploy to SmartThings Hub

### Prerequisites

1. **SmartThings CLI Installation**
   ```bash
   npm install -g @smartthings/cli
   ```

2. **Login to SmartThings**
   ```bash
   smartthings login
   ```

3. **List Your Hubs**
   ```bash
   smartthings edge:drivers:installed
   ```

### Deployment Steps

#### 1. Package the Driver
```bash
cd /Users/peter/Projects/st-gree-driver
./package.sh
```

This creates `gree-driver-v1.0.0.tar.gz`

#### 2. Install Driver to Hub

**Option A: SmartThings CLI**
```bash
# Package and upload
smartthings edge:drivers:package gree-driver-v1.0.0.tar.gz

# Install to your hub
smartthings edge:drivers:install
# Follow prompts to select hub
```

**Option B: Developer Workspace**
1. Go to https://smartthings.developer.samsung.com/workspace/projects
2. Create new project or open existing
3. Upload `gree-driver-v1.0.0.tar.gz`
4. Deploy to test hub
5. In SmartThings mobile app:
   - Go to Hub settings
   - Available Drivers
   - Find "Gree AC Driver"
   - Install

#### 3. View Live Logs
```bash
smartthings edge:drivers:logcat
```

This shows real-time logs from your driver running on the hub.

#### 4. Add Device in App

1. Open SmartThings mobile app
2. Tap "+" to add device
3. **Option A: Scan Nearby**
   - Let discovery run
   - Should find Gree devices on network
   
4. **Option B: Manual Add**
   - My Testing Devices
   - Gree Air Conditioner
   - Add manually

5. **Configure Device Settings**
   - Device IP: `10.0.0.164`
   - Device MAC: `c039379a2dc9`
   - Encryption Key: `5Gh8Jk1Mn4Pq7St0`
   - Sub-Unit MAC: `e137811d0000000` (for Living Room)

6. **Repeat for Second Unit**
   - Same IP, MAC, Key
   - Different Sub-Unit MAC: `8f917e1d0000000` (for Bedroom)

## Testing on Hub

### Basic Function Test

1. **Turn ON via SmartThings App**
   ```
   Expected: AC unit turns on physically
   Check logs: Should see "Turning device ON"
   ```

2. **Turn OFF via SmartThings App**
   ```
   Expected: AC unit turns off physically
   Check logs: Should see "Turning device OFF"
   ```

3. **Check Status Display**
   ```
   Expected: Mode and Temperature shown in app
   Check logs: Should see "Polling device status"
   ```

4. **Tap Refresh**
   ```
   Expected: Status updates immediately
   Check logs: Should see "Refreshing device status"
   ```

### Multi-Split Test

1. **Turn Living Room ON, Bedroom OFF**
   - Only Living Room should respond
   - Check logs for correct sub-unit MAC in commands

2. **Turn Bedroom ON, Living Room OFF**
   - Only Bedroom should respond

3. **Turn Both ON**
   - Both units respond

4. **Turn Both OFF**
   - Both units respond

### Monitoring Commands

**Watch Logs in Real-Time:**
```bash
smartthings edge:drivers:logcat --hub-address=<YOUR_HUB_IP>
```

**Filter for Errors:**
```bash
smartthings edge:drivers:logcat | grep ERROR
```

**Filter for Your Driver:**
```bash
smartthings edge:drivers:logcat | grep "Gree AC"
```

## Critical Issues to Fix Before Deployment

### 1. UDP Socket Implementation

**Current Issue:**
- Using `socket = require "socket"` (LuaSocket)
- DNS resolution error: "nodename nor servname provided, or not known"
- Workaround: netcat for testing

**SmartThings Edge Solution:**

SmartThings Edge drivers should use **cosock** (coroutine socket wrapper):

```lua
-- WRONG (current):
local socket = require "socket"

-- CORRECT (for Edge):
local cosock = require "cosock"
local socket = require "cosock.socket"
```

**Update Required in `gree_protocol.lua`:**

```lua
-- At the top of file, replace:
local socket = require "socket"

-- With:
local cosock = require "cosock"
local socket = require "cosock.socket"

-- UDP socket creation becomes:
local function create_udp_socket()
  local udp = socket.udp()
  if not udp then
    log.error("Failed to create UDP socket")
    return nil
  end
  
  udp:settimeout(5)  -- 5 second timeout
  return udp
end
```

**Why cosock?**
- Designed for SmartThings Edge coroutine environment
- Handles async I/O properly with SmartThings scheduler
- Prevents blocking the driver thread
- Compatible with Edge runtime

### 2. JSON Library

**Current:**
```lua
local json = require "dkjson"  -- May not be available in Edge
```

**SmartThings Edge:**
```lua
local json = require "st.json"  -- Built-in Edge JSON library
-- OR
local json = require "dkjson"  -- If included in your driver package
```

### 3. Log Module

**Current:**
```lua
local log = require "log"
```

**SmartThings Edge:**
```lua
local log = require "log"  -- This should work in Edge
-- Messages appear in: smartthings edge:drivers:logcat
```

## Integration Tests (Optional - Advanced)

The SmartThings test framework is primarily for Zigbee/Z-Wave, but we can create tests for our LAN driver:

### Create `test/integration_test.lua`

```lua
-- Gree AC Driver Integration Tests
local test = require "integration_test"
local t_utils = require "integration_test.utils"
local capabilities = require "st.capabilities"

-- Mock device for testing
local mock_gree_device = test.mock_device.build_test_lan_device({
  profile = t_utils.get_profile_definition("gree-ac.yml"),
  device_network_id = "c039379a2dc9",
  label = "Test Gree AC"
})

-- Test initialization
local function test_init()
  test.mock_device.add_test_device(mock_gree_device)
end

test.set_test_init_function(test_init)

-- Test: Switch ON command
test.register_coroutine_test(
  "Switch ON should send power command",
  function()
    test.socket.capability:__queue_receive({
      mock_gree_device.id,
      { capability = "switch", command = "on", args = {} }
    })
    
    -- We can't easily test UDP packets, but we can verify
    -- the driver processes the command without errors
    test.wait_for_events()
    
    -- Verify switch state updated
    test.socket.capability:__expect_send(
      mock_gree_device:generate_test_message("main", 
        capabilities.switch.switch.on())
    )
  end
)

-- Test: Switch OFF command
test.register_coroutine_test(
  "Switch OFF should send power command",
  function()
    test.socket.capability:__queue_receive({
      mock_gree_device.id,
      { capability = "switch", command = "off", args = {} }
    })
    
    test.wait_for_events()
    
    test.socket.capability:__expect_send(
      mock_gree_device:generate_test_message("main", 
        capabilities.switch.switch.off())
    )
  end
)

-- Test: Refresh command
test.register_coroutine_test(
  "Refresh should poll device status",
  function()
    test.socket.capability:__queue_receive({
      mock_gree_device.id,
      { capability = "refresh", command = "refresh", args = {} }
    })
    
    test.wait_for_events()
    
    -- Should trigger status polling
    -- (difficult to verify UDP without real device)
  end
)

-- Run all tests
test.run_registered_tests()
```

**Note:** Integration tests for LAN devices are challenging because:
- UDP communication is hard to mock
- No direct test framework for LAN (like there is for Zigbee)
- Real device testing on hub is more practical

## Recommended Testing Workflow

### Phase 1: Fix Socket Implementation ⚠️ CRITICAL
```bash
# Update gree_protocol.lua to use cosock
# Test locally if possible (may need Edge runtime)
```

### Phase 2: Package & Deploy
```bash
./package.sh
smartthings edge:drivers:package gree-driver-v1.0.0.tar.gz
smartthings edge:drivers:install
```

### Phase 3: Manual Testing on Hub
```bash
# Terminal 1: Watch logs
smartthings edge:drivers:logcat

# Terminal 2: Make changes, re-deploy
# SmartThings App: Test all functions
```

### Phase 4: Complete TESTING_CHECKLIST.md
```bash
# Work through all items in checklist
# Document any issues found
# Fix and re-test
```

## Debugging Tips

### Common Issues

**1. Driver Not Appearing in App**
- Check driver installed: `smartthings edge:drivers:installed`
- Verify hub online: `smartthings hubs:list`
- Check for compilation errors in logs

**2. Device Not Discovered**
- Verify AC on same network as hub
- Check UDP port 7000 not blocked by firewall
- Verify discovery_handler is being called (check logs)

**3. Commands Not Working**
- Check device preferences are configured
- Verify encryption key is correct
- Check for UDP socket errors in logs
- Confirm device IP is reachable from hub

**4. Status Not Updating**
- Check polling interval setting
- Verify poll_device function running (check logs)
- Ensure status query succeeding

### Log Analysis

**Look for these messages:**
```
[INFO] Gree Air Conditioner Driver initialized - Version 1.0
[INFO] Sending command to device: c039379a2dc9
[INFO] Sub-unit MAC: e137811d0000000
[INFO] Device turned ON
[INFO] Polling device status
[DEBUG] Decrypted response: {"..."}
[ERROR] Failed to send command: <error details>
```

## Testing Checklist Summary

- [ ] Fix cosock/socket implementation
- [ ] Package driver successfully
- [ ] Install on SmartThings Hub
- [ ] Driver appears in logs
- [ ] Add device in SmartThings app
- [ ] Configure device preferences
- [ ] Test ON command - Living Room
- [ ] Test OFF command - Living Room  
- [ ] Test ON command - Bedroom
- [ ] Test OFF command - Bedroom
- [ ] Verify status display (Mode)
- [ ] Verify status display (Temperature)
- [ ] Test refresh command
- [ ] Test polling (wait 30+ seconds)
- [ ] Test error handling (wrong IP)
- [ ] Test network resilience (disconnect/reconnect)
- [ ] Run for 24 hours stability test
- [ ] Complete full TESTING_CHECKLIST.md

## Next Steps

1. **Immediate:** Fix socket implementation to use `cosock`
2. **Deploy:** Package and install to hub
3. **Test:** Work through testing checklist
4. **Document:** Record any issues found
5. **Iterate:** Fix issues and re-deploy
6. **Release:** Once stable, consider public release

## Resources

- **SmartThings Edge Testing**: https://developer.smartthings.com/docs/devices/hub-connected/test-your-driver
- **SmartThings CLI**: https://developer.smartthings.com/docs/tools/smartthings-cli
- **Edge Driver Reference**: https://developer.smartthings.com/docs/edge-device-drivers/
- **Cosock Documentation**: Available in SmartThings Edge runtime
- **LAN Driver Examples**: Check SmartThingsEdgeDrivers GitHub repo for LAN device examples
