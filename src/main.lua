-- (c) Fabien Fleutot, 2014.
-- Released under the MIT public license.

local log     = require "log"
local sched   = require "sched"
local web     = require "web.server"
local datalog = require "datalog.airvantage"
local shell   = require 'shell.telnet'

local WEB_PORT = 9001
local BMV_DEV_FILE = '/dev/ttyAMA0'

bmv = assert(require 'victron.bmv'.new(BMV_DEV_FILE))
require "bmv_web_pages"

local function main()
  log.setlevel('ALL', 'VICTRON-VED')
  log("APP", "INFO", "BMV monitoring example")
  web.start(WEB_PORT)
  shell.init{ address='0.0.0.0', port=3000, editmode='edit', historysize=64 }
  datalog.init(bmv)
  datalog.start()
end
 
sched.run(main)
sched.loop()
