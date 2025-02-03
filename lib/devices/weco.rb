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
        SysRunTim: values[11, 4].pack("n*").unpack1("Q>"),
        SysVol: values[15],
        Current: values[16],
        MaxTmp: values[17],
        MinTmp: values[18],
        MaxVol: values[19],
        MinVol: values[20],
        SocValue: values[21],
        FactCap: values[22],
        VolValue_0: values[23],
        VolValue_1: values[24],
        VolValue_2: values[25],
        VolValue_3: values[26],
        VolValue_4: values[27],
        VolValue_5: values[28],
        VolValue_6: values[29],
        VolValue_7: values[30],
        VolValue_8: values[31],
        VolValue_9: values[32],
        VolValue_10: values[33],
        VolValue_11: values[34],
        VolValue_12: values[35],
        VolValue_13: values[36],
        VolValue_14: values[37],
        VolValue_15: values[38],
      }
    end

    def battery_pack_response
      _unit, _function, len = @serial.read(3).unpack("CCC")
      values = @serial.read(len).unpack("n*")
      _crc1, _crc2 = @serial.read(2).unpack("CC")
      {
        sys_vol: values[0],
        current: values[1],
        max_tmp: values[2],
        min_tmp: values[3],
        max_vol: values[4],
        min_vol: values[5],
        soc_value: values[6],
        fact_cap: values[7],
      }
    end
  end
end
