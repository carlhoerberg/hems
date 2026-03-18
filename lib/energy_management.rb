require_relative "./devices"
require_relative "./solar_forecast"
require "net/http"
require "json"
require "time"

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

  BATTERY_CAPACITY_KWH = 31.8
  NOMINAL_VOLTAGE = 230
  MIN_SOLAR_PRODUCTION_WH = 200 # minimum Wh in a period to count as "solar producing"

  HEATER_PHASE_LIMIT = 22 # max amps per phase for heater best-fit

  # All heaters with per-phase amp draw
  # phase_amps: { phase_number => amps_on_that_phase }
  HEATERS = [
    { id: :shelly_2kw_p2, host: "192.168.0.190", phase_amps: { 1 => 4 } },
    # { id: :shelly_2kw_p3, host: "192.168.0.137", phase_amps: { 3 => 9 } },
    { id: :heater_6kw, phase_amps: { 1 => 9, 2 => 9, 3 => 9 } },
    { id: :heater_9kw, phase_amps: { 1 => 13, 2 => 13, 3 => 13 } },
  ].freeze

  INVERTER_CURRENT_LIMIT = 26
  GENSET_CURRENT_LIMIT = 50

  GENSET_DEMAND_START_DELAY = 180    # seconds of unmet demand before starting genset
  GENSET_DEMAND_STOP_DELAY = 15 * 60 # seconds after last demand before stopping genset

  VICTRON_INVERTER_ONLY_MIN_SOC = 50 # only shed Victron charging if SoC > this
  MIN_PHASE_VOLTAGE = 220 # turn off shelly demands if any phase drops below this
  SOLAR_EXCESS_HEATER_STOP_SOC = 95   # keep solar excess heaters on until this SoC

  # Shelly units with demand switching — poll input to catch missed register/deregister actions
  SHELLY_DEMAND_UNITS = [
    { host: "192.168.0.160", name: "Huvuddiskmaskinen", amps: 16 },
    { host: "192.168.0.174", name: "Glasdiskmaskinen", amps: 9 },
  ].freeze

  STATE_FILE = File.join(ENV.fetch("STATE_DIRECTORY", "/var/lib/hems"), "energy_management.json")

  def initialize(devices)
    @devices = devices
    @stopped = false
    @shelly_demands = {}  # { device_id => { amps:, active: false, unmet_since: nil } }
    @shelly_demands_mutex = Mutex.new
    @phase_current_history = []
    @genset_started_for_demand = false # true if we manually started genset for shelly demand
    @last_shelly_demand_at = nil      # monotonic time of last shelly demand registration
    @ac_source_enabled = @devices.next3.acsource.enabled?
    @solar_forecast = SolarForecast.new
    @last_threshold_check = 0
    @last_solar_actual_update = 0
    load_state
  end

  def start
    until @stopped
      begin
        duration = Time.measure do
          manage_ac_source
          update_phase_current_history
          poll_shelly_demand_inputs
          manage_shelly_demands
          manage_genset_for_demand
          manage_heaters
          manage_goe_amperage
          manage_victron_mode
          update_solar_actual
          genset_threshold_management
          save_state
        end
        puts "Energy management loop duration: #{duration.round(2)}s" if duration > 5
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

