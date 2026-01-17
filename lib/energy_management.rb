require_relative "./devices"
require_relative "./solar_forecast"
require "net/http"
require "json"

class Time
  # Monotonic seconds since boot
  def self.monotonic
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def self.measure(&)
    start = monotonic
    yield
    monotonic - start
  end
end

# Hållfjället energy management system
class EnergyManagement
  DEFAULT_GENSET_ACTIVATION_SOC = 20
  DEFAULT_GENSET_DEACTIVATION_SOC = 95

  # Genset load management thresholds
  GENSET_MAX_LOAD_PCT = 95
  HEATER_6KW_LOAD_PCT = 25
  HEATER_9KW_LOAD_PCT = 40
  AFTERTREATMENT_MIN_TEMP = 250

  def initialize(devices)
    @devices = devices
    @stopped = false
    @shelly_demands = {}  # { device_id => { host:, amps:, active: false } }
    @shelly_demands_mutex = Mutex.new
  end

  def start
    duration = 0
    until @stopped
      begin
        duration = Time.measure do
          genset_load_management
          manage_shelly_demands
        end
        puts "Energy management loop duration: #{duration.round(2)}s" if duration > 1
        break if @stopped
        sleep [5 - duration, 0].max
      rescue => e
        puts "[ERROR] #{e.inspect}"
        e.backtrace.each { |l| print "\t", l, "\n" }
      end
    end
  end

  def stop
    @stopped = true
  end

  # Add heater load when:
  # 1. Genset running: keep it at high load (DFS requires it)
  # 2. Solar excess: use excess solar to heat water
  # Only when battery is charge-limited by BMS, stop if discharging
  def load_shedding(soc = @devices.next3.battery.soc)
    heaters_on = @devices.relays.any_heater_on?

    # Stop heaters if battery is discharging
    if battery_discharging?
      if heaters_on
        puts "Battery discharging, turning off heaters"
        turn_off_heaters
      end
      return
    end

    # Only add load when battery is charge-limited by BMS
    unless battery_charge_limited?
      turn_off_heaters if heaters_on
      return
    end

    if genset_running?
      # genset_load_shedding
    else
      solar_load_shedding
    end
  end

  def battery_discharging?
    @devices.next3.battery.charging_current < 0
  end

  def battery_charge_limited?
    recommended = @devices.next3.battery.bms_recommended_charging_current
    actual = @devices.next3.battery.charging_current
    # Limited when actual is within 5A of recommended
    recommended - actual < 5
  end

  # Add heaters to match rated_current when genset is running
  def genset_load_shedding
    rated = @devices.next3.acsource.rated_current
    max_current = (1..3).map { |p| @devices.next3.acsource.current(p) }.max

    # Heater current per phase (3-phase balanced load)
    current_6kw = 6000.0 / 3 / 230  # ~8.7A
    current_9kw = 9000.0 / 3 / 230  # ~13A

    heater_6kw_on = @devices.relays.heater_6kw?
    heater_9kw_on = @devices.relays.heater_9kw?

    # Add back current from active heaters to get total available capacity
    # (their draw is already included in max_current)
    available = rated - max_current
    available += current_6kw if heater_6kw_on
    available += current_9kw if heater_9kw_on

    if available >= current_6kw + current_9kw + 2
      unless heater_6kw_on && heater_9kw_on
        puts "Genset available #{available.round(1)}A, turning on both heaters"
        @devices.relays.heater_6kw = true
        @devices.relays.heater_9kw = true
      end
    elsif available >= current_9kw + 2
      unless heater_9kw_on && !heater_6kw_on
        puts "Genset available #{available.round(1)}A, using 9kW heater"
        @devices.relays.heater_6kw = false
        @devices.relays.heater_9kw = true
      end
    elsif available >= current_6kw + 2
      unless heater_6kw_on && !heater_9kw_on
        puts "Genset available #{available.round(1)}A, using 6kW heater"
        @devices.relays.heater_6kw = true
        @devices.relays.heater_9kw = false
      end
    else
      turn_off_heaters if heater_6kw_on || heater_9kw_on
    end
  end

  # Add heaters when solar production exceeds consumption
  def solar_load_shedding
    current_6kw = 6000.0 / 3 / 230  # ~8.7A
    current_9kw = 9000.0 / 3 / 230  # ~13A

    heater_6kw_on = @devices.relays.heater_6kw?
    heater_9kw_on = @devices.relays.heater_9kw?
    excess = @devices.next3.solar.excess?

    if excess
      if !heater_6kw_on && phase_current_capacity?(current_6kw)
        puts "Solar excess, turning on 6kW heater"
        @devices.relays.heater_6kw = true
      elsif heater_6kw_on && !heater_9kw_on && phase_current_capacity?(current_9kw)
        puts "Solar excess, turning on 9kW heater"
        @devices.relays.heater_9kw = true
      end
    elsif heater_6kw_on || heater_9kw_on
      # Keep heaters on if solar is contributing (discharge power < heater power)
      # Turn off one heater at a time, matching size to the deficit
      heater_power = (heater_6kw_on ? 6000 : 0) + (heater_9kw_on ? 9000 : 0)
      discharge_power = -@devices.next3.battery.power  # positive when discharging

      if discharge_power > heater_power
        # Turn off heater that best matches the discharge
        if heater_6kw_on && heater_9kw_on
          # Both on: turn off the one closest to discharge power
          if discharge_power < 9000
            puts "Discharge #{discharge_power.round}W, turning off 6kW heater"
            @devices.relays.heater_6kw = false
          else
            puts "Discharge #{discharge_power.round}W, turning off 9kW heater"
            @devices.relays.heater_9kw = false
          end
        elsif heater_9kw_on
          puts "Discharge #{discharge_power.round}W > 9kW, turning off 9kW heater"
          @devices.relays.heater_9kw = false
        else
          puts "Discharge #{discharge_power.round}W > 6kW, turning off 6kW heater"
          @devices.relays.heater_6kw = false
        end
      end
    end
  end

  def genset_running?
    true
  end

  def turn_off_heaters
    puts "Turning off heaters"
    @devices.relays.heater_6kw = false
    @devices.relays.heater_9kw = false
  end

  # Manage genset load using 6kW and 9kW heaters
  # Turn on heaters if aftertreatment temp < 250°C, off if any phase > 90%
  # Shelly demands have priority over heaters
  def genset_load_management
    measurements = @devices.gencomm.measurements
    max_load = [measurements[:load_pct_l1], measurements[:load_pct_l2], measurements[:load_pct_l3]].max
    aftertreatment_temp = measurements[:aftertreatment_temp]
    heater_6kw_on = @devices.relays.heater_6kw?
    heater_9kw_on = @devices.relays.heater_9kw?
    has_shelly_demand = @shelly_demands_mutex.synchronize { !@shelly_demands.empty? }

    # Turn off heaters if shelly demand or load too high
    if has_shelly_demand && (heater_6kw_on || heater_9kw_on)
      puts "Shelly demand registered, turning off heaters"
      turn_off_heaters
    elsif max_load > GENSET_MAX_LOAD_PCT
      if heater_6kw_on
        puts "Genset load #{max_load.round(1)}% > #{GENSET_MAX_LOAD_PCT}%, turning off 6kW heater"
        @devices.relays.heater_6kw = false
      elsif heater_9kw_on
        puts "Genset load #{max_load.round(1)}% > #{GENSET_MAX_LOAD_PCT}%, turning off 9kW heater"
        @devices.relays.heater_9kw = false
      end
    # Turn on heaters if aftertreatment temp too low
    elsif !has_shelly_demand
      if !heater_9kw_on && max_load + HEATER_9KW_LOAD_PCT <= GENSET_MAX_LOAD_PCT
        puts "No shelly demand, turning on 9kW heater"
        @devices.relays.heater_9kw = true
      elsif !heater_6kw_on && max_load + HEATER_6KW_LOAD_PCT <= GENSET_MAX_LOAD_PCT
        puts "No shelly demand, turning on 6kW heater"
        @devices.relays.heater_6kw = true
      end
    end
  rescue => e
    puts "[ERROR] Genset load management: #{e.message}"
  end

  def phase_current
    (1..3).map do |phase|
      @devices.next3.acload.current(phase)
    end
  end

  INVERTER_CURRENT_LIMIT = 22

  # Returns true if the current on any phase has been over 20A for 25s in a row,
  # during the last 5 minutes. That will result in a voltage drop. 
  def high_phase_current?
    not phase_current_capacity?(0)
  end

  # Can the requested current be added without overload? Look at the current draw
  # for the past 5 minutes
  def phase_current_capacity?(requested_current)
    # we can't know if there's capacity until we have 5 or more measurments
    return false if @phase_current_history.size < 5

    (0..2).each do |phase|
      streak = 0
      @phase_current_history.each do |phases|
        if INVERTER_CURRENT_LIMIT - phases[phase] - requested_current < 0
          streak += 1
        else
          streak = 0
        end
        return false if streak >= 5
      end
    end
    true
  end

  # Check if any phase is overloaded (>= 100%)
  def genset_overloaded?
    derived = @devices.gencomm.derived_measurements
    [derived[:load_pct_l1], derived[:load_pct_l2], derived[:load_pct_l3]].any? { |l| l >= 100 }
  end

  # Check if genset load allows additional amps
  def genset_load_allows?(amps)
    derived = @devices.gencomm.derived_measurements
    max_load = [derived[:load_pct_l1], derived[:load_pct_l2], derived[:load_pct_l3]].max
    estimated_additional_load = amps * 230 / 1000.0 * 3  # rough % estimate
    max_load + estimated_additional_load < GENSET_MAX_LOAD_PCT
  end

  # Shelly demand management
  def register_shelly_demand(host, amps)
    @shelly_demands_mutex.synchronize do
      @shelly_demands[host] = { amps:, active: false }

      # Immediately check if we can activate
      if genset_overloaded?
        return { activated: false, reason: "overloaded" }
      end

      if genset_running? && genset_load_allows?(amps)
        puts "Activating Shelly #{host} (#{amps}A) on registration"
        turn_on_shelly(host)
        @shelly_demands[host][:active] = true
        { activated: true }
      else
        { activated: false, reason: "no_capacity" }
      end
    end
  end

  def deregister_shelly_demand(host)
    @shelly_demands_mutex.synchronize do
      demand = @shelly_demands.delete(host)
      turn_off_shelly(host) if demand&.dig(:active)
    end
  end

  def shelly_demands_status
    @shelly_demands_mutex.synchronize { @shelly_demands.dup }
  end

  def manage_shelly_demands
    @shelly_demands_mutex.synchronize do
      return if @shelly_demands.empty?

      # If any phase overloaded, turn off all active demands
      if genset_overloaded?
        @shelly_demands.each do |host, demand|
          if demand[:active]
            puts "Genset overloaded, turning off Shelly #{host}"
            turn_off_shelly(host)
            demand[:active] = false
          end
        end
        return
      end

      # Manage demands based on genset load capacity
      @shelly_demands.each do |host, demand|
        if demand[:active]
          # Already active, check if we need to shed load
          unless genset_load_allows?(0)
            puts "Genset load high, turning off Shelly #{host}"
            turn_off_shelly(host)
            demand[:active] = false
          end
        else
          # Not active, check if we have capacity
          if genset_load_allows?(demand[:amps])
            puts "Capacity available, turning on Shelly #{host} (#{demand[:amps]}A)"
            turn_on_shelly(host)
            demand[:active] = true
          end
        end
      end
    end
  end

  def turn_on_shelly(host)
    shelly_rpc(host, "Switch.Set", { id: 0, on: true })
  rescue => e
    puts "[ERROR] Failed to turn on Shelly #{host}: #{e.message}"
  end

  def turn_off_shelly(host)
    shelly_rpc(host, "Switch.Set", { id: 0, on: false })
  rescue => e
    puts "[ERROR] Failed to turn off Shelly #{host}: #{e.message}"
  end

  def shelly_rpc(host, method, params = {})
    uri = URI("http://#{host}/rpc")
    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = 2
    http.read_timeout = 3
    request = Net::HTTP::Post.new(uri.path, { "Content-Type" => "application/json" })
    request.body = { id: 0, method:, params: }.to_json
    http.request(request)
  end

  BATTERY_KWH = 31.2

  # Manage genset start/stop thresholds via Next3 aux1 relay
  def genset_threshold_management(soc = @devices.next3.battery.soc)
    return if Time.monotonic - @last_threshold_check < 60
    @last_threshold_check = Time.monotonic

    current_deactivation = @devices.next3.aux1.soc_deactivation_threshold
    target_deactivation = DEFAULT_GENSET_DEACTIVATION_SOC

    # If weco module SoC drift > 5%, increase deactivation threshold to 99%
    # to allow batteries to balance
    soc_diff = weco_module_soc_diff
    if soc_diff > 5
      target_deactivation = 99
      puts "Battery module SoC drift #{soc_diff.round(1)}% > 5%, setting genset deactivation to 99%"
    # If solar forecast shows we'll survive, decrease threshold to stop genset earlier
    elsif genset_running? && will_survive_on_solar?(soc)
      target_deactivation = [soc.ceil + 5, DEFAULT_GENSET_DEACTIVATION_SOC].min
      puts "Solar forecast positive, lowering genset deactivation to #{target_deactivation}%"
    end

    if current_deactivation != target_deactivation
      puts "Adjusting genset deactivation threshold: #{current_deactivation}% -> #{target_deactivation}%"
      @devices.next3.aux1.soc_deactivation_threshold = target_deactivation
    end
  end

  # Check if solar will sustain us for the rest of the day
  def will_survive_on_solar?(soc)
    return false if @phase_current_history.size < 5

    avg_power_kw = @phase_current_history.sum { |phases| phases.sum } * 230 / @phase_current_history.size / 1000.0
    battery_kwh = BATTERY_KWH * soc / 100.0

    produced_solar_today = @devices.next3.solar.total_day_energy / 1000.0
    @solar_forecast.actual = produced_solar_today if produced_solar_today > 1

    last_time = start = Time.now
    @solar_forecast.estimate_watt_hours.each do |t, watthours|
      time = Time.parse(t)
      next if time <= last_time

      period = (time - last_time) / 3600
      battery_kwh += ((watthours / 1000.0) - (avg_power_kw * period))
      estimated_soc = (battery_kwh / BATTERY_KWH * 100).round
      return false if estimated_soc <= DEFAULT_GENSET_ACTIVATION_SOC

      last_time = time
    end
    return false if last_time == start
    true
  rescue => e
    puts "[ERROR] Solar forecast: #{e.inspect}"
    false
  end

  def weco_module_soc_diff
    min_soc = nil
    max_soc = nil
    @devices.weco.modules.each do |mod|
      min_soc = mod[:soc_value] if min_soc.nil? || mod[:soc_value] < min_soc
      max_soc = mod[:soc_value] if max_soc.nil? || mod[:soc_value] > max_soc
    end
    max_soc - min_soc
  end
end
