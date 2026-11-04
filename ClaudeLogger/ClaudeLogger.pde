// ClaudeLogger.pde
// Serial logger (CSV format) with a scrolling monitor window, for Arduino.
// Written by Claude.AI Sonnet 5.5 Medium
// Based on the original by David Dubins
// Created: 04-Nov-26
//
// Features:
//  - Port and baud rate dropdown menus (baud can be changed while connected)
//  - Connect / Disconnect and Rescan buttons
//  - Timestamp and Autoscroll tick boxes
//  - Scrollable history: mouse wheel, scrollbar (click/drag), Up/Down/PgUp/PgDn/Home/End
//  - Each Connect creates a new timestamped .csv in this sketch's folder
//  - Everything received is written to the file, even lines that scroll out of the
//    on-screen history.
//
// Make sure each line of your transmitted data ends with a new line (\n).
// Close any Serial Monitor/Plotter before connecting: only one program can use a port.

import processing.serial.*;

// ---------------- Settings you might want to change ----------------
int timeOut = 5;                 // seconds of silence before a "no data" notice is shown
boolean timeStampDefault = false;
int[] baudRates = {300, 1200, 2400, 4800, 9600, 19200, 38400, 57600, 74880,
                   115200, 230400, 250000, 500000, 1000000, 2000000};
int defaultBaudIndex = 4;        // index into baudRates (4 = 9600)
int maxLines = 50000;            // lines kept on screen (the file keeps everything)

// ---------------- Layout ----------------
int winW = 900;
int winH = 700;
int toolbarH = 76;
int statusH = 44;
int pad = 10;
int lineH = 18;
int sbW = 14;                    // scrollbar width
int logTop = toolbarH;
int logH = winH - toolbarH - statusH;
int logW = winW - sbW;

// ---------------- State ----------------
Serial mySerial;
PrintWriter output;
String filename = "";
String portName = "";
boolean connected = false;

ArrayList<LogLine> log = new ArrayList<LogLine>();
int firstLine = 0;               // index of the first visible line
StringBuilder rx = new StringBuilder();
int lastRx = 0;

boolean draggingThumb = false;
int dragOffset = 0;

PFont fontUI, fontMono;

Dropdown portDD, baudDD;
Dropdown[] dds;
Button rescanBtn, connectBtn, clearBtn;
Checkbox timeStampCB, autoScrollCB;

class LogLine {
  String text;
  boolean sys;                   // true = notice from this program, not device data
  LogLine(String t, boolean s) { text = t; sys = s; }
}

// =====================================================================
void settings() {
  size(winW, winH);
}

void setup() {
  surface.setTitle("Serial Logger");
  fontUI = createFont("SansSerif", 14, true);
  fontMono = createFont("Monospaced", 14, true);

  portDD = new Dropdown(50, 10, 240, 28);
  baudDD = new Dropdown(430, 10, 120, 28);
  dds = new Dropdown[] { portDD, baudDD };

  String[] b = new String[baudRates.length];
  for (int i = 0; i < b.length; i++) b[i] = str(baudRates[i]);
  baudDD.setItems(b);
  baudDD.sel = defaultBaudIndex;

  rescanBtn = new Button(298, 10, 70, 28, "Rescan");
  connectBtn = new Button(565, 10, 110, 28, "Connect");
  clearBtn = new Button(690, 10, 70, 28, "Clear");

  timeStampCB = new Checkbox(10, 48, "Timestamp");
  timeStampCB.checked = timeStampDefault;
  autoScrollCB = new Checkbox(150, 48, "Autoscroll");
  autoScrollCB.checked = true;

  rescanPorts();
  sysMsg("Pick a port and baud rate, then press Connect.");
}

void draw() {
  readSerial();
  if (autoScrollCB.checked) firstLine = maxFirst();

  background(255);
  drawLog();
  drawScrollbar();
  drawToolbar();
  drawStatus();
  portDD.drawList();             // open lists are drawn last so they sit on top
  baudDD.drawList();
}

