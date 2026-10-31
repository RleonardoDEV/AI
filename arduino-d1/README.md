# Proyectos para la placa D1 (ESP8266)

Seis mini proyectos listos para subir a una **WeMos D1** (D1 R1, D1 R2 o D1 mini).
Están ordenados de más fácil a más difícil. Los tres primeros **no necesitan nada más que la placa**.

| # | Proyecto | Qué hace | Material extra |
|---|----------|----------|----------------|
| 1 | [Parpadeo SOS](01_parpadeo_sos) | El LED integrado envía SOS en Morse | Ninguno |
| 2 | [LED desde el móvil](02_led_desde_el_movil) | La placa crea una red WiFi y una web para controlar el LED | Ninguno |
| 3 | [Escáner WiFi](03_escaner_wifi) | Lista las redes WiFi cercanas y su señal | Ninguno |
| 4 | [Semáforo](04_semaforo) | Semáforo con botón para peatones | 3 LEDs, 3 resistencias 220 Ω, 1 pulsador |
| 5 | [Juego de reflejos](05_juego_reflejos) | Mide cuánto tardas en pulsar al encenderse el LED | 1 LED, 1 resistencia 220 Ω, 1 pulsador |
| 6 | [Termómetro web](06_termometro_web) | Muestra temperatura y humedad en el móvil | Sensor DHT11 o DHT22 |

## Preparar el Arduino IDE (solo la primera vez)

1. Abre **Archivo > Preferencias** y en *Gestor de URLs adicionales de tarjetas* pega:
   ```
   https://arduino.esp8266.com/stable/package_esp8266com_index.json
   ```
2. Ve a **Herramientas > Placa > Gestor de tarjetas**, busca **esp8266** e instálalo.
3. En **Herramientas > Placa > ESP8266 Boards** elige tu modelo:
   - Placa con forma de Arduino UNO → **WeMos D1 R1** (o *LOLIN(WEMOS) D1 R2 & mini* si pone "R2")
   - Placa pequeña → **LOLIN(WEMOS) D1 R2 & mini**
4. Conecta la placa por USB y elige el puerto en **Herramientas > Puerto**.
   Si no aparece, instala el driver **CH340** (es el chip USB que lleva la D1).

## Subir un proyecto

1. Abre el archivo `.ino` de la carpeta del proyecto (la carpeta y el archivo deben llamarse igual).
2. Pulsa **Subir** (flecha →).
3. Abre **Herramientas > Monitor Serie** y pon la velocidad en **115200 baudios** para ver los mensajes.

## Cosas a tener en cuenta

- La D1 funciona a **3,3 V**: no conectes 5 V a los pines de señal.
- El LED azul integrado se enciende con `LOW` y se apaga con `HIGH` (al revés de lo habitual).
- Usa los nombres `D2`, `D5`… tal y como están impresos en la placa.
- Proyectos 2 y 6: la placa crea su propia red WiFi (clave `12345678`). Conéctate con el móvil
  y abre `http://192.168.4.1`. El móvil puede avisar de que "no hay Internet": es normal.
- Si tu placa es una **D1 R32** (con chip ESP32), estos programas no sirven tal cual:
  habría que cambiar las librerías WiFi.
