import sys
from lupa import lua52
L = lua52.LuaRuntime(unpack_returned_tuples=True)
L.globals().MODFILE = sys.argv[1]
L.globals().MODE = sys.argv[2]
L.execute(r'''
CLIENT = MODE == "sp"; SERVER = MODE == "mp"
hooks, out, now = {}, {}, 100
Hook = { Add = function(ev, name, fn) hooks[ev] = fn end }
Game = { IsMultiplayer = SERVER, SendDirectChatMessage = function(m, c) out[#out+1] = c.Name .. "> " .. m.text end }
GUI = { AddMessage = function(t, c, l) out[#out+1] = "GUI> " .. t end }
Timer = { GetTime = function() return now end }
function Color() return {} end
ChatMessageType = { Server = 1 }
ChatMessage = { Create = function(_, t) return { text = t } end }
print = function(s) out[#out+1] = "LOG> " .. s end
local function mk(name, comps, cond)
  return { Name = name, Condition = cond or 100, ConditionPercentage = cond or 100, Prefab = { Identifier = { Value = name } },
           GetComponentString = function(c) return comps[c] end }
end
meter = mk("EG_Multimeter", {})
jb = mk("Junction Box", { PowerTransfer = { PowerConnections = { {Grid=nil}, {Grid={Power=5000, Load=2000}} }, Voltage = 2.5, OverloadVoltage = 2, CanBeOverloaded = true, Overload = true, PowerLoad = 0 } })
jbok = mk("Junction Box", { PowerTransfer = { PowerConnections = {}, Voltage = 1.0, OverloadVoltage = 2, CanBeOverloaded = true, Overload = false, PowerLoad = 900 } })
jbbroken = mk("Junction Box", { PowerTransfer = {} }, 0)
bat = mk("Battery", { PowerContainer = { ChargePercentage = 63.4, Charge = 634, Capacity = 1000, CurrPowerOutput = 120, MaxOutPut = 500, RechargeSpeed = 0, MaxRechargeSpeed = 500 } })
pump = mk("Pump", { Powered = { Voltage = 0.3, MinVoltage = 0.5, CurrPowerConsumption = 30, PowerConsumption = 100 } })
crate = mk("Crate", {})
user = { ID = 7 }
Client = { ClientList = { { Name = "Other", Character = {} }, { Name = "Me", Character = user } } }
''')
L.execute('loadfile(MODFILE)()')
L.execute(r'''
local use = hooks["item.use"]
for _, t in ipairs({ jb, jbok, jbbroken, bat, pump, crate }) do
  user.FocusedItem = t; now = now + 2; use(meter, user, nil, nil)
end
user.FocusedItem = nil; now = now + 2; use(meter, user, nil, nil)
user.FocusedItem = pump; now = now + 0.1; use(meter, user, nil, nil) -- throttled, no output
use(crate, user, nil, nil) -- not a multimeter, ignored
''')
for s in L.globals().out.values(): print(s)