// =====================================================================
// Serial handling
// =====================================================================
void readSerial() {
  if (!connected || mySerial == null) return;
  boolean got = false;
  while (mySerial.available() > 0) {
    int v = mySerial.read();
    if (v < 0) break;
    char c = (char) v;
    if (c == '\n' || c == '\r') {
      if (rx.length() > 0) {
        addDataLine(rx.toString());
        rx.setLength(0);
        got = true;
      }
    } else if (c >= ' ' && c <= '~') {   // skip non-printable characters
      rx.append(c);
      if (rx.length() > 2000) {          // runaway line with no newline
        addDataLine(rx.toString());
        rx.setLength(0);
        got = true;
      }
    }
    lastRx = millis();
  }
  if (got) {
    if (output != null) output.flush();
    trimLog();
  }
  if (millis() - lastRx > timeOut * 1000) {
    sysMsg("No data received for " + timeOut + " s. Check port connection.");
    lastRx = millis();
  }
}

void addDataLine(String line) {
  String s = line;
  if (timeStampCB.checked) {
    s = nf(hour(), 2) + ":" + nf(minute(), 2) + ":" + nf(second(), 2) + ", " + line;
  }
  if (output != null) output.println(s);
  log.add(new LogLine(s, false));
}

void sysMsg(String s) {
  log.add(new LogLine("[" + s + "]", true));
}

void trimLog() {
  if (log.size() > maxLines + 1000) {
    int k = log.size() - maxLines;
    log.subList(0, k).clear();
    if (!autoScrollCB.checked) firstLine = max(0, firstLine - k);
  }
}

void rescanPorts() {
  String prev = portDD.selected();
  String[] ports = Serial.list();
  portDD.setItems(ports);
  for (int i = 0; i < ports.length; i++) {
    if (ports[i].equals(prev)) portDD.sel = i;
  }
  sysMsg("Found " + ports.length + " serial port(s).");
}

void connect() {
  if (portDD.items.length == 0) {
    sysMsg("No port available. Plug in your device and press Rescan.");
    return;
  }
  String p = portDD.selected();
  int baud = baudRates[baudDD.sel];
  try {
    mySerial = new Serial(this, p, baud);
  } catch (Exception e) {
    mySerial = null;
    sysMsg("Could not open " + p + ". Close any Serial Monitor/Plotter using it, then try again.");
    return;
  }
  portName = p;
  filename = year() + nf(month(), 2) + nf(day(), 2) + "-" + nf(hour(), 2) + nf(minute(), 2) + nf(second(), 2);
  output = createWriter(filename + ".csv");
  rx.setLength(0);
  lastRx = millis();
  connected = true;
  connectBtn.label = "Disconnect";
  portDD.enabled = false;
  rescanBtn.enabled = false;
  sysMsg("Connected to " + p + " at " + baud + " bps. Logging to " + filename + ".csv");
}

void disconnect() {
  if (mySerial != null) {
    mySerial.stop();
    mySerial = null;
  }
  if (output != null) {
    output.flush();
    output.close();
    output = null;
    sysMsg("Disconnected. Saved log file: " + sketchPath(filename + ".csv"));
  }
  connected = false;
  connectBtn.label = "Connect";
  portDD.enabled = true;
  rescanBtn.enabled = true;
}

void changeBaud() {
  if (!connected) return;
  int baud = baudRates[baudDD.sel];
  if (mySerial != null) mySerial.stop();
  try {
    mySerial = new Serial(this, portName, baud);
    rx.setLength(0);
    lastRx = millis();
    sysMsg("Baud rate changed to " + baud + " bps.");
  } catch (Exception e) {
    mySerial = null;
    sysMsg("Could not reopen " + portName + " at " + baud + " bps.");
    disconnect();
  }
}

// =====================================================================
// Scrolling helpers
// =====================================================================
int visibleLines() {
  return max(1, (logH - 8) / lineH);
}

int maxFirst() {
  return max(0, log.size() - visibleLines());
}

void scrollTo(int v) {
  firstLine = constrain(v, 0, maxFirst());
  autoScrollCB.checked = (firstLine >= maxFirst());   // scrolling to the bottom re-enables autoscroll
}

int thumbH() {
  int n = log.size(), v = visibleLines();
  if (n <= v) return logH;
  return max(24, (int) ((float) logH * v / n));
}

int thumbY() {
  int mf = maxFirst();
  if (mf == 0) return logTop;
  return logTop + (int) ((logH - thumbH()) * (float) firstLine / mf);
}

