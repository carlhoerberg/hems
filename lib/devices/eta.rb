require "net/http"
require "rexml"

class Devices
  class ETA
    def initialize(host, port = 8080)
      @http = Net::HTTP.new(host, port)
      @lock = Mutex.new
    end

    def tank_temps
      5.times.map do |i|
        get("/user/var/123/10601/0/#{11327 + i}/0")
      end
    end

    def tank_temp(i)
      raise ArgumentError, "Tank has 5 temperature gauges" unless [1..5].include?(i)
      get("/user/var/123/10601/0/#{11326 + i}/0")
    end

    def outdoor_temp
      get("/user/var/123/10601/0/0/12197")
    end

    def boiler_temp(number)
      get("/user/var/4#{number}/10021/0/11109/0")
    end

    def boiler_return_temp(number)
      get("/user/var/4#{number}/10021/0/11160/0")
    end

    def pellets
      get("/41/10201/0/0/12015")
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
  end
end
