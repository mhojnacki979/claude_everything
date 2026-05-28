---
name: esp32
description: Expert ESP32 firmware engineering skill for Arduino and ESP-IDF frameworks. Use this skill whenever the user mentions ESP32, microcontroller, embedded, firmware, FreeRTOS, PlatformIO, Arduino IDE, WiFi/BLE/MQTT on hardware, LED matrix, HUB75, WS2812B, FastLED, serial debugging, peripheral drivers, master/slave UDP, or any hardware/embedded coding task. Also trigger for requests to build custom C++ libraries for embedded targets, structure multi-file PlatformIO projects, or architect distributed embedded systems. If the user pastes serial monitor output, pin maps, wiring diagrams, or error traces related to embedded hardware, use this skill immediately. Also triggers for: archery timer firmware, LED panel control, P10 RGB panels, ESP32-S3, PCB design questions related to ESP32, pressure monitor, weather station, foal watch firmware.
---

# ESP32 Firmware Engineering Skill

## Overview

Michael is an experienced ESP32 builder working at production complexity — multi-node distributed systems, HUB75 RGB matrix displays, addressable LED strips, FreeRTOS task architecture, UDP networking, and custom C++ library authoring. He works in both Arduino framework (via PlatformIO) and ESP-IDF, primarily on Mac Studio M4 Max.

**Default output:** Production-ready, multi-file PlatformIO project structure unless a quick sketch is explicitly requested.

---

## Michael's Active Hardware Projects

| Project | Hardware | Status |
|---|---|---|
| Archery Tournament Timer | ESP32-S3, P10 RGB outdoor panels (HUB75), master/slave UDP, web UI | Commercial product target — competing with Chronotir (~$3,599), COGS ~$225-260 |
| Weather Station | ESP32, sensors, MQTT | Built |
| Pressure Monitor | ESP32 | Active |
| Foal Watch | ESP32 (PlatformIO) | Active |
| ArcherForm AI | iOS app, not firmware — skip this skill |

---

## Workflow Routing

### Quick sketch (single file)
Trigger: "quick," "just show me," "prototype," "test this idea"
→ Single `.ino` or `main.cpp`, inline comments, minimal setup

### Full project (multi-file)
Trigger: anything production, anything with networking, anything with RTOS tasks, anything with display output
→ Full PlatformIO structure (see below), header/source split, clear task separation

### Triage / debug
Trigger: user pastes serial output, stack trace, crash log, watchdog reset, or describes erratic behavior
→ Load `references/debug-triage.md`, diagnose first, then patch

### Library authoring
Trigger: "make this reusable," "build a library," "package this up"
→ Load `references/library-authoring.md`, produce `lib/` structure

---

## Standard PlatformIO Project Structure

```
project-name/
├── platformio.ini
├── src/
│   ├── main.cpp
│   ├── config.h          # pin defs, constants, compile-time flags
│   ├── tasks/
│   │   ├── display_task.cpp / .h
│   │   ├── network_task.cpp / .h
│   │   └── sensor_task.cpp / .h
│   ├── drivers/
│   │   └── [peripheral drivers]
│   └── utils/
│       └── [helpers]
├── lib/
│   └── [custom libraries]
├── include/
│   └── [shared headers]
└── test/
    └── [unit tests]
```

---

## platformio.ini Starters

### ESP32-S3 (primary — archery timer)
```ini
[env:esp32-s3]
platform = espressif32
board = esp32-s3-devkitc-1
framework = arduino
monitor_speed = 115200
build_flags =
    -DCORE_DEBUG_LEVEL=3
    -DBOARD_HAS_PSRAM
lib_deps =
    mrfaptastic/ESP32 HUB75 LED MATRIX PANEL DMA Display
    fastled/FastLED
    bblanchon/ArduinoJson
    ayushsharma82/ElegantOTA
```

### ESP32 (general)
```ini
[env:esp32]
platform = espressif32
board = esp32dev
framework = arduino
monitor_speed = 115200
build_flags = -DCORE_DEBUG_LEVEL=3
lib_deps =
    bblanchon/ArduinoJson
    knolleary/PubSubClient
```

---

## HUB75 / P10 RGB Panel Patterns

Michael uses `ESP32-HUB75-MatrixPanel-DMA` library. Key patterns:

```cpp
#include <ESP32-HUB75-MatrixPanel-I2S-DMA.h>

// Panel config — adjust for P10 panel count/chain
#define PANEL_WIDTH  32
#define PANEL_HEIGHT 16
#define PANELS_NUMBER 4   // chained panels

HUB75_I2S_CFG mxconfig(PANEL_WIDTH, PANEL_HEIGHT, PANELS_NUMBER);
MatrixPanel_I2S_DMA *dma_display = nullptr;

void initDisplay() {
    mxconfig.gpio.e = 18;  // adjust per wiring
    mxconfig.clkphase = false;
    mxconfig.driver = HUB75_I2S_CFG::FM6126A;  // common P10 driver
    dma_display = new MatrixPanel_I2S_DMA(mxconfig);
    dma_display->begin();
    dma_display->setBrightness8(128);
    dma_display->clearScreen();
}

// Color helpers
uint16_t red   = dma_display->color565(255, 0, 0);
uint16_t green = dma_display->color565(0, 255, 0);
uint16_t white = dma_display->color565(255, 255, 255);

// Countdown timer display
void showCountdown(int seconds) {
    dma_display->clearScreen();
    dma_display->setTextSize(3);
    dma_display->setTextColor(seconds <= 10 ? red : green);
    dma_display->setCursor(4, 2);
    dma_display->printf("%02d", seconds);
}
```

