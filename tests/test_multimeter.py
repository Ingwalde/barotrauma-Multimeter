"""Assert Multimeter behavior against a mocked Lua 5.2 game API."""
import argparse
from pathlib import Path
import unittest

from lupa import lua52

MODFILE = Path(__file__).resolve().parents[1] / 'Lua/Autorun/Multimeter.lua'


def runtime(mode):
    lua = lua52.LuaRuntime(unpack_returned_tuples=True)
    lua.globals().MODFILE = MODFILE.as_posix()
    lua.globals().MODROOT = MODFILE.parents[2].as_posix()
    lua.globals().MODE = mode
    lua.execute(r'''
        CLIENT = MODE ~= 'mp'; SERVER = MODE == 'mp'
        hooks, messages, logs, now = {}, {}, {}, 100
        Hook = {Add=function(event, name, fn) hooks[event]=fn end}
        Game = {
            IsMultiplayer = MODE ~= 'sp',
            Settings = {CurrentConfig={Language={Value='Ukrainian'}}},
            SendDirectChatMessage=function(msg, client)
                messages[#messages+1]={text=msg.text, recipient=client.Name, channel='chat'}
            end
        }
        GUI = {AddMessage=function(text, color, duration)
            messages[#messages+1]={text=text, channel='gui', duration=duration}
        end}
        Timer = {GetTime=function() return now end}
        function Color() return {} end
        ChatMessageType = {Server=1}
        ChatMessage = {Create=function(_, text) return {text=text} end}
        print = function(text) logs[#logs+1]=text end
        function item(name, components, condition)
            return {Name=name, Condition=condition or 100, ConditionPercentage=condition or 100,
                Prefab={Identifier={Value=name}},
                GetComponentString=function(kind) return components[kind] end}
        end
        meter=item('EG_Multimeter',{})
        transfer={PowerConnections={{}, {Grid={Power=5000,Load=2000}}},
            Voltage=2.5, OverloadVoltage=2, CanBeOverloaded=true, Overload=true, PowerLoad=900}
        junction=item('Junction Box',{PowerTransfer=transfer})
        relayInput={Name='power_in',Grid={Power=5000,Load=2000,Voltage=2.5}}
        relayOutput={Name='power_out',Grid={Power=300,Load=1000,Voltage=0.3}}
        relayComponent={PowerConnections={relayInput,relayOutput},IsOn=true,Voltage=2.5}
        relay=item('Relay',{RelayComponent=relayComponent,PowerTransfer=relayComponent})
        battery=item('Battery',{PowerContainer={ChargePercentage=63.4,Charge=634,Capacity=1000,
            GetCapacity=function() return 1000 end,
            CurrPowerOutput=120,MaxOutPut=500,RechargeSpeed=25,MaxRechargeSpeed=200}})
        powered={Voltage=0.3,MinVoltage=0.5,CurrPowerConsumption=30,PowerConsumption=100}
        pump=item('Pump',{Powered=powered})
        crate=item('Crate',{})
        user={ID=7}
        other={ID=8}
        Client={ClientList={{Name='Other',Character=other,Language={Value='Ukrainian'}},
                           {Name='Me',Character=user,Language={Value='Ukrainian'}}}}
        function use(target)
            user.FocusedItem=target
            hooks['item.use'](meter,user,nil,nil)
        end
        loadfile(MODFILE)(MODROOT)
    ''')
    return lua


