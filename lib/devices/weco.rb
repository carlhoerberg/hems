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
        CellNum: values[6],
        TmpNum: values[7],
        BootVersion: values[8],
        SoftVersion: values[9],
        HardVersion: values[10],
        SysRunTim: values[11, 2].pack("n*").unpack1("L>"),
        SysVol: values[13],
        Current: values[14],
        MaxTmp: values[15] - 40,
        MinTmp: values[16] - 40,
        MaxVol: values[17],
        MinVol: values[18],
        SocValue: values[19] / 2.5,
        FactCap: values[20],
        VolValue_0: values[21] / 1000.0,
        VolValue_1: values[22] / 1000.0,
        VolValue_2: values[23] / 1000.0,
        VolValue_3: values[24] / 1000.0,
        VolValue_4: values[25] / 1000.0,
        VolValue_5: values[26] / 1000.0,
        VolValue_6: values[27] / 1000.0,
        VolValue_7: values[28] / 1000.0,
        VolValue_8: values[29] / 1000.0,
        VolValue_9: values[30] / 1000.0,
        VolValue_10: values[31] / 1000.0,
        VolValue_11: values[32] / 1000.0,
        VolValue_12: values[33] / 1000.0,
        VolValue_13: values[34] / 1000.0,
        VolValue_14: values[35] / 1000.0,
        VolValue_15: values[36] / 1000.0,
      }
    end

    def battery_pack_response
      _unit, _function, len = @serial.read(3).unpack("CCC")
      values = @serial.read(len).unpack("n*")
      _crc1, _crc2 = @serial.read(2).unpack("CC")
      {
        sys_vol: values[0] / 100.0,
        current: values[1] / 100.0,
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
