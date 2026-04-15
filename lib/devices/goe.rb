require 'net/http'
require 'json'

class Devices
  # go-e Charger HTTP API v2 integration
  # Port 80, HTTP GET /api/status and /api/set
  class GoE
    MIN_AMPS = 6
    MAX_AMPS = 16

    def initialize(host, port = 80)
      @host = host
      @port = port
    end

    def close
    end

    # Error code (0=None, 1=FiAc, 2=FiDc, 3=Phase, 4=Overvolt, 5=Overamp, ...)
    def error
      get_status(%w[err])['err']
    end

    # Car state: 0=Unknown/Error, 1=Idle, 2=Charging, 3=WaitCar, 4=Complete, 5=Error
    def car_state
      get_status(%w[car])['car']
    end

    def charging?
      car_state == 2
    end

    def car_connected?
      car_state >= 2
    end

    # Cable current limit in A (nil if no cable)
    def cable_amps
      get_status(%w[cbl])['cbl']
    end

    # Current on L1 in amps
    def amp_l1
      get_status(%w[nrg])['nrg'][4]
    end

    # Current on L2 in amps
    def amp_l2
      get_status(%w[nrg])['nrg'][5]
    end

    # Current on L3 in amps
    def amp_l3
      get_status(%w[nrg])['nrg'][6]
    end

    # Total power in kW
    def power_total
      get_status(%w[nrg])['nrg'][11] / 1000.0
    end

    # Total energy charged in kWh
    def energy_total
      get_status(%w[eto])['eto'] / 1000.0
    end

    # Whether the car is allowed to charge right now
    def allow?
      get_status(%w[alw])['alw']
    end

    # allow=true: Neutral (resume normal logic), allow=false: Force off
    def allow=(value)
      set_value('frc', value ? 0 : 1)
    end

    # Current ampere setting in A
    def ampere
      get_status(%w[amp])['amp']
    end

    # Set charging current (6-16A)
    def ampere=(value)
      set_value('amp', value.to_i.clamp(MIN_AMPS, MAX_AMPS))
    end

    # Absolute max amps configured on the device
    def ampere_max
      get_status(%w[ama])['ama']
    end

    def measurements
      data = get_status(%w[car cbl err nrg eto alw amp ama cus tma])
      nrg = data['nrg']
      {
        car_state: data['car'],
        cable_amps: data['cbl'],
        error: data['err'],
        volt_l1: nrg[0],
        volt_l2: nrg[1],
        volt_l3: nrg[2],
        volt_n: nrg[3],
        amp_l1: nrg[4],
        amp_l2: nrg[5],
        amp_l3: nrg[6],
        power_total: nrg[11] / 1000.0,
        energy_total: data['eto'] / 1000.0,
        allow: data['alw'] ? 1 : 0,
        ampere_max: data['ama'],
        ampere: data['amp'],
        cable_unlock_status: data['cus'],
        temp_cable: data['tma'][0],
        temp_psu: data['tma'][1],
      }.freeze
    end

    private

    def get_status(keys)
      uri = URI("http://#{@host}:#{@port}/api/status")
      uri.query = "filter=#{keys.join(',')}"
      response = Net::HTTP.get_response(uri)
      JSON.parse(response.body)
    end

    def set_value(key, value)
      uri = URI("http://#{@host}:#{@port}/api/set")
      uri.query = "#{key}=#{value}"
      Net::HTTP.get_response(uri)
    end
  end
end
