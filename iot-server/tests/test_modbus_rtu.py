import unittest

from protocol.modbus_rtu import ModbusRTUParser


def with_crc(payload: bytes) -> bytes:
    crc = ModbusRTUParser.calculate_crc16(payload)
    return payload + bytes((crc & 0xFF, (crc >> 8) & 0xFF))


class ModbusRTUParserTests(unittest.TestCase):
    def test_crc_round_trip_and_corruption(self):
        frame = with_crc(bytes((0x01, 0x03, 0x00, 0x00, 0x00, 0x02)))
        self.assertTrue(ModbusRTUParser.verify_crc(frame))

        corrupted = bytearray(frame)
        corrupted[2] ^= 0x01
        self.assertFalse(ModbusRTUParser.verify_crc(bytes(corrupted)))

    def test_parse_temperature_and_humidity(self):
        # Humidity 60.0%, temperature 25.5 C.
        frame = with_crc(bytes((0x01, 0x03, 0x04, 0x02, 0x58, 0x00, 0xFF)))
        result = ModbusRTUParser.parse_temp_humidity_response(frame)

        self.assertIsNotNone(result)
        self.assertEqual(result.device_address, 0x01)
        self.assertAlmostEqual(result.humidity, 60.0)
        self.assertAlmostEqual(result.temperature, 25.5)

    def test_parse_circuit_breaker_state(self):
        frame = with_crc(bytes((0x02, 0x03, 0x02, 0x00, 0x01)))
        result = ModbusRTUParser.parse_circuit_breaker_response(frame)

        self.assertIsNotNone(result)
        self.assertTrue(result.is_closed)

    def test_query_command_contains_valid_crc(self):
        command = ModbusRTUParser.build_door_query_command(0x41)
        self.assertEqual(command[0], 0x41)
        self.assertTrue(ModbusRTUParser.verify_crc(command))


if __name__ == '__main__':
    unittest.main()

