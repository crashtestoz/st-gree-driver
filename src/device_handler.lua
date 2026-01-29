-- SmartThings Gree AC Device Handler
-- Version 1.3.11 - airConditionerFanMode for proper Auto/Low/Medium/High labels
-- Command-based state tracking for multi-split sub-units

local capabilities = require "st.capabilities"
local log = require "log"
local gree_protocol = require "gree_protocol"

local device_handler = {}

-- Device state storage
local device_states = {}

-- Mode mapping: Gree -> SmartThings
local MODE_MAP = {
  [0] = "auto",
  [1] = "cool",
  [2] = "dryair",
  [3] = "fanonly",
  [4] = "heat"
}

-- Reverse mode map: SmartThings -> Gree
local REVERSE_MODE_MAP = {
  auto = 0,
  cool = 1,
  dryair = 2,
  fanonly = 3,
  heat = 4
}

-- Fan mode mapping: Gree WdSpd -> SmartThings airConditionerFanMode
-- Gree: 0=auto, 1=low, 2=med-low, 3=medium, 4=med-high, 5=high
-- SmartThings: auto, low, medium, high
local FAN_MODE_MAP = {
  [0] = "auto",
  [1] = "low",
  [2] = "low",
  [3] = "medium",
  [4] = "high",
  [5] = "high"
}

-- Reverse fan mode map: SmartThings -> Gree
local REVERSE_FAN_MODE_MAP = {
  auto = 0,
  low = 1,
  medium = 3,
  high = 5
}

-- Helper: Get device preferences
local function get_device_config(device)
  -- Priority: 1) Discovered data (auto-configured), 2) User preferences (manual override)
  local function get_value(discovered_name, pref_name)
    -- First check discovered value from auto-configuration
    if discovered_name then
      local discovered_val = device:get_field(discovered_name)
      if discovered_val and discovered_val ~= "" then
        log.debug("Using discovered value for " .. pref_name .. ": " .. tostring(discovered_val))
        return discovered_val
      else
        log.debug("No discovered field '" .. discovered_name .. "' found")
      end
    end
    
    -- Then check user preference (manual override)
    local pref_val = device.preferences[pref_name]
    if pref_val and pref_val ~= "" and pref_val ~= nil then
      log.debug("Using preference value for " .. pref_name .. ": " .. tostring(pref_val))
      return pref_val
    end
    
    log.debug("No value found for " .. pref_name)
    return nil
  end
  
  -- Get sub_mac from preferences (manual configuration required for multi-split)
  local sub_mac = get_value(nil, "subUnitMac")
  
  if not sub_mac or sub_mac == "" then
    local is_sub_unit = device:get_field("is_sub_unit")
    if is_sub_unit then
      log.warn("Multi-split sub-unit missing sub_mac configuration - configure in device settings")
    end
  end
  
  -- Get encryption key - priority: 1) From bind (stored field), 2) User preference, 3) Generic key
  local key = device:get_field("encryption_key") -- From successful bind
  if key and key ~= "" then
    log.debug("Using encryption key from bind: " .. key)
  else
    key = get_value(nil, "encryptionKey") -- From user preference
    if not key or key == "" then
      log.debug("No encryption key configured, using generic key")
      key = gree_protocol.GENERIC_KEY
    end
  end
  
  return {
    ip = get_value("discovered_ip", "deviceIp"),
    mac = get_value("discovered_mac", "deviceMac"),
    key = key,
    sub_mac = sub_mac
  }
end

-- Helper: Store device state
local function store_device_state(device, state_data)
  device:set_field("device_state", state_data)
  device_states[device.id] = state_data
end

-- Helper: Get device state
local function get_device_state(device)
  return device:get_field("device_state") or device_states[device.id] or {}
end

