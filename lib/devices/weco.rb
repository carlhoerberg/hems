require "uart"

class Devices
  class Weco
    def initialize
      @lock = Mutex.new
      @key = 0x85F9 # rand(0xFFFF)
      set_key
    end

    def system_voltage
      lock do
        read_holding_register(14) / 100.0
      end
    end

    def min_soc
      lock do
        min = read_holding_register(20) / 2.5 # master module
        (1..5).each do |unit|
          value = read_holding_register(117 + unit * 10) / 2.5
          min = value if value < min
        end
        min
      end
    end

    def charge_limit
      lock do
        read_holding_register(203) / 10.0
      end
    end

    def currents
      lock do
        values = read_holding_registers(203, 3)
        {
          charge_limit: values[0] / 10.0, # positive
          discharge_limit: values[1] / 10.0, # positive
          current: values[2] / 10.0, # negative while charging
        }
      end
    end

    def modules
      lock do
        Array.new(6) do |i|
          case i
          when 0 then master_status
          else        slave_status(i)
          end
        end
      end
    end

    def total
      lock do
        values = read_holding_registers(203, 7)
        {
          charge_current_recommended: values[0] / 10.0,
          discharge_current_limit: values[1] / 10.0,
          current: values[2] / 10.0,
          soc: values[3] / 2.5,
          forced_state: values[4],
          forced_seconds: values[5, 2].pack("n2").unpack1("L>") / 10.0,
        }
      end
    end

    def lock(&)
      @lock.synchronize do
        @serial ||= UART.open("/dev/ttyUSB1", 115200)
        @serial.flock(File::LOCK_EX)
        begin
          yield @serial
        rescue
          @serial.flock(File::LOCK_UN)
          @serial.close
          @serial = nil
          raise
        ensure
          @serial.flock(File::LOCK_UN) if @serial
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

    def read_holding_register(addr)
      read_holding_registers(addr, 1).first
    end

    def set_key(key = @key)
      lock do |serial|
        serial.write [0, 3, key, 1].pack("CCS>S>")
        response = serial.read(6) || raise(EOFError.new)
        unit, func, addr, len = response.unpack("CCS>S>")
        raise("Unexpected response: #{response.dump}") if unit != 1 || func != 3 || addr != 0x0323 || len != 0
        crc = serial.read(2).unpack1("S<")
        raise("Unexpected crc #{crc} != #{checksum(response, key)}") if crc != checksum(response, key)
      end
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
  end
end
