require_relative "./devices"
require_relative "./smhi_solar_forecast"
require_relative "./victoriametrics"
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

  BATTERY_CAPACITY_KWH = 31.8 * 2

  # Fallback hourly load profile (kW) derived from observed data (Apr 9-12)
  HOURLY_LOAD_FALLBACK_KW = [
    5.1, 4.2, 3.6, 3.7, 3.8, 3.4,   # 00-05
    3.6, 6.6, 6.5, 6.4, 8.1, 7.8,   # 06-11
    7.3, 7.8, 10.1, 11.1, 11.2, 10.0, # 12-17
    7.0, 7.1, 7.3, 7.4, 7.3, 7.2,   # 18-23
  ].freeze

  # All heaters with per-phase amp draw
  # phase_amps: { phase_number => amps_on_that_phase }
  HEATERS = [
    # { id: :shelly_2kw_p3, host: "192.168.0.137", phase_amps: { 3 => 9 } },
    { id: :heater_6kw, host: "192.168.0.224", channel: 1, phase_amps: { 1 => 9, 2 => 9, 3 => 9 } },
    { id: :heater_9kw, host: "192.168.0.224", channel: 0, phase_amps: { 1 => 13, 2 => 13, 3 => 13 } },
  ].freeze

  SPORTSTUGAN_HEATER_HOST = "192.168.0.190"
  SPORTSTUGAN_HEATER_W = 1100
  SPORTSTUGAN_DEACTIVATION_CHARGE_W = 0

  GENSET_CURRENT_LIMITS = { gencomm: 50, sdmo: 10 }.freeze

  INVERTER_CURRENT_LIMIT = 44

  MIN_PHASE_VOLTAGE = 210 # turn off shelly demands if any phase drops below this
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
    @last_shelly_demand_at = nil      # monotonic time of last shelly demand registration
    @ac_source_enabled = @devices.next3.acsource.enabled?
    @sdmo_cooling_down = false
    @solar_forecast = SmhiSolarForecast.new
    @last_threshold_check = 0
    @last_solar_actual_update = 0
    @last_forecast_push = 0
    @active_genset = :gencomm
    @hourly_load_kwh = Array.new(24, nil)
    @last_total_energy_wh = nil
    @last_hourly_kwh_at = nil
    @last_hourly_load_update = 0
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
          manage_heaters
          manage_sportstugan_heater
          manage_goe_amperage
          push_solar_forecast
          update_hourly_load_profile
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
  def active_genset
    @active_genset
  end

  def active_genset=(new_genset)
    new_genset = new_genset.to_sym
    raise ArgumentError, "Unknown genset: #{new_genset}" unless GENSET_CURRENT_LIMITS.key?(new_genset)
    return if @active_genset == new_genset

    @active_genset = new_genset
    limit = GENSET_CURRENT_LIMITS[new_genset]
    puts "Active genset changed to #{new_genset}, setting AC source rated current to #{limit}A"
    @devices.next3.acsource.rated_current = limit
    save_state
  end

  def genset_current_limit
    GENSET_CURRENT_LIMITS[@active_genset]
  end

  def manage_ac_source
    if @active_genset == :sdmo
      # SDMO in manual mode: start/stop based on aux relay binary_input
      # binary_input bit 1: 1 = start request (aux relay closed), 0 = stop request (aux relay open)
      if @sdmo_cooling_down
        temp = genset.coolant_temperature
        if temp <= 80
          puts "SDMO coolant #{temp}°C <= 80°C, stopping genset"
          genset.stop
          @sdmo_cooling_down = false
          unless @ac_source_enabled
            puts "SDMO stopped, enabling AC source (fail-safe)"
            @devices.next3.acsource.enable
            @ac_source_enabled = true
          end
        end
      else
        start_request = genset.binary_input[1] == 1
        if start_request
          unless genset.ready_to_load?
            puts "SDMO aux relay closed, starting genset"
            genset.start
            @devices.goe.ampere = 6 # SDMO GCB trips by high DC current from charging
          end
          if genset.ready_to_load? && !@ac_source_enabled
            puts "SDMO running, enabling AC source"
            @devices.next3.acsource.enable
            @ac_source_enabled = true
          end
        elsif genset.ready_to_load?
          # Aux just opened while running: disable AC source and begin cooldown
          if @ac_source_enabled
            puts "SDMO start request cleared, disabling AC source for cooldown"
            @devices.next3.acsource.disable
            @ac_source_enabled = false
          end
          @sdmo_cooling_down = true
        else
          # Aux open, not running: fail-safe enable AC source
          unless @ac_source_enabled
            puts "SDMO genset off, enabling AC source (fail-safe)"
            @devices.next3.acsource.enable
            @ac_source_enabled = true
          end
        end
      end
    end
  rescue => e
    puts "[ERROR] manage_ac_source: #{e.message}"
  end

  def battery_soc
    socs = @devices.weco.values.map(&:avg_soc)
    socs.sum / socs.size
  rescue => e
    puts "[WARN] Weco SoC unavailable (#{e.message}), falling back to Next3"
    @devices.next3.battery.soc
  end

  def genset_running?
    @active_genset == :sdmo ? genset.ready_to_load? : genset.is_running?
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

  # Per-phase current capacity: inverter 44A, genset adds its rated limit
  def per_phase_capacity
    if genset_running?
      [INVERTER_CURRENT_LIMIT + genset_current_limit, 80].min # transfer limit 80A
    else
      INVERTER_CURRENT_LIMIT
    end
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

  def solar_excess?
    @devices.next3.solar.excess?
  rescue => e
    puts "[ERROR] solar_excess? check failed: #{e.message}"
    false
  end

  def unmet_shelly_demand_amps
    @shelly_demands_mutex.synchronize { @shelly_demands.sum { |_, d| d[:active] ? 0 : d[:amps] } }
  end

  def has_unmet_shelly_demand?
    @shelly_demands_mutex.synchronize { @shelly_demands.any? { |_, d| !d[:active] } }
  end

  def has_shelly_demand?
    @shelly_demands_mutex.synchronize { @shelly_demands.any? }
  end

  def manage_heaters
    demand = has_unmet_shelly_demand?

    if low_voltage?
      turn_off_one_heater("voltage sag")
      return
    elsif demand
      turn_off_one_heater("unmet shelly demand")
      return
    elsif (soc = battery_soc) < SOLAR_EXCESS_HEATER_STOP_SOC
      turn_off_one_heater("SoC #{soc}% below #{SOLAR_EXCESS_HEATER_STOP_SOC}%")
      return
    end

    return unless solar_excess?
    return if has_shelly_demand?

    return if @phase_current_history.empty?
    currents = @phase_current_history.last

    # Turn on heaters in order if they fit (one per iteration)
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
    heater_shelly_on?(heater[:host], heater[:channel])
  end

  # Check if turning on this heater would keep all its phases under phase limit
  def heater_fits?(heater, currents)
    limit = per_phase_capacity
    heater[:phase_amps].all? { |phase, amps| currents[phase - 1] + amps < limit }
  end

  def turn_on_heater(heater)
    puts "Turning on #{heater[:id]} heater"
    turn_on_shelly(heater[:host], heater[:channel])
  end

  def turn_off_heater(heater, reason = nil)
    msg = "Turning off #{heater[:id]} heater"
    msg += " (#{reason})" if reason
    puts msg
    turn_off_shelly(heater[:host], heater[:channel])
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

  def total_battery_charging_power
    @devices.next3.system_total.battery_charging_power
  end

  def manage_sportstugan_heater
    power = total_battery_charging_power
    currently_on = heater_shelly_on?(SPORTSTUGAN_HEATER_HOST)
    return if currently_on.nil?

    if !currently_on && power > SPORTSTUGAN_HEATER_W
      puts "Battery charging at #{power.round}W > #{SPORTSTUGAN_HEATER_W}W, enabling sportstugan heater"
      turn_on_shelly(SPORTSTUGAN_HEATER_HOST)
    elsif currently_on && power < SPORTSTUGAN_DEACTIVATION_CHARGE_W
      puts "Battery discharging at #{power.round}W, disabling sportstugan heater"
      turn_off_shelly(SPORTSTUGAN_HEATER_HOST)
    end
  rescue => e
    puts "[ERROR] manage_sportstugan_heater: #{e.message}"
  end

  # Adapt go-e charger amperage so that L1 on the inverter never exceeds INVERTER_CURRENT_LIMIT.
  # Calculates the non-charger load on L1, then sets the charger to use whatever headroom remains.
  def manage_goe_amperage
    return if @goe_unavailable

    l1_current = @phase_current_history.last[0]
    charger_current = @devices.goe.amp_l1
    limit = per_phase_capacity

    other_load = l1_current - charger_current
    demand_amps = unmet_shelly_demand_amps
    target = (limit - other_load - demand_amps).floor

    max_amps = genset_running? ? 8 : Devices::GoE::MAX_AMPS # avoid GCB tripping when genset is running by capping at 8A
    target = target.clamp(0, max_amps)

    if target < Devices::GoE::MIN_AMPS
      if @devices.goe.allow?
        puts "go-e: L1 headroom too low (#{(limit - other_load).round(1)}A), pausing charging"
        @devices.goe.allow = false
      end
    else
      if !@devices.goe.allow?
        puts "go-e: L1 headroom available (#{target}A), resuming charging at #{target}A"
        @devices.goe.allow = true
        @devices.goe.ampere = target
      elsif (current_setting = @devices.goe.ampere) != target
        puts "go-e: adjusting amperage #{current_setting}A -> #{target}A (L1: #{l1_current.round(1)}A, other: #{other_load.round(1)}A, demand: #{demand_amps}A)"
        @devices.goe.ampere = target
      end
    end
  rescue SocketError, SystemCallError, IOError => e
    @goe_unavailable = true
    puts "[ERROR] go-e charger unavailable: #{e.message}"
  rescue => e
    puts "[ERROR] manage_goe_amperage: #{e.message}"
  end

  def heater_shelly_on?(host, channel = 0)
    response = shelly_rpc(host, "Switch.GetStatus", { id: channel })
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

  def turn_on_shelly(host, channel = 0)
    puts "Turning on Shelly #{host} channel #{channel}"
    shelly_rpc(host, "Switch.Set", { id: channel, on: true })
  rescue => e
    puts "[ERROR] Failed to turn on Shelly #{host}: #{e.message}"
  end

  def turn_off_shelly(host, channel = 0)
    puts "Turning off Shelly #{host} channel #{channel}"
    shelly_rpc(host, "Switch.Set", { id: channel, on: false })
  rescue => e
    puts "[ERROR] Failed to turn off Shelly #{host}: #{e.message}"
  end

  def save_state
    @shelly_demands_mutex.synchronize do
      state = {
        shelly_demands: @shelly_demands,
        active_genset: @active_genset,
        hourly_load_kwh: @hourly_load_kwh,
        last_total_energy_wh: @last_total_energy_wh,
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
    saved_genset = state[:active_genset]&.to_sym
    @active_genset = saved_genset if saved_genset && GENSET_CURRENT_LIMITS.key?(saved_genset)
    saved_profile = state[:hourly_load_kwh]
    @hourly_load_kwh = saved_profile if saved_profile&.size == 24
    @last_total_energy_wh = state[:last_total_energy_wh]
    puts "Loaded state from #{STATE_FILE}"
  rescue => e
    puts "[ERROR] Failed to load state: #{e.message}"
  end

  def genset
    @devices.public_send(@active_genset)
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
  # at every point through the next two days, accounting for solar production and load.
  # Looks ahead through tomorrow so nighttime runs charge enough to survive until next-day solar.
  def solar_aware_deactivation_soc(current_soc)
    forecast = @solar_forecast.estimate_watt_hours
    return DEFAULT_GENSET_DEACTIVATION_SOC unless forecast&.any?

    now = Time.now
    tomorrow = now.to_date + 1
    prev_time = now
    cumulative_kwh = 0.0
    worst_deficit_kwh = 0.0
    best_surplus_kwh = 0.0

    forecast.each do |time_str, wh|
      period_time = Time.parse(time_str)
      next if period_time < now
      break if period_time.to_date > tomorrow

      hours = (period_time - prev_time) / 3600.0
      mid_hour = (prev_time + (period_time - prev_time) / 2).hour
      load_kw = expected_load_kw(mid_hour)
      cumulative_kwh += wh / 1000.0 - (hours * load_kw)
      worst_deficit_kwh = cumulative_kwh if cumulative_kwh < worst_deficit_kwh
      best_surplus_kwh = cumulative_kwh if cumulative_kwh > best_surplus_kwh
      prev_time = period_time
    end

    return DEFAULT_GENSET_DEACTIVATION_SOC if prev_time == now

    # Account for energy already in the battery above the activation threshold.
    # Only the gap beyond that buffer needs to come from the genset.
    current_buffer_kwh = ((current_soc - DEFAULT_GENSET_ACTIVATION_SOC) / 100.0) * BATTERY_CAPACITY_KWH
    net_deficit = worst_deficit_kwh + current_buffer_kwh
    worst_deficit_soc = net_deficit < 0 ? (-net_deficit / BATTERY_CAPACITY_KWH) * 100 : 0
    deficit_target = DEFAULT_GENSET_ACTIVATION_SOC + worst_deficit_soc

    # Keep running until forecasted solar surplus can push the battery to 90% SoC.
    surplus_soc = (best_surplus_kwh / BATTERY_CAPACITY_KWH) * 100
    solar_charge_target = 90 - surplus_soc

    target_soc = [deficit_target, solar_charge_target].max.ceil
    target_soc = target_soc.clamp(30, DEFAULT_GENSET_DEACTIVATION_SOC)

    @solar_deactivation_detail = "soc=#{current_soc}% load=#{expected_load_kw(now.hour).round(1)}kW worst_deficit=#{(-worst_deficit_kwh).round(1)}kWh best_surplus=#{best_surplus_kwh.round(1)}kWh"

    target_soc
  rescue => e
    puts "[WARN] Solar forecast unavailable: #{e.message}"
    DEFAULT_GENSET_DEACTIVATION_SOC
  end

  def average_load_kw
    return 3.0 if @phase_current_history.empty?

    total_amps = @phase_current_history.sum { |phases| phases.sum } / @phase_current_history.size.to_f
    total_amps * 230 / 1000.0
  end

  def expected_load_kw(hour)
    @hourly_load_kwh[hour] || HOURLY_LOAD_FALLBACK_KW[hour]
  end

  def hourly_load_kwh
    @hourly_load_kwh
  end

  # Reads the all-time consumed energy counter from Next3 once per hour and
  # updates a per-hour-of-day EMA so solar_aware_deactivation_soc can use
  # realistic load estimates instead of the instantaneous current snapshot.
  def update_hourly_load_profile
    return if Time.monotonic - @last_hourly_load_update < 3600

    current_wh = @devices.next3.acload.total_consumed_energy_all_phases
    now = Time.now

    if @last_total_energy_wh && @last_hourly_kwh_at
      elapsed_h = (now - @last_hourly_kwh_at) / 3600.0
      if elapsed_h.between?(0.5, 2.0)
        kwh_per_hour = ((current_wh - @last_total_energy_wh) / 1000.0) / elapsed_h
        hour = @last_hourly_kwh_at.hour
        prev = @hourly_load_kwh[hour]
        @hourly_load_kwh[hour] = prev ? prev * 0.85 + kwh_per_hour * 0.15 : kwh_per_hour
        puts "Updated load profile hour #{hour}: #{kwh_per_hour.round(2)} kWh/h (EMA: #{@hourly_load_kwh[hour].round(2)})"
      end
    end

    @last_total_energy_wh = current_wh
    @last_hourly_kwh_at = now
    @last_hourly_load_update = Time.monotonic
  rescue => e
    puts "[WARN] Failed to update hourly load profile: #{e.message}"
  end

  def push_solar_forecast
    return if Time.monotonic - @last_forecast_push < 3600
    forecast = @solar_forecast.estimate_watt_hours
    return unless forecast&.any?
    lines = forecast.first(24).each_with_index.map do |(_, wh), i|
      "solar_forecast_wh{horizon_hours=\"#{i + 1}\"} #{wh}"
    end.join("\n")
    VictoriaMetrics.push(lines)
    @last_forecast_push = Time.monotonic
    puts "Pushed solar forecast to VictoriaMetrics (#{forecast.size} hours)"
  rescue => e
    puts "[WARN] Failed to push solar forecast: #{e.message}"
  end

  def weco_module_soc_diff
    @devices.weco.values.map do |pack|
      socs = pack.modules.map { |m| m[:soc_value] }
      socs.max - socs.min
    end.max
  end
end
