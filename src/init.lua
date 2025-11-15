-- SmartThings Gree Air Conditioner Driver - Version 1.3.6
-- Copyright (c) 2025
-- Features: ON/OFF control, Temperature setpoint control, Mode control (auto/cool/dry/fan/heat)
-- Fixed: Prevents duplicate device creation during discovery
-- Multi-split support with smart refresh (command-based status queries)
-- Auto-configuration: IP, MAC, and encryption key auto-detected
-- Manual configuration: Sub-unit MAC (for multi-split systems)

local Driver = require "st.driver"
local capabilities = require "st.capabilities"
local log = require "log"

-- Import our modules
local gree_protocol = require "gree_protocol"
local device_handler = require "device_handler"

-- Driver initialization
local function driver_init(driver)
  log.info("Starting Gree AC driver - Version 1.3.6 - Mode control with explicit supported modes")
  log.info("Features: ON/OFF control, Temperature setpoint control, Mode control (auto/cool/dry/fan/heat), Manual refresh")
  log.info("Multi-split: Auto-creates sub-unit devices, requires sub_mac configuration in settings")
  log.info("See README for multi-split configuration instructions")
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
    -- Switch ON/OFF control
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = device_handler.switch_on,
      [capabilities.switch.commands.off.NAME] = device_handler.switch_off
    },
    -- Temperature setpoint control (v1.1.1)
    [capabilities.thermostatCoolingSetpoint.ID] = {
      [capabilities.thermostatCoolingSetpoint.commands.setCoolingSetpoint.NAME] = device_handler.set_cooling_setpoint
    },
    -- Thermostat mode control (v1.3.4)
    [capabilities.thermostatMode.ID] = {
      [capabilities.thermostatMode.commands.setThermostatMode.NAME] = device_handler.set_thermostat_mode
    },
    -- Manual status refresh
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = device_handler.refresh
    }
  }
}

-- Create and run the driver
local driver = Driver("gree-ac-driver", driver_config)
  log.info("Starting Gree AC driver - Auto-create sub-unit devices")
driver:run()