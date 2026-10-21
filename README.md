# Multimeter

Barotrauma handheld tool for electricians (item + Lua). Point at a junction box, battery or powered device and press use to read its electrical values.

## Readings

- **Junction boxes and relays:** grid power and load, voltage (supply/load ratio), overload threshold and whether the box is overloaded.
- **Batteries:** charge percent, charge/capacity, output, recharge speed.
- **Other powered devices:** voltage, minimum voltage, current and nominal power consumption.

In multiplayer the result is sent to the user as a chat message, in single player it appears as an on-screen message. Readings are throttled to once per second per character.

## Requirements

- Barotrauma 1.13.4.0
- [Lua For Barotrauma](https://github.com/evilfactory/LuaCsForBarotrauma) enabled

## Install

Copy this folder into `<Steam>/steamapps/common/Barotrauma/LocalMods/Multimeter` and enable it plus Lua For Barotrauma in Settings -> Mods. Spawn one with `spawnitem eg_multimeter inventory`, or craft it from plastic and copper (Electrical 20).

## Status

Version 0.1.0. Logic is unit-tested against a mocked game API. **Not yet tested in a real game.** Open questions: whether LMB still fires while a device is focused, and whether the server sees the focused item at that moment.

## Tests

```
pip install lupa
python tests/test_multimeter.py
```

The suite asserts readings and status messages, per-character cooldowns, private multiplayer
delivery, single-player GUI delivery, ignored calls, and recovery after a measurement error.
It also checks that multiplayer clients do not register a duplicate measurement hook.
These checks use Lua 5.2 with mocked game APIs; they do not replace an in-game test.

To run only one mode, use `python tests/test_multimeter.py Lua/Autorun/Multimeter.lua mp`
or replace `mp` with `sp`.
