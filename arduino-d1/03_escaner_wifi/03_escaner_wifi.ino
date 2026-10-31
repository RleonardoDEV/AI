/*
  Proyecto 3 — Escáner de redes WiFi
  ----------------------------------
  Material: solo la placa D1.

  Cada 10 segundos busca las redes WiFi cercanas y las muestra en el
  Monitor Serie (115200 baudios) con su señal en barras.
  El LED parpadea una vez por cada red encontrada.
*/

#include <ESP8266WiFi.h>

const int LED = LED_BUILTIN;   // activo en LOW

String barras(int rssi) {
  if (rssi > -55) return "[####]";
  if (rssi > -65) return "[### ]";
  if (rssi > -75) return "[##  ]";
  if (rssi > -85) return "[#   ]";
  return "[    ]";
}

void setup() {
  Serial.begin(115200);
  pinMode(LED, OUTPUT);
  digitalWrite(LED, HIGH);
  WiFi.mode(WIFI_STA);
  WiFi.disconnect();
  delay(100);
}

void loop() {
  Serial.println("\nBuscando redes...");
  int total = WiFi.scanNetworks();

  if (total == 0) {
    Serial.println("No se encontró ninguna red.");
  } else {
    Serial.printf("Encontradas %d redes:\n", total);
    for (int i = 0; i < total; i++) {
      Serial.printf("%2d. %s %4d dBm  canal %2d  %s  %s\n",
                    i + 1,
                    barras(WiFi.RSSI(i)).c_str(),
                    WiFi.RSSI(i),
                    WiFi.channel(i),
                    WiFi.encryptionType(i) == ENC_TYPE_NONE ? "ABIERTA " : "con clave",
                    WiFi.SSID(i).c_str());
      digitalWrite(LED, LOW);  delay(80);
      digitalWrite(LED, HIGH); delay(120);
    }
  }
  WiFi.scanDelete();
  delay(10000);
}
