# SmartThings Gree Air Conditioner Driver

A Samsung SmartThings Edge driver for Gree air conditioners using the ME31-00/C7 WiFi dongle module.

## Features
- Local control without cloud dependencies
- Auto-discovery of Gree AC units on local network
- Support for standard thermostat functions (temperature, mode, fan speed)
- Real-time status updates

## Supported Models
- Gree air conditioners with ME31-00/C7 WiFi module

## Installation
1. Package the driver: `tar -czf gree-driver.tar.gz src/ profiles/ config/ fingerprints.yml`
2. Install via SmartThings CLI or Developer Workspace

## Development
See `.github/copilot-instructions.md` for detailed development guidance.