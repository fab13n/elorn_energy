-- (c) Fabien Fleutot, 2014.
-- Released under the MIT public license.

---
-- Very simplistic web page.
-- 

require 'web.server'
require 'web.template'

--- Returns all the lines from a BMV request, as triplets,
--  sorted by their name's alphabetic order.
function web_server_get_bmv_lines()
  local record, msg = bmv :record(3)
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
  return lines
end

--- Display the current state
web.site[''] = web.template 'default' {
    title = [[Data Monitoring: Elorn's batteries]],
    body = [[
    <% local record = web_server_get_bmv_lines() %>
    <p>Instant power: <%=record.current * record.voltage%>W</p>
    <table style='border: 2px solid gray;'>
      <% for _, line in ipairs(record) do
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
