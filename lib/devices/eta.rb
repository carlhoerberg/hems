require "net/http"
require "rexml"

class Devices
  class ETA
    def initialize(host, port = 8080)
      @host = host
      @port = port
      @http = Net::HTTP.new(host, port).tap do |h|
        h.open_timeout = 1
        h.read_timeout = 1
      end
      @lock = Mutex.new
    end

    def tank_sensors
      5
    end

    def tank_temp(i)
      raise ArgumentError, "Tank has 5 temperature sensors" unless (1..5).include?(i)
      get("/user/var/123/10601/0/#{11326 + i}/0")
    end

    def tank_should_temp
      get("/user/var/123/10601/0/0/13194")
    end

    def tank_return_temp
      get("/user/var/123/10601/0/0/12520")
    end

    def tank_requested_power
      get("/user/var/123/10601/0/0/12077")
    end

    def tank_charge_status
      get("/user/var/123/10601/0/0/12528")
    end

    def tank_consumers_requested_temp
      get("/user/var/123/10601/0/0/13203")
    end

    def outdoor_temp
      get("/user/var/123/10601/0/0/12197")
    end

    def boiler_temp(number)
      get("/user/var/4#{number}/10021/0/11109/0")
    end

    def boiler_should_temp(number)
      get("/user/var/4#{number}/10021/0/0/12001")
    end

    def boiler_return_temp(number)
      get("/user/var/4#{number}/10021/0/11160/0")
    end

    def boiler_total_consumption(number)
      get("/user/var/4#{number}/10021/0/0/12016")
    end

    def boiler_pump_speed(number)
      get("/user/var/4#{number}/10021/0/11123/0")
    end

    def boiler_flue_gas_fan_rpm(number)
      get("/user/var/4#{number}/10021/0/0/12165")
    end

    def boiler_flue_gas_temp(number)
      get("/user/var/4#{number}/10021/0/11110/0")
    end

    def boiler_pressure(number)
      get("/user/var/4#{number}/10021/0/0/12180")
    end

    def boiler_air_valve(number)
      get("/user/var/4#{number}/10021/0/11115/0")
    end

    def boiler_requested_power(number)
      get("/user/var/4#{number}/10021/0/0/12077")
    end

    def boiler_requested_temp(number)
      get("/user/var/4#{number}/10021/0/0/12006")
    end

    def pellets_in_storage
      get("/user/var/41/10201/0/0/12015")
    end

    def pellets_feed_screw_current
      get("/user/var/41/10201/0/11029/2091")
    end

    def stallet_temp
      get("/user/var/124/10101/0/11125/2121")
    end

    def stallet_should_temp
      get("/user/var/124/10101/0/11125/2120")
    end

    def stallet_pump
      get("/user/var/124/10101/0/11124/0")
    end

    def vvx_primary_temp
      get("/user/var/124/10581/0/11410/0")
    end

    def vvx_primary_should_temp
      get("/user/var/124/10581/0/11410/2120")
    end

    def vvx_primary_return_temp
      get("/user/var/124/10581/0/11186/0")
    end

    def vvx_secondary_temp
      get("/user/var/124/10581/0/11140/0")
    end

    def menu
      Net::HTTP.start(@host, @port) do |http|
        res = http.get("/user/menu")
        raise "HTTP response not 200 OK: #{res.inspect}" unless Net::HTTPOK === res
        menu = REXML::Document.new(res.body, ignore_whitespace_nodes: :all)
        menu.root.children[0].each_element do |child|
          get_children(child, http)
        end
        menu.to_s
      end
    end

    private

    def get(path)
      @lock.synchronize do
        @http.start unless @http.started?
        res = @http.get(path)
        case res
        when Net::HTTPOK
          doc = REXML::Document.new(res.body, ignore_whitespace_nodes: :all)
          val = doc.root[0]
          val.text.to_f / val["scaleFactor"].to_i
        else
          raise "HTTP response not 200 OK: #{res.inspect}"
        end
      end
    end

    def get_children(element, http)
      if uri = element["uri"]
        res = http.get("/user/var#{uri}")
        if Net::HTTPOK === res
          xml = REXML::Document.new(res.body, ignore_whitespace_nodes: :all)
          element.add_element xml.root.children[0]
        end
      end
      element.each_element do |ch|
        get_children(ch, http)
      end
    end
  end
end
