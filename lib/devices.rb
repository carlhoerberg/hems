require_relative "./devices/next3"
require_relative "./devices/genset"
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

class Devices
  attr_reader :next3, :genset, :eta, :starlink, :shelly, :relays, :ups, :unifi, :topas, :weco, :ecowitt, :envistar, :casa, :grundfos, :lk

  def initialize
    @next3 = Next3.new
    @genset = Genset.new
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
      "hallen" => LK.new("lksystemsgw-2E3511D75D54D1D4", zone_names: {
        1 => "Entréhall",
        2 => "WC",
        3 => "Köket",
        4 => "Altan ingång",
      }),
      "kontoret" => LK.new("lksystemsgw-2218C1D75D54CC7E", zone_names: {
        1 => "Disken",
        2 => "Personalrum",
        3 => "Personalrum",
        4 => "Kontoret",
        5 => "Personalbadrum",
        6 => "Bastun",
      }),
    }
  end
end