// =====================================================================
// Drawing
// =====================================================================
void drawLog() {
  clip(0, logTop, logW, logH);
  textFont(fontMono, 14);
  textAlign(LEFT, CENTER);
  noStroke();
  int n = log.size();
  int last = min(n, firstLine + visibleLines() + 1);
  for (int i = firstLine; i < last; i++) {
    LogLine ln = log.get(i);
    if (ln.sys) fill(170, 90, 0); else fill(30);
    text(ln.text, pad, logTop + 4 + (i - firstLine) * lineH + lineH / 2);
  }
  noClip();
  textFont(fontUI, 14);
}

void drawScrollbar() {
  int x = winW - sbW;
  noStroke();
  fill(240);
  rect(x, logTop, sbW, logH);
  if (log.size() > visibleLines()) {
    fill(draggingThumb ? 120 : 175);
    rect(x + 2, thumbY(), sbW - 4, thumbH(), 4);
  }
}

void drawToolbar() {
  noStroke();
  fill(235);
  rect(0, 0, winW, toolbarH);
  stroke(190);
  line(0, toolbarH, winW, toolbarH);

  fill(30);
  noStroke();
  textAlign(LEFT, CENTER);
  text("Port:", pad, 24);
  text("Baud:", 385, 24);

  portDD.drawBox();
  rescanBtn.show();
  baudDD.drawBox();
  connectBtn.show();
  clearBtn.show();
  timeStampCB.show();
  autoScrollCB.show();
}

void drawStatus() {
  int y0 = winH - statusH;
  noStroke();
  fill(225);
  rect(0, y0, winW, statusH);
  stroke(190);
  line(0, y0, winW, y0);
  noStroke();
  fill(30);
  textAlign(LEFT, CENTER);
  String l1 = connected ? "Connected: " + portName + " @ " + baudRates[baudDD.sel] + " bps"
                        : "Not connected";
  String l2 = filename.length() == 0 ? "Log file: (created when you connect)"
            : (connected ? "Logging to: " : "Last log file: ") + sketchPath(filename + ".csv");
  text(l1, pad, y0 + 13);
  text(fit(l2, winW - 2 * pad), pad, y0 + 31);
}

String fit(String s, float maxW) {
  if (textWidth(s) <= maxW) return s;
  while (s.length() > 1 && textWidth(s + "...") > maxW) s = s.substring(0, s.length() - 1);
  return s + "...";
}

// =====================================================================
// Input
// =====================================================================
void mousePressed() {
  // An open dropdown gets the first claim on any click
  for (Dropdown d : dds) {
    if (d.open) {
      int r = d.overRow();
      if (r >= 0) {
        d.sel = r;
        if (d == baudDD) changeBaud();
      }
      d.open = false;
      return;
    }
  }

  if (portDD.enabled && portDD.overBox()) { portDD.open = true; return; }
  if (baudDD.overBox()) { baudDD.open = true; return; }

  if (rescanBtn.enabled && rescanBtn.over()) { rescanPorts(); return; }
  if (connectBtn.over()) {
    if (connected) disconnect(); else connect();
    return;
  }
  if (clearBtn.over()) {
    log.clear();
    firstLine = 0;
    return;
  }
  if (timeStampCB.over()) { timeStampCB.checked = !timeStampCB.checked; return; }
  if (autoScrollCB.over()) {
    autoScrollCB.checked = !autoScrollCB.checked;
    if (autoScrollCB.checked) firstLine = maxFirst();
    return;
  }

  // Scrollbar
  if (mouseX >= winW - sbW && mouseY >= logTop && mouseY < logTop + logH && log.size() > visibleLines()) {
    int ty = thumbY();
    if (mouseY >= ty && mouseY <= ty + thumbH()) {
      draggingThumb = true;
      dragOffset = mouseY - ty;
    } else if (mouseY < ty) {
      scrollTo(firstLine - visibleLines());
    } else {
      scrollTo(firstLine + visibleLines());
    }
  }
}

void mouseDragged() {
  if (draggingThumb) {
    int range = logH - thumbH();
    if (range > 0) {
      float r = (mouseY - dragOffset - logTop) / (float) range;
      scrollTo(round(r * maxFirst()));
    }
  }
}

void mouseReleased() {
  draggingThumb = false;
}

void mouseWheel(processing.event.MouseEvent e) {
  scrollTo(firstLine + e.getCount() * 3);
}

