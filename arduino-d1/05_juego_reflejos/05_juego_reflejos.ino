/*
  Proyecto 5 — Juego de reflejos
  ------------------------------
  Material:
    - 1 LED + resistencia de 220 Ω  (o usa el LED integrado, ver abajo)
    - 1 pulsador

  Conexiones:
    D5 -> resistencia -> LED -> GND
    D2 -> pulsador -> GND

  Cómo se juega (mira el Monitor Serie a 115200 baudios):
    1. Espera a que se encienda el LED (tarda un tiempo al azar).
    2. Pulsa el botón lo más rápido que puedas.
    3. Te dice tu tiempo en milisegundos y guarda tu récord.
    Si pulsas antes de que se encienda... ¡trampa!

  ¿Sin LED externo? Cambia LED a LED_BUILTIN y LED_ON a LOW.
*/

const int LED    = D5;
const int LED_ON = HIGH;
const int BOTON  = D2;

unsigned long record = 0;

bool pulsado() { return digitalRead(BOTON) == LOW; }

void ledEncendido(bool on) { digitalWrite(LED, on ? LED_ON : !LED_ON); }

void esperarSoltar() {
  while (pulsado()) delay(10);
  delay(50);  // anti-rebote
}

void setup() {
  Serial.begin(115200);
  pinMode(LED, OUTPUT);
  pinMode(BOTON, INPUT_PULLUP);
  ledEncendido(false);
  randomSeed(analogRead(A0) ^ micros());
  Serial.println("\n=== JUEGO DE REFLEJOS ===");
}

void loop() {
  Serial.println("\nPulsa el botón para empezar una ronda...");
  while (!pulsado()) delay(10);
  esperarSoltar();

  Serial.println("Prepárate...");
  unsigned long espera = random(1500, 5000);
  unsigned long inicio = millis();

  while (millis() - inicio < espera) {
    if (pulsado()) {
      Serial.println("¡Trampa! Pulsaste antes de tiempo.");
      for (int i = 0; i < 6; i++) { ledEncendido(i % 2 == 0); delay(100); }
      ledEncendido(false);
      esperarSoltar();
      return;
    }
    delay(1);
  }

  ledEncendido(true);
  unsigned long t0 = millis();
  while (!pulsado()) yield();
  unsigned long tiempo = millis() - t0;
  ledEncendido(false);

  Serial.printf("Tiempo: %lu ms", tiempo);
  if (record == 0 || tiempo < record) {
    record = tiempo;
    Serial.print("  ¡NUEVO RÉCORD!");
  }
  Serial.printf("\nRécord actual: %lu ms\n", record);

  if (tiempo < 200)      Serial.println("Nivel: ¡Ninja! 🥷");
  else if (tiempo < 300) Serial.println("Nivel: Muy rápido");
  else if (tiempo < 450) Serial.println("Nivel: Normal");
  else                   Serial.println("Nivel: ¿Estabas dormido? 😴");

  esperarSoltar();
}
