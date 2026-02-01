require_relative "../modbus/ascii_udp"

class Devices
  # Chauvin Arnoux / AEMC PEL 103 Power & Energy Logger
  # Communication via Modbus ASCII over UDP
  class PEL103
    using Modbus::TypeExtensions

    # Register map decoded from protocol analysis
    # Base address 0x0500 (1280 decimal), 32-bit values (2 registers each)
    REGISTERS = {
      v1_n:  { offset: 0,  scale: 100.0, unit: "V" },
      v2_n:  { offset: 2,  scale: 100.0, unit: "V" },
      v3_n:  { offset: 4,  scale: 100.0, unit: "V" },
      vn:    { offset: 6,  scale: 100.0, unit: "V" },
      v1_2:  { offset: 8,  scale: 100.0, unit: "V" },
      v2_3:  { offset: 10, scale: 100.0, unit: "V" },
      v3_1:  { offset: 12, scale: 100.0, unit: "V" },
      i1:    { offset: 14, scale: 10.0,  unit: "mA" },
      i2:    { offset: 16, scale: 10.0,  unit: "mA" },
      i3:    { offset: 18, scale: 10.0,  unit: "mA" },
      in:    { offset: 20, scale: 10.0,  unit: "mA" },
      p1:    { offset: 22, scale: 1.0,   unit: "W" },
      p2:    { offset: 24, scale: 1.0,   unit: "W" },
      p3:    { offset: 26, scale: 1.0,   unit: "W" },
      pt:    { offset: 28, scale: 1.0,   unit: "W" },
      q1:    { offset: 30, scale: 1.0,   unit: "var", signed: true },
      q2:    { offset: 32, scale: 1.0,   unit: "var", signed: true },
      q3:    { offset: 34, scale: 1.0,   unit: "var", signed: true },
      qt:    { offset: 36, scale: 1.0,   unit: "var", signed: true },
      s1:    { offset: 38, scale: 1.0,   unit: "VA" },
      s2:    { offset: 40, scale: 1.0,   unit: "VA" },
      s3:    { offset: 42, scale: 1.0,   unit: "VA" },
      st:    { offset: 44, scale: 1.0,   unit: "VA" },
    }.freeze

    def initialize(host = "192.168.0.189", port = 80, unit: 4)
      @transport = Modbus::AsciiUDP.new(host, port)
      @modbus = @transport.unit(unit)
    end

    def close
      @transport.close
    end

    # Read all real-time measurements in a single request
    def measurements
      # Read 125 registers from 0x0500 (1280) - real-time measurements block
      regs = @modbus.read_holding_registers(0x0500, 125)

      result = {}
      REGISTERS.each do |name, config|
        offset = config[:offset]
        raw = [regs[offset], regs[offset + 1]].to_u32
        raw = [regs[offset], regs[offset + 1]].to_i32 if config[:signed]
        result[name] = raw / config[:scale]
      end
      result
    end

    # Individual accessors for convenience
    def voltage_l1_n
      read_register(:v1_n)
    end

    def voltage_l2_n
      read_register(:v2_n)
    end

    def voltage_l3_n
      read_register(:v3_n)
    end

    def voltage_l1_l2
      read_register(:v1_2)
    end

    def voltage_l2_l3
      read_register(:v2_3)
    end

    def voltage_l3_l1
      read_register(:v3_1)
    end

    def current_l1
      read_register(:i1) / 1000.0  # Convert mA to A
    end

    def current_l2
      read_register(:i2) / 1000.0
    end

    def current_l3
      read_register(:i3) / 1000.0
    end

    def current_neutral
      read_register(:in) / 1000.0
    end

    def power_l1
      read_register(:p1)
    end

    def power_l2
      read_register(:p2)
    end

    def power_l3
      read_register(:p3)
    end

    def power_total
      read_register(:pt)
    end

    def reactive_power_l1
      read_register(:q1)
    end

    def reactive_power_l2
      read_register(:q2)
    end

    def reactive_power_l3
      read_register(:q3)
    end

    def reactive_power_total
      read_register(:qt)
    end

    def apparent_power_l1
      read_register(:s1)
    end

    def apparent_power_l2
      read_register(:s2)
    end

    def apparent_power_l3
      read_register(:s3)
    end

    def apparent_power_total
      read_register(:st)
    end

    # Convenience methods
    def voltages
      m = measurements
      {
        l1_n: m[:v1_n],
        l2_n: m[:v2_n],
        l3_n: m[:v3_n],
        l1_l2: m[:v1_2],
        l2_l3: m[:v2_3],
        l3_l1: m[:v3_1],
      }
    end

    def currents
      m = measurements
      {
        l1: m[:i1] / 1000.0,
        l2: m[:i2] / 1000.0,
        l3: m[:i3] / 1000.0,
        neutral: m[:in] / 1000.0,
      }
    end

    def powers
      m = measurements
      {
        active_l1: m[:p1],
        active_l2: m[:p2],
        active_l3: m[:p3],
        active_total: m[:pt],
        reactive_l1: m[:q1],
        reactive_l2: m[:q2],
        reactive_l3: m[:q3],
        reactive_total: m[:qt],
        apparent_l1: m[:s1],
        apparent_l2: m[:s2],
        apparent_l3: m[:s3],
        apparent_total: m[:st],
      }
    end

    private

    def read_register(name)
      config = REGISTERS[name]
      raise ArgumentError, "Unknown register: #{name}" unless config

      # For single register reads, still fetch the full block for efficiency
      # (the device may not support small reads)
      m = measurements
      m[name]
    end
  end
end
