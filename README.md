# Multimeter

Barotrauma handheld tool for electricians (item + Lua). Point at a junction box, battery or powered device and press use to read its electrical values.

## Readings

- **Junction boxes:** grid power and load, voltage (supply/load ratio), overload threshold and whether the box is overloaded.
- **Relays:** output grid power, load and voltage, with explicit off and disconnected-output statuses. Output grid power can include other sources connected to that grid.
- **Batteries:** charge percent, charge/effective capacity (including modifiers), output, recharge speed.
- **Other powered devices:** voltage, minimum voltage, current and nominal power consumption.

In multiplayer the result is sent to the user as a chat message, in single player it appears as an on-screen message. Readings are throttled to once per second per character.

## Languages

Readings and the item's name/description follow each player's game language. 14 languages supported: Brazilian Portuguese, Castilian Spanish, English, French, German, Japanese, Korean, Latin American Spanish, Polish, Russian, Simplified Chinese, Traditional Chinese, Turkish, Ukrainian. In multiplayer every player sees readings in their own client language; unsupported languages fall back to English.

## Requirements

- Barotrauma 1.13.4.0
- [Lua For Barotrauma](https://github.com/evilfactory/LuaCsForBarotrauma) enabled

## Install

Copy this folder into `<Steam>/steamapps/common/Barotrauma/LocalMods/Multimeter` and enable it plus Lua For Barotrauma in Settings -> Mods. Spawn one with `spawnitem eg_multimeter inventory`, craft it from iron (Mechanical 20, same recipe as the screwdriver), or buy it from merchants (same price and availability as the screwdriver).

## Status

Version 0.3.0. Logic is unit-tested against a mocked game API. **Not yet tested in a real game.** Open questions: whether LMB still fires while a device is focused, and whether the server sees the focused item at that moment.

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
