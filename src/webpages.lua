-- (c) Fabien Fleutot, 2014.
-- Released under the MIT public license.

---
-- Very simplistic web page.
-- 

require 'web.server'
require 'web.template'

--- Takes a record and turns it into a list of lines,
--  ordered alphabetically.
local function get_lines(asset)
  local record, msg = asset :record(3)
  if not record then return { { " Error ", msg, "" } } end
  local lines  = { }
  for name, value in pairs(record) do
    if tonumber(value) and value%1~=0 then
      value = string.format('%.2f', value)
    end
    local line = { name, value, bmv.units[name] or '' }
    table.insert(lines, line)
  end
  local function comp_lines(a, b) return a[1]<b[1] end
  table.sort(lines, comp_lines)
  return lines, record
end

--- Displays the current BMV state
web.site['bmv'] = web.template 'default' {
    title = [[Data Monitoring: Elorn's batteries]],
    body = [[
    <% local lines, r = get_lines(assets.bmv) 
       local power = r.current * r.voltage %>
    <h2>Instant power: <%=string.format('%+.0f', power)%>W</h2>
    <table style='border: 2px solid gray;'>
      <% for _, line in ipairs(lines) do
           local name, value, unit = unpack(line) %>
      <tr>
        <th class='data-name' style='background-color: gray; color: white; font-family: sans-serif'><%=name%></th>
        <td class='data-value' id='value_<%=value%>'><%=value%></td>
        <td class='data-unit'><%=unit%></td>
      </tr>
      <% end %>
     </table>
     <p><a href=''>Refresh</a></p>
]] }

--- Displays the current MPPT state
web.site['mppt'] = web.template 'default' {
    title = [[Data Monitoring: Elorn's batteries]],
    body = [[
    <% local lines, r = get_lines(assets.mppt) %>
    <h2>Instant power: <%=string.format('%+.0f', r.power_panels)%>W</h2>
    <table style='border: 2px solid gray;'>
      <% for _, line in ipairs(lines) do
           local name, value, unit = unpack(line) %>
      <tr>
        <th class='data-name' style='background-color: gray; color: white; font-family: sans-serif'><%=name%></th>
        <td class='data-value' id='value_<%=value%>'><%=value%></td>
        <td class='data-unit'><%=unit%></td>
      </tr>
      <% end %>
     </table>
     <p><a href=''>Refresh</a></p>
]] }


web.site['pic'] = [[
<!DOCTYPE html PUBLIC
  "-//W3C//DTD XHTML 1.0 Strict//EN"
  "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en">
  <head>
    <title></title>
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8"/>
    <script
       type="text/javascript"
       src="http://ajax.googleapis.com/ajax/libs/jquery/1.11.0/jquery.min.js">
    </script>
    <script type="text/javascript">

      function fill(record) {
        for(var key in record) {
          var value = record[key]
          $("#"+key).text(value)
          $("."+key).text(value)
        }
      }

      function refresh() {
        $.getJSON("data.json", fill)
      }

      var PERIOD = 5 // Refresh every `PERIOD` seconds

      $(document).ready(function() {
        $("refresh").click(refresh)
        setInterval(refresh, PERIOD*1000)
        refresh()
      })

    </script>
    <style type="text/css">
      #diagram {
        position:   relative;
        background: url('diagram.png');
        width:      900px;
        height:     647px;
        text-align: center;
        margin: auto;
      }
      .display {
        position:    absolute;
        font-family: "sans-serif";
        font-size:   18px;
        font-weight: bold;
        color:       #ff0000;
      }
      #GPS       { top: 105px; left:  80px; }
      #PV1       { top:  65px; left: 520px; }
      #PV2       { top: 152px; left: 340px; }
      #batteries { top: 217px; left: 190px; font-size: 24px; }
      #DC        { top: 245px; left: 520px; }
      #shore     { top: 387px; left: 235px; }
      #genset    { top: 509px; left: 235px; }
      #inv-DC    { top: 337px; left: 340px; }
      #inv-AC    { top: 450px; left: 520px; }
    </style>
  </head>
  <body>
    <button type="button" id="refresh">Refresh</button>
    <div id='diagram'>
      <p class='display' id='GPS'>
        <span id='latitude'>?</span>&deg;N <br/>
        <span id='longitude'>?</span>&deg;E
      </p>
      <p class='display' id='PV1'>
        <span id='power_panels'>?</span>W @ <span id='voltage_panels'>?</span>V
      </p>
      <p class='display' id='PV2'>
        <span class='voltage_battery'>?</span>V/<span id='current_battery'>?</span>A
      </p>
      <p class='display' id='shore'><span id='power_shore'>?</span>W</p>
      <p class='display' id='genset'><span id='power_genset'>?</span>W</p>
      <p class='display' id='DC'><span id='power_24v'>?</span>W</p>
      <p class='display' id='inv-DC'>
        <span class='voltage_battery'>?</span>V/<span id='current_inv'>?</span>A
      </p>
      <p class='display' id='inv-AC'><span id='power_ac'>?</span>W</p>
      <p class='display' id='batteries'>
        <span id='consummed_energy'>?</span>kWh<br/>
        (<span id='state_of_charge'>?</span>%)
      </p>
    </div>
  </body>
</html>
]]

web.site['data.json'] = {
  function (echo, env)
    local record = { power_panels = 123 } -- TODO fill with actual values
    local response = { }
    for k, v in ipairs(record) do
      table.insert(response, '"'..k..'": "'..v..'"')
    end
    echo("{\n  "..table.concat(response, ',\n  ')..'\n}')
  end
}
