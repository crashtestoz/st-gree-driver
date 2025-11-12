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
  return {
    ip = device.preferences.deviceIp or device:get_field("device_ip"),
    mac = device.preferences.deviceMac or device:get_field("device_mac"),
    key = device.preferences.encryptionKey or device:get_field("encryption_key"),
    sub_mac = device.preferences.subUnitMac or device:get_field("sub_unit_mac")
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
  
  -- Set initial values
  device:emit_event(capabilities.switch.switch.off())
  device:emit_event(capabilities.thermostatMode.thermostatMode.auto())
  device:emit_event(capabilities.thermostatCoolingSetpoint.coolingSetpoint({value = 24, unit = "C"}))
  device:emit_event(capabilities.temperatureMeasurement.temperature({value = 22, unit = "C"}))
  
  -- Start polling
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

-- Poll device status
function device_handler.poll_device(driver, device)
  local config = get_device_config(device)
  
  if not config.ip or not config.mac or not config.key then
    log.warn("Device not fully configured, skipping poll")
    return
  end
  
  log.debug("Polling device status...")
  
  -- Query status
  local params_to_query = {"Pow", "Mod", "SetTem", "WdSpd", "TemUn", "TemSen"}
  local status, err = gree_protocol.query_status(config.ip, config.mac, config.key, params_to_query)
  
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
  
  -- Build command
  local params = {
    Pow = 1,
    Mod = 1,  -- Default to Cool mode
    SetTem = 24,  -- Default to 24°C
    TemUn = 0  -- Celsius
  }
  
  -- Send command
  local result, err = gree_protocol.send_command(config.ip, config.mac, params, config.key, config.sub_mac)
  
  if result then
    device:emit_event(capabilities.switch.switch.on())
    log.info("Device turned ON")
    
    -- Poll immediately to update status
    device.thread:call_with_delay(1, function()
      device_handler.poll_device(driver, device)
    end)
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
  
  -- Build command
  local params = {
    Pow = 0
  }
  
  -- Send command
  local result, err = gree_protocol.send_command(config.ip, config.mac, params, config.key, config.sub_mac)
  
  if result then
    device:emit_event(capabilities.switch.switch.off())
    log.info("Device turned OFF")
    
    -- Poll immediately to update status
    device.thread:call_with_delay(1, function()
      device_handler.poll_device(driver, device)
    end)
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
  
  -- Discover Gree devices on the network
  local devices = gree_protocol.discover_devices()
  
  if not devices or #devices == 0 then
    log.warn("No Gree devices found during discovery")
    return
  end
  
  log.info("Found " .. #devices .. " Gree device(s)")
  
  -- Create metadata for each discovered device
  for _, device_info in ipairs(devices) do
    local metadata = {
      type = "LAN",
      device_network_id = device_info.mac,
      label = "Gree AC (" .. device_info.mac:sub(-4) .. ")",
      profile = "gree-ac",
      manufacturer = "Gree",
      model = device_info.name or "Air Conditioner",
      vendor_provided_label = device_info.name or "Gree Air Conditioner"
    }
    
    -- Add discovered device to SmartThings
    driver:try_create_device(metadata)
    log.info("Created device: " .. metadata.label .. " at " .. device_info.ip)
    
    -- If this is a multi-split system, create separate devices for each sub-unit
    if device_info.subCnt and device_info.subCnt > 1 then
      log.info("Multi-split system detected with " .. device_info.subCnt .. " sub-units")
      -- Note: Sub-unit discovery would require additional protocol calls
      -- For Version 1, users must manually configure sub-unit MACs in preferences
    end
  end
end

return device_handler