-- (c) Fabien Fleutot, 2014.
-- Released under the MIT public license.

local log   = require "log"
local sched = require "sched"
local web   = require "web.server"
local bmv   = require "victron.bmv"

require "bmv_web_pages"

local WEB_PORT = 9001

local function main()
    log.setlevel('ALL', 'VICTRON-BMV')
    log("APP", "INFO", "BMV monitoring example")
    web.start(WEB_PORT)
end
 
sched.run(main)
sched.loop()