class ReadingChecks:
    def setUp(self):
        self.lua = runtime(self.mode)

    def execute(self, code):
        self.lua.execute(code)

    def lines(self):
        messages = list(self.lua.globals().messages.values())
        for msg in messages:
            self.assertEqual(msg['channel'], 'chat' if self.mode == 'mp' else 'gui')
            if self.mode == 'mp':
                self.assertEqual(msg['recipient'], 'Me')
            else:
                self.assertEqual(msg['duration'], 6.0)
        self.assertEqual(list(self.lua.globals().logs.values()), ['[Multimeter] loaded'])
        return '\n'.join(msg['text'] for msg in messages).splitlines()

    def test_grid_readings_and_overload(self):
        self.execute('use(junction)')
        lines = self.lines()
        self.assertEqual(lines[:4], [
            'Мультиметр: Junction Box',
            'Подача: 5000 кВт | Навантаження: 2000 кВт',
            'Напруга: 250% (перевантаження з 200%)',
            'Стан: 100%',
        ])
        self.assertTrue(lines[4].startswith('Статус: ПЕРЕВАНТАЖЕННЯ'))
        self.assertEqual(len(lines), 5)
        self.assertEqual(len(self.lua.globals().messages), 5 if self.mode == 'mp' else 1)

    def test_no_grid_derives_supply_from_voltage_and_load(self):
        self.execute('transfer.PowerConnections={}; transfer.Voltage=1.2; transfer.Overload=false; use(junction)')
        lines = self.lines()
        self.assertEqual(lines[1], 'Подача: 1080 кВт | Навантаження: 900 кВт')
        self.assertEqual(lines[-1], 'Статус: норма')

    def test_transfer_statuses(self):
        cases = [(1.8, 'близько до перевантаження'),
                 (0, 'немає живлення'), (0.4, 'не вистачає живлення'), (1, 'норма')]
        for voltage, expected in cases:
            with self.subTest(voltage=voltage):
                self.lua.globals().voltage = voltage
                self.execute('messages={}; now=now+2; transfer.Overload=false; transfer.Voltage=voltage; use(junction)')
                self.assertIn(expected, self.lines()[-1])

    def test_non_overloadable_transfer_does_not_warn(self):
        self.execute('transfer.CanBeOverloaded=false; use(junction)')
        self.assertEqual(self.lines()[-1], 'Статус: норма')

    def test_relay_uses_output_grid_despite_powered_input(self):
        for reverse in (False, True):
            with self.subTest(reverse=reverse):
                if reverse:
                    self.execute('relayComponent.PowerConnections={relayOutput,relayInput}')
                self.execute('messages={}; now=now+2; use(relay)')
                lines = self.lines()
                self.assertEqual(lines[:4], [
                    'Мультиметр: Relay',
                    'Подача у вихідній мережі: 300 кВт | Навантаження: 1000 кВт',
                    'Вихідна напруга: 30%', 'Стан: 100%',
                ])
                self.assertIn('не вистачає живлення', lines[-1])

    def test_disabled_relay_never_reports_ok_even_with_powered_output(self):
        self.execute('relayComponent.IsOn=false; relayOutput.Grid.Voltage=1; use(relay)')
        self.assertEqual(self.lines()[-1], 'Статус: реле вимкнене. Струм не проходить.')

    def test_relay_without_output_grid_does_not_fall_back_to_input(self):
        self.execute('relayOutput.Grid=nil; use(relay)')
        self.assertEqual(self.lines(), [
            'Мультиметр: Relay', 'Стан: 100%',
            'Статус: вихід реле не підключений до електромережі.',
        ])

    def test_relay_output_statuses(self):
        for voltage, expected in [(0, 'немає живлення'), (0.5, 'норма'), (2.5, 'норма')]:
            with self.subTest(voltage=voltage):
                self.lua.globals().voltage = voltage
                self.execute('messages={}; now=now+2; relayOutput.Grid.Voltage=voltage; use(relay)')
                self.assertIn(expected, self.lines()[-1])

    def test_broken_relay_does_not_read_power_fields(self):
        self.execute("use(item('Broken Relay',{RelayComponent={}},0))")
        self.assertEqual(self.lines(), ['Мультиметр: Broken Relay', 'Зламано (стан 0%). Струм не проходить.'])

    def test_broken_junction_does_not_read_power_fields(self):
        self.execute("use(item('Broken Box',{PowerTransfer={}},0))")
        self.assertEqual(self.lines(), ['Мультиметр: Broken Box', 'Зламано (стан 0%). Струм не проходить.'])

    def test_battery_values_and_rounding(self):
        self.execute('use(battery)')
        self.assertEqual(self.lines(), [
            'Мультиметр: Battery', 'Заряд: 63% (634 / 1000 кВт*хв)',
            'Віддача: 120 кВт (макс 500) | Зарядка: 25 / 200 кВт', 'Стан: 100%',
        ])

    def test_device_values_and_low_power(self):
        self.execute('use(pump)')
        lines = self.lines()
        self.assertEqual(lines[:4], ['Мультиметр: Pump', 'Напруга: 30% (потрібно 50%)',
                                    'Споживання: 30 кВт (номінал 100 кВт)', 'Стан: 100%'])
        self.assertIn('не вистачає живлення', lines[-1])

    def test_battery_capacity_includes_modifiers(self):
        self.execute('''
            local component=battery.GetComponentString('PowerContainer')
            component.GetCapacity=function() return 1500 end
            component.Charge=1200
            component.ChargePercentage=80
            use(battery)
        ''')
        self.assertEqual(self.lines()[1], 'Заряд: 80% (1200 / 1500 кВт*хв)')

    def test_device_zero_power_and_minimum_voltage(self):
        for voltage, expected in [(0, 'немає живлення'), (0.5, 'норма')]:
            with self.subTest(voltage=voltage):
                self.lua.globals().voltage = voltage
                self.execute('messages={}; now=now+2; powered.Voltage=voltage; use(pump)')
                self.assertIn(expected, self.lines()[-1])

    def test_specific_component_precedes_generic_powered(self):
        self.execute('''
            battery.GetComponentString=function(kind)
                if kind=='Powered' then error('generic component must not be read') end
                if kind=='PowerContainer' then
                    return {ChargePercentage=50,Charge=50,Capacity=100,
                        GetCapacity=function() return 100 end,
                        CurrPowerOutput=0,MaxOutPut=10,RechargeSpeed=0,MaxRechargeSpeed=10}
                end
            end
            use(battery)
        ''')
        self.assertEqual(self.lines()[1], 'Заряд: 50% (50 / 100 кВт*хв)')

    def test_non_electrical_and_missing_targets(self):
        self.execute('use(crate)')
        self.assertEqual(self.lines(), ['Мультиметр: Crate', 'Це не електричний пристрій.'])
        for target in ('nil', 'meter'):
            with self.subTest(target=target):
                self.execute(f'messages={{}}; now=now+2; use({target})')
                self.assertEqual(self.lines(), ['Спершу наведи на пристрій (він має підсвітитися).'])

    def test_cooldown_allows_exactly_one_second(self):
        self.execute('use(pump); messages={}; now=100.5; use(pump); now=100.99; use(pump)')
        self.assertEqual(self.lines(), [])
        self.execute('now=101; use(pump)')
        self.assertEqual(len(self.lines()), 5)

    def test_cooldown_is_per_character(self):
        self.execute('use(pump); messages={}; user=other; use(pump)')
        messages = list(self.lua.globals().messages.values())
        self.assertEqual(len(messages), 5 if self.mode == 'mp' else 1)
        if self.mode == 'mp':
            self.assertTrue(all(msg['recipient'] == 'Other' for msg in messages))
        else:
            self.assertEqual(messages[0]['channel'], 'gui')

    def test_ignored_calls_do_not_use_cooldown(self):
        self.execute("hooks['item.use'](nil,user); hooks['item.use'](meter,nil); hooks['item.use'](crate,user)")
        self.assertEqual(self.lines(), [])
        self.execute('use(pump)')
        self.assertEqual(len(self.lines()), 5)

    def test_measurement_error_is_logged_and_next_reading_recovers(self):
        self.execute("use({GetComponentString=function() error('sensor failed') end,Name='Bad'})")
        self.assertEqual(len(self.lua.globals().messages), 0)
        logs = list(self.lua.globals().logs.values())
        self.assertEqual(len(logs), 2)
        self.assertTrue(logs[1].startswith('[Multimeter] error:'))
        self.assertIn('sensor failed', logs[1])
        self.execute("logs={'[Multimeter] loaded'}; now=now+2; use(pump)")
        self.assertEqual(len(self.lines()), 5)


