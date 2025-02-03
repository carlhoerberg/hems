require "uart"

class Devices
  class Weco
    def initialize
      device = Dir.glob("/dev/ttyUSB0").first || raise("No serial device found")
      @serial = UART.open(device, 115200)
    end

    def any
      @serial.write "\x01\x03\x00\x01\x00\x26\x1c\x2a"
      p main_pack_response
      #@serial.write "\x01\x03\x00\x27\x00\x06\x1c\x38"
      #response
      #@serial.write "\x01\x03\x00\x2e\x00\x03\x1c\x38"
      #response
      #@serial.write "\x01\x03\x00\x52\x00\x07\x1c\x22"
      #response
      @serial.write "\x01\x03\x00\x79\x00\x0a\x1c\x6a" # module 1
      p battery_pack_response
      @serial.write "\x01\x03\x00\x83\x00\x0a\x1c\x5a" # module 2
      p battery_pack_response
      @serial.write "\x01\x03\x00\x8d\x00\x0a\x1c\x18"
      p battery_pack_response
      @serial.write "\x01\x03\x00\x97\x00\x0a\x1c\x5a"
      p battery_pack_response
      @serial.write "\x01\x03\x00\xa1\x00\x0a\x1c\x50"
      p battery_pack_response
    end

    def main_pack_response
      _unit, _function, len = @serial.read(3).unpack("CCC")
      values = @serial.read(len).unpack("n*")
      _crc1, _crc2 = @serial.read(2).unpack("CC")
      {
        cell_num: values[6],
        tmp_num: values[7],
        boot_version: values[8],
        soft_version: values[9],
        hard_version: values[10],
        sys_runtime: values[11, 2].pack("n*").unpack1("L<"),
        sys_vol: values[13] / 100.0,
        current: values[14] / 100.0,
        max_tmp: values[15] - 40,
        min_tmp: values[16] - 40,
        max_vol: values[17] / 1000.0,
        min_vol: values[18] / 1000.0,
        soc_value: values[19] / 2.5,
        fact_cap: values[20],
        cell_voltage_0: values[22] / 1000.0,
        cell_voltage_1: values[23] / 1000.0,
        cell_voltage_2: values[24] / 1000.0,
        cell_voltage_3: values[25] / 1000.0,
        cell_voltage_4: values[26] / 1000.0,
        cell_voltage_5: values[27] / 1000.0,
        cell_voltage_6: values[28] / 1000.0,
        cell_voltage_7: values[29] / 1000.0,
        cell_voltage_8: values[30] / 1000.0,
        cell_voltage_9: values[31] / 1000.0,
        cell_voltage_10: values[32] / 1000.0,
        cell_voltage_11: values[33] / 1000.0,
        cell_voltage_12: values[34] / 1000.0,
        cell_voltage_13: values[35] / 1000.0,
        cell_voltage_14: values[36] / 1000.0,
        cell_voltage_15: values[37] / 1000.0,
      }
    end

    def battery_pack_response
      _unit, _function, len = @serial.read(3).unpack("CCC")
      values = @serial.read(len).unpack("n*")
      _crc1, _crc2 = @serial.read(2).unpack("CC")
      {
        sys_vol: values[0] / 10.0,
        current: values[1] / 10.0,
        max_tmp: values[2] / 100.0,
        min_tmp: values[3] / 100.0,
        max_vol: values[4] / 1000.0,
        min_vol: values[5] / 1000.0,
        soc_value: values[6] / 2.5,
        fact_cap: values[7], # factory capacity (Ah)
      }
    end
  end
end
