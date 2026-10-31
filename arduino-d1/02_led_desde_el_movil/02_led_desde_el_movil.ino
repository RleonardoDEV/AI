/*
  Proyecto 2 — Controla el LED desde tu móvil (WiFi)
  --------------------------------------------------
  Material: solo la placa D1.

  La placa crea su propia red WiFi (no necesitas router):
    1. Sube el programa.
    2. En el móvil conéctate a la red "D1-Arduino" (clave: 12345678).
    3. Abre el navegador en http://192.168.4.1
    4. Pulsa los botones para encender / apagar / hacer parpadear el LED.
*/

#include <ESP8266WiFi.h>
#include <ESP8266WebServer.h>

const char* NOMBRE_RED = "D1-Arduino";
const char* CLAVE_RED  = "12345678";   // mínimo 8 caracteres

const int LED = LED_BUILTIN;           // activo en LOW
ESP8266WebServer servidor(80);

enum Modo { APAGADO, ENCENDIDO, PARPADEO };
Modo modo = APAGADO;
unsigned long ultimoCambio = 0;
bool estadoParpadeo = false;

String pagina() {
  String estado = (modo == ENCENDIDO) ? "Encendido" : (modo == PARPADEO) ? "Parpadeando" : "Apagado";
  String html =
    "<!DOCTYPE html><html><head><meta charset='utf-8'>"
    "<meta name='viewport' content='width=device-width,initial-scale=1'>"
    "<title>D1 LED</title><style>"
    "body{font-family:sans-serif;text-align:center;background:#111;color:#eee;padding:20px}"
    "a{display:block;margin:14px auto;max-width:280px;padding:18px;border-radius:12px;"
    "font-size:20px;color:#fff;text-decoration:none}"
    ".on{background:#2e7d32}.off{background:#c62828}.blink{background:#1565c0}"
    "</style></head><body><h1>💡 LED de mi D1</h1>"
    "<p>Estado: <b>" + estado + "</b></p>"
    "<a class='on' href='/on'>Encender</a>"
    "<a class='off' href='/off'>Apagar</a>"
    "<a class='blink' href='/parpadeo'>Parpadear</a>"
    "</body></html>";
  return html;
}

void responder() {
  servidor.send(200, "text/html", pagina());
}

void setup() {
  Serial.begin(115200);
  pinMode(LED, OUTPUT);
  digitalWrite(LED, HIGH);

  WiFi.mode(WIFI_AP);
  WiFi.softAP(NOMBRE_RED, CLAVE_RED);
  Serial.print("\nRed creada. Abre http://");
  Serial.println(WiFi.softAPIP());

  servidor.on("/", responder);
  servidor.on("/on", []() { modo = ENCENDIDO; digitalWrite(LED, LOW);  responder(); });
  servidor.on("/off", []() { modo = APAGADO;  digitalWrite(LED, HIGH); responder(); });
  servidor.on("/parpadeo", []() { modo = PARPADEO; responder(); });
  servidor.begin();
}

void loop() {
  servidor.handleClient();

  if (modo == PARPADEO && millis() - ultimoCambio > 300) {
    ultimoCambio = millis();
    estadoParpadeo = !estadoParpadeo;
    digitalWrite(LED, estadoParpadeo ? LOW : HIGH);
  }
}