-- Helper: Emit all UI states from a state table
-- This updates fan speed, display light, mode, and temperature from command responses
local function emit_all_states(device, state)
  if not state then return end
  
  -- Power state
  if state.Pow ~= nil then
    if state.Pow == 1 then
      device:emit_event(capabilities.switch.switch.on())
    else
      device:emit_event(capabilities.switch.switch.off())
    end
  end
  
  -- Mode
  if state.Mod ~= nil then
    local mode = MODE_MAP[state.Mod] or "auto"
    device:emit_event(capabilities.thermostatMode.thermostatMode(mode))
    device:emit_event(capabilities.thermostatMode.supportedThermostatModes({"auto", "cool", "dryair", "fanonly", "heat"}))
  end
  
  -- Set temperature
  if state.SetTem ~= nil and state.SetTem > 0 then
    local unit = (state.TemUn == 1) and "F" or "C"
    device:emit_event(capabilities.thermostatCoolingSetpoint.coolingSetpoint({
      value = state.SetTem,
      unit = unit
    }))
  end
  
  -- Fan mode (using airConditionerFanMode for auto/low/medium/high labels)
  if state.WdSpd ~= nil then
    local fan_mode = FAN_MODE_MAP[state.WdSpd] or "auto"
    pcall(function()
      device:emit_event(capabilities.airConditionerFanMode.fanMode(fan_mode))
      device:emit_event(capabilities.airConditionerFanMode.supportedAcFanModes({"auto", "low", "medium", "high"}))
    end)
    log.info("Fan mode updated: Gree WdSpd=" .. state.WdSpd .. " -> ST fanMode=" .. fan_mode)
  end
end

