-- (c) Fabien Fleutot, 2014.
-- Released under the MIT public license.

local log     = require "log"
local sched   = require "sched"
local web     = require "web.server"
local datalog = require "datalog.airvantage"
local shell   = require 'shell.telnet'

local WEB_PORT = 9001

--- Associates USB product ids with the asset they're attached to.
local ASSET_USB_ID = {
  ['067b:2303'] = 'bmv',
  ['0403:6001'] = 'mppt',
  ['0403:6015'] = 'multiplus'
}

-- Web server main page
require "webpages"

--- Translates product id into `/dev/ttyUSB<X>` serial port device,
--  according to product ids in `ASSET_USB_ID`.
--  @return a table associating asset names with Unix device file names
local function find_devices()
  local f = assert(io.popen("/usr/local/bin/lsttyusb","r"))
  local r = { }
  while true do
    local line = f:read'*l'
    if not line then break end
    local usb_id, dev_file = line :match "^(.-) = (.*)$"
    local asset_id = usb_id and ASSET_USB_ID[usb_id]
    if asset_id then
      log('APP', 'INFO', "Found %s on device %s", asset_id, dev_file)
      r[asset_id] = dev_file
    end 
  end
  return r
end

assets = { }

--- Starts device monitoring modules
local function setup_devices()
  local dev = find_devices()
  for _, name in ipairs{ 'bmv', 'mppt' } do
    local filename = dev[name]
    if filename then
      local x, msg = require('victron.'..name).new (filename)
      log('APP', 'INFO', "Start monitoring %s on %s", name, filename)
      if x then assets[name]=x
      else log('APP', 'ERROR', "Cannot connect with "..name) end
    end
  end
end

local function main()
  log.setlevel('ALL', 'VICTRON-VED', 'APP')
  log("APP", "INFO", " ***** STARTING APPLICATION ELORN_ENERGY *****")
  shell.init{ address='0.0.0.0', port=3000, editmode='edit', historysize=64 }
  setup_devices()
  web.start(WEB_PORT)
  datalog.init(assets)
  datalog.start()
end

-- Log in a file
logfile = io.open('/var/log/elorn_energy', 'a')
logfile :write('\n')

function log.displaylogger(mod, level, msg)
  logfile :write (msg..'\n')
  logfile :flush()
end
log.setlevel('INFO', 'SCHED')
log.setlevel('ALL')

sched.run(main)
sched.loop()
