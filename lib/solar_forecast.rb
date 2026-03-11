require "net/http"
require "json"
require "time"

class SolarForecast
  CACHE_TTL = 900

  def initialize(token = ENV.fetch("FORECAST_SOLAR_API_TOKEN"))
    @token = token
    @watt_hours_cache = nil
    @watt_hours_fetched_at = nil
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
    if @watt_hours_cache && @watt_hours_fetched_at &&
       Time.now - @watt_hours_fetched_at < CACHE_TTL
      return @watt_hours_cache
    end

    uri = URI.parse("https://api.forecast.solar/#{@token}/estimate/watt_hours_period/63.2512/12.9495/67/0/16")
    uri.query = URI.encode_www_form({
      time: "iso8601",
      limit: 2,
    })
    Net::HTTP.get_response(uri) do |resp|
      raise "HTTP response not 200 OK: #{resp.inspect}" unless Net::HTTPOK === resp
      @watt_hours_cache = JSON.parse(resp.body).dig("result")
      @watt_hours_fetched_at = Time.now
      return @watt_hours_cache
    end
  end
end
