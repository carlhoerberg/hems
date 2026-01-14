require_relative "./devices/next3"
require_relative "./devices/sdmo"
require_relative "./devices/eta"
require_relative "./devices/starlink"
require_relative "./devices/shelly"
require_relative "./devices/relays"
require_relative "./devices/ups"
require_relative "./devices/unifi"
require_relative "./devices/topas"
require_relative "./devices/weco"
require_relative "./devices/ecowitt"
require_relative "./devices/envistar"
require_relative "./devices/casa"
require_relative "./devices/grundfos"
require_relative "./devices/lk"
require_relative "./devices/gencomm"

class Devices
  attr_reader :next3, :sdmo, :eta, :starlink, :shelly, :relays, :ups, :unifi, :topas, :weco, :ecowitt, :envistar, :casa, :grundfos, :lk, :gencomm

  def initialize
    @next3 = Next3.new
    @sdmo = SDMO.new
    @eta = ETA.new
    @starlink = Starlink.new
    @shelly = Shelly.new
    @relays = Relays.new
    @ups = UPS.new
    @unifi = Unifi.new
    @topas = Topas.new
    @weco = Weco.new
    @ecowitt = Ecowitt.new
    @envistar = Envistar.new
    @casa = Casa.new
    @grundfos = Grundfos.new
    @lk = {
      "hallen" => LK.new("lksystemsgw-2E3511D75D54D1D4",
        zone_names: {
          1 => "Entréhall",
          2 => "WC",
          3 => "Köket",
          4 => "Altan ingång",
        },
        actuator_names: {
          1 => "WC",
          2 => "Kök",
          3 => "Kök",
          4 => "Entré hall",
          5 => "Altan ingång",
        }),
      "kontoret" => LK.new("lksystemsgw-2218C1D75D54CC7E",
        zone_names: {
          1 => "Disken",
          2 => "Personalrum",
          3 => "Personalentré",
          4 => "Kontoret",
          5 => "Personalbadrum",
          6 => "Bastun",
        },
        actuator_names: {
          1 => "Kontoret",
          2 => "Personalentré",
          3 => "Personalrum",
          4 => "Personalbadrum",
          5 => "Bastu",
          6 => "Bastu",
          7 => "Disken",
        }),
    }
    @gencomm = GenComm.new("192.168.0.4", unit: 10)
  end
end
