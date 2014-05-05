-- (c) Fabien Fleutot, 2014.
-- Released under the MIT public license.

local log = require 'log'
local sched = require 'sched'
local bmv = require 'victron.bmv'
local airvantage = require 'airvantage'
local timer = require 'timer'

--- @module datalog.airvantage
--  Regularly log data and pushes it to an AirVantage server.
--  
local M = { }

-- TODO should be remotely configurable (stored in airvantage.tree)
M.PERIOD = 60
M.POLICY = "hourly"

--- Airvantage data-staging tables
M.tables = { }

--- Columns to report from BMV records
M.bmv_columns_list = { 
  'voltage', 'current', 'state_of_charge', 'time_to_go', 
  'power', 'timestamp' }
  
M.bmv_columns_set  = { }
for _, x in pairs(M.bmv_columns_list) do  M.bmv_columns_set[x]=true end

--- Removes unwanted columns, adds missing ones.
local function clean_bmv_record(record)
  for k in pairs(record) do
    if not M.bmv_columns_set[k] then record[k]=nil end
  end
  record.power = record.voltage * record.current
  record.timestamp = os.time()
end

--- Acquires and accumulates one BMV record.
function M.log()
  local record, msg = bmv.record()
  if not record then
    log('DATALOG-AIRVANTAGE', 'ERROR', "Can't read BMV data: %s", msg)
  else
    clean_bmv_record(record)
    M.tables.bmv :pushrow(record)
  end
end

--- Start periodically logging
function M.start()
  if M.timer then return nil, "Already started" end
  log('DATALOG-AIRVANTAGE', 'INFO', "Start logging every %d seconds", M.PERIOD)
  M.log()
  M.timer = timer.new(-math.abs(M.PERIOD), M.log)
  return 'ok'
end

--- Stops periodically logging
function M.stop()
  if not M.timer then return nil, "Was not started" end
  M.timer :cancel()
  M.timer=nil
  return 'ok'
end

--- Initializes the agent and logging tables.
function M.init()
  airvantage.init()
  M.asset = airvantage.newasset 'boat'
  M.asset :start()
  M.tables.bmv = M.asset:newtable('batteries', M.bmv_columns_list, 'ram', M.POLICY)
end

return M