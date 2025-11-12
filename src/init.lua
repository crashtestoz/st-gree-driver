-- SmartThings Gree Air Conditioner Driver - Version 1.0
-- Copyright (c) 2025
-- Features: ON/OFF control, Mode display (read-only), Temperature display (read-only)

local Driver = require "st.driver"
local capabilities = require "st.capabilities"
local log = require "log"

-- Import our modules
local gree_protocol = require "gree_protocol"
local device_handler = require "device_handler"

-- Driver initialization
local function driver_init(driver)
  log.info("Gree Air Conditioner Driver initialized - Version 1.0")
  log.info("Features: ON/OFF control, Mode display, Temperature display")
end

-- Driver configuration
local driver_config = {
  discovery = device_handler.discovery_handler,
  lifecycle_handlers = {
    init = driver_init,
    added = device_handler.device_added,
    driverSwitched = device_handler.device_init,
    infoChanged = device_handler.device_init,
    removed = device_handler.device_removed
  },
  capability_handlers = {
    -- Version 1: Switch ON/OFF control only
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = device_handler.switch_on,
      [capabilities.switch.commands.off.NAME] = device_handler.switch_off
    },
    -- Manual status refresh
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = device_handler.refresh
    }
    -- Note: Mode and temperature are read-only in Version 1
    -- Future versions will add control capabilities
  }
}

-- Create and run the driver
local driver = Driver("gree-ac-driver", driver_config)
log.info("Starting Gree AC driver - Version 1.0")
driver:run()