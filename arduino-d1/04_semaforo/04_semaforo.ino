/*
  Proyecto 4 — Semáforo con botón para peatones
  ---------------------------------------------
  Material:
    - 3 LEDs (rojo, amarillo, verde)
    - 3 resistencias de 220 Ω
    - 1 pulsador
    - protoboard y cables

  Conexiones:
    D5 -> resistencia -> LED verde    -> GND
    D6 -> resistencia -> LED amarillo -> GND
    D7 -> resistencia -> LED rojo     -> GND
    D2 -> pulsador -> GND   (usa la resistencia interna, no hace falta otra)

  Funcionamiento: el semáforo está en verde para los coches. Al pulsar el
  botón pasa a amarillo, luego a rojo (cruzan los peatones) y vuelve a verde.
*/

const int VERDE    = D5;
const int AMARILLO = D6;
const int ROJO     = D7;
const int BOTON    = D2;

void luz(bool v, bool a, bool r) {
  digitalWrite(VERDE, v);
  digitalWrite(AMARILLO, a);
  digitalWrite(ROJO, r);
}

void setup() {
  Serial.begin(115200);
  pinMode(VERDE, OUTPUT);
  pinMode(AMARILLO, OUTPUT);
  pinMode(ROJO, OUTPUT);
  pinMode(BOTON, INPUT_PULLUP);   // sin pulsar = HIGH, pulsado = LOW
  luz(HIGH, LOW, LOW);
  Serial.println("\nSemáforo listo. Pulsa el botón para cruzar.");
}

void loop() {
  if (digitalRead(BOTON) == LOW) {
    Serial.println("Peatón esperando...");
    delay(1000);

    luz(LOW, HIGH, LOW);          // amarillo
    delay(2000);

    luz(LOW, LOW, HIGH);          // rojo: cruzan los peatones
    Serial.println("¡Puedes cruzar!");
    delay(5000);

    for (int i = 0; i < 4; i++) { // aviso: el amarillo parpadea
      luz(LOW, HIGH, HIGH); delay(300);
      luz(LOW, LOW, HIGH);  delay(300);
    }

    luz(HIGH, LOW, LOW);          // verde otra vez
    Serial.println("Verde para los coches.");
    delay(3000);                  // tiempo mínimo en verde
  }
}