-- Initialize device on addition
function device_handler.device_added(driver, device)
  log.info("Device added: " .. device.label)
  log.debug("Device network ID: " .. tostring(device.device_network_id))
  log.debug("Device UUID: " .. device.id)
  
  -- Check if this device was just discovered and has cached info
  discovered_devices_cache = discovered_devices_cache or {}
  
  -- Debug: Log cache contents
  local cache_size = 0
  for key, _ in pairs(discovered_devices_cache) do
    cache_size = cache_size + 1
    log.debug("  Cache key: " .. tostring(key))
  end
  log.debug("Discovery cache has " .. cache_size .. " entries")
  
  -- Try to find cached info - look in cache by device_network_id or label pattern
  local cached_info = nil
  
  if device.device_network_id then
    cached_info = discovered_devices_cache[device.device_network_id]
  end
  
  -- Fallback: Search cache for MAC matching device label (e.g., "Gree AC Unit 1 (2dc9)")
  if not cached_info then
    local mac_suffix = device.label:match("%((%w+)%)")
    if mac_suffix then
      log.debug("Searching cache for MAC ending in: " .. mac_suffix)
      for key, info in pairs(discovered_devices_cache) do
        if info.mac and info.mac:sub(-#mac_suffix) == mac_suffix then
          log.debug("Found matching MAC in cache: " .. info.mac)
          cached_info = info
          break
        end
      end
    end
  end
  
  if cached_info then
    log.info("Auto-configuring from discovery: IP=" .. cached_info.ip .. ", MAC=" .. cached_info.mac)
    
    -- Save discovered info to device fields (these will be used by get_device_config)
    device:set_field("discovered_ip", cached_info.ip, {persist = true})
    device:set_field("discovered_mac", cached_info.mac, {persist = true})
    log.info("Stored discovered IP and MAC to device fields")
    
    if cached_info.sub_index then
      log.info("Sub-unit " .. cached_info.sub_index .. " of " .. cached_info.subCnt)
      device:set_field("discovered_sub_index", cached_info.sub_index, {persist = true})
      device:set_field("is_sub_unit", true, {persist = true})
      
      -- Store sub_mac if available from discovery
      if cached_info.sub_mac then
        log.info("Auto-detected sub-unit MAC: " .. cached_info.sub_mac)
        device:set_field("discovered_sub_mac", cached_info.sub_mac, {persist = true})
      end
    end
    
    -- Note: Don't clear cache here - multiple devices may share the same discovery info
    -- Cache will be cleared when discovery runs again
  else
    log.warn("No cached discovery info found for device - will need manual configuration")
  end
  
  -- Set initial values (only capabilities we can reliably update)
  device:emit_event(capabilities.switch.switch.off())
  device:emit_event(capabilities.thermostatMode.thermostatMode.auto())
  device:emit_event(capabilities.thermostatMode.supportedThermostatModes({"auto", "cool", "dryair", "fanonly", "heat"}))
  device:emit_event(capabilities.thermostatCoolingSetpoint.coolingSetpoint({value = 25, unit = "C"}))
  
  -- Set fan mode initial state (may not exist on older profiles)
  local ok, err = pcall(function()
    device:emit_event(capabilities.airConditionerFanMode.fanMode("auto"))
    device:emit_event(capabilities.airConditionerFanMode.supportedAcFanModes({"auto", "low", "medium", "high"}))
  end)
  if not ok then
    log.warn("Fan mode capability not available on this device profile")
  end
  
  -- Start polling with empty p[] array to avoid changing AC state
  device.thread:call_on_schedule(
    device.preferences.pollingInterval or 30,
    function()
      device_handler.poll_device(driver, device)
    end,
    "polling_schedule"
  )
  
  log.info("Device initialized: " .. device.label)
end

-- Initialize device on driver start
function device_handler.device_init(driver, device)
  log.info("Initializing device: " .. device.label)
  
  -- Try to update device profile to latest version (enables new capabilities)
  local ok, err = pcall(function()
    device:try_update_metadata({profile = "gree-ac"})
  end)
  if ok then
    log.info("Device profile update requested")
  else
    log.debug("Profile update not needed or not supported: " .. tostring(err))
  end
  
  local config = get_device_config(device)
  
  -- Check if configuration is missing (common after driver switch)
  if not config.ip or not config.mac then
    log.warn("Device configuration missing after driver switch!")
    log.warn("Please configure manually in device settings:")
    log.warn("  - Device IP Address")
    log.warn("  - Device MAC Address")
    log.warn("  - Sub-Unit MAC (for multi-split systems)")
    log.warn("Or delete device and rediscover to auto-configure")
    return
  end
  
  -- If we have config, try to bind (or verify existing binding)
  if config.ip and config.mac and not config.key then
    log.info("Attempting to bind with device...")
    local key, err = gree_protocol.bind_device(config.ip, config.mac)
    if key then
      log.info("Bind successful, saving encryption key")
      device:set_field("encryption_key", key, {persist = true})
    else
      log.warn("Bind failed: " .. tostring(err))
    end
  end
  
  -- Emit supported modes to ensure UI shows only valid options
  device:emit_event(capabilities.thermostatMode.supportedThermostatModes({"auto", "cool", "dryair", "fanonly", "heat"}))
  log.info("Emitted supportedThermostatModes: auto, cool, dryair, fanonly, heat")
  
  -- Emit initial states for all capabilities to enable controls (not grayed out)
  -- These defaults will be overwritten by actual values from polling or commands
  local last_state = get_device_state(device) or {}
  
  -- Power state
  if last_state.Pow == 1 then
    device:emit_event(capabilities.switch.switch.on())
  else
    device:emit_event(capabilities.switch.switch.off())
  end
  
  -- Mode
  local mode = MODE_MAP[last_state.Mod or 0] or "auto"
  device:emit_event(capabilities.thermostatMode.thermostatMode(mode))
  
  -- Temperature setpoint
  local temp = last_state.SetTem or 25
  device:emit_event(capabilities.thermostatCoolingSetpoint.coolingSetpoint({value = temp, unit = "C"}))
  
  -- Fan mode (protected for profile compatibility)
  local fan_mode = FAN_MODE_MAP[last_state.WdSpd or 0] or "auto"
  pcall(function()
    device:emit_event(capabilities.airConditionerFanMode.fanMode(fan_mode))
    device:emit_event(capabilities.airConditionerFanMode.supportedAcFanModes({"auto", "low", "medium", "high"}))
  end)
  
  log.info("Emitted initial capability states")
  
  -- Start status polling
  device_handler.poll_device(driver, device)
end

-- Remove device
function device_handler.device_removed(driver, device)
  log.info("Device removed: " .. device.label)
  device_states[device.id] = nil
end

-- Attempt to bind device (or rebind if failing)
local function attempt_bind(device, config)
  if not config.ip or not config.mac then
    log.error("Cannot bind: missing IP or MAC")
    return false
  end
  
  log.info("Attempting to bind with device at " .. config.ip)
  local key, err = gree_protocol.bind_device(config.ip, config.mac)
  
  if key then
    log.info("✓ Bind successful! Encryption key: " .. key)
    device:set_field("encryption_key", key, {persist = true})
    log.info("Encryption key stored and will be used for all commands")
    return true
  else
    log.error("✗ Bind failed: " .. tostring(err))
    return false
  end
end

-- Poll device status
function device_handler.poll_device(driver, device)
  local config = get_device_config(device)
  
  if not config.ip or not config.mac then
    log.warn("Device missing IP or MAC, cannot poll")
    return
  end
  
  -- If no encryption key, attempt to bind first
  if not config.key or config.key == "" then
    log.info("No encryption key found, attempting bind...")
    if attempt_bind(device, config) then
      -- Refresh config after binding
      config = get_device_config(device)
    else
      log.error("Cannot poll without encryption key")
      return
    end
  end
  
  log.debug("Polling device status...")
  
  local status, err
  local is_sub_unit = device:get_field("is_sub_unit") or false
  
  -- IMPORTANT: Sub-units do not support status queries with this hardware
  -- Status polling for sub-units always returns zeros regardless of actual state
  -- The hardware only provides actual values in command responses (t:res)
  -- Therefore: skip polling for sub-units and rely on command response state
  if (is_sub_unit or (config.sub_mac and config.sub_mac ~= "")) then
    log.debug("Skipping status poll for sub-unit: " .. (config.sub_mac or "unknown"))
    log.debug("Sub-unit state maintained from command responses only")
    -- Return the last known state from device memory
    local last_state = get_device_state(device)
    if next(last_state) then
      log.debug("Using cached state from previous commands")
      return  -- State is already set from last command
    else
      log.warn("No cached state for sub-unit - state unknown until first command")
      return
    end
  else
    -- Query status for main unit (traditional status query works here)
    log.debug("Using traditional status query for main unit")
    local params_to_query = {"Pow", "Mod", "SetTem", "WdSpd", "Lig", "TemUn", "TemSen"}
    status, err = gree_protocol.query_status(config.ip, config.mac, config.key, params_to_query, nil)
  end
  
  if not status then
    log.error("Failed to query status: " .. tostring(err))
    return
  end
  
  -- Store state
  store_device_state(device, status)
  
  -- Update capabilities
  
  -- Power state
  if status.Pow ~= nil then
    if status.Pow == 1 then
      device:emit_event(capabilities.switch.switch.on())
    else
      device:emit_event(capabilities.switch.switch.off())
    end
  end
  
  -- Mode
  if status.Mod ~= nil then
    local mode = MODE_MAP[status.Mod] or "auto"
    device:emit_event(capabilities.thermostatMode.thermostatMode(mode))
    -- Always emit supported modes to ensure UI shows only valid options
    device:emit_event(capabilities.thermostatMode.supportedThermostatModes({"auto", "cool", "dryair", "fanonly", "heat"}))
  end
  
  -- Set temperature
  if status.SetTem ~= nil and status.SetTem > 0 then
    local unit = (status.TemUn == 1) and "F" or "C"
    device:emit_event(capabilities.thermostatCoolingSetpoint.coolingSetpoint({
      value = status.SetTem,
      unit = unit
    }))
  end
  
  -- Current temperature (from sensor)
  if status.TemSen ~= nil and status.TemSen ~= "" then
    -- Gree TemSen has +40 offset
    local temp = tonumber(status.TemSen)
    if temp then
      local actual_temp = temp - 40
      local unit = (status.TemUn == 1) and "F" or "C"
      device:emit_event(capabilities.temperatureMeasurement.temperature({
        value = actual_temp,
        unit = unit
      }))
    end
  end
  
  -- Fan mode (protected for older profiles)
  if status.WdSpd ~= nil then
    local st_fan_mode = FAN_MODE_MAP[status.WdSpd] or "auto"
    pcall(function()
      device:emit_event(capabilities.airConditionerFanMode.fanMode(st_fan_mode))
      device:emit_event(capabilities.airConditionerFanMode.supportedAcFanModes({"auto", "low", "medium", "high"}))
    end)
  end
  
  log.debug("Status update complete")
end

-- Set thermostat mode command
function device_handler.set_thermostat_mode(driver, device, command)
  log.info("Setting thermostat mode: " .. device.label .. " to " .. command.args.mode)
  
  local config = get_device_config(device)
  
  if not config.ip or not config.mac or not config.key then
    log.error("Device not configured")
    return
  end
  
  -- Convert SmartThings mode to Gree mode value
  local gree_mode = REVERSE_MODE_MAP[command.args.mode]
  
  if not gree_mode then
    log.error("Invalid mode: " .. tostring(command.args.mode))
    return
  end
  
  -- Build command
  local params = {
    Mod = gree_mode
  }
  
  -- Send command
  local result, err = gree_protocol.send_command(config.ip, config.mac, params, config.key, config.sub_mac)
  
  if result then
    log.info("Mode set to: " .. command.args.mode .. " (Gree value: " .. gree_mode .. ")")
    
    -- Update stored state and emit ALL UI states
    if result.val and result.opt then
      local state_update = get_device_state(device) or {}
      for i, opt_name in ipairs(result.opt) do
        state_update[opt_name] = result.val[i]
      end
      store_device_state(device, state_update)
      emit_all_states(device, state_update)
      log.info("Updated all UI states from command response")
    else
      device:emit_event(capabilities.thermostatMode.thermostatMode(command.args.mode))
      device:emit_event(capabilities.thermostatMode.supportedThermostatModes({"auto", "cool", "dryair", "fanonly", "heat"}))
    end
  else
    log.error("Failed to set mode: " .. tostring(err))
  end
end

-- Switch ON command
function device_handler.switch_on(driver, device, command)
  log.info("Turning device ON: " .. device.label)
  
  local config = get_device_config(device)
  
  if not config.ip or not config.mac or not config.key then
    log.error("Device not configured")
    return
  end
  
  -- Build command - only send Pow parameter
  -- Some AC models reject commands with multiple parameters during power changes
  -- Send command with ALL parameters we want to read back
  -- The response will include val[] for all opts[] we send
  -- This allows us to sync temperature, fan mode, display light on power on
  local params = {
    Pow = 1,
    SetTem = nil,  -- nil means "read current value"
    Mod = nil,
    WdSpd = nil,
    Lig = nil
  }
  
  -- Actually, Gree protocol requires explicit values. Let's send Pow and query the rest.
  -- We'll use a two-step approach: send Pow=1, then query status
  local result, err = gree_protocol.send_command(config.ip, config.mac, {Pow = 1}, config.key, config.sub_mac)
  
  if result then
    log.info("Device turned ON")
    device:emit_event(capabilities.switch.switch.on())
    
    -- Now send a "read" command to get all current values
    -- We do this by sending current known values (or defaults) and reading back
    local current_state = get_device_state(device) or {}
    local read_params = {
      Pow = 1,
      SetTem = current_state.SetTem or 25,
      Mod = current_state.Mod or 1,
      WdSpd = current_state.WdSpd or 0,
      Lig = current_state.Lig or 1
    }
    
    local read_result, read_err = gree_protocol.send_command(config.ip, config.mac, read_params, config.key, config.sub_mac)
    
    if read_result and read_result.val and read_result.opt then
      local state_update = {}
      for i, opt_name in ipairs(read_result.opt) do
        state_update[opt_name] = read_result.val[i]
      end
      store_device_state(device, state_update)
      emit_all_states(device, state_update)
      log.info("Synced all UI states after power on")
    end
  else
    log.error("Failed to turn ON: " .. tostring(err))
  end
end

-- Switch OFF command
function device_handler.switch_off(driver, device, command)
  log.info("Turning device OFF: " .. device.label)
  
  local config = get_device_config(device)
  
  if not config.ip or not config.mac or not config.key then
    log.error("Device not configured")
    return
  end
  
  -- Build command - only send Pow parameter
  -- Some AC models reject commands with multiple parameters during power changes
  local params = {
    Pow = 0
  }
  
  -- Send command
  local result, err = gree_protocol.send_command(config.ip, config.mac, params, config.key, config.sub_mac)
  
  if result then
    log.info("Device turned OFF")
    
    -- Update stored state from command response
    if result.val and result.opt then
      local state_update = get_device_state(device) or {}
      for i, opt_name in ipairs(result.opt) do
        state_update[opt_name] = result.val[i]
      end
      store_device_state(device, state_update)
      
      -- Emit ALL UI states from command response
      emit_all_states(device, state_update)
      log.info("Updated all UI states from command response")
    else
      -- Fallback: just emit power off
      device:emit_event(capabilities.switch.switch.off())
    end
  else
    log.error("Failed to turn OFF: " .. tostring(err))
  end
end

-- Refresh command (manual status update)
function device_handler.refresh(driver, device, command)
  log.info("Refreshing device status: " .. device.label)
  
  local config = get_device_config(device)
  local is_sub_unit = (config.sub_mac and config.sub_mac ~= "")
  
  if is_sub_unit then
    log.warn("LIMITATION: Multi-split sub-units cannot be polled for status")
    log.warn("Status reflects last SmartThings command only")
    log.warn("Changes via Gree app or remote control are NOT detected")
    log.warn("For accurate status, control ONLY via SmartThings")
    
    -- Re-emit last known state from command responses (or defaults)
    local last_state = get_device_state(device) or {}
    emit_all_states(device, last_state)
    log.info("Re-emitted all states for sub-unit")
    return
  end
  
  -- For main units, try normal status polling
  device_handler.poll_device(driver, device)
end

-- Set cooling setpoint (temperature)
function device_handler.set_cooling_setpoint(driver, device, command)
  local target_temp = command.args.setpoint
  log.info("Received setpoint command - Raw value: " .. tostring(target_temp) .. " (type: " .. type(target_temp) .. ")")
  log.debug("Full command args: " .. require("st.json").encode(command.args))
  
  -- SmartThings sends temperature as integer Celsius, but let's ensure it's correct
  -- Convert to integer (SmartThings may send as float)
  target_temp = math.floor(target_temp + 0.5)  -- Round to nearest integer
  
  log.info("Setting cooling setpoint to " .. target_temp .. "°C for: " .. device.label)
  
  local config = get_device_config(device)
  
  if not config.ip or not config.mac or not config.key then
    log.error("Device not configured")
    return
  end
  
  -- Check if AC is powered on
  local current_switch = device:get_latest_state("main", capabilities.switch.ID, capabilities.switch.switch.NAME)
  if current_switch ~= "on" then
    log.warn("Cannot set temperature while AC is OFF - turn AC on first")
    return
  end
  
  -- Validate temperature range (16-30°C for Gree)
  if target_temp < 16 or target_temp > 30 then
    log.error("Temperature out of range (16-30°C): " .. target_temp)
    return
  end
  
  log.info("Sending SetTem command with value: " .. target_temp)
  
  -- Build command - only send SetTem parameter
  local params = {
    SetTem = target_temp
  }
  
  -- Send command
  local result, err = gree_protocol.send_command(config.ip, config.mac, params, config.key, config.sub_mac)
  
  if result then
    log.info("Cooling setpoint set to " .. target_temp .. "°C")
    
    -- Update stored state and emit ALL UI states
    if result.val and result.opt then
      local state_update = get_device_state(device) or {}
      for i, opt_name in ipairs(result.opt) do
        state_update[opt_name] = result.val[i]
      end
      store_device_state(device, state_update)
      emit_all_states(device, state_update)
      log.info("Updated all UI states from command response")
    else
      device:emit_event(capabilities.thermostatCoolingSetpoint.coolingSetpoint({value = target_temp, unit = "C"}))
    end
  else
    log.error("Failed to set temperature: " .. tostring(err))
  end
end

-- Set fan mode command (airConditionerFanMode: auto/low/medium/high)
function device_handler.set_fan_mode(driver, device, command)
  local fan_mode = command.args.fanMode
  log.info("Setting fan mode to " .. tostring(fan_mode) .. " for: " .. device.label)
  
  local config = get_device_config(device)
  
  if not config.ip or not config.mac or not config.key then
    log.error("Device not configured")
    return
  end
  
  -- Convert SmartThings fan mode to Gree WdSpd value
  local gree_speed = REVERSE_FAN_MODE_MAP[fan_mode]
  if not gree_speed then
    log.error("Invalid fan mode: " .. tostring(fan_mode))
    return
  end
  
  log.info("Sending WdSpd command with value: " .. gree_speed)
  
  -- Build command
  local params = {
    WdSpd = gree_speed
  }
  
  -- Send command
  local result, err = gree_protocol.send_command(config.ip, config.mac, params, config.key, config.sub_mac)
  
  if result then
    log.info("Fan mode set to " .. fan_mode .. " (Gree WdSpd: " .. gree_speed .. ")")
    
    -- Update stored state and emit ALL UI states
    if result.val and result.opt then
      local state_update = get_device_state(device) or {}
      for i, opt_name in ipairs(result.opt) do
        state_update[opt_name] = result.val[i]
      end
      store_device_state(device, state_update)
      emit_all_states(device, state_update)
      log.info("Updated all UI states from command response")
    else
      device:emit_event(capabilities.airConditionerFanMode.fanMode(fan_mode))
    end
  else
    log.error("Failed to set fan mode: " .. tostring(err))
  end
end

-- Discovery handler
function device_handler.discovery_handler(driver, opts, cont)
  log.info("Starting device discovery...")
  
  -- Clear any stale cached discovery info from previous scans
  discovered_devices_cache = {}
  
  -- Discover Gree devices on the network
  local devices = gree_protocol.discover_devices()
  
  if not devices or #devices == 0 then
    log.warn("No Gree devices found during discovery")
    return
  end
  
  log.info("Found " .. #devices .. " Gree device(s)")
  for i, dev in ipairs(devices) do
    log.info("  Device " .. i .. ": MAC=" .. dev.mac .. ", IP=" .. dev.ip .. ", subCnt=" .. tostring(dev.subCnt or 0))
  end
  
  -- Create metadata for each discovered device
  for _, device_info in ipairs(devices) do
    -- Store discovered info - will be set as device fields in device_added handler
    -- We'll use device_network_id to encode the discovered info temporarily
    local metadata = {
      type = "LAN",
      device_network_id = device_info.mac,
      label = "Gree AC (" .. device_info.mac:sub(-4) .. ")",
      profile = "gree-ac",
      manufacturer = "Gree",
      model = device_info.name or "Air Conditioner",
      vendor_provided_label = device_info.name or "Gree Air Conditioner"
    }
    
    -- Store discovered info globally so device_added can access it
    discovered_devices_cache = discovered_devices_cache or {}
    discovered_devices_cache[device_info.mac] = device_info
    
    -- If this is a multi-split system, create separate devices for each sub-unit
    if device_info.subCnt and device_info.subCnt > 0 then
      log.info("Multi-split system detected with " .. device_info.subCnt .. " sub-units")
      log.info("Main unit MAC: " .. device_info.mac .. " at " .. device_info.ip)
      
      -- Note: Auto-detection of sub-unit MACs requires the encryption key
      -- For now, sub_mac will need to be configured via preferences or stored from previous configuration
      -- The generic key should work for already-bound devices, but we still need the specific sub_mac values
      log.info("Sub-unit MACs must be configured in device settings")
      log.info("Check device settings or use Gree+ app to identify sub-unit addresses")
      
      for i = 1, device_info.subCnt do
        local sub_network_id = device_info.mac .. "_sub" .. i
        
        -- Check if device with this network_id or matching label already exists
        local device_exists = false
        local expected_label = "Gree AC Unit " .. i .. " (" .. device_info.mac:sub(-4) .. ")"
        
        for _, existing_device in pairs(driver:get_devices()) do
          if (existing_device.device_network_id == sub_network_id) or
             (existing_device.label == expected_label) or
             (existing_device.label and existing_device.label:match(device_info.mac:sub(-4))) then
            log.info("Device already exists: " .. existing_device.label .. ", skipping creation")
            device_exists = true
            break
          end
        end
        
        if not device_exists then
          local sub_metadata = {
            type = "LAN",
            device_network_id = sub_network_id,
            label = expected_label,
            profile = "gree-ac",
            manufacturer = "Gree",
            model = device_info.name or "Air Conditioner (Sub-unit)",
            vendor_provided_label = "Gree Air Conditioner Sub-unit " .. i
          }
          
          -- Store sub-unit info for device_added
          discovered_devices_cache[sub_network_id] = {
            ip = device_info.ip,
            mac = device_info.mac,
            name = device_info.name,
            sub_index = i,
            subCnt = device_info.subCnt,
            sub_mac = nil  -- Must be configured manually in device settings
          }
          
          driver:try_create_device(sub_metadata)
          log.info("Created sub-unit device " .. i .. ": " .. sub_metadata.label)
        end
      end
    else
      -- Single unit system - create normal device
      driver:try_create_device(metadata)
      log.info("Created device: " .. metadata.label .. " at " .. device_info.ip)
    end
  end
end

return device_handler