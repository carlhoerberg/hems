require_relative "./devices/next3"
require_relative "./devices/genset"
require_relative "./devices/eta"
require_relative "./devices/starlink"
require_relative "./devices/shelly"
require_relative "./devices/relays"
require_relative "./devices/ups"
require_relative "./devices/unifi"
require_relative "./devices/topas"

class Devices
  attr_reader :next3, :genset, :eta, :starlink, :shelly, :relays, :ups, :unifi, :topas

  def initialize
    @next3 = Next3.new
    @genset = Genset.new
    @eta = ETA.new("192.168.0.12")
    @starlink = Starlink.new
    @shelly = Shelly.new
    @relays = Relays.new
    @ups = UPS.new
    @unifi = Unifi.new
    @topas = Topas.new
  end
end
