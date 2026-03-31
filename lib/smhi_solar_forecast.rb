require "net/http"
require "json"
require "time"
require "uri"

class SmhiSolarForecast
  SMHI_URL = "https://opendata-download-metfcst.smhi.se/api/category/snow1g/version/1/geotype/point/lon/12.9513/lat/63.2509/data.json"

  LAT_DEG       = 63.2509
  LON_DEG       = 12.9513
  TILT_DEG      = 67.0
  INSTALLED_KWP = 15.84   # 36 × 440 W

  SOLAR_CONSTANT    = 1367.0
  BIFACIALITY       = 0.80
  TEMP_COEFF        = -0.003   # -0.30 %/°C (Denim U N3 440 BTG spec)
  # NOCT = 43±2°C (Denim U N3 440 BTG spec, measured at 800 W/m², 20°C ambient, 1 m/s wind)
  NOCT_DELTA        = 23.0     # T_cell_NOCT − T_ambient_NOCT = 43 − 20

  ALTITUDE_M            = 780.0
  # Pressure ratio relative to sea level (barometric formula); reduces effective air mass
  PRESSURE_RATIO        = Math.exp(-ALTITUDE_M / 8500.0)  # ≈ 0.912

  LAT_RAD               = LAT_DEG * Math::PI / 180.0
  LAT_MINUS_TILT_RAD    = (LAT_DEG - TILT_DEG) * Math::PI / 180.0
  TILT_RAD              = TILT_DEG * Math::PI / 180.0
  REAR_VIEW_GROUND      = (1.0 - Math.cos(TILT_RAD)) / 2.0  # ≈ 0.305
  SKY_VIEW_FRONT        = (1.0 + Math.cos(TILT_RAD)) / 2.0  # ≈ 0.695

  def actual=(_kwh)
    # no-op: SMHI forecast has no feedback mechanism
  end

  def estimate_watt_hours
    data = fetch_smhi_data
    now    = Time.now.utc
    cutoff = now + 48 * 3600

    result = {}
    data["timeSeries"].each do |entry|
      valid_time = Time.parse(entry["time"])
      next if valid_time <= now
      break if valid_time > cutoff

      wh = compute_watt_hours(valid_time, entry["data"])
      result[valid_time.iso8601] = wh.round
    end

    result
  end

  private

  def fetch_smhi_data
    uri = URI.parse(SMHI_URL)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 3
    http.read_timeout = 3
    response = http.get(uri.request_uri)
    raise "SMHI API error: #{response.code} #{response.message}" unless Net::HTTPOK === response
    JSON.parse(response.body)
  end

  def compute_watt_hours(valid_time, params)
    lcc       = params["low_type_cloud_area_fraction"]    || 0.0
    mcc       = params["medium_type_cloud_area_fraction"] || 0.0
    hcc       = params["high_type_cloud_area_fraction"]   || 0.0
    t_ambient = params["air_temperature"]                 || 10.0
    wind_ms   = params["wind_speed"]                      || 1.0
    vis_km    = params["visibility_in_air"]               || 50.0

    # Solar geometry at midpoint of the hour (SMHI validTime is period end)
    mid_time = valid_time - 1800
    sin_elev, cos_aoi = solar_geometry(mid_time)

    return 0 if sin_elev <= 0.0

    # Kasten-Young air mass: stable at low sun angles (important at 63°N),
    # scaled by pressure ratio to account for 780m altitude (thinner atmosphere)
    elevation_deg = Math.asin(sin_elev) * 180.0 / Math::PI

    air_mass = 1.0 / (sin_elev + 0.50572 * (6.07995 + elevation_deg) ** (-1.6364)) * PRESSURE_RATIO

    # Orbital correction: Earth–Sun distance varies ±3.3% over the year
    doy = mid_time.yday
    orbital_correction = 1.0 + 0.033 * Math.cos(2.0 * Math::PI * doy / 365.0)
    adjusted_solar_constant = SOLAR_CONSTANT * orbital_correction

    atm = 0.7 ** air_mass

    # Fog/haze attenuation via Koschmieder's law: T = exp(-3.912 / vis_km)
    # Only applied when skies are mostly clear — low visibility under heavy cloud cover
    # is the cloud itself, not additional aerosol, so suppress to avoid double-counting.
    cloud_cover_fraction = [lcc, mcc, hcc].max / 8.0
    visibility_factor = if cloud_cover_fraction < 0.5
      Math.exp(-3.912 / [vis_km, 0.1].max)
    else
      1.0
    end

    clearsky_beam_front = adjusted_solar_constant * atm * visibility_factor * [cos_aoi, 0.0].max
    clearsky_ghi        = adjusted_solar_constant * atm * visibility_factor * sin_elev

    # Beam cloud transmission.
    # lcc coefficient reduced to 0.55 (from 0.85): at 780m altitude, lcc=8 often means
    # thin cloud layer rather than thick lowland stratus — less beam attenuation in practice.
    cloud_factor = (1.0 - 0.15 * hcc / 8.0) *
                   (1.0 - 0.50 * mcc / 8.0) *
                   (1.0 - 0.55 * lcc / 8.0)

    i_front = clearsky_beam_front * cloud_factor

    # Diffuse sky irradiance (Skartveit-Olseth inspired):
    # Clear sky has ~15% diffuse. As beam is blocked by clouds it forward-scatters into
    # diffuse — thin overcast at 780m altitude can produce nearly clear-sky total irradiance
    # via this "cloud enhancement" effect. Coefficient 0.40 calibrated to observed behaviour.
    # Floor: even the thickest overcast transmits at least 5% of the extraterrestrial GHI.
    diffuse_ghi = [
      clearsky_ghi * (0.15 + 0.40 * (1.0 - cloud_factor)),
      adjusted_solar_constant * 0.05 * sin_elev
    ].max
    i_diffuse = diffuse_ghi * SKY_VIEW_FRONT

    # Bifacial rear: ground-reflected light, albedo depends on snow season
    month  = valid_time.month
    albedo = ([11, 12].include?(month) || month <= 4) ? 0.70 : 0.20
    i_rear = clearsky_ghi * cloud_factor * albedo * REAR_VIEW_GROUND

    effective = i_front + i_diffuse + BIFACIALITY * i_rear

    # Cell temperature: NOCT measured at 1 m/s wind; higher wind cools the cell.
    # Wind correction factor: 9.5 / (5.7 + 3.8 × ws) = 1.0 at ws=1 m/s (NOCT reference)
    wind_correction = 9.5 / (5.7 + 3.8 * wind_ms)
    t_cell = t_ambient + NOCT_DELTA * ((i_front + i_diffuse) / 800.0) * wind_correction
    f_temp = 1.0 + TEMP_COEFF * (t_cell - 25.0)

    [INSTALLED_KWP * effective * f_temp, 0.0].max
  end

  def solar_geometry(utc_time)
    doy = utc_time.yday.to_f
    b   = (360.0 / 365.0) * (doy - 81.0) * Math::PI / 180.0

    declination = 23.45 * Math.sin(b) * Math::PI / 180.0

    # Equation of time (minutes)
    eot = 9.87 * Math.sin(2.0 * b) - 7.53 * Math.cos(b) - 1.5 * Math.sin(b)

    solar_minutes = utc_time.hour * 60.0 + utc_time.min + utc_time.sec / 60.0 + LON_DEG * 4.0 + eot
    hour_angle    = (solar_minutes / 60.0 - 12.0) * 15.0 * Math::PI / 180.0

    # sin(elevation) for atmospheric path length and GHI
    sin_elev = Math.sin(LAT_RAD) * Math.sin(declination) +
               Math.cos(LAT_RAD) * Math.cos(declination) * Math.cos(hour_angle)

    # cos(AOI) for south-facing tilted panel: uses (lat − tilt) shortcut
    cos_aoi = Math.sin(LAT_MINUS_TILT_RAD) * Math.sin(declination) +
              Math.cos(LAT_MINUS_TILT_RAD) * Math.cos(declination) * Math.cos(hour_angle)

    [sin_elev, cos_aoi]
  end
end
