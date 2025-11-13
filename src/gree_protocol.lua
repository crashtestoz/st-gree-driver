-- Gree Protocol Implementation
-- UDP communication for Gree WiFi air conditioners
-- Based on: https://github.com/bekmansurov/gree-hvac-protocol

-- SmartThings Edge uses cosock (coroutine socket wrapper)
-- Fallback to regular socket for local testing
local log = require "log"
local socket
local json
local crypto = require "crypto"

-- Detect SmartThings Edge environment
local status, cosock = pcall(require, "cosock")
if status then
  -- SmartThings Edge environment
  socket = require "cosock.socket"
else
  -- Local testing environment  
  socket = require "socket"
end

-- JSON library
status, json = pcall(require, "st.json")
if not status then
  -- Fallback for local testing
  json = require "dkjson"
end

local gree_protocol = {}

-- Protocol constants
gree_protocol.BROADCAST_PORT = 7000
gree_protocol.DEVICE_PORT = 7000
gree_protocol.DISCOVERY_TIMEOUT = 5
gree_protocol.COMMAND_TIMEOUT = 2

-- Gree protocol parameter mappings
gree_protocol.PARAMS = {
  power = "Pow",           -- 0=off, 1=on
  mode = "Mod",            -- 0=auto, 1=cool, 2=dry, 3=fan, 4=heat
  temp_set = "SetTem",     -- Temperature setpoint (16-30°C)
  fan_speed = "WdSpd",     -- 0=auto, 1=low, 2=med-low, 3=medium, 4=med-high, 5=high
  air_mode = "Air",        -- 0=off, 1=inside, 2=outside, 3=mode3
  blow = "Blo",            -- 0=off, 1=on
  health = "Health",       -- 0=off, 1=on
  sleep = "SwhSlp",        -- 0=off, 1=on
  lights = "Lig",          -- 0=off, 1=on
  swing_vert = "SwUpDn",   -- 0=default, 1=full, 2-6=positions, 7=swing
  swing_horiz = "SwingLfRig", -- 0=default, 1=full, 2-6=positions, 7=swing
  quiet = "Quiet",         -- 0=off, 1=on, 2=auto
  turbo = "Turbo",         -- 0=off, 1=on
  power_save = "SvSt",     -- 0=off, 1=on
  temp_unit = "TemUn",     -- 0=celsius, 1=fahrenheit
  temp_sensor = "TemSen",  -- Current temperature from sensor
}

-- Device storage (will be persisted in SmartThings device state)
local devices = {}

-- Create UDP socket for communication
local function create_udp_socket()
  local udp = socket.udp()
  if not udp then
    log.error("Failed to create UDP socket")
    return nil
  end
  
  -- Bind to wildcard address on a random port to enable both sending AND receiving
  -- This is critical for receiving responses from the AC unit
  local ok, err = udp:setsockname("*", 0)
  if not ok then
    log.error("Failed to bind socket: " .. tostring(err))
    return nil
  end
  
  -- Enable broadcast for discovery
  udp:setoption("broadcast", true)
  
  udp:settimeout(gree_protocol.COMMAND_TIMEOUT)
  
  -- Log the local port we're bound to
  local ip, port = udp:getsockname()
  log.debug("UDP socket bound to " .. tostring(ip) .. ":" .. tostring(port))
  
  return udp
end

