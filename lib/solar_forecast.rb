require "net/http"
require "json"
require "time"

class SolarForecast
  def initialize(token = ENV.fetch("FORECAST_SOLAR_API_TOKEN"))
    @token = token
  end

  def actual=(kwh)
    uri = URI.parse("https://api.forecast.solar/#{@token}/estimate/63.2512/12.9495/67/0/16")
    uri.query = URI.encode_www_form({
      limit: 0,
      actual: kwh,
    })
    Net::HTTP.get_response(uri) do |resp|
      raise "HTTP response not OK: #{resp.inspect}" unless Net::HTTPSuccess === resp
      #return JSON.parse(resp.body).dig("message", "info", "planes_factors", 0)
    end
  end

  def estimate_watt_hours
    uri = URI.parse("https://api.forecast.solar/#{@token}/estimate/watt_hours_period/63.2512/12.9495/67/0/16")
    uri.query = URI.encode_www_form({
      time: "iso8601",
      limit: 2,
    })
    Net::HTTP.get_response(uri) do |resp|
      raise "HTTP response not 200 OK: #{resp.inspect}" unless Net::HTTPOK === resp
      return JSON.parse(resp.body).dig("result")
    end
  end
end
