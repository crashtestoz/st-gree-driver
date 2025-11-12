-- SmartThings Gree Air Conditioner Driver
-- Copyright (c) 2025

local Driver = require "st.driver"
local log = require "log"

-- Import our modules
local gree_protocol = require "gree_protocol"
local device_handler = require "device_handler"

-- Driver configuration
local driver_config = {
  discovery = gree_protocol.discovery_handler,
  lifecycle_handlers = {
    init = device_handler.device_init,
    added = device_handler.device_added,
    removed = device_handler.device_removed
  },
  capability_handlers = {
    [capabilities.thermostatCoolingSetpoint.ID] = {
      [capabilities.thermostatCoolingSetpoint.commands.setCoolingSetpoint.NAME] = device_handler.set_cooling_setpoint
    },
    [capabilities.thermostatMode.ID] = {
      [capabilities.thermostatMode.commands.setThermostatMode.NAME] = device_handler.set_thermostat_mode
    },
    [capabilities.fanSpeed.ID] = {
      [capabilities.fanSpeed.commands.setFanSpeed.NAME] = device_handler.set_fan_speed
    },
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = device_handler.switch_on,
      [capabilities.switch.commands.off.NAME] = device_handler.switch_off
    }
  }
}

-- Create and run the driver
local driver = Driver("gree-ac-driver", driver_config)
log.info("Starting Gree AC driver")
driver:run()