-- Broadcast discovery message
function gree_protocol.discover_devices()
  log.info("Starting Gree device discovery...")
  
  local udp = create_udp_socket()
  if not udp then
    return {}
  end
  
  -- Enable broadcast
  local ok, err = udp:setoption("broadcast", true)
  if not ok then
    log.error("Failed to enable broadcast: " .. tostring(err))
    udp:close()
    return {}
  end
  
  -- Create discovery message
  local discovery_msg = {
    t = "scan"
  }
  local msg_json = json.encode(discovery_msg)
  
  log.debug("Sending discovery broadcast: " .. msg_json)
  
  -- Try broadcast first, then fallback to specific IP if known
  local broadcast_addresses = {"255.255.255.255", "10.0.0.255"}
  local sent = false
  
  for _, addr in ipairs(broadcast_addresses) do
    local ok, err = udp:sendto(msg_json, addr, gree_protocol.BROADCAST_PORT)
    if ok then
      log.debug("Sent to " .. addr)
      sent = true
    else
      log.debug("Failed to send to " .. addr .. ": " .. tostring(err))
    end
  end
  
  if not sent then
    log.error("Failed to send discovery broadcast to any address")
    udp:close()
    return {}
  end
  
  -- Collect responses
  local discovered_devices = {}
  local start_time = socket.gettime()
  
  while socket.gettime() - start_time < gree_protocol.DISCOVERY_TIMEOUT do
    local data, ip, port = udp:receivefrom()
    
    if data then
      log.debug("Received discovery response from " .. ip .. ":" .. port)
      log.trace("Raw response: " .. data)
      
      local response = json.decode(data)
      
      -- Handle encrypted pack format
      if response and response.t == "pack" and response.pack then
        log.debug("Decrypting discovery response...")
        local decrypted = crypto.decrypt(response.pack, gree_protocol.GENERIC_KEY)
        if decrypted then
          response = json.decode(decrypted)
          log.trace("Decrypted response: " .. decrypted)
        end
      end
      
      if response and response.t == "dev" then
        local device_info = {
          ip = ip,
          port = port,
          mac = response.mac or response.cid,
          name = response.name,
          brand = response.brand,
          model = response.model,
          version = response.ver,
          cid = response.cid,
          subCnt = response.subCnt or 1
        }
        
        log.info("Discovered Gree device: " .. (device_info.name or "Unknown") .. " (" .. device_info.mac .. ") at " .. ip)
        table.insert(discovered_devices, device_info)
        
        -- Store for later use
        devices[device_info.mac] = device_info
      end
    end
  end
  
  udp:close()
  log.info("Discovery complete. Found " .. #discovered_devices .. " device(s)")
  
  return discovered_devices
end

-- Bind with device to get encryption key
function gree_protocol.bind_device(device_ip, device_mac)
  log.info("Binding with device: " .. device_mac .. " at " .. device_ip)
  
  local udp = create_udp_socket()
  if not udp then
    return nil, "Failed to create socket"
  end
  
  -- Create bind request (inner payload)
  local bind_msg = {
    mac = device_mac,
    t = "bind",
    uid = 0
  }
  local bind_json = json.encode(bind_msg)
  
  log.debug("Bind request payload: " .. bind_json)
  
  -- Encrypt with generic key
  local generic_key = "a3K8Bx%2r8Y7#xDh"
  local encrypted = crypto.encrypt(bind_json, generic_key)
  
  -- Wrap in pack structure
  local message = {
    cid = "app",
    i = 1,
    t = "pack",
    uid = 0,
    tcid = device_mac,
    pack = encrypted
  }
  
  local msg_json = json.encode(message)
  log.debug("Sending encrypted bind request (pack)")
  
  -- Send bind request
  local ok, err = udp:sendto(msg_json, device_ip, gree_protocol.DEVICE_PORT)
  if not ok then
    log.error("Failed to send bind request: " .. tostring(err))
    udp:close()
    return nil, "Send failed"
  end
  
  -- Wait for response
  local data, resp_ip, resp_port = udp:receivefrom()
  udp:close()
  
  if not data then
    log.error("No bind response received")
    return nil, "No response"
  end
  
  log.debug("Received bind response (encrypted pack)")
  
  -- Parse outer message
  local message = json.decode(data)
  if not message or not message.pack then
    log.error("Invalid bind response format")
    return nil, "Invalid format"
  end
  
  -- Decrypt the pack with generic key
  local decrypted = crypto.decrypt(message.pack, generic_key)
  if not decrypted then
    log.error("Failed to decrypt bind response")
    return nil, "Decryption failed"
  end
  
  log.debug("Decrypted bind response: " .. decrypted)
  
  -- Parse inner response
  local response = json.decode(decrypted)
  if not response then
    log.error("Failed to parse bind response JSON")
    return nil, "Invalid JSON"
  end
  
  -- Check response type (case-insensitive: "bindok" or "bindOk")
  local response_type = response.t and response.t:lower()
  if response_type ~= "bindok" then
    log.error("Invalid bind response type: " .. tostring(response.t))
    return nil, "Invalid response"
  end
  
  -- Extract encryption key
  local key = response.key
  if not key then
    log.error("No encryption key in bind response")
    return nil, "No key"
  end
  
  log.info("Successfully bound with device. Key: " .. key)
  
  -- Store key for this device
  if devices[device_mac] then
    devices[device_mac].key = key
  end
  
  return key
end

-- Send command to device
function gree_protocol.send_command(device_ip, device_mac, params, encryption_key, sub_unit_mac)
  log.info("Sending command to device: " .. device_mac)
  if sub_unit_mac then
    log.info("Sub-unit MAC: " .. sub_unit_mac)
  end
  log.debug("Parameters: " .. json.encode(params))
  
  local udp = create_udp_socket()
  if not udp then
    return nil, "Failed to create socket"
  end
  
  -- Build columns and values arrays
  local cols = {}
  local dat = {}
  for param_name, value in pairs(params) do
    table.insert(cols, param_name)
    table.insert(dat, value)
  end
  
  -- Create command payload
  local command = {
    opt = cols,
    p = dat,
    t = "cmd"
  }
  
  -- Add sub-unit MAC if provided (for multi-split systems)
  if sub_unit_mac then
    command.sub = sub_unit_mac
  end
  
  local command_json = json.encode(command)
  log.debug("Command payload: " .. command_json)
  
  -- Encrypt command
  local encrypted = crypto.encrypt(command_json, encryption_key)
  
  -- Create message
  local message = {
    cid = "app",
    i = 0,
    t = "pack",
    uid = 0,
    tcid = device_mac,
    pack = encrypted
  }
  
  local msg_json = json.encode(message)
  log.debug("Sending encrypted message: " .. msg_json)
  
  -- Send command
  log.debug("Sending to " .. device_ip .. ":" .. gree_protocol.DEVICE_PORT)
  local ok, err = udp:sendto(msg_json, device_ip, gree_protocol.DEVICE_PORT)
  if not ok then
    log.error("Failed to send command: " .. tostring(err))
    udp:close()
    return nil, "Send failed"
  end
  
  log.debug("Waiting for command response (timeout: " .. gree_protocol.COMMAND_TIMEOUT .. "s)...")
  
  -- Wait for response
  local data, resp_ip, resp_port = udp:receivefrom()
  
  if not data then
    log.warn("No command response received (may be normal)")
    log.debug("receivefrom returned: data=" .. tostring(data) .. ", ip=" .. tostring(resp_ip) .. ", port=" .. tostring(resp_port))
    udp:close()
    return true -- Consider it successful even without response
  end
  
  log.debug("Received response from " .. tostring(resp_ip) .. ":" .. tostring(resp_port) .. ", length: " .. #data)
  udp:close()
  
  log.debug("Received command response: " .. data)
  
  local response = json.decode(data)
  if response and response.pack then
    -- Decrypt response
    local decrypted = crypto.decrypt(response.pack, encryption_key)
    log.debug("Decrypted response: " .. decrypted)
    
    local resp_data = json.decode(decrypted)
    return resp_data
  end
  
  return true
end

-- Query device status
function gree_protocol.query_status(device_ip, device_mac, encryption_key, params_to_query, sub_unit_mac)
  log.info("Querying status from device: " .. device_mac)
  if sub_unit_mac then
    log.info("Sub-unit MAC: " .. sub_unit_mac)
  end
  
  local udp = create_udp_socket()
  if not udp then
    return nil, "Failed to create socket"
  end
  
  -- Default parameters to query
  params_to_query = params_to_query or {
    "Pow", "Mod", "SetTem", "WdSpd", "Air", "Blo", "Health",
    "SwhSlp", "Lig", "SwUpDn", "SwingLfRig", "Quiet", "Turbo",
    "SvSt", "TemUn", "TemSen"
  }
  
  -- Create status query
  local query = {
    cols = params_to_query,
    mac = device_mac,
    t = "status"
  }
  
  -- Add sub-unit MAC if provided (for multi-split systems)
  if sub_unit_mac then
    query.sub = sub_unit_mac
  end
  
  local query_json = json.encode(query)
  log.debug("Status query payload: " .. query_json)
  
  -- Encrypt query
  local encrypted = crypto.encrypt(query_json, encryption_key)
  
  -- Create message
  local message = {
    cid = "app",
    i = 0,
    t = "pack",
    uid = 0,
    tcid = device_mac,
    pack = encrypted
  }
  
  local msg_json = json.encode(message)
  log.debug("Sending encrypted status query: " .. msg_json)
  
  -- Send query
  log.debug("Sending to " .. device_ip .. ":" .. gree_protocol.DEVICE_PORT)
  local ok, err = udp:sendto(msg_json, device_ip, gree_protocol.DEVICE_PORT)
  if not ok then
    log.error("Failed to send status query: " .. tostring(err))
    udp:close()
    return nil, "Send failed"
  end
  
  log.debug("Waiting for status response (timeout: " .. gree_protocol.COMMAND_TIMEOUT .. "s)...")
  
  -- Wait for response
  local data, resp_ip, resp_port = udp:receivefrom()
  
  if not data then
    log.error("No status response received (timeout or error)")
    log.debug("receivefrom returned: data=" .. tostring(data) .. ", ip=" .. tostring(resp_ip) .. ", port=" .. tostring(resp_port))
    udp:close()
    return nil, "No response"
  end
  
  log.debug("Received response from " .. tostring(resp_ip) .. ":" .. tostring(resp_port) .. ", length: " .. #data)
  udp:close()
  
  log.debug("Received status response: " .. data)
  
  local response = json.decode(data)
  if not response or not response.pack then
    log.error("Invalid status response")
    return nil, "Invalid response"
  end
  
  -- Decrypt response
  local decrypted = crypto.decrypt(response.pack, encryption_key)
  log.debug("Decrypted status: " .. decrypted)
  
  local status_data = json.decode(decrypted)
  
  -- Convert cols/dat arrays to key-value pairs
  if status_data and status_data.cols and status_data.dat then
    local status = {}
    for i, col in ipairs(status_data.cols) do
      status[col] = status_data.dat[i]
    end
    return status
  end
  
  return status_data
end

-- Smart refresh: Use command-based query for sub-units (status queries don't work)
-- This sends a "read" command that returns current state in val array
function gree_protocol.refresh_status(device_ip, device_mac, encryption_key, sub_unit_mac)
  log.info("Smart refresh for device: " .. device_mac)
  if sub_unit_mac then
    log.info("Sub-unit MAC: " .. sub_unit_mac)
  end
  
  local udp = create_udp_socket()
  if not udp then
    return nil, "Failed to create socket"
  end
  
  -- Parameters we want to query
  local params = {"Pow", "Mod", "SetTem", "WdSpd", "TemUn", "TemSen", "SwUpDn", "Quiet", "Turbo", "Lig"}
  
  -- Create a "query" command - we request current values
  -- IMPORTANT: Use p=[] with same count as opt[] to query without changing state
  -- The AC will return actual state in val array, p values are ignored for reads
  local command = {
    opt = params,
    p = {},  -- Empty array - don't send any values, just query
    t = "cmd"
  }
  
  -- Add sub-unit MAC if provided
  if sub_unit_mac then
    command.sub = sub_unit_mac
  end
  
  local command_json = json.encode(command)
  log.debug("Smart refresh command payload: " .. command_json)
  
  -- Encrypt command
  local encrypted = crypto.encrypt(command_json, encryption_key)
  
  -- Create message
  local message = {
    cid = "app",
    i = 0,
    t = "pack",
    uid = 0,
    tcid = device_mac,
    pack = encrypted
  }
  
  local msg_json = json.encode(message)
  log.debug("Sending smart refresh command")
  
  -- Send command
  local ok, err = udp:sendto(msg_json, device_ip, gree_protocol.DEVICE_PORT)
  if not ok then
    udp:close()
    return nil, "Failed to send: " .. tostring(err)
  end
  
  -- Wait for response
  udp:settimeout(3)
  local data, err = udp:receive()
  udp:close()
  
  if not data then
    return nil, "No response: " .. tostring(err)
  end
  
  log.debug("Received smart refresh response")
  
  local response = json.decode(data)
  if response and response.pack then
    -- Decrypt response
    local decrypted = crypto.decrypt(response.pack, encryption_key)
    log.debug("Decrypted response: " .. decrypted)
    
    local resp_data = json.decode(decrypted)
    
    -- Convert opt/val arrays to key-value pairs
    if resp_data and resp_data.opt and resp_data.val then
      local status = {
        _raw_response = resp_data  -- Keep raw for debugging
      }
      for i, opt in ipairs(resp_data.opt) do
        status[opt] = resp_data.val[i]
      end
      log.info("Smart refresh returned state: Pow=" .. tostring(status.Pow) .. 
               ", Mod=" .. tostring(status.Mod) .. 
               ", SetTem=" .. tostring(status.SetTem))
      return status
    end
    
    return resp_data
  end
  
  return nil, "No pack in response"
end

-- Get stored device info
function gree_protocol.get_device(device_mac)
  return devices[device_mac]
end

-- Discovery handler for SmartThings driver
function gree_protocol.discovery_handler(driver, opts, cont)
  log.info("Gree AC discovery handler called")
  
  local discovered = gree_protocol.discover_devices()
  
  for _, device_info in ipairs(discovered) do
    -- Create SmartThings device metadata
    local metadata = {
      type = "LAN",
      device_network_id = device_info.mac,
      label = device_info.name or "Gree Air Conditioner",
      profile = "gree-ac",
      manufacturer = device_info.brand or "Gree",
      model = device_info.model or "Unknown",
      vendor_provided_label = device_info.name
    }
    
    -- Try to create device
    log.info("Adding discovered device: " .. metadata.label)
    cont(driver, metadata)
  end
end

return gree_protocol