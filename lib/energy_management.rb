require_relative "./devices"
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

  # 2kW single-phase Shelly heaters (9A each)
  SHELLY_HEATER_2KW = [
    { host: "192.168.0.190", phase: 2, amps: 9 },  # Phase 2
    { host: "192.168.0.137", phase: 3, amps: 9 },  # Phase 3
  ].freeze

  INVERTER_CURRENT_LIMIT = 22
  GENSET_CURRENT_LIMIT = 50

  BATTERY_KWH = 31.2

  def initialize(devices)
    @devices = devices
    @stopped = false
    @shelly_demands = {}  # { device_id => { amps:, active: false } }
    @shelly_demands_mutex = Mutex.new
    @phase_current_history = []
    @genset_heaters_on = false
  end

  def start
    until @stopped
      begin
        duration = Time.measure do
          update_phase_current_history
          manage_shelly_demands
          manage_genset_heaters
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

  def genset_running?
    @devices.gencomm.is_running?
  rescue => e
    puts "[ERROR] genset_running? check failed: #{e.message}"
    false
  end

  # Aux1 operating mode: 0 = Manual Off, 1 = Manual On, 2 = Auto
  def aux1_operating_mode
    @devices.next3.aux1.operating_mode
  end

  def genset_auto_started?
    aux1_operating_mode == 2
  end

  # Manually start genset by setting aux1 to Manual On
  def start_genset
    puts "Starting genset (aux1 manual on)"
    @devices.next3.aux1.operating_mode = 1
  end

  # Stop genset by returning aux1 to Auto mode
  def stop_genset
    puts "Stopping genset (aux1 back to auto)"
    @devices.next3.aux1.operating_mode = 2
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

  def update_phase_current_history
    @phase_current_history << phase_current
    @phase_current_history.shift if @phase_current_history.size > 60
  end

  # Check if any phase is currently overloaded
  def phase_overloaded?
    capacity = per_phase_capacity
    phase_current.any? { |c| c >= capacity }
  end

  # Check if adding amps would overload any phase
  def phase_allows?(amps)
    capacity = per_phase_capacity
    phase_current.max + amps < capacity
  end

  # Returns true if the current on any phase has been over the limit for 25s in a row,
  # during the last 5 minutes
  def high_phase_current?
    not phase_current_capacity?(0)
  end

  # Can the requested current be added without overload? Look at the current draw
  # for the past 5 minutes
  def phase_current_capacity?(requested_current)
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

  # Shelly demand management
  def register_shelly_demand(host, amps)
    @shelly_demands_mutex.synchronize do
      @shelly_demands[host] = { amps:, active: false }

      if phase_overloaded?
        turn_off_shelly(host)
        return { activated: false, reason: "overloaded" }
      end

      if phase_allows?(amps)
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
      @shelly_demands.delete(host)
      turn_off_shelly(host)
    end
  end

  def shelly_demands_status
    @shelly_demands_mutex.synchronize { @shelly_demands.dup }
  end

  def manage_shelly_demands
    @shelly_demands_mutex.synchronize do
      @shelly_demands.each do |host, demand|
        if demand[:active]
          if phase_overloaded?
            puts "Phase overloaded, turning off Shelly #{host}"
            turn_off_shelly(host)
            demand[:active] = false
          end
        else
          if phase_allows?(demand[:amps])
            puts "Capacity available, turning on Shelly #{host} (#{demand[:amps]}A)"
            turn_on_shelly(host)
            demand[:active] = true
          end
        end
      end
    end
  end

  def manage_genset_heaters
    if genset_running?
      unless @genset_heaters_on
        puts "Genset running, turning on 2kW heaters"
        SHELLY_HEATER_2KW.each { |heater| turn_on_2kw_heater(heater) }
        @genset_heaters_on = true
      end
    else
      if @genset_heaters_on
        puts "Genset stopped, turning off 2kW heaters"
        turn_off_2kw_heaters
        @genset_heaters_on = false
      end
    end
  end

  def turn_off_heaters
    puts "Turning off heaters"
    @devices.relays.heater_6kw = false
    @devices.relays.heater_9kw = false
    turn_off_2kw_heaters
  end

  def turn_on_2kw_heater(heater)
    puts "Turning on 2kW heater #{heater[:host]} (phase #{heater[:phase]})"
    turn_on_shelly(heater[:host])
  end

  def turn_off_2kw_heater(heater)
    puts "Turning off 2kW heater #{heater[:host]} (phase #{heater[:phase]})"
    turn_off_shelly(heater[:host])
  end

  def turn_off_2kw_heaters
    SHELLY_HEATER_2KW.each { |heater| turn_off_2kw_heater(heater) }
  end

  def any_2kw_heater_on?
    SHELLY_HEATER_2KW.any? { |heater| heater_2kw_on?(heater) }
  end

  def heater_2kw_on?(heater)
    response = shelly_rpc(heater[:host], "Switch.GetStatus", { id: 0 })
    JSON.parse(response.body)["result"]["output"]
  rescue => e
    puts "[ERROR] Failed to get 2kW heater status #{heater[:host]}: #{e.message}"
    false
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
    end

    if current_deactivation != target_deactivation
      puts "Adjusting genset deactivation threshold: #{current_deactivation}% -> #{target_deactivation}%"
      @devices.next3.aux1.soc_deactivation_threshold = target_deactivation
    end
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