**Wiring notes for P10 outdoor panels:**
- Use level shifter (3.3V → 5V) on all HUB75 signals
- Separate 5V PSU for panels (not ESP power rail)
- Keep signal wires short and twisted where possible
- `gpio.e` pin varies by panel — check datasheet

---

## UDP Master/Slave Architecture (Archery Timer)

```cpp
// master.cpp — broadcasts commands to all slaves
#include <WiFiUdp.h>
WiFiUDP udp;
#define BROADCAST_PORT 12345
#define BROADCAST_IP "192.168.4.255"  // AP broadcast

void sendCommand(const char* cmd) {
    udp.beginPacket(BROADCAST_IP, BROADCAST_PORT);
    udp.write((uint8_t*)cmd, strlen(cmd));
    udp.endPacket();
}

// slave.cpp — listens and acts
void udpListenTask(void* param) {
    udp.begin(BROADCAST_PORT);
    char packet[64];
    while (true) {
        int len = udp.parsePacket();
        if (len) {
            udp.read(packet, sizeof(packet) - 1);
            packet[len] = '\0';
            handleCommand(packet);
        }
        vTaskDelay(10 / portTICK_PERIOD_MS);
    }
}
```

**Web UI pattern:** Master runs AsyncWebServer, serves control page, slaves are display-only.

---

## FreeRTOS Task Patterns

```cpp
// Always pin tasks to a core — display on core 1, network on core 0
xTaskCreatePinnedToCore(
    displayTask,    // function
    "DisplayTask",  // name
    8192,           // stack size (bytes) — increase if stack overflow
    NULL,           // params
    2,              // priority (higher = more urgent)
    &displayHandle, // handle
    1               // core (0 or 1)
);

// Safe inter-task communication via queue
QueueHandle_t cmdQueue = xQueueCreate(10, sizeof(Command));

// Producer (network task)
Command cmd = {CMD_START_TIMER, 120};
xQueueSend(cmdQueue, &cmd, portMAX_DELAY);

// Consumer (display task)
Command received;
if (xQueueReceive(cmdQueue, &received, 0) == pdTRUE) {
    handleCommand(received);
}

// Mutex for shared state
SemaphoreHandle_t stateMutex = xSemaphoreCreateMutex();
if (xSemaphoreTake(stateMutex, pdMS_TO_TICKS(100))) {
    // access shared data
    xSemaphoreGive(stateMutex);
}
```

**Stack sizing:** Start at 4096 for simple tasks, 8192 for tasks using Serial/JSON/networking, 16384 for display tasks with fonts.

---

## WS2812B / Addressable LED Patterns (FastLED)

```cpp
#include <FastLED.h>
#define LED_PIN     5
#define NUM_LEDS    60
#define LED_TYPE    WS2812B
#define COLOR_ORDER GRB

CRGB leds[NUM_LEDS];

void setup() {
    FastLED.addLeds<LED_TYPE, LED_PIN, COLOR_ORDER>(leds, NUM_LEDS)
           .setCorrection(TypicalLEDStrip);
    FastLED.setBrightness(96);
}

// Non-blocking chase — call from task, never use delay()
void chaseTask(void* param) {
    int pos = 0;
    while (true) {
        fadeToBlackBy(leds, NUM_LEDS, 20);
        leds[pos] = CHSV(millis() / 10, 255, 255);
        FastLED.show();
        pos = (pos + 1) % NUM_LEDS;
        vTaskDelay(30 / portTICK_PERIOD_MS);
    }
}
```

---

## Networking Patterns

### WiFi AP + STA simultaneously
```cpp
WiFi.mode(WIFI_AP_STA);
WiFi.softAP("ArcheryTimer-Master", "password");
WiFi.begin(ssid, pass);  // optional uplink
```

### OTA updates (production essential)
```cpp
#include <AsyncElegantOTA.h>
AsyncElegantOTA.begin(&server);  // http://[ip]/update
```

### MQTT
```cpp
PubSubClient mqttClient(espClient);
mqttClient.setServer(MQTT_HOST, 1883);
mqttClient.subscribe("timer/command");
```

---

## Coding Standards

- **Never use `delay()`** in tasks — always `vTaskDelay(ms / portTICK_PERIOD_MS)`
- **Never use global variables across tasks without mutex**
- **Always handle WiFi reconnect** — assume connection drops
- **Use `config.h`** for all pin definitions and compile-time constants
- **Serial debug** wrapped in `#ifdef DEBUG` — never in production builds
- **ArduinoJson** for all JSON — never manual string parsing
- **`const char*` for string literals**, `String` only when concatenation is unavoidable

---

## Serial Debug Triage Quick Reference

| Symptom | First check |
|---|---|
| `Guru Meditation Error: Core panic'd` | Stack overflow or null pointer — check task stack sizes |
| `Watchdog timeout` | Blocking call in task — find `delay()` or blocking loop |
| `Brownout detector was triggered` | Power supply — panels pulling too much current |
| Display flickering | Signal integrity — level shifter, wire length, clock phase |
| UDP packets missing | Broadcast IP wrong, or slaves on different subnet |
| OTA fails | Partition scheme — switch to `min_spiffs` in platformio.ini |
| `assert failed: xQueueReceive` | Queue handle NULL — init order issue |

---

## Reference Files

- `references/hub75-panels.md` — HUB75 wiring, drivers, common P10 gotchas
- `references/addressable-leds.md` — FastLED, NeoPixel, power calc
- `references/networking.md` — UDP, MQTT, BLE, OTA patterns
- `references/freertos.md` — tasks, queues, semaphores, stack sizing
- `references/library-authoring.md` — building reusable PlatformIO libs
- `references/debug-triage.md` — crash analysis, serial output interpretation
