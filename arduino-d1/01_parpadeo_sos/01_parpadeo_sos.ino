/*
  Proyecto 1 — Parpadeo SOS en código Morse
  -----------------------------------------
  Material: solo la placa D1. Usa el LED azul que ya trae integrado.

  Ojo: en la D1 el LED integrado funciona "al revés":
  LOW = encendido, HIGH = apagado.
*/

const int LED = LED_BUILTIN;   // GPIO2 (pin D4)
const int PUNTO = 200;         // duración de un punto en ms
const int RAYA  = PUNTO * 3;

void encender(int ms) {
  digitalWrite(LED, LOW);      // encender
  delay(ms);
  digitalWrite(LED, HIGH);     // apagar
  delay(PUNTO);                // pausa entre señales
}

void letraS() { for (int i = 0; i < 3; i++) encender(PUNTO); }
void letraO() { for (int i = 0; i < 3; i++) encender(RAYA); }

void setup() {
  pinMode(LED, OUTPUT);
  digitalWrite(LED, HIGH);
  Serial.begin(115200);
  Serial.println("\nEnviando SOS...");
}

void loop() {
  letraS();
  delay(RAYA);
  letraO();
  delay(RAYA);
  letraS();
  Serial.println("SOS enviado");
  delay(PUNTO * 7);            // pausa entre palabras
}
