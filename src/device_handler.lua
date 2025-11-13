-- SmartThings Gree AC Device Handler
-- Version 1.0 - Basic ON/OFF control with Mode and Temperature display

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
  [2] = "dry",
  [3] = "fan",
  [4] = "heat"
}

-- Reverse mode map: SmartThings -> Gree
local REVERSE_MODE_MAP = {
  auto = 0,
  cool = 1,
  dry = 2,
  fan = 3,
  heat = 4
}

-- Helper: Get device preferences
local function get_device_config(device)
  -- Priority: 1) Discovered data (auto-configured), 2) User preferences (manual override)
  local function get_value(discovered_name, pref_name)
    -- First check discovered value from auto-configuration
    local discovered_val = discovered_name and device:get_field(discovered_name)
    if discovered_val and discovered_val ~= "" then
      log.debug("Using discovered value for " .. pref_name .. ": " .. tostring(discovered_val))
      return discovered_val
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
  local sub_mac = get_value("subUnitMac")
  
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

-- Initialize device on addition
function device_handler.device_added(driver, device)
  log.info("Device added: " .. device.label)
  log.debug("Device network ID: " .. tostring(device.device_network_id))
  
  -- Check if this device was just discovered and has cached info
  discovered_devices_cache = discovered_devices_cache or {}
  
  -- Debug: Log cache contents
  log.debug("Discovery cache has " .. tostring(#discovered_devices_cache) .. " entries")
  for key, _ in pairs(discovered_devices_cache) do
    log.debug("  Cache key: " .. tostring(key))
  end
  
  local cached_info = discovered_devices_cache[device.device_network_id]
  
  if cached_info then
    log.info("Auto-configuring from discovery: IP=" .. cached_info.ip .. ", MAC=" .. cached_info.mac)
    
    -- Save discovered info to device fields (these will be used by get_device_config)
    device:set_field("discovered_ip", cached_info.ip, {persist = true})
    device:set_field("discovered_mac", cached_info.mac, {persist = true})
    
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
  end
  
  -- Set initial values (only capabilities we can reliably update)
  device:emit_event(capabilities.switch.switch.off())
  device:emit_event(capabilities.thermostatMode.thermostatMode.auto())
  device:emit_event(capabilities.thermostatCoolingSetpoint.coolingSetpoint({value = 24, unit = "C"}))
  
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
  
  local config = get_device_config(device)
  
  -- If we have config, try to bind (or verify existing binding)
  if config.ip and config.mac and not config.key then
    log.info("Attempting to bind with device...")
    local key, err = gree_protocol.bind_device(config.ip, config.mac)
    if key then
      log.info("Bind successful, saving encryption key")
      device:set_field("encryption_key", key)
    else
      log.warn("Bind failed: " .. tostring(err))
    end
  end
  
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
  
  -- For sub-unit devices, use smart refresh (command-based query)
  -- Status queries don't work for sub-units, but commands return actual state in val array
  if is_sub_unit or (config.sub_mac and config.sub_mac ~= "") then
    log.debug("Using smart refresh for sub-unit device")
    -- Use sub_mac if configured, otherwise nil (will likely timeout for multi-split)
    local sub_id = config.sub_mac and config.sub_mac ~= "" and config.sub_mac or nil
    status, err = gree_protocol.refresh_status(config.ip, config.mac, config.key, sub_id)
  else
    -- Query status for main unit (traditional status query works here)
    log.debug("Using traditional status query for main unit")
    local params_to_query = {"Pow", "Mod", "SetTem", "WdSpd", "TemUn", "TemSen"}
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
  
  log.debug("Status update complete")
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
  local params = {
    Pow = 1
  }
  
  -- Send command
  local result, err = gree_protocol.send_command(config.ip, config.mac, params, config.key, config.sub_mac)
  
  if result then
    device:emit_event(capabilities.switch.switch.on())
    log.info("Device turned ON")
    -- Note: For multi-split systems, don't poll status after commands
    -- The command response is the authoritative state
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
    device:emit_event(capabilities.switch.switch.off())
    log.info("Device turned OFF")
    -- Note: For multi-split systems, don't poll status after commands
    -- The command response is the authoritative state
  else
    log.error("Failed to turn OFF: " .. tostring(err))
  end
end

-- Refresh command (manual status update)
function device_handler.refresh(driver, device, command)
  log.info("Refreshing device status: " .. device.label)
  device_handler.poll_device(driver, device)
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
        local sub_metadata = {
          type = "LAN",
          device_network_id = sub_network_id,
          label = "Gree AC Unit " .. i .. " (" .. device_info.mac:sub(-4) .. ")",
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
    else
      -- Single unit system - create normal device
      driver:try_create_device(metadata)
      log.info("Created device: " .. metadata.label .. " at " .. device_info.ip)
    end
  end
end

return device_handler