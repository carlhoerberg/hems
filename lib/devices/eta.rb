require "net/http"
require "rexml"

class Devices
  class ETA
    def initialize(host, port = 8080)
      @host = host
      @port = port
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
      get("/user/var/41/10201/0/0/12015")
    end

    def stallet_temp
      get("/user/var/124/10101/0/11060/0")
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
      element.each_element do |ch|
        get_children(ch, http)
      end
      if uri = element["uri"]
        res = http.get("/user/var#{uri}")
        if Net::HTTPOK === res
          xml = REXML::Document.new(res.body, ignore_whitespace_nodes: :all)
          element.add_element xml.root.children[0]
        end
      end
    end
  end
end