class MultiplayerTests(ReadingChecks, unittest.TestCase):
    mode = 'mp'

    def test_unassociated_character_does_not_broadcast(self):
        self.execute('user={ID=9}; use(pump)')
        self.assertEqual(self.lines(), [])


class SinglePlayerTests(ReadingChecks, unittest.TestCase):
    mode = 'sp'


class MultiplayerClientTests(unittest.TestCase):
    def test_client_does_not_register_or_send_duplicate_readings(self):
        lua = runtime('client')
        self.assertIsNone(lua.globals().hooks['item.use'])
        self.assertEqual(len(lua.globals().messages), 0)
        self.assertEqual(len(lua.globals().logs), 0)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('modfile', nargs='?', type=Path, default=MODFILE)
    parser.add_argument('mode', nargs='?', choices=('mp', 'sp', 'all'), default='all')
    args = parser.parse_args()
    MODFILE = args.modfile.resolve()
    classes = {'mp': [MultiplayerTests, MultiplayerClientTests],
               'sp': [SinglePlayerTests],
               'all': [MultiplayerTests, SinglePlayerTests, MultiplayerClientTests]}[args.mode]
    suite = unittest.TestSuite(unittest.defaultTestLoader.loadTestsFromTestCase(cls) for cls in classes)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    raise SystemExit(0 if result.wasSuccessful() else 1)