# Enable AC source only when genset mains breaker is closed (supplying power).
  # Disable during warmup/cooldown (fuel relay on but mains breaker off).
  # Fail-safe: re-enable when genset is fully off (both relays off).
  def manage_ac_source
    fuel = @devices.gencomm.fuel_relay
    mains_breaker = @devices.gencomm.mains_breaker_relay

    if fuel && mains_breaker
      # Genset running, mains breaker closed, power available
      unless @ac_source_enabled
        puts "Fuel and mains breaker relays on, enabling AC source"
        @devices.next3.acsource.enable
        @ac_source_enabled = true
      end
    elsif fuel
      # Warming up or cooling down, no stable power
      if @ac_source_enabled
        puts "Fuel relay on but mains breaker off (warmup/cooldown), disabling AC source"
        @devices.next3.acsource.disable
        @ac_source_enabled = false
      end
    else
      # Genset fully off, fail-safe: enable AC source
      unless @ac_source_enabled
        puts "Genset off (fuel relay off), enabling AC source (fail-safe)"
        @devices.next3.acsource.enable
        @ac_source_enabled = true
      end
    end
  rescue => e
    puts "[ERROR] manage_ac_source: #{e.message}"
  end

  def battery_soc
    @devices.weco.avg_soc
  rescue => e
    puts "[WARN] Weco SoC unavailable (#{e.message}), falling back to Next3"
    @devices.next3.battery.soc
  end

  def genset_running?
    @devices.gencomm.is_running?
  rescue => e
    puts "[ERROR] genset_running? check failed: #{e.message}"
    false
  end

  def victron_inverter_only?
    @devices.victron.mode == Devices::Victron::VEBUS_MODE_INVERTER_ONLY
  rescue => e
    puts "[ERROR] victron_inverter_only? check failed: #{e.message}"
    false
  end

  # Aux1 operating mode: 0 = Manual Off, 1 = Manual On, 2 = Auto
  def aux1_operating_mode
    @devices.next3.aux1.operating_mode
  end

  # Set aux1 relay operating mode on the Next3.
  # 0 = Manual Off, 1 = Manual On, 2 = Auto
  def set_aux_mode(mode)
    puts "Setting aux1 operating mode to #{mode}"
    @devices.next3.aux1.operating_mode = mode
  end

  # Per-phase current capacity: inverter 22A, genset adds 50A
  def per_phase_capacity
    genset_running? ? INVERTER_CURRENT_LIMIT + GENSET_CURRENT_LIMIT : INVERTER_CURRENT_LIMIT
  end

  def phase_current
    (1..3).map do |phase|
      @devices.next3.acload.current(phase)
    end
  end

  def low_voltage?
    (1..3).any? { |phase| @devices.next3.acload.voltage(phase) < MIN_PHASE_VOLTAGE }
  end

  def update_phase_current_history
    @phase_current_history << phase_current
    @phase_current_history.shift if @phase_current_history.size > 60
  end

  # Check if any phase is currently overloaded
  def phase_overloaded?
    return false if @phase_current_history.empty?
    capacity = per_phase_capacity
    @phase_current_history.last.any? { |c| c >= capacity }
  end

  # Can the requested current be added without overload? Checks that no phase
  # has been over the limit for 5 consecutive samples in the history.
  def phase_current_capacity?(requested_current)
    no_capacity_reason(requested_current).nil?
  end

  # Returns nil if capacity is available, or a reason string if not.
  def no_capacity_reason(requested_current)
    return "no current data" if @phase_current_history.empty?

    limit = per_phase_capacity
    currents = @phase_current_history.last
    (0..2).each do |phase|
      headroom = limit - currents[phase]
      if headroom < requested_current
        return "L#{phase + 1} over limit (#{headroom.round(1)}A headroom, need #{requested_current}A)"
      end
    end
    nil
  end

  # Poll known Shelly demand units' input state to catch missed register/deregister actions
  def poll_shelly_demand_inputs
    SHELLY_DEMAND_UNITS.each do |unit|
      input_on = shelly_input_on?(unit[:host])
      next if input_on.nil? # unreachable, skip

      has_demand = @shelly_demands_mutex.synchronize { @shelly_demands.key?(unit[:host]) }

      if input_on && !has_demand
        puts "Shelly #{unit[:name]} (#{unit[:host]}) input is on but no demand registered, registering"
        register_shelly_demand(unit[:host], unit[:amps])
      elsif !input_on && has_demand
        puts "Shelly #{unit[:name]} (#{unit[:host]}) input is off but demand registered, deregistering"
        deregister_shelly_demand(unit[:host])
      end
    end
  end

  # Shelly demand management
  def register_shelly_demand(host, amps)
    @shelly_demands_mutex.synchronize do
      puts "Registering Shelly demand: #{host} (#{amps}A)"
      @shelly_demands[host] = { amps:, active: false, unmet_since: nil }
      @last_shelly_demand_at = Time.monotonic

      reason = no_capacity_reason(amps)
      if reason.nil?
        puts "Activating Shelly #{host} (#{amps}A) on registration"
        turn_on_shelly(host)
        @shelly_demands[host][:active] = true
        { activated: true }
      else
        puts "Cannot activate Shelly #{host} (#{amps}A): #{reason}"
        @shelly_demands[host][:unmet_since] = Time.monotonic
        { activated: false, reason: }
      end
    end
  end

  def deregister_shelly_demand(host)
    @shelly_demands_mutex.synchronize do
      puts "Deregistering Shelly demand: #{host}"
      @shelly_demands.delete(host)
      turn_off_shelly(host)
    end
  end

  def shelly_demands_status
    @shelly_demands_mutex.synchronize { @shelly_demands.dup }
  end

  def manage_shelly_demands
    @shelly_demands_mutex.synchronize do
      has_active = @shelly_demands.any? { |_, d| d[:active] }

      if has_active && low_voltage?
        puts "Low voltage detected, turning off all active Shelly demands"
        @shelly_demands.each do |host, demand|
          next unless demand[:active]
          turn_off_shelly(host)
          demand[:active] = false
          demand[:unmet_since] = Time.monotonic
        end
        return
      end

      @shelly_demands.each do |host, demand|
        if demand[:active]
          if phase_overloaded?
            puts "Phase overloaded, turning off Shelly #{host}"
            turn_off_shelly(host)
            demand[:active] = false
            demand[:unmet_since] = Time.monotonic
          end
        else
          if demand[:unmet_since] && shelly_input_on?(host) == false
            puts "Shelly #{host} input is off, removing stale demand"
            @shelly_demands.delete(host)
          elsif (reason = no_capacity_reason(demand[:amps])).nil?
            puts "Capacity available, turning on Shelly #{host} (#{demand[:amps]}A)"
            turn_on_shelly(host)
            demand[:active] = true
            demand[:unmet_since] = nil
          else
            puts "Shelly #{host} demand unmet: #{reason}" if demand[:unmet_since].nil?
            demand[:unmet_since] ||= Time.monotonic
          end
        end
      end
    end
  end

  # Shed Victron charging load when there's unmet shelly demand due to phase overload
  # and SoC is sufficient. Restore normal mode when all demands are met or SoC drops too low.
  def manage_victron_mode
    @shelly_demands_mutex.synchronize do
      has_capacity_unmet = @shelly_demands.any? do |_, d|
        !d[:active] && no_capacity_reason(d[:amps])&.include?("over limit")
      end

      if has_capacity_unmet && !victron_inverter_only? &&
         @devices.victron.battery_soc > VICTRON_INVERTER_ONLY_MIN_SOC
        puts "Unmet shelly demand (phase over limit), setting Victron to inverter-only mode"
        @devices.victron.mode = Devices::Victron::VEBUS_MODE_INVERTER_ONLY
      elsif victron_inverter_only? && (!has_capacity_unmet ||
            @devices.victron.battery_soc <= VICTRON_INVERTER_ONLY_MIN_SOC)
        puts "Restoring Victron to normal mode"
        @devices.victron.mode = Devices::Victron::VEBUS_MODE_ON
      end
    end
  rescue => e
    puts "[ERROR] manage_victron_mode: #{e.message}"
  end

  def manage_genset_for_demand
    @shelly_demands_mutex.synchronize do
      now = Time.monotonic
      demand_ready = @shelly_demands.any? do |_, d|
        d[:unmet_since] && now - d[:unmet_since] >= GENSET_DEMAND_START_DELAY
      end

      if demand_ready && !@genset_started_for_demand && !genset_running?
        puts "Shelly demand unmet for #{GENSET_DEMAND_START_DELAY}s, starting genset"
        set_aux_mode(1)
        @genset_started_for_demand = true
      end

      if @genset_started_for_demand
        if @shelly_demands.empty? && @last_shelly_demand_at &&
           Time.monotonic - @last_shelly_demand_at >= GENSET_DEMAND_STOP_DELAY
          puts "No shelly demand for #{GENSET_DEMAND_STOP_DELAY / 60} minutes, stopping genset"
          set_aux_mode(2)
          @genset_started_for_demand = false
        end
      end
    end
  end


  def solar_excess?
    @devices.next3.solar.excess?
  rescue => e
    puts "[ERROR] solar_excess? check failed: #{e.message}"
    false
  end

  def has_unmet_shelly_demand?
    @shelly_demands_mutex.synchronize { @shelly_demands.any? { |_, d| !d[:active] } }
  end

  def has_shelly_demand?
    @shelly_demands_mutex.synchronize { @shelly_demands.any? }
  end

  def manage_heaters
    genset = genset_running?
    demand = has_unmet_shelly_demand?

    if low_voltage?
      turn_off_one_heater("voltage sag")
      return
    elsif demand
      turn_off_one_heater("unmet shelly demand")
      return
    elsif !genset && (soc = battery_soc) < SOLAR_EXCESS_HEATER_STOP_SOC
      turn_off_one_heater("SoC #{soc}% below #{SOLAR_EXCESS_HEATER_STOP_SOC}%")
      return
    end

    return if !genset && !solar_excess?
    return if has_shelly_demand?

    return if @phase_current_history.empty?
    currents = @phase_current_history.last

    # Turn on heaters in order if they fit under HEATER_PHASE_LIMIT (one per iteration)
    HEATERS.each do |heater|
      state = heater_on?(heater)
      next if state || state.nil? # skip if on or unreachable
      if heater_fits?(heater, currents)
        turn_on_heater(heater)
        return
      end
    end
  end

  def heater_on?(heater)
    if heater[:host]
      heater_shelly_on?(heater[:host])
    else
      @devices.relays.send(:"#{heater[:id]}?")
    end
  end

  # Check if turning on this heater would keep all its phases under HEATER_PHASE_LIMIT
  def heater_fits?(heater, currents)
    limit = genset_running? ? HEATER_PHASE_LIMIT + GENSET_CURRENT_LIMIT : HEATER_PHASE_LIMIT
    heater[:phase_amps].all? { |phase, amps| currents[phase - 1] + amps < limit }
  end

  def turn_on_heater(heater)
    puts "Turning on #{heater[:id]} heater"
    if heater[:host]
      turn_on_shelly(heater[:host])
    else
      @devices.relays.send(:"#{heater[:id]}=", true)
    end
  end

  def turn_off_heater(heater, reason = nil)
    msg = "Turning off #{heater[:id]} heater"
    msg += " (#{reason})" if reason
    puts msg
    if heater[:host]
      turn_off_shelly(heater[:host])
    else
      @devices.relays.send(:"#{heater[:id]}=", false)
    end
  end

  # Turn off one heater in reverse order (9kW first, then 6kW, then 2kW shellys)
  def turn_off_one_heater(reason = nil)
    HEATERS.reverse_each do |heater|
      if heater_on?(heater)
        turn_off_heater(heater, reason)
        return true
      end
    end
    false
  end

  # Adapt go-e charger amperage so that L1 on the inverter never exceeds INVERTER_CURRENT_LIMIT.
  # Calculates the non-charger load on L1, then sets the charger to use whatever headroom remains.
  def manage_goe_amperage
    return if @goe_unavailable
    return unless @devices.goe.car_connected?

    # Only charge with solar (SoC >= 95% implies solar is producing) or genset
    soc = battery_soc
    if has_shelly_demand? || (soc < SOLAR_EXCESS_HEATER_STOP_SOC && !genset_running?)
      if @devices.goe.allow != 0
        reason = has_shelly_demand? ? "shelly demand" : "SoC #{soc.round}% < #{SOLAR_EXCESS_HEATER_STOP_SOC}% and no genset"
        puts "go-e: pausing charging (#{reason})"
        @devices.goe.allow = false
      end
      return
    end

    l1_current = @devices.next3.acload.current(1)
    current_setting = @devices.goe.ampere
    limit = per_phase_capacity

    other_load = l1_current - current_setting
    target = (limit - other_load).floor
    target = target.clamp(0, Devices::GoE::MAX_AMPS)

    if target < Devices::GoE::MIN_AMPS
      if @devices.goe.allow != 0
        puts "go-e: L1 headroom too low (#{(limit - other_load).round(1)}A), pausing charging"
        @devices.goe.allow = false
      end
    else
      if @devices.goe.allow == 0
        puts "go-e: L1 headroom available (#{target}A), resuming charging at #{target}A"
        @devices.goe.ampere = target
        @devices.goe.allow = true
      elsif current_setting != target
        puts "go-e: adjusting amperage #{current_setting}A -> #{target}A (L1: #{l1_current.round(1)}A, other: #{other_load.round(1)}A)"
        @devices.goe.ampere = target
      end
    end
  rescue SocketError, SystemCallError, IOError => e
    @goe_unavailable = true
    puts "[ERROR] go-e charger unavailable: #{e.message}"
  rescue => e
    puts "[ERROR] manage_goe_amperage: #{e.message}"
  end

  def heater_shelly_on?(host)
    response = shelly_rpc(host, "Switch.GetStatus", { id: 0 })
    @heater_shelly_errors&.delete(host)
    JSON.parse(response.body)["output"]
  rescue => e
    @heater_shelly_errors ||= {}
    unless @heater_shelly_errors[host]
      puts "[WARN] Shelly heater #{host} unreachable: #{e.message}"
      @heater_shelly_errors[host] = true
    end
    nil
  end

  def shelly_input_on?(host)
    response = shelly_rpc(host, "Input.GetStatus", { id: 0 })
    JSON.parse(response.body)["state"]
  rescue => e
    puts "[WARN] Failed to poll Shelly input #{host}: #{e.message}"
    nil
  end

  def turn_on_shelly(host)
    puts "Turning on Shelly #{host}"
    shelly_rpc(host, "Switch.Set", { id: 0, on: true })
  rescue => e
    puts "[ERROR] Failed to turn on Shelly #{host}: #{e.message}"
  end

  def turn_off_shelly(host)
    puts "Turning off Shelly #{host}"
    shelly_rpc(host, "Switch.Set", { id: 0, on: false })
  rescue => e
    puts "[ERROR] Failed to turn off Shelly #{host}: #{e.message}"
  end

  def save_state
    @shelly_demands_mutex.synchronize do
      state = {
        shelly_demands: @shelly_demands,
        genset_started_for_demand: @genset_started_for_demand,
      }
      File.write(STATE_FILE, JSON.pretty_generate(state))
    end
  rescue => e
    puts "[ERROR] Failed to save state: #{e.message}"
  end

  def load_state
    return unless File.exist?(STATE_FILE)

    state = JSON.parse(File.read(STATE_FILE), symbolize_names: true)
    @shelly_demands = (state[:shelly_demands] || {}).transform_keys(&:to_s)
    @genset_started_for_demand = state[:genset_started_for_demand] || false
    puts "Loaded state from #{STATE_FILE}"
  rescue => e
    puts "[ERROR] Failed to load state: #{e.message}"
  end

  def shelly_rpc(host, method, params)
    http = Net::HTTP.new(host)
    http.open_timeout = 3
    http.read_timeout = 3
    http.get("/rpc/#{method}?#{URI.encode_www_form(params)}")
  end

  # Manage genset start/stop thresholds via Next3 aux1 relay
  def genset_threshold_management(soc = battery_soc)
    return if Time.monotonic - @last_threshold_check < 300
    @last_threshold_check = Time.monotonic

    current_deactivation = @devices.next3.aux1.soc_deactivation_threshold
    target_deactivation = genset_running? ? solar_aware_deactivation_soc(soc) : DEFAULT_GENSET_DEACTIVATION_SOC
    if target_deactivation == DEFAULT_GENSET_DEACTIVATION_SOC
      # If weco module SoC drift, increase deactivation threshold to 99%
      # to allow batteries to balance
      soc_diff = weco_module_soc_diff
      if soc_diff > 10
        target_deactivation = 99
        puts "Battery module SoC drift #{soc_diff.round(1)}% > 10%, setting genset deactivation to 99%"
      end
    end

    if current_deactivation != target_deactivation
      detail = @solar_deactivation_detail ? " (#{@solar_deactivation_detail})" : ""
      puts "Adjusting genset deactivation threshold: #{current_deactivation}% -> #{target_deactivation}%#{detail}"
      @devices.next3.aux1.soc_deactivation_threshold = target_deactivation
    end
  end

  # Calculate genset deactivation SoC so that battery stays above activation threshold
  # at every hour through the end of the solar day, accounting for both solar production and load.
  def solar_aware_deactivation_soc(current_soc)
    forecast = @solar_forecast.estimate_watt_hours
    return DEFAULT_GENSET_DEACTIVATION_SOC unless forecast&.any?

    now = Time.now
    today = now.to_date
    load_kw = average_load_kw
    prev_time = now
    cumulative_kwh = 0.0
    worst_deficit_kwh = 0.0

    forecast.each do |time_str, wh|
      period_time = Time.parse(time_str)
      next if period_time < now
      break if period_time.to_date != today

      hours = (period_time - prev_time) / 3600.0
      cumulative_kwh += wh / 1000.0 - (hours * load_kw)
      worst_deficit_kwh = cumulative_kwh if cumulative_kwh < worst_deficit_kwh
      prev_time = period_time
    end

    return DEFAULT_GENSET_DEACTIVATION_SOC if prev_time == now

    worst_deficit_soc = (-worst_deficit_kwh / BATTERY_CAPACITY_KWH) * 100
    target_soc = (DEFAULT_GENSET_ACTIVATION_SOC + worst_deficit_soc).ceil
    target_soc = target_soc.clamp(50, DEFAULT_GENSET_DEACTIVATION_SOC)

    @solar_deactivation_detail = "load=#{load_kw.round(1)}kW worst_deficit=#{(-worst_deficit_kwh).round(1)}kWh"

    target_soc
  rescue => e
    puts "[WARN] Solar forecast unavailable: #{e.message}"
    DEFAULT_GENSET_DEACTIVATION_SOC
  end

  def average_load_kw
    return 3.0 if @phase_current_history.empty?

    total_amps = @phase_current_history.sum { |phases| phases.sum } / @phase_current_history.size.to_f
    total_amps * NOMINAL_VOLTAGE / 1000.0
  end


  def update_solar_actual
    return if Time.monotonic - @last_solar_actual_update < 300

    today_wh = @devices.next3.solar.total_day_energy
    return if today_wh < 1000

    @solar_forecast.actual = today_wh / 1000.0
    @last_solar_actual_update = Time.monotonic
    puts "Updated solar forecast actual: #{(today_wh / 1000.0).round(2)}kWh"
  rescue => e
    puts "[WARN] Failed to update solar forecast actual: #{e.message}"
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
