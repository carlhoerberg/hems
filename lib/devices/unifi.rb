require "net/http"
require "json"

class Devices
  class Unifi
    def initialize(host = "192.168.0.1", port = 443)
      @http = Net::HTTP.new(host, port).tap do |h|
        h.use_ssl = true
        h.open_timeout = 3
        h.read_timeout = 2
        h.verify_mode = OpenSSL::SSL::VERIFY_NONE
      end
      @lock = Mutex.new
      @cookie = get_cookie
    end

    def health
      get("/proxy/network/api/s/default/stat/health").group_by { |e| e["subsystem"] }
    end

    private

    def get(path)
      @lock.synchronize do
        loop do
          @http.start unless @http.started?
          headers = { "Cookie" => @cookie }
          res = @http.get(path, headers)
          case res
          when Net::HTTPOK
            return JSON.parse(res.body).fetch("data")
          when Net::HTTPUnauthorized
            @cookie = get_cookie
          else
            raise "HTTP response not 200 OK: #{res.inspect}"
          end
        end
      end
    end

    def get_cookie
      body = %({"username": "#{ENV["UNIFI_USER"]}", "password": "#{ENV["UNIFI_PASSWORD"]}"})
      headers = { "Content-Type" => "application/json" }
      res = @http.post("/api/auth/login", body, headers)
      if (c = res.response['set-cookie'])
        c.split('; ').first
      end
    end
  end
end
