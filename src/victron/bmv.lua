-- (c) Fabien Fleutot, 2014.
-- Released under the MIT public license.

--- @module victron.bmv
--  Reads and decodes Victron BMV60x frames.
--
--  This module generates specific instances of the more generic handlers
--  provided by `victron.ve-direct`: it acquires the frames by pairs
--  (a snapshot frame and an history frame), converts label names into
--  more human-readable ones, and converts unusual units into more
--  familiar ones (ampers, volts, hours... the one s generally displayed
--  on the BMV's screen).
--

-- Incoming frame pair example:
-- V   26717
-- I   0
-- CE  0
-- SOC 1000
-- TTG -1
-- Alarm   OFF
-- Relay   OFF
-- AR  0
-- BMV 600S
-- FW  212
-- Checksum    ?
-- H1  0
-- H2  0
-- H3  0
-- H4  0
-- H5  0
-- H6  0
-- H7  26708
-- H8  26718
-- H9  0
-- H10 1
-- H11 0
-- H12 0
-- Checksum    ?

local checks = require 'checks'
local ved    = require 'victron.ve-direct'

--- Instance prototype
local P = { n_frames=2 }

local M = { prototype=P }

--- User-friendly names:
P.names = {
  BMV = 'model',
  FW  = 'firmware',
  AR  = 'alarm_reason',
  V   = 'voltage',
  VS  = 'voltage2',
  I   = 'current',
  CE  = 'consumed_energy',
  SOC = 'state_of_charge',
  TTG = 'time_to_go',
  H1  = 'discharge_max',
  H2  = 'discharge_last',
  H3  = 'discharge_average',
  H4  = 'discharge_n_cycles',
  H5  = 'discharge_n_full',
  H6  = 'ah_total',
  H7  = 'voltage_min',
  H8  = 'voltage_max',
  H9  = 'days_since_full_charge',
  H10 = 'n_auto_synchro',
  H11 = 'n_alarms_voltage_low',
  H12 = 'n_alarms_voltage_high',
  H13 = 'n_alarms_voltage2_low',
  H14 = 'n_alarms_voltage2_high',
  H15 = 'voltage2_min',
  H16 = 'voltage2_max',
  Relay = 'relay',
  Alarm = 'alarm',
}

-- Helper to generate `M.units`.
local units = {
  V='V', VS='V', I='A', CE='Ah', SOC='%', TTG='hours',
  H1='Ah', H2='Ah', H3='Ah', H6='Ah', H7='V', H8='V',
  H9='days', H15='V', H16='V'}

--- mane -> unit name correspondance table.
--  Not used by this module, but helpful for other modules exlpoiting the data.
P.units = { }; for k, v in pairs(units) do P.units[P.names[k]]=v end

--- Conversion factors, for values given in unusual units:
P.factors = {
  V   = 1000, -- mV      -> V
  VS  = 1000, -- mV      -> V
  I   = 1000, -- mA      -> A
  CE  = 1000, -- mAh     -> Ah
  SOC = 10,   -- per1000 -> percents
  TTG = function(x) return
    not tonumber(x) and x or
    x>=0 and x/60 or 
    "+infty" 
  end, -- minutes -> hours; negative -> +infty
  H1  = 1000, -- mAh     -> Ah
  H2  = 1000, -- mAh     -> Ah
  H3  = 1000, -- mAh     -> Ah
  H6  = 1000, -- mAh     -> Ah
  H7  = 1000, -- mV      -> V
  H8  = 1000, -- mV      -> V
  H9  = 86400,-- seconds -> days
  H15 = 1000, -- mV      -> V
  H16 = 1000, -- mV      -> V
}


function M.new(dev_file)
  checks('string')
  return ved.new(M.prototype, dev_file) 
end

return M