void keyPressed() {
  if (key == CODED) {
    if (keyCode == UP) scrollTo(firstLine - 1);
    else if (keyCode == DOWN) scrollTo(firstLine + 1);
    else if (keyCode == 33) scrollTo(firstLine - visibleLines());   // Page Up
    else if (keyCode == 34) scrollTo(firstLine + visibleLines());   // Page Down
    else if (keyCode == 36) scrollTo(0);                            // Home
    else if (keyCode == 35) scrollTo(maxFirst());                   // End
  }
}

void exit() {                    // make sure the file closes
  disconnect();
  if (filename.length() > 0) {
    println("Saved log file: " + sketchPath(filename + ".csv") + ". You may now close Processing.");
  }
  super.exit();
}

// =====================================================================
// Minimal widgets
// =====================================================================
class Dropdown {
  int x, y, w, h;
  String[] items = new String[0];
  int sel = 0;
  boolean open = false;
  boolean enabled = true;
  int rowH = 24;

  Dropdown(int x, int y, int w, int h) {
    this.x = x; this.y = y; this.w = w; this.h = h;
  }

  void setItems(String[] it) {
    items = it;
    if (sel >= items.length) sel = max(0, items.length - 1);
  }

  String selected() {
    return items.length > 0 ? items[sel] : "";
  }

  void drawBox() {
    stroke(enabled ? 120 : 190);
    fill(enabled ? 255 : 240);
    rect(x, y, w, h, 4);
    noStroke();
    fill(enabled ? 30 : 150);
    textAlign(LEFT, CENTER);
    String s = items.length > 0 ? items[sel] : "(no ports found)";
    text(fit(s, w - 34), x + 8, y + h / 2 - 1);
    triangle(x + w - 20, y + h / 2 - 3, x + w - 10, y + h / 2 - 3, x + w - 15, y + h / 2 + 4);
  }

  void drawList() {
    if (!open) return;
    int r = overRow();
    for (int i = 0; i < items.length; i++) {
      int ry = y + h + i * rowH;
      stroke(120);
      fill(i == r ? color(200, 220, 245) : (i == sel ? color(235, 242, 250) : 255));
      rect(x, ry, w, rowH);
      noStroke();
      fill(30);
      textAlign(LEFT, CENTER);
      text(fit(items[i], w - 16), x + 8, ry + rowH / 2 - 1);
    }
  }

  boolean overBox() {
    return mouseX >= x && mouseX <= x + w && mouseY >= y && mouseY <= y + h;
  }

  int overRow() {
    if (!open || mouseX < x || mouseX > x + w || mouseY < y + h) return -1;
    int r = (mouseY - (y + h)) / rowH;
    return (r >= 0 && r < items.length) ? r : -1;
  }
}

class Button {
  int x, y, w, h;
  String label;
  boolean enabled = true;

  Button(int x, int y, int w, int h, String label) {
    this.x = x; this.y = y; this.w = w; this.h = h; this.label = label;
  }

  void show() {
    boolean hov = enabled && over();
    stroke(enabled ? 120 : 190);
    fill(!enabled ? 238 : (hov ? (mousePressed ? 190 : 215) : 247));
    rect(x, y, w, h, 4);
    noStroke();
    fill(enabled ? 30 : 150);
    textAlign(CENTER, CENTER);
    text(label, x + w / 2, y + h / 2 - 1);
  }

  boolean over() {
    return mouseX >= x && mouseX <= x + w && mouseY >= y && mouseY <= y + h;
  }
}

class Checkbox {
  int x, y;
  String label;
  boolean checked = false;

  Checkbox(int x, int y, String label) {
    this.x = x; this.y = y; this.label = label;
  }

  void show() {
    stroke(120);
    fill(255);
    rect(x, y, 16, 16, 3);
    if (checked) {
      stroke(30, 120, 200);
      strokeWeight(2);
      line(x + 3, y + 8, x + 7, y + 12);
      line(x + 7, y + 12, x + 13, y + 4);
      strokeWeight(1);
    }
    noStroke();
    fill(30);
    textAlign(LEFT, CENTER);
    text(label, x + 24, y + 7);
  }

  boolean over() {
    return mouseX >= x && mouseX <= x + 24 + textWidth(label) && mouseY >= y && mouseY <= y + 16;
  }
}
