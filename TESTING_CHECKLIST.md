# SmartThings Edge Testing Checklist

## Pre-Deployment Testing

### Local Development Environment
- [x] Lua syntax validation
- [x] Protocol testing with netcat
- [x] Encryption/decryption working
- [x] Discovery tested
- [x] Binding tested
- [x] Commands tested (ON/OFF)
- [x] Multi-split addressing tested
- [ ] Fix LuaSocket UDP issue
- [ ] Test with SmartThings socket library

## Deployment Preparation

### Build Package
- [ ] Run `./package.sh`
- [ ] Verify package contents:
  - [ ] src/init.lua
  - [ ] src/crypto.lua
  - [ ] src/gree_protocol.lua
  - [ ] src/device_handler.lua
  - [ ] profiles/gree-ac.yml
  - [ ] fingerprints.yml
  - [ ] preferences.yml
- [ ] Check package size (should be <1MB)

### SmartThings Developer Workspace
- [ ] Login to developer.smartthings.com
- [ ] Create new project or update existing
- [ ] Upload package
- [ ] Validate no errors in driver validation

## Hub Installation

### Install Driver
- [ ] Open SmartThings app
- [ ] Go to Hub settings
- [ ] Available Drivers > Gree AC Driver
- [ ] Click Install
- [ ] Verify driver installed successfully

### View Logs
- [ ] Install SmartThings CLI
- [ ] Run `smartthings edge:drivers:log`
- [ ] Verify driver initialization logs appear
- [ ] Check for any startup errors

## Device Discovery Testing

### Automatic Discovery
- [ ] In SmartThings app: Add Device > Scan Nearby
- [ ] Verify Gree AC devices appear
- [ ] Check discovery finds correct MAC addresses
- [ ] Test with WiFi module powered on/off

### Manual Device Addition
- [ ] Add Device > My Testing Devices > Gree AC
- [ ] Device appears in device list
- [ ] Can access device settings

## Device Configuration

### Single Unit Configuration
- [ ] Set Device IP Address
- [ ] Set Device MAC Address
- [ ] Set Encryption Key
- [ ] Leave Sub-Unit MAC blank
- [ ] Save settings
- [ ] Verify no errors in logs

### Multi-Split Configuration
- [ ] Create first device (Living Room)
  - [ ] Set IP, MAC, Key
  - [ ] Set Sub-Unit MAC (e.g., e137811d0000000)
- [ ] Create second device (Bedroom)
  - [ ] Set same IP, MAC, Key
  - [ ] Set different Sub-Unit MAC (e.g., 8f917e1d0000000)
- [ ] Verify both devices appear separately

## Functional Testing

### Power Control
- [ ] **Turn ON** via SmartThings app
  - [ ] Device turns on physically
  - [ ] Status updates to ON in app
  - [ ] Check logs for command success
- [ ] **Turn OFF** via SmartThings app
  - [ ] Device turns off physically
  - [ ] Status updates to OFF in app
  - [ ] Check logs for command success

### Status Display
- [ ] **Mode Display**
  - [ ] Change mode on physical remote/app
  - [ ] Wait for polling interval (30s default)
  - [ ] Verify mode updates in SmartThings
  - [ ] Test all modes: Auto, Cool, Dry, Fan, Heat
- [ ] **Temperature Display**
  - [ ] Check current temperature shown
  - [ ] Compare with physical display
  - [ ] Verify temperature is accurate (check offset)
  - [ ] Test Celsius/Fahrenheit preference

### Refresh Command
- [ ] Make change on physical remote
- [ ] Tap Refresh in SmartThings app
- [ ] Status updates immediately
- [ ] Verify all values correct

### Multi-Split Testing
- [ ] Turn Living Room ON, Bedroom OFF
  - [ ] Only Living Room responds
- [ ] Turn Bedroom ON, Living Room OFF
  - [ ] Only Bedroom responds
- [ ] Turn both ON
  - [ ] Both respond
- [ ] Turn both OFF
  - [ ] Both respond
- [ ] Verify no cross-control between units

## Polling Testing

### Automatic Status Updates
- [ ] Set polling interval to 30 seconds
- [ ] Change AC state manually (remote/app)
- [ ] Wait 30 seconds
- [ ] Status updates in SmartThings
- [ ] Check logs for polling activity

### Polling Interval Adjustment
- [ ] Change to 10 seconds (faster)
  - [ ] Verify faster updates
- [ ] Change to 60 seconds (slower)
  - [ ] Verify slower updates
- [ ] Change to 300 seconds (max)
  - [ ] Verify updates still work

## Error Handling Testing

### Network Issues
- [ ] Disconnect WiFi module from network
  - [ ] Commands fail gracefully
  - [ ] Error messages in logs
  - [ ] App shows device offline/error
