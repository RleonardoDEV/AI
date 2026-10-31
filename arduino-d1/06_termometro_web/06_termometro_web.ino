/*
  Proyecto 6 — Termómetro WiFi (sensor DHT11 o DHT22)
  ---------------------------------------------------
  Material:
    - Sensor DHT11 (azul) o DHT22 (blanco)
    - Si el sensor viene suelto (4 patas): resistencia de 10 kΩ entre DATA y 3V3
      (los módulos de 3 patas ya la traen)

  Conexiones:
    DHT  VCC  -> 3V3
    DHT  DATA -> D2
    DHT  GND  -> GND

  Librería necesaria (Programa > Incluir librería > Administrar bibliotecas):
    "DHT sensor library" de Adafruit (acepta instalar también "Adafruit Unified Sensor")

  Uso: igual que el proyecto 2 — conéctate a la red "D1-Termometro"
  (clave 12345678) y abre http://192.168.4.1
  La página se actualiza sola cada 5 segundos.
*/

#include <ESP8266WiFi.h>
#include <ESP8266WebServer.h>
#include <DHT.h>

#define PIN_DHT  D2
#define TIPO_DHT DHT11       // cambia a DHT22 si usas ese sensor

const char* NOMBRE_RED = "D1-Termometro";
const char* CLAVE_RED  = "12345678";

DHT dht(PIN_DHT, TIPO_DHT);
ESP8266WebServer servidor(80);

float temperatura = NAN, humedad = NAN;
unsigned long ultimaLectura = 0;

void leerSensor() {
  float t = dht.readTemperature();
  float h = dht.readHumidity();
  if (!isnan(t) && !isnan(h)) {
    temperatura = t;
    humedad = h;
    Serial.printf("Temp: %.1f °C  Humedad: %.0f %%\n", t, h);
  } else {
    Serial.println("Error leyendo el sensor (revisa los cables)");
  }
}

void paginaPrincipal() {
  String t = isnan(temperatura) ? String("--") : String(temperatura, 1);
  String h = isnan(humedad) ? String("--") : String(humedad, 0);
  String html =
    "<!DOCTYPE html><html><head><meta charset='utf-8'>"
    "<meta name='viewport' content='width=device-width,initial-scale=1'>"
    "<meta http-equiv='refresh' content='5'>"
    "<title>Termómetro D1</title><style>"
    "body{font-family:sans-serif;text-align:center;background:#0d1b2a;color:#fff;padding:20px}"
    ".c{background:#1b263b;border-radius:16px;padding:20px;margin:16px auto;max-width:300px}"
    ".v{font-size:56px;font-weight:bold}"
    "</style></head><body><h1>🌡️ Mi termómetro</h1>"
    "<div class='c'>Temperatura<div class='v'>" + t + " °C</div></div>"
    "<div class='c'>Humedad<div class='v'>" + h + " %</div></div>"
    "</body></html>";
  servidor.send(200, "text/html", html);
}

void datosJson() {
  String json = "{\"temperatura\":" + (isnan(temperatura) ? String("null") : String(temperatura, 1)) +
                ",\"humedad\":" + (isnan(humedad) ? String("null") : String(humedad, 0)) + "}";
  servidor.send(200, "application/json", json);
}

void setup() {
  Serial.begin(115200);
  dht.begin();

  WiFi.mode(WIFI_AP);
  WiFi.softAP(NOMBRE_RED, CLAVE_RED);
  Serial.print("\nRed creada. Abre http://");
  Serial.println(WiFi.softAPIP());

  servidor.on("/", paginaPrincipal);
  servidor.on("/datos", datosJson);   // para usarlo desde otros programas
  servidor.begin();
}

void loop() {
  servidor.handleClient();
  if (millis() - ultimaLectura > 2000) {   // el DHT no admite leer más rápido
    ultimaLectura = millis();
    leerSensor();
  }
}
