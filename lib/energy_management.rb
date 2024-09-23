require_relative "./devices"

# Hållfjället energy management system
class EnergyManagement
  def initialize
    @devices = Devices.new
    @stopped = false
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
    if @devices.relays.heater_6kw?
      if soc < 85
        puts "SOC #{soc}%, turning off 9kw heater"
        @devices.relays.heater_6kw = false
      end
    end
    if @devices.relays.heater_9kw?
      if soc < 85
        puts "SOC #{soc}%, turning off 9kw heater"
        @devices.relays.heater_9kw = false
      elsif (tp = @devices.next3.acload.total_apparent_power) > 16_000
        puts "Total power #{tp}, turning off 9kw heater"
        @devices.relays.heater_9kw = false
      end
    else # 9kw heater is off
      if soc > 99 &&
          15_000 - @devices.next3.acload.total_apparent_power > 9_000 &&
          Time.now.hour < 18
        puts "Solar excess, turning on 9kw heater"
        @devices.relays.heater_9kw = true
      end
    end
  end

  # Heat as much as possible, start as early as possible during the day
  # Turn heat on if expected kWh produced today covers:
  # * Base load
  # * Load shedding
  # * Battery at 100% at the end of the solar day
  # How many kWh needed to fill up the battery at the end of the day?
  # How many kWh needed for base load for the rest of the day?
  #
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
      if soc >= 95 || overheated?
        stop_genset
      else
        keep_hz
      end
    else # genset is not running
      if soc <= 14
        start_genset
      end
    end
  end

  def overheated?
    temp = @devices.genset.coolant_temperature
    105 < temp && temp < 200 # higher values are probably read errors
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
    # puts "Turning of load to cool down"
    # @devices.next3.acsource.disable
    # sleep 60
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
    if hz < 49.8
      rated_current = @devices.next3.acsource.rated_current
      puts "hz=#{hz} adjusting current down from #{rated_current}"
      @devices.next3.acsource.rated_current = rated_current - 1
    elsif hz > 50.1
      rated_current = @devices.next3.acsource.rated_current
      if rated_current < 18 # never try to draw more than 18A
        puts "hz=#{hz} adjusting current up from #{rated_current}"
        @devices.next3.acsource.rated_current = rated_current + 1
      end
    end
  end
end