- [ ] Reconnect WiFi module
  - [ ] Device recovers automatically
  - [ ] Status updates resume

### Invalid Configuration
- [ ] Wrong IP address
  - [ ] Commands fail
  - [ ] Appropriate error logged
- [ ] Wrong MAC address
  - [ ] Commands fail
  - [ ] Appropriate error logged
- [ ] Wrong encryption key
  - [ ] Commands fail (decryption error)
  - [ ] Appropriate error logged

### Connection Recovery
- [ ] Power cycle AC unit
  - [ ] Device reconnects
  - [ ] Commands resume working
- [ ] Power cycle SmartThings hub
  - [ ] Driver reinitializes
  - [ ] Devices reappear
  - [ ] All functions work

## Performance Testing

### Response Time
- [ ] Time command to physical action
  - [ ] Should be <2 seconds typical
- [ ] Time status query to update
  - [ ] Should be <1 second typical

### Reliability
- [ ] Send 10 ON/OFF commands rapidly
  - [ ] All commands succeed
  - [ ] No missed commands
- [ ] Run for 24 hours
  - [ ] No crashes
  - [ ] No memory leaks
  - [ ] Polling continues working

### Multiple Devices
- [ ] Test with 2 units (if available)
- [ ] Test with 4+ units (if available)
- [ ] All units respond independently
- [ ] No command conflicts

## SmartThings Integration

### Automation Testing
- [ ] Create routine: "Turn AC ON at sunset"
  - [ ] Routine triggers correctly
  - [ ] AC turns on
- [ ] Create routine: "Turn AC OFF when leaving"
  - [ ] Location trigger works
  - [ ] AC turns off

### Voice Control (if configured)
- [ ] "Alexa, turn on Living Room AC"
  - [ ] Device responds
- [ ] "Hey Google, turn off Bedroom AC"
  - [ ] Device responds

### SmartThings Scenes
- [ ] Add AC to scene
- [ ] Activate scene
- [ ] AC responds as configured

## Logging & Debugging

### Log Analysis
- [ ] Enable debug logging preference
- [ ] Check logs for:
  - [ ] Discovery messages
  - [ ] Binding attempts
  - [ ] Command transmissions
  - [ ] Status queries
  - [ ] Decryption details
- [ ] Disable debug logging for production
- [ ] Verify normal logging level appropriate

### Error Messages
- [ ] Verify error messages are clear
- [ ] Check for stack traces (should be handled)
- [ ] Confirm no sensitive data in logs

## Security Testing

### Configuration Security
- [ ] Verify encryption key not visible in app UI
- [ ] Check preferences stored securely
- [ ] Confirm no keys in device metadata

### Network Security
- [ ] Verify communication is local only
- [ ] No data sent to external servers
- [ ] Check for any unexpected network traffic

## Documentation Testing

### User Guide
- [ ] Follow CONFIG_TEMPLATE.md step-by-step
- [ ] Verify all steps work
- [ ] Check for missing information
- [ ] Test troubleshooting steps

### Quick Start
- [ ] Follow QUICK_REFERENCE.md
- [ ] Verify commands work as documented
- [ ] Check examples are accurate

## Regression Testing

### After Code Changes
- [ ] Re-run all functional tests
- [ ] Verify no broken features
- [ ] Check logs for new errors
- [ ] Test edge cases again

## Final Validation

### Version 1.0 Requirements
- [ ] ✅ ON/OFF control working
- [ ] ✅ Mode display working (read-only)
- [ ] ✅ Temperature display working (read-only)
- [ ] ✅ Multi-split support working
- [ ] ✅ Status polling working
- [ ] ✅ Configuration via preferences working
- [ ] ✅ Discovery working
- [ ] ✅ No hardcoded credentials
- [ ] ✅ Documentation complete

### Production Readiness
- [ ] All tests passed
- [ ] No critical bugs
- [ ] Performance acceptable
- [ ] Logs clean (no spam)
- [ ] Error handling robust
- [ ] User experience smooth

## Sign-Off

**Tested By:** _________________  
**Date:** _________________  
**Version:** 1.0.0  
**Hub Model:** _________________  
**Test Devices:** _________________

**Overall Status:** [ ] Pass [ ] Fail [ ] Needs Work

**Notes:**
_________________________________________
_________________________________________
_________________________________________

## Post-Deployment Monitoring

### Week 1
- [ ] Check logs daily
- [ ] User feedback collection
- [ ] Bug reports tracked
- [ ] Performance monitoring

### Month 1
- [ ] Review reliability metrics
- [ ] Analyze common issues
- [ ] Plan improvements
- [ ] Begin Version 2.0 planning

---

**Next Steps After Testing:**
1. Document any issues found
2. Fix critical bugs
3. Update documentation
4. Plan Version 2.0 features
5. Consider public release
