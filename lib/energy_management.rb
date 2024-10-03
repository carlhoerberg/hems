require_relative "./devices"
require_relative "./solar_forecast"

# Hållfjället energy management system
class EnergyManagement
  def initialize
    @devices = Devices.new
    @stopped = false
    @solar_forecast = SolarForecast.new
    @power_measurements = []
  end

  def start
    until @stopped
      begin
        sleep 5
        soc = @devices.next3.battery.soc
        genset_support(soc)
        load_shedding(soc)
      rescue => e
        puts "[ERROR] #{e.inspect}"
        e.backtrace.each { |l| print "\t", l, "\n" }
      end
    end
  end

  def stop
    @stopped = true
  end

  # Turn on the 9kw heater when solar is power limited
  # Turn off if load > 16kw
  # Turn off when SOC < 85
  # Turn off if forecast doesn't expect us to reach 100% SOC at the end of the solar day
  def load_shedding(soc = @devices.next3.battery.soc)
    pc = phase_capacity
    if @devices.relays.heater_6kw?
      if soc <= 90
        puts "SOC #{soc}%, turning off 6kw heater"
        @devices.relays.heater_6kw = false
      elsif pc.any? { |p| p < 0 }
        puts "Over power, turning off 6kw heater"
        @devices.relays.heater_6kw = false
      end
    else # 6kw heater is off
      if soc > 95 && pc.all? { |p| p > 6000 / 3 }
        puts "Solar excess, turning on 6kw heater"
        @devices.relays.heater_6kw = true
      end
    end
    if @devices.relays.heater_9kw?
      if soc <= 90
        puts "SOC #{soc}%, turning off 9kw heater"
        @devices.relays.heater_9kw = false
      elsif pc.any? { |p| p < 0 }
        puts "Over power, turning off 9kw heater"
        @devices.relays.heater_9kw = false
      end
    else # 9kw heater is off
      if soc > 95 && pc.all? { |p| p > 9000 / 3 }
        puts "Solar excess, turning on 9kw heater"
        @devices.relays.heater_9kw = true
      end
    end
  end

  def phase_capacity
    (1..3).map do |phase|
      5_000 - @devices.next3.acload.apparent_power(phase)
    end
  end

  # Heat as much as possible, start as early as possible during the day
  # Turn heat on if expected kWh produced today covers:
  # * Base load
  # * Load shedding
  # * Battery at 100% at the end of the solar day
  # How many kWh needed to fill up the battery at the end of the day?
  # How many kWh needed for base load for the rest of the day?
  def heating
    now = Time.now
    midnight = Time.local(now.year, now.month, now.day) + (24 * 60 * 60)
    hours_rest_of_today = (midnight - now) / 3600.0
    expected_kwh_consumed_rest_of_today = baseload * hours_rest_of_today
    expected_kwh_produced_rest_of_today = SolarForecast.new.expected.kwh_rest_of_today
    kwh_to_fill_battery = BATTERY_KWH * (1 - @devices.next3.battery.soc / 100.0)
    excess_kwh = expected_kwh_produced_rest_of_today -
      kwh_to_fill_battery -
      expected_kwh_consumed_rest_of_today
    if excess_kwh.positive?
      @devices.relays.heater_9kw = true
    end
  end

  BATTERY_KWH = 31.2

  def genset_support(soc = @devices.next3.battery.soc)
    if @devices.genset.is_running?
      if soc >= 94 || will_reach_full_battery_with_solar?(soc)
        stop_genset
      elsif overheated?
        stop_genset
      else
        keep_hz
      end
    else # genset is not running
      if soc <= 12
        start_genset
      end
    end
  end

  def will_reach_full_battery_with_solar?(soc)
    # collect power measuremnts to be able to calculate an averge once in a while
    @power_measurements << @devices.next3.acload.total_apparent_power
    puts "Got #{@power_measurements.size} power measurements, avg: #{@power_measurements.sum / @power_measurements.size / 1000.0}"
    return if @power_measurements.size < 600 / 5 # 10 minutes, 5s interval measurements

    avg_power_kw = @power_measurements.sum / @power_measurements.size / 1000.0
    puts "Avg power kw: #{avg_power_kw}"
    @power_measurements.clear # don't use a sliding window as we don't want to poll forecast api too much

    battery_kwh = BATTERY_KWH * soc / 100.0
    puts "Battery kWh: #{battery_kwh}"
    runtime = battery_kwh / avg_power_kw
    puts "Battery runtime: #{runtime}"

    # improve accuracy of forecast by telling how much is consumed yet today
    produced_solar_today = @devices.next3.solar.total_day_energy / 1000.0
    @solar_forecast.actual = produced_solar_today if produced_solar_today > 1 # don't report too early in the day

    expected_solar_kwh_during_runtime = @solar_forecast.kwh_next_hours(runtime)
    puts "Expected solar kWh next #{runtime} hours: #{expected_solar_kwh_during_runtime}"
    expected_solar_kwh_during_runtime -= runtime * avg_power_kw
    puts "Expected solar kWh next #{runtime} hours minus power during runtime: #{expected_solar_kwh_during_runtime}"

    puts "Expected battery kWh in #{runtime}h: #{battery_kwh + expected_solar_kwh_during_runtime}"
    battery_kwh + expected_solar_kwh_during_runtime >= BATTERY_KWH
  end

  def overheated?
    temp = @devices.genset.coolant_temperature
    95 < temp && temp < 200 # higher values are probably read errors
  end

  def start_genset
    @devices.relays.open_air_vents
    puts "Opening air vents, takes 2:30"
    sleep 150 # it takes 2:30 for the vents to fully open
    puts "Air vents should be fully open"

    puts "Starting genset"
    @devices.genset.start
    sleep 3 # should have started in this time
    unless @devices.genset.is_running?
      puts "Genset didn't start", "Status: #{@devices.genset.status}"
      raise "Genset didn't start"
    end
  end

  def stop_genset
    puts "Turning of load to cool down"
    @devices.next3.acsource.disable
    sleep 90
    puts "Stopping genset"
    @devices.genset.stop
    sleep 3
    if @devices.genset.is_running?
      puts "Genset did not stop", "Status: #{genset.status}"
      raise "Genset didn't stop"
    end
    puts "Restoring AC source values"
    @devices.next3.acsource.rated_current = 16
    @devices.next3.acsource.enable
    puts "Closing air vents"
    @devices.relays.close_air_vents
  end

  def keep_hz
    hz = @devices.genset.frequency
    if hz < 49.7
      rated_current = @devices.next3.acsource.rated_current
      puts "hz=#{hz} adjusting current down to #{rated_current - 1}"
      @devices.next3.acsource.rated_current = rated_current - 1
    elsif hz > 50.1
      rated_current = @devices.next3.acsource.rated_current
      if rated_current < 18 # never try to draw more than 18A
        puts "hz=#{hz} adjusting current up to #{rated_current + 1}"
        @devices.next3.acsource.rated_current = rated_current + 1
      end
    end
  end
end
