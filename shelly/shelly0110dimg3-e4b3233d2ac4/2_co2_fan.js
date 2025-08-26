// Shelly Script: Adjust light brightness based on CO₂ levels from "number:201"
// Light brightness: 0% at 440 ppm, 100% at 1440 ppm

const minCO2 = 440;
const maxCO2 = 1440;
const lightId = 0; // Adjust this if your light is not id 0

function co2ToBrightness(co2) {
  // Clamp CO₂ between min and max
  if (co2 <= minCO2) return 0;
  if (co2 >= maxCO2) return 100;

  // Linear interpolation
  return Math.round(((co2 - minCO2) / (maxCO2 - minCO2)) * 100);
}

Shelly.addStatusHandler(function (event) {
  if (event.component === "number:201") {
    print(JSON.stringify(event))
    const co2 = event.delta.value;
      const brightness = co2ToBrightness(co2);
      Shelly.call(
        "Light.Set",
        { id: lightId, brightness: brightness, on: brightness > 0 },
        function (res, err) {
          if (err) {
            print("Error setting brightness:", JSON.stringify(err));
          } else {
            print("CO₂:", co2, "=> Brightness:", brightness);
          }
        }
      );
  }
});
