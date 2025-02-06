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
      @serial.write "\x01\x03\x00\x33\x00\x1d\x1c\x32"

      _unit, _function, len = @serial.read(3).unpack("CCC")
      values = @serial.read(len).unpack("s>*")
      _crc1, _crc2 = @serial.read(2).unpack("CC")
      {
        #Warn_Over_Vol_Set_2 = Convert.ToInt16((int) Data[3] * 256 + (int) Data[4]);
        #Warn_Over_Vol_Set_1 = Convert.ToInt16((int) Data[5] * 256 + (int) Data[6]);
        #Warn_Low_Vol_Set_2 = Convert.ToInt16((int) Data[7] * 256 + (int) Data[8]);
        #Warn_Low_Vol_Set_1 = Convert.ToInt16((int) Data[9] * 256 + (int) Data[10]);
        #Warn_Over_SumVol_Set = (int) Data[11] * 256 + (int) Data[12];
        #Warn_Over_SumVol_Rec = (int) Data[13] * 256 + (int) Data[14];
        #Warn_Low_SumVol_Set = (int) Data[15] * 256 + (int) Data[16];
        #Warn_Low_SumVol_Rec = (int) Data[17] * 256 + (int) Data[18];
        #Warn_Over_DisChargeCur_Set = (short) ((int) Data[19] * 256 + (int) Data[20]);
        #Warn_Over_ChargeCur_Set = (short) ((int) Data[21] * 256 + (int) Data[22]);
        #Warn_Over_Tmp_Set_Charge_2 = (short) ((int) Data[23] * 256 + (int) Data[24]);
        #Warn_Over_Tmp_Set_Charge_1 = (short) ((int) Data[25] * 256 + (int) Data[26]);
        #Warn_Over_Tmp_Set_Discharge_2 = (short) ((int) Data[27] * 256 + (int) Data[28]);
        #Warn_Over_Tmp_Set_Discharge_1 = (short) ((int) Data[29] * 256 + (int) Data[30]);
        #Warn_Low_Tmp_Set_Charge_2 = (short) ((int) Data[31] * 256 + (int) Data[32]);
        #Warn_Low_Tmp_Set_Charge_1 = (short) ((int) Data[33] * 256 + (int) Data[34]);
        #Warn_Low_Tmp_Set_Discharge_2 = (short) ((int) Data[35] * 256 + (int) Data[36]);
        #Warn_Low_Tmp_Set_Discharge_1 = (short) ((int) Data[37] * 256 + (int) Data[38]);
        #VolTmp.Rec_Charge_Vol = Convert.ToInt32((int) Data[39] * 256 + (int) Data[40]);
        #VolTmp.Rec_Charge_Cur = Convert.ToDouble((int) Data[41] * 256 + (int) Data[42]);

        #VolTmp.Hard_Sum_Vol = Convert.ToInt32((int) Data[45] * 256 + (int) Data[46]);
        #VolTmp.Hall_Cur = (short) ((int) Data[47] * 256 + (int) Data[48]);
        #VolTmp.Force_charge = (int) (short) ((int) Data[49] * 256 + (int) Data[50]);
        #VolTmp.Ch_Oc_times = (int) (short) ((int) Data[51] * 256 + (int) Data[52]);
        #VolTmp.Disch_Oc_times = (int) (short) ((int) Data[53] * 256 + (int) Data[54]);
        #VolTmp.Disch_limit_Vol = (double) (short) ((int) Data[55] * 256 + (int) Data[56]);
        #VolTmp.Disch_limit_Cur = (double) (short) ((int) Data[57] * 256 + (int) Data[58]);
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
      }
    end

  end
end
