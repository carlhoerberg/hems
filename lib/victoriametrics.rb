require "net/http"
require "uri"

module VictoriaMetrics
  PUSH_URL = URI("http://localhost:8429/api/v1/import/prometheus")

  def self.push(lines)
    http = Net::HTTP.new(PUSH_URL.host, PUSH_URL.port)
    http.open_timeout = 3
    http.read_timeout = 3
    http.post(PUSH_URL.path, lines, "Content-Type" => "text/plain")
  end
end
