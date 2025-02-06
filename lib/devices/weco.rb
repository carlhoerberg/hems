require "uart"

class Devices
  class Weco
    def initialize
      @lock = Mutex.new
      @key = 0x85F9 # rand(0xFFFF)
      #set_key
    end

    def status
      modules = []
      lock do
        modules << master_status
        (1..5).each do |s|
          modules << slave_status(s)
        end
      end
      modules
    end

    def lock(&)
      @lock.synchronize do
        @serial ||= UART.open("/dev/ttyUSB0", 115200)
        @serial.flock(File::LOCK_EX)
        begin
          yield @serial
        rescue
          @serial.close
          @serial = nil
          raise
        else
          @serial.flock(File::LOCK_UN)
        end
      end
    end

    def master_status
      values = read_holding_registers(14, 7)
      {
        sys_vol: values[0] / 100.0,
        current: values[1] / 100.0,
        max_tmp: values[2] - 40,
        min_tmp: values[3] - 40,
        max_vol: values[4] / 1000.0,
        min_vol: values[5] / 1000.0,
        soc_value: values[6] / 2.5,
      }
    end

    def slave_status(unit)
      values = read_holding_registers(111 + unit * 10, 7)
      {
        sys_vol: values[0] / 10.0,
        current: values[1] / 10.0,
        max_tmp: values[2] / 100.0,
        min_tmp: values[3] / 100.0,
        max_vol: values[4] / 1000.0,
        min_vol: values[5] / 1000.0,
        soc_value: values[6] / 2.5,
      }
    end

    def read_holding_registers(addr, count)
      unit = 1
      function = 3
      request = [unit, function, addr, count].pack("CCS>S>")
      @serial.write request, [checksum(request)].pack("S<")

      head = @serial.read(3) || raise(EOFError.new)
      runit, rfunction, len = head.unpack("CCC")
      raise("Unexpected response, unit #{runit} != #{unit}") if runit != unit
      raise("Unexpected response, function #{rfunction} != #{function}") if rfunction != function
      raise("Unexpected response, len #{len} != #{count} * 2") if len != count * 2
      data = @serial.read(len) || raise(EOFError.new)
      crc = @serial.read(2).unpack1("S<")
      expected_crc = checksum(head + data)
      warn "CRC mismatch: #{crc} != #{expected_crc}" if crc != expected_crc
      data.unpack("s>*")
    end

    def set_key(key = @key)
      @serial.write [0, 3, key, 1].pack("CCS>S>")
      response = @serial.read(6) || raise(EOFError.new)
      unit, func, addr, len = response.unpack("CCS>S>")
      raise("Unexpected response: #{response.dump}") if unit != 1 || func != 3 || addr != 0x0323 || len != 0
      crc = @serial.read(2).unpack1("S<")
      raise("Unexpected crc #{crc} != #{checksum(response, key)}") if crc != checksum(response, key)
    end

    def checksum(data, key = @key)
      crc = 0xFFFF
      data.each_byte do |byte|
        crc ^= byte
        8.times do
          if (crc & 1) != 0
            crc = (crc >> 1) ^ 0xA001
          else
            crc >>= 1
          end
        end
      end
      (~(crc | key) + 26) & 0xFFFF
    end

    def warn_response
      # "\x01\x03\x00\x33\x00\x1d\x1c\x32"
      values = read_holding_registers(0x33, 0x1d)
      {
        Warn_Over_Vol_Set_2: values[0],
        Warn_Over_Vol_Set_1: values[1],
        Warn_Low_Vol_Set_2: values[2],
        Warn_Low_Vol_Set_1: values[3],
        Warn_Over_SumVol_Set: values[4],
        Warn_Over_SumVol_Rec: values[5],
        Warn_Low_SumVol_Set: values[6],
        Warn_Low_SumVol_Rec: values[7],
        Warn_Over_DisChargeCur_Set: values[7],
        Warn_Over_ChargeCur_Set: values[8],
        Warn_Over_Tmp_Set_Charge_2: values[9],
        Warn_Over_Tmp_Set_Charge_1: values[10],
        Warn_Over_Tmp_Set_Discharge_2: values[11],
        Warn_Over_Tmp_Set_Discharge_1: values[12],
        Warn_Low_Tmp_Set_Charge_2: values[13],
        Warn_Low_Tmp_Set_Charge_1: values[14],
        Warn_Low_Tmp_Set_Discharge_2: values[15],
        Warn_Low_Tmp_Set_Discharge_1: values[16],
        VolTmp_Rec_Charge_Vol: values[17],
        VolTmp_Rec_Charge_Cur: values[18],
        # values[19] <= Data[43, 44]
        #Warn.DI1 = ((int) Data[44] & 1) != 1 ? (byte) 0 : (byte) 1;
        #Warn.DI2 = ((int) Data[44] & 2) != 2 ? (byte) 0 : (byte) 1;
        #Warn.DO1 = ((int) Data[44] & 4) != 4 ? (byte) 0 : (byte) 1;
        #Warn.DO2 = ((int) Data[44] & 8) != 8 ? (byte) 0 : (byte) 1;
        #Warn.Contact_Charge = ((int) Data[44] & 16) != 16 ? (byte) 0 : (byte) 1;
        #Warn.Contact_Ready_Charge = ((int) Data[44] & 32) != 32 ? (byte) 0 : (byte) 1;
        #Warn.Contact_Discharge = ((int) Data[44] & 64) != 64 ? (byte) 0 : (byte) 1;
        #Warn.Contact_Mag_Discharge = ((int) Data[44] & 128) != 128 ? (byte) 0 : (byte) 1;
        #if (((int) Data[43] & 1) == 1)
        #  {
        #    this.AGVData.Warn.Contact_Mag_Charge = (byte) 1;
        #    break;
        #  }
        #  this.AGVData.Warn.Contact_Mag_Charge = (byte) 0;
        VolTmp_Hard_Sum_Vol: values[20],
        VolTmp_Hall_Cur: values[21],
        VolTmp_Force_charge: values[22],
        VolTmp_Ch_Oc_times: values[23],
        VolTmp_Disch_Oc_times: values[24],
        VolTmp_Disch_limit_Vol: values[25],
        VolTmp_Disch_limit_Cur: values[26],
        #Warn.slave1_commLost = ((int) Data[60] & 1) != 1 ? (byte) 1 : (byte) 0;
        #Warn.slave2_commLost = ((int) Data[60] & 2) != 2 ? (byte) 1 : (byte) 0;
        #Warn.slave3_commLost = ((int) Data[60] & 4) != 4 ? (byte) 1 : (byte) 0;
        #Warn.slave4_commLost = ((int) Data[60] & 8) != 8 ? (byte) 1 : (byte) 0;
        #Warn.slave5_commLost = ((int) Data[60] & 16) != 16 ? (byte) 1 : (byte) 0;
        #Warn.slave6_commLost = ((int) Data[60] & 32) != 32 ? (byte) 1 : (byte) 0;
        #Warn.slave7_commLost = ((int) Data[60] & 64) != 64 ? (byte) 1 : (byte) 0;
        #Warn.slave8_commLost = ((int) Data[60] & 128) != 128 ? (byte) 1 : (byte) 0;
        #Warn.slave9_commLost = ((int) Data[59] & 1) != 1 ? (byte) 1 : (byte) 0;
        #Warn.slave10_commLost = ((int) Data[59] & 2) != 2 ? (byte) 1 : (byte) 0;
        #Warn.slave11_commLost = ((int) Data[59] & 4) != 4 ? (byte) 1 : (byte) 0;
        #Warn.slave12_commLost = ((int) Data[59] & 8) != 8 ? (byte) 1 : (byte) 0;
        #Warn.slave12_commLost = ((int) Data[59] & 8) != 8 ? (byte) 1 : (byte) 0;
        #Warn.slave13_commLost = ((int) Data[59] & 16) != 16 ? (byte) 1 : (byte) 0;
        #Warn.slave14_commLost = ((int) Data[59] & 32) != 32 ? (byte) 1 : (byte) 0;
        #Warn.pack_vol_imbalance = ((int) Data[59] & 128) != 128 ? (byte) 0 : (byte) 1;
      }
    end
  end
end
