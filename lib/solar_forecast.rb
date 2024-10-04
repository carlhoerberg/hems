require "net/http"
require "json"
require "time"

class SolarForecast
  def initialize(token = ENV.fetch("FORECAST_SOLAR_API_TOKEN"))
    @token = token
  end

  def timewindow(baseload)
    uri = URI.parse("https://api.forecast.solar/#{@token}/timewindow/63.2511/12.9506/67/0/16")
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
    uri = URI.parse("https://api.forecast.solar/#{@token}/estimate/63.2511/12.9506/67/0/16")
    uri.query = URI.encode_www_form({
      time: "iso8601",
      inverter: 16,
    })
    Net::HTTP.get_response(uri) do |resp|
      raise "HTTP response not 200 OK: #{resp.inspect}" unless Net::HTTPOK === resp
      return Estimate.new JSON.parse(resp.body)
    end
  end

  def actual=(kwh)
    uri = URI.parse("https://api.forecast.solar/#{@token}/estimate/63.2511/12.9506/67/0/16")
    uri.query = URI.encode_www_form({
      limit: 0,
      actual: kwh,
    })
    Net::HTTP.get_response(uri) do |resp|
      raise "HTTP response not OK: #{resp.inspect}" unless Net::HTTPSuccess === resp
      #return JSON.parse(resp.body).dig("message", "info", "planes_factors", 0)
    end
  end

  # Estimated produced kWh in the next `hours`
  def kwh_next_hours(hours)
    uri = URI.parse("https://api.forecast.solar/#{@token}/estimate/watthours/period/63.2511/12.9506/67/0/16")
    uri.query = URI.encode_www_form({
      time: "iso8601",
      inverter: 16,
      limit: 2
    })
    Net::HTTP.get_response(uri) do |resp|
      raise "HTTP response not 200 OK: #{resp.inspect}" unless Net::HTTPOK === resp
      now = Time.now
      period_end = now + hours * 3600
      period_wh = 0
      JSON.parse(resp.body).dig("result").each do |period, wh|
        next if Time.parse(period) <= now
        break if Time.parse(period) > period_end
        period_wh += wh
      end
      return period_wh / 1000.0 # convert to kWh
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
