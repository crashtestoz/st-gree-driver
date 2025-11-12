#!/usr/bin/env lua

-- Test script for Gree protocol implementation
-- Tests discovery, binding, and basic commands

-- Stub out SmartThings-specific modules for testing
package.loaded["cosock.socket"] = require "socket"
package.loaded["st.base64"] = {
  encode = function(data)
    local b64chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    return ((data:gsub('.', function(x) 
        local r,b='',x:byte()
        for i=8,1,-1 do r=r..(b%2^i-b%2^(i-1)>0 and '1' or '0') end
        return r;
    end)..'0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
        if (#x < 6) then return '' end
        local c=0
        for i=1,6 do c=c+(x:sub(i,i)=='1' and 2^(6-i) or 0) end
        return b64chars:sub(c+1,c+1)
    end)..({ '', '==', '=' })[#data%3+1])
  end,
  decode = function(data)
    local b64chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    data = string.gsub(data, '[^'..b64chars..'=]', '')
    return (data:gsub('.', function(x)
        if (x == '=') then return '' end
        local r,f='',(b64chars:find(x)-1)
        for i=6,1,-1 do r=r..(f%2^i-f%2^(i-1)>0 and '1' or '0') end
        return r;
    end):gsub('%d%d%d?%d?%d?%d?%d?%d?', function(x)
        if (#x ~= 8) then return '' end
        local c=0
        for i=1,8 do c=c+(x:sub(i,i)=='1' and 2^(8-i) or 0) end
        return string.char(c)
    end))
  end
}
package.loaded["log"] = {
  info = function(msg) print("[INFO] " .. msg) end,
  debug = function(msg) print("[DEBUG] " .. msg) end,
  trace = function(msg) print("[TRACE] " .. msg) end,
  warn = function(msg) print("[WARN] " .. msg) end,
  error = function(msg) print("[ERROR] " .. msg) end
}

package.path = package.path .. ";./src/?.lua"

local gree_protocol = require "gree_protocol"
local json = require "dkjson"

print("=== Gree Protocol Test Suite ===\n")

-- Test 1: Discovery
print("Test 1: Device Discovery")
print("Broadcasting discovery message on port 7000...")
local devices = gree_protocol.discover_devices()

if #devices == 0 then
    print("❌ No devices found")
    print("\nNote: Make sure your Gree AC is:")
    print("  - Connected to the same network")
    print("  - WiFi module is powered on")
    print("  - Not in sleep/power-saving mode")
    os.exit(1)
end

print("✓ Found " .. #devices .. " device(s)\n")

for i, device in ipairs(devices) do
    print(string.format("Device %d:", i))
    print("  Name: " .. (device.name or "Unknown"))
    print("  IP: " .. device.ip)
    print("  MAC: " .. device.mac)
    print("  Brand: " .. (device.brand or "Unknown"))
    print("  Model: " .. (device.model or "Unknown"))
    print("")
end

-- Use first device for testing
local device = devices[1]

-- Test 2: Binding
print("\nTest 2: Device Binding")
print("Attempting to bind with " .. device.name .. " (" .. device.mac .. ")...")

local key, err = gree_protocol.bind_device(device.ip, device.mac)

if not key then
    print("❌ Binding failed: " .. tostring(err))
    os.exit(1)
end

print("✓ Successfully bound to device")
print("  Encryption key: " .. key)

-- Test 3: Status Query
print("\nTest 3: Status Query")
print("Querying device status...")

local status, err = gree_protocol.query_status(device.ip, device.mac, key)

if not status then
    print("❌ Status query failed: " .. tostring(err))
else
    print("✓ Status retrieved successfully:")
    print(json.encode(status, { indent = true }))
    
    -- Decode common parameters
    print("\nDecoded Status:")
    if status.Pow ~= nil then
        print("  Power: " .. (status.Pow == 1 and "ON" or "OFF"))
    end
    if status.Mod ~= nil then
        local modes = {"Auto", "Cool", "Dry", "Fan", "Heat"}
        print("  Mode: " .. (modes[status.Mod + 1] or "Unknown"))
    end
    if status.SetTem ~= nil then
        print("  Set Temperature: " .. status.SetTem .. "°C")
    end
    if status.TemSen ~= nil then
        print("  Current Temperature: " .. status.TemSen .. "°C")
    end
    if status.WdSpd ~= nil then
        local speeds = {"Auto", "Low", "Med-Low", "Medium", "Med-High", "High"}
        print("  Fan Speed: " .. (speeds[status.WdSpd + 1] or "Unknown"))
    end
end

-- Test 4: Send Command (optional - uncomment to test)
-- print("\nTest 4: Send Command")
-- print("Attempting to turn device ON...")
-- local params = {
--     Pow = 1  -- Turn on
-- }
-- local result, err = gree_protocol.send_command(device.ip, device.mac, params, key)
-- if result then
--     print("✓ Command sent successfully")
-- else
--     print("❌ Command failed: " .. tostring(err))
-- end

print("\n=== All tests completed ===")
print("\nDevice is ready for SmartThings integration!")
print("Next step: Implement device_handler.lua for capability mappings")