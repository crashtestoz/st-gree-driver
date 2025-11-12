# SmartThings Gree AC Driver - Version 1

## Version 1.0 Features

### Control
- ✅ **Power ON/OFF** - Turn AC units on and off

### Display (Read-Only)
- 📊 **Mode** - Show current mode (Auto, Cool, Dry, Fan, Heat)
- 🌡️ **Temperature** - Show set temperature and current temperature

### Device Support
- ✅ Multi-split systems (2 sub-units)
- ✅ Individual control per AC unit
- ✅ Living AC (Master) - MAC: e137811d0000000
- ✅ Bedroom AC (Secondary) - MAC: 8f917e1d0000000

## Implementation Status

### Completed
- [x] Gree protocol encryption (AES-128-ECB)
- [x] UDP communication
- [x] Device discovery with multi-split detection
- [x] Device binding with encryption key retrieval
- [x] Multi-split sub-unit identification
- [x] Power ON/OFF command testing (both units)

### To Do
- [ ] Fix luasocket UDP implementation (currently using netcat)
- [ ] Create device_handler.lua with basic capabilities
- [ ] Implement status polling for Mode and Temperature display
- [ ] Package driver for SmartThings
- [ ] Test in SmartThings environment

## SmartThings Capabilities for v1

```yaml
capabilities:
  - switch (ON/OFF)
  - temperatureMeasurement (display current temp)
  - thermostatCoolingSetpoint (display set temp)
  - thermostatMode (display mode - read only for v1)
```

## Future Versions

### Version 2.0 (Planned)
- Change temperature setpoint
- Change mode (Auto, Cool, Dry, Fan, Heat)
- Change fan speed
- Swing control

### Version 3.0 (Planned)
- Advanced features (Quiet mode, Turbo, Health mode)
- Scheduling
- Energy monitoring
- Cloud integration option

## Testing Results

**Device**: Gree Multi-Split AC System at 10.0.0.164
**Main MAC**: c039379a2dc9
**Encryption Key**: 5Gh8Jk1Mn4Pq7St0

### Living AC (Master) - e137811d0000000
- ✅ Turn ON: Working
- ✅ Turn OFF: Working
- ✅ Individual control: Working

### Bedroom AC (Secondary) - 8f917e1d0000000
- ✅ Turn ON: Working
- ✅ Turn OFF: Working
- ✅ Individual control: Working
