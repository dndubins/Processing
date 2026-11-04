// MenuDemo.ino
// A small serial menu to try out the send box in ClaudeLogger.
//
//   1) Read A0     - streams readings from pin A0
//   2) Read A1     - streams readings from pin A1
//   3) Set reading frequency in Hz
//
// How to use it with ClaudeLogger:
//   - Baud rate 9600, line ending set to "Newline".
//   - Send 1 or 2 to start streaming. Send any key to stop and return to the menu.
//   - Send 3, then a number (and press Enter) to change how often readings are taken.
//
// Readings are printed as "A0:512" so the live plot picks them up and labels the line.
// Status messages deliberately avoid standalone numbers and commas, so the plot
// doesn't mistake them for data.

const unsigned long BAUD_RATE = 9600;
const int MIN_HZ = 1;
const int MAX_HZ = 50;           // keeps 9600 baud from overflowing; raise it if you use 115200

enum State { MENU, STREAMING, ASK_FREQ };
State state = MENU;

int streamPin = A0;
const char* streamName = "A0";
int rateHz = 5;                  // readings per second
unsigned long lastRead = 0;

char numBuf[6];                  // digits typed while setting the frequency
byte numLen = 0;

void printMenu() {
  Serial.println();
  Serial.println(F("=== Menu ==="));
  Serial.println(F("1) Read A0"));
  Serial.println(F("2) Read A1"));
  Serial.print(F("3) Set reading frequency in Hz (now "));
  Serial.print(rateHz);
  Serial.println(F("Hz)"));
}

void startStream(int pin, const char* name) {
  streamPin = pin;
  streamName = name;
  state = STREAMING;
  lastRead = 0;                  // take the first reading straight away
  Serial.print(F("Reading "));
  Serial.print(name);
  Serial.print(F(" at "));
  Serial.print(rateHz);
  Serial.println(F("Hz. Send any key to stop."));
}

// Handles one incoming character. Line endings (\r and \n) are ignored in the menu
// and while streaming, so "1" followed by a newline works the same as just "1".
void handleChar(char c) {
  switch (state) {
    case MENU:
      if (c == '1') {
        startStream(A0, "A0");
      } else if (c == '2') {
        startStream(A1, "A1");
      } else if (c == '3') {
        numLen = 0;
        state = ASK_FREQ;
        Serial.print(F("Enter frequency in Hz (1-"));
        Serial.print(MAX_HZ);
        Serial.println(F(") then press Enter:"));
      } else if (!isspace(c)) {
        Serial.println(F("Unknown choice."));
        printMenu();
      }
      break;

    case STREAMING:
      if (!isspace(c)) {         // any visible key stops the stream
        state = MENU;
        Serial.println(F("Stopped."));
        printMenu();
      }
      break;

    case ASK_FREQ:
      if (c == '\n' || c == '\r') {
        if (numLen == 0) break;  // e.g. the line ending that followed the "3"
        numBuf[numLen] = 0;
        int hz = atoi(numBuf);
        if (hz >= MIN_HZ && hz <= MAX_HZ) {
          rateHz = hz;
          Serial.print(F("Rate set to "));
          Serial.print(rateHz);
          Serial.println(F("Hz."));
        } else {
          Serial.println(F("Out of range. No change."));
        }
        state = MENU;
        printMenu();
      } else if (isDigit(c)) {
        if (numLen < sizeof(numBuf) - 1) numBuf[numLen++] = c;
      } else if (!isspace(c)) {  // any other character cancels
        state = MENU;
        Serial.println(F("Cancelled."));
        printMenu();
      }
      break;
  }
}

void setup() {
  Serial.begin(BAUD_RATE);
  while (!Serial) { }            // only matters on boards with native USB
  printMenu();
}

void loop() {
  while (Serial.available() > 0) {
    handleChar(Serial.read());
  }

  if (state == STREAMING && millis() - lastRead >= 1000UL / rateHz) {
    lastRead = millis();
    Serial.print(streamName);
    Serial.print(':');
    Serial.println(analogRead(streamPin));
  }
}
