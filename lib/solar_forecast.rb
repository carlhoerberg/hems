require "net/http"
require "json"
require "time"

class SolarForecast
  def initialize(token = ENV.fetch("FORECAST_SOLAR_API_TOKEN"))
    @token = token
  end

  def timewindow(baseload)
    uri = URI.parse("https://api.forecast.solar/#{@token}/timewindow/63.2511/12.9506/67/0/24")
    uri.query = URI.encode_www_form({
      time: "iso8601",
      inverter: 16,
      baseload: baseload
    })
    Net::HTTP.get_response(@uri) do |resp|
      raise "HTTP response not 200 OK: #{resp.inspect}" unless Net::HTTPOK === resp
      data = JSON.parse(resp.body)
      data.dig("result", "watt_hours_day").values.first
    end
  end

  def estimate
    uri = URI.parse("https://api.forecast.solar/#{@token}/estimate/63.2511/12.9506/67/0/24")
    uri.query = URI.encode_www_form({
      time: "iso8601",
      inverter: 16,
    })
    Net::HTTP.get_response(uri) do |resp|
      raise "HTTP response not 200 OK: #{resp.inspect}" unless Net::HTTPOK === resp
      Estimate.new JSON.parse(resp.body)
    end
  end

  class Estimate
    def initialize(data)
      @data = data
    end

    def wh_today
      @data.dig("result", "watt_hours_day").values.first
    end

    def to_h
      @data
    end
  end
end
