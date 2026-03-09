require_relative "../modbus/tcp"

class Devices
  # go-e Charger Modbus TCP integration (API v1)
  # Port 502, unit ID 1
  # Uses AMPERE_VOLATILE (register 299) for energy management control
  class GoE
    using Modbus::TypeExtensions

    # Input Registers (read-only)
    REG_CAR_STATE    = 100  # u16: 1=ready/no car, 2=charging, 3=waiting, 4=finished
    REG_PP_CABLE     = 101  # u16: cable ampere coding (13-32, 0=no cable)
    REG_VOLT_L1      = 108  # u32: voltage L1 in volts
    REG_VOLT_L2      = 110  # u32: voltage L2 in volts
    REG_VOLT_L3      = 112  # u32: voltage L3 in volts
    REG_AMP_L1       = 114  # u32: current L1 in 0.1A
    REG_AMP_L2       = 116  # u32: current L2 in 0.1A
    REG_AMP_L3       = 118  # u32: current L3 in 0.1A
    REG_POWER_TOTAL  = 120  # u32: total power in 0.01kW
    REG_ENERGY_TOTAL = 128  # u32: total energy in 0.1kWh
    REG_POWER_L1     = 146  # u32: power L1 in 0.1kW
    REG_POWER_L2     = 148  # u32: power L2 in 0.1kW
    REG_POWER_L3     = 150  # u32: power L3 in 0.1kW
    REG_PHASES       = 205  # u16: phase flags

    # Holding Registers (read/write)
    REG_ALLOW          = 200  # u16: allow charging (0/1)
    REG_AMPERE_MAX     = 211  # u16: absolute max amps
    REG_AMPERE_VOLATILE = 299 # u16: current amps (volatile, 6-16A, for energy control)

    MIN_AMPS = 6
    MAX_AMPS = 16

    def initialize(host, port = 502)
      @modbus = Modbus::TCP.new(host, port).unit(1)
    end

    def close
      @modbus.close
    end

    # Car state: 1=ready/no car, 2=charging, 3=waiting, 4=finished
    def car_state
      @modbus.read_input_register(REG_CAR_STATE)
    end

    def charging?
      car_state == 2
    end

    def car_connected?
      car_state >= 2
    end

    # Cable ampere limit (13-32A, 0=no cable)
    def cable_amps
      @modbus.read_input_register(REG_PP_CABLE)
    end

    # Current on L1 in amps
    def amp_l1
      @modbus.read_input_registers(REG_AMP_L1, 2).to_u32 / 10.0
    end

    # Current on L2 in amps
    def amp_l2
      @modbus.read_input_registers(REG_AMP_L2, 2).to_u32 / 10.0
    end

    # Current on L3 in amps
    def amp_l3
      @modbus.read_input_registers(REG_AMP_L3, 2).to_u32 / 10.0
    end

    # Total power in kW
    def power_total
      @modbus.read_input_registers(REG_POWER_TOTAL, 2).to_u32 / 100.0
    end

    # Total energy charged in kWh
    def energy_total
      @modbus.read_input_registers(REG_ENERGY_TOTAL, 2).to_u32 / 10.0
    end

    # Allow/disallow charging
    def allow
      @modbus.read_holding_register(REG_ALLOW)
    end

    def allow=(value)
      @modbus.write_holding_register(REG_ALLOW, value ? 1 : 0)
    end

    # Current ampere setting (volatile, for energy control)
    def ampere
      @modbus.read_holding_register(REG_AMPERE_VOLATILE)
    end

    # Set charging current (6-16A, volatile)
    def ampere=(value)
      value = value.to_i.clamp(MIN_AMPS, MAX_AMPS)
      @modbus.write_holding_register(REG_AMPERE_VOLATILE, value)
    end

    # Absolute max amps configured on the device
    def ampere_max
      @modbus.read_holding_register(REG_AMPERE_MAX)
    end

    def measurements
      # Registers 100-129: car_state, cable, volts, amps, power, energy_total (30 regs, 1 request)
      inp = @modbus.read_input_registers(REG_CAR_STATE, 30)
      # Registers 200-211: allow through ampere_max (12 regs, 1 request)
      hold = @modbus.read_holding_registers(REG_ALLOW, 12)
      # Register 299: volatile ampere setting (1 request)
      amp_setting = @modbus.read_holding_register(REG_AMPERE_VOLATILE)
      {
        car_state: inp[0],
        cable_amps: inp[1],
        volt_l1: [inp[8], inp[9]].to_u32,
        volt_l2: [inp[10], inp[11]].to_u32,
        volt_l3: [inp[12], inp[13]].to_u32,
        amp_l1: [inp[14], inp[15]].to_u32 / 10.0,
        amp_l2: [inp[16], inp[17]].to_u32 / 10.0,
        amp_l3: [inp[18], inp[19]].to_u32 / 10.0,
        power_total: [inp[20], inp[21]].to_u32 / 100.0,
        energy_total: [inp[28], inp[29]].to_u32 / 10.0,
        allow: hold[0],
        ampere_max: hold[11],
        ampere: amp_setting,
      }.freeze
    end
  end
end
