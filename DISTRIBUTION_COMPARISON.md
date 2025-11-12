# Distribution Comparison: LGTV vs Gree AC Driver

## Overview
Comparison between Todd Austin's LGTV driver (community-distributed via channel) and your Gree AC driver to identify differences in structure, settings, and distribution.

---

## ✅ What Your Driver Already Has (Matches LGTV Pattern)

### 1. **Core Structure** ✅
- **hubpackage/** equivalent structure:
  - `src/` folder with Lua modules ✅
  - `profiles/` folder with YAML profile ✅
  - Settings/preferences file ✅
- **Your structure is correct** - just needs a `config.yml` file (see below)

### 2. **Device Profile** ✅
- Both use YAML format for profiles
- Both define capabilities, components, categories
- **LGTV**: `lgtv_v1.yaml` with Television category
- **Gree**: `gree-ac.yml` with AirConditioner category
- ✅ **Your profile structure is correct**

### 3. **Preferences/Settings** ✅
- Both use preferences for user configuration
- **LGTV**: Embedded in profile YAML
- **Gree**: Separate `preferences.yml` file
- ✅ **Both approaches are valid** - Your separate file is cleaner

### 4. **Device Capabilities** ✅
- Both use standard + custom capabilities
- **LGTV**: Uses custom capabilities like `partyvoice23922.lgmediainputsource`
- **Gree**: Uses standard capabilities (switch, thermostat, temperature, fan, refresh)
- ✅ **Your capabilities are appropriate for AC control**

---

## ⚠️ What Your Driver Needs to Add

### 1. **config.yml File** ⚠️ **MISSING - REQUIRED**
**LGTV has:**
```yaml
name: 'LG TV V1.1'
packageKey: 'lgtv.v1'
permissions:
    lan: {}
    discovery: {}
```

**You need to create:** `config/config.yml`
```yaml
name: 'Gree AC Driver V1.0'
packageKey: 'gree.v1'
permissions:
    lan: {}
    discovery: {}
```

**Critical:** This file is REQUIRED for Edge drivers. It defines:
- Driver name shown in channel
- Unique package key
- Required permissions (LAN and discovery for network devices)

### 2. **Fingerprints** ⚠️ **INCORRECT FORMAT**
**Your current fingerprints.yml** is for Zigbee devices:
```yaml
zigbeeManufacturer: Gree
zigbeeModel: 
  - "AC_LAN"
```

**LAN devices don't use fingerprints** - they use **discovery** instead:
- LGTV uses SSDP discovery in code
- Gree should use UDP broadcast discovery (already in your `gree_protocol.lua`)
- ⚠️ **Delete fingerprints.yml** - it's not needed for LAN devices

### 3. **Package Structure for Distribution**
**LGTV structure:**
```
LGTV/
├── hubpackage/
│   ├── config.yml          ← REQUIRED
│   ├── profiles/
│   │   └── lgtv_v1.yaml
│   └── src/
│       └── init.lua
├── capabilities/           ← Only if using custom capabilities
└── README.md
```

**Your current structure:**
```
st-gree-driver/
├── profiles/
│   └── gree-ac.yml
├── src/
│   ├── init.lua
│   ├── crypto.lua
│   ├── gree_protocol.lua
│   └── device_handler.lua
├── preferences.yml
├── fingerprints.yml        ← DELETE THIS
└── config/                 ← ADD config.yml HERE
```

**Recommended restructure:**
```
st-gree-driver/
├── config/
│   └── config.yml          ← CREATE THIS
├── profiles/
│   └── gree-ac.yml
├── src/
│   ├── init.lua
│   ├── crypto.lua
│   ├── gree_protocol.lua
│   └── device_handler.lua
└── preferences.yml         ← Keep this
```

---

## 📦 Distribution via SmartThings Channel

### How LGTV is Distributed
**Channel URL:** https://bestow-regional.api.smartthings.com/invite/Q1jP7BqnNNlL

**Process:**
1. Developer uploads driver package via CLI: `smartthings edge:drivers:package`
2. Developer creates/assigns to a channel: `smartthings edge:channels:create`
3. Developer assigns driver to channel: `smartthings edge:channels:assign`
4. Developer creates shareable invite link
5. Users enroll hub via invite link
6. Users scan for devices (driver's discovery runs)

### Your Distribution Path
**Option A: Public Channel (Like LGTV)**
1. Fix structure (add config.yml, remove fingerprints.yml)
2. Package driver: `smartthings edge:drivers:package`
3. Create channel: `smartthings edge:channels:create`
4. Assign driver to channel: `smartthings edge:channels:assign <driver-id> <version> --channel <channel-id>`
5. Create public invite: `smartthings edge:channels:invites:create --channel <channel-id>`
6. Share invite URL with community

**Option B: Developer Workspace (Testing)**
1. Upload to: https://smartthings.developer.samsung.com/workspace/projects
2. Test with your own hub
3. Eventually publish to channel

---

## 🔧 Settings/Preferences Comparison

### LGTV Settings (Embedded in Profile)
```yaml
preferences:
  - title: "Refresh Frequency"
    name: freq
    preferenceType: integer
    definition:
      minimum: 10
      maximum: 86400
      default: 60
  - title: "WOL MAC Address"
    name: macaddr
    preferenceType: string
    required: false
  - title: "WOL Broadcast Address"
    name: bcastaddr
    preferenceType: string
    required: false
```

### Your Settings (Separate File) ✅ **BETTER APPROACH**
```yaml
preferences:
  - name: deviceIp
    title: "Device IP Address"
    preferenceType: string
    required: true
  - name: deviceMac
    title: "Device MAC Address"
    preferenceType: string
    required: true
  - name: encryptionKey
    title: "Encryption Key"
    preferenceType: string
    required: true
  - name: pollingInterval
    preferenceType: integer
    definition:
      minimum: 10
      maximum: 300
      default: 30
```

**Your approach is cleaner** - separate preferences file is easier to maintain.

---

## 🎯 Key Differences Summary

| Feature | LGTV Driver | Gree AC Driver | Action Needed |
|---------|-------------|----------------|---------------|
| **config.yml** | ✅ Has it | ❌ Missing | **CREATE** |
| **Profile YAML** | ✅ Works | ✅ Works | None |
| **Preferences** | Embedded in profile | Separate file | ✅ Your way is better |
| **Fingerprints** | Not used (LAN) | ❌ Wrong (Zigbee) | **DELETE** |
| **Discovery** | SSDP in code | UDP in code | ✅ Already implemented |
| **LAN Permissions** | ✅ In config.yml | ❌ Not declared | **ADD to config.yml** |
| **Capabilities** | Custom + Standard | Standard only | ✅ Sufficient for V1 |
| **Channel Distribution** | ✅ Public channel | Not yet | After testing |

---

## 🚀 What You Need to Do Before Distribution

### Immediate (For Testing on Your Hub)
1. **Create `config/config.yml`** with proper structure
2. **Delete `fingerprints.yml`** (not needed for LAN devices)
3. **Update `package.sh`** to exclude fingerprints.yml
4. **Test on your hub** via SmartThings CLI

### Later (For Public Distribution)
1. Create a SmartThings channel
2. Upload driver package
3. Assign driver to channel
4. Create shareable invite link
5. Document installation process (like LGTV's README)

---

## 📝 Preferences Integration

### LGTV Approach (Embedded)
- Preferences defined in profile YAML
- Tight coupling between profile and settings
- Harder to maintain separately

### Your Approach (Separate File) ✅ **RECOMMENDED**
- `preferences.yml` separate from profile
- Easier to modify without touching profile
- Better for version control
- **Keep this approach**

**However:** SmartThings may require preferences to be in the profile. If packaging fails, you may need to:
1. Move preferences section from `preferences.yml` into `profiles/gree-ac.yml`
2. Add a `metadata:` section if needed

---

## 🔗 Distribution URL Format

**LGTV Channel URL:**
```
https://bestow-regional.api.smartthings.com/invite/Q1jP7BqnNNlL
```

**Your Future URL:**
```
https://bestow-regional.api.smartthings.com/invite/<your-invite-code>
```

**How to Generate:**
1. After creating channel and assigning driver
2. Run: `smartthings edge:channels:invites:create --channel <channel-id>`
3. Get shareable URL from response

---

## ✅ Bottom Line

**Your driver structure is 95% correct!** You just need:

1. **Add `config/config.yml`** ← Critical
2. **Delete `fingerprints.yml`** ← Not for LAN devices
3. **Test on your hub first** before public distribution
4. **Create channel + invite** when ready for community

**Your driver will work exactly like LGTV** - users will:
1. Enroll hub via your channel invite URL
2. Turn on Gree AC units
3. Run "Scan for nearby devices"
4. Configure IP/MAC/Key in device settings
5. Control via SmartThings app

The key difference is LGTV auto-discovers TVs, but Gree requires manual IP/MAC/Key configuration due to the binding process.
