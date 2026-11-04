// ClaudeLogger.pde
// Serial logger (CSV format) with a scrolling monitor window, for Arduino.
// Written by Claude.AI Sonnet 5.5 Medium
// Based on the original by David Dubins
// Created: 04-Nov-26
//
// Features:
//  - Port and baud rate dropdown menus (baud can be changed while connected)
//  - Connect / Disconnect and Rescan buttons
//  - Timestamp, Autoscroll and Plot tick boxes
//  - Scrollable history: mouse wheel, scrollbar (click/drag), Up/Down/PgUp/PgDn/Home/End
//  - Live plot of numeric columns (up to 8 channels, auto-scaling, adjustable window)
//  - Each Connect creates a new timestamped .csv in this sketch's folder
//  - Everything received is written to the file, even lines that scroll out of the
//    on-screen history.
//
// Plot input formats (one sample per line):
//    12.5,30,7.1            comma/semicolon separated columns
//    12.5 30 7.1            space separated columns
//    temp:12.5,hum:30       "name:value" pairs (names are used in the legend)
//    temp,hum,pressure      a header line of names (only read before the first data line)
// Columns that aren't numbers leave a gap in that channel's line.
//
// Make sure each line of your transmitted data ends with a new line (\n).
// Close any Serial Monitor/Plotter before connecting: only one program can use a port.

import processing.serial.*;

// ---------------- Settings you might want to change ----------------
int timeOut = 5;                 // seconds of silence before a "no data" notice is shown
boolean timeStampDefault = false;
boolean plotDefault = true;      // show the live plot at start-up
int[] baudRates = {300, 1200, 2400, 4800, 9600, 19200, 38400, 57600, 74880,
                   115200, 230400, 250000, 500000, 1000000, 2000000};
int defaultBaudIndex = 4;        // index into baudRates (4 = 9600)
int maxLines = 50000;            // lines kept on screen (the file keeps everything)
int[] plotWindows = {100, 200, 500, 1000, 2000, 5000};  // selectable plot widths (samples)
int defaultPlotWindowIndex = 3;  // 3 = 1000 samples
int plotH = 280;                 // plot panel height in pixels

// ---------------- Layout ----------------
int winW = 900;
int winH = 760;
int toolbarH = 76;
int statusH = 44;
int pad = 10;
int lineH = 18;
int sbW = 14;                    // scrollbar width
int logTop = toolbarH;           // these two change when the plot is shown/hidden
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

// ---------------- Plot data ----------------
int maxCh = 8;
int plotCap = 5000;              // must be >= the largest value in plotWindows
float[][] plotBuf = new float[maxCh][plotCap];
long plotTotal = 0;              // total samples received (ring buffer position)
int nCh = 0;                     // number of channels seen so far
String[] chName = new String[maxCh];
int[] chColor = {0xFF1F77B4, 0xFFFF7F0E, 0xFF2CA02C, 0xFFD62728,
                 0xFF9467BD, 0xFF8C564B, 0xFFE377C2, 0xFF7F7F7F};

PFont fontUI, fontMono;

Dropdown portDD, baudDD, plotDD;
Dropdown[] dds;
Button rescanBtn, connectBtn, clearBtn;
Checkbox timeStampCB, autoScrollCB, plotCB;

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
  surface.setTitle("Claude Logger");
  fontUI = createFont("SansSerif", 14, true);
  fontMono = createFont("Monospaced", 14, true);

  portDD = new Dropdown(50, 10, 240, 28);
  baudDD = new Dropdown(430, 10, 120, 28);
  plotDD = new Dropdown(435, 43, 90, 26);
  dds = new Dropdown[] { portDD, baudDD, plotDD };

  String[] b = new String[baudRates.length];
  for (int i = 0; i < b.length; i++) b[i] = str(baudRates[i]);
  baudDD.setItems(b);
  baudDD.sel = defaultBaudIndex;

  String[] w = new String[plotWindows.length];
  for (int i = 0; i < w.length; i++) w[i] = str(plotWindows[i]);
  plotDD.setItems(w);
  plotDD.sel = defaultPlotWindowIndex;

  rescanBtn = new Button(298, 10, 70, 28, "Rescan");
  connectBtn = new Button(565, 10, 110, 28, "Connect");
  clearBtn = new Button(690, 10, 70, 28, "Clear");

  timeStampCB = new Checkbox(10, 48, "Timestamp");
  timeStampCB.checked = timeStampDefault;
  autoScrollCB = new Checkbox(150, 48, "Autoscroll");
  autoScrollCB.checked = true;
  plotCB = new Checkbox(290, 48, "Plot");
  plotCB.checked = plotDefault;
  plotDD.enabled = plotCB.checked;

  updateLayout();
  rescanPorts();
  sysMsg("Pick a port and baud rate, then press Connect.");
}

void draw() {
  readSerial();
  if (autoScrollCB.checked) firstLine = maxFirst();

  background(255);
  textFont(fontUI, 14);
  drawPlot();
  drawLog();
  drawScrollbar();
  drawToolbar();
  drawStatus();
  for (Dropdown d : dds) d.drawList();   // open lists are drawn last so they sit on top
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
  parsePlot(line);                       // plot uses the raw line, without any timestamp
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
  resetPlot(true);                       // new session = fresh plot
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
// Plot data
// =====================================================================
void resetPlot(boolean clearNames) {
  plotTotal = 0;
  nCh = 0;
  if (clearNames) {
    for (int c = 0; c < maxCh; c++) chName[c] = null;
  }
}

float sample(int c, long absIdx) {
  return plotBuf[c][(int) (absIdx % plotCap)];
}

void parsePlot(String line) {
  boolean delim = line.indexOf(',') >= 0 || line.indexOf(';') >= 0;
  String[] tok = delim ? line.split("[,;]", -1) : line.trim().split("\\s+");
  int n = min(tok.length, maxCh);
  float[] vals = new float[n];
  String[] names = new String[n];
  boolean any = false;

  for (int i = 0; i < n; i++) {
    String t = tok[i].trim();
    int colon = t.indexOf(':');
    if (colon > 0) {                     // "name:value"
      names[i] = t.substring(0, colon).trim();
      t = t.substring(colon + 1).trim();
    }
    float v = Float.NaN;
    if (t.length() > 0) {
      try {
        v = Float.parseFloat(t);
      } catch (NumberFormatException e) {
        // not a number: leave as NaN
      }
    }
    if (Float.isInfinite(v)) v = Float.NaN;
    if (!Float.isNaN(v)) any = true;
    vals[i] = v;
  }

  if (!any) {
    // A line of names before any data can serve as a header
    if (delim && plotTotal == 0 && tok.length <= maxCh) {
      for (int i = 0; i < tok.length; i++) {
        String h = tok[i].trim();
        if (h.length() > 0) chName[i] = h;
      }
    }
    return;
  }

  int idx = (int) (plotTotal % plotCap);
  for (int c = 0; c < maxCh; c++) {
    plotBuf[c][idx] = (c < n) ? vals[c] : Float.NaN;
  }
  for (int c = 0; c < n; c++) {
    if (names[c] != null) chName[c] = names[c];
    else if (chName[c] == null) chName[c] = "ch" + (c + 1);
  }
  nCh = max(nCh, n);
  plotTotal++;
}

// =====================================================================
// Layout / scrolling helpers
// =====================================================================
void updateLayout() {
  logTop = toolbarH + (plotCB.checked ? plotH : 0);
  logH = winH - logTop - statusH;
  firstLine = constrain(firstLine, 0, maxFirst());
  if (autoScrollCB.checked) firstLine = maxFirst();
}

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
String fmt(float v) {
  float a = abs(v);
  if (a >= 1000) return String.format("%.0f", v);
  if (a >= 100) return String.format("%.1f", v);
  return String.format("%.2f", v);
}

void drawPlot() {
  if (!plotCB.checked) return;
  int top = toolbarH;
  noStroke();
  fill(248);
  rect(0, top, winW, plotH);
  stroke(190);
  line(0, top + plotH, winW, top + plotH);

  int px = 64, py = top + 14;
  int pw = winW - px - 130, ph = plotH - 14 - 28;
  stroke(150);
  noFill();
  rect(px, py, pw, ph);

  textFont(fontUI, 12);
  int win = plotWindows[plotDD.sel];
  int n = (int) min((long) win, plotTotal);
  if (n == 0 || nCh == 0) {
    noStroke();
    fill(140);
    textAlign(CENTER, CENTER);
    text("Waiting for numeric data...", px + pw / 2, py + ph / 2);
    textFont(fontUI, 14);
    return;
  }
  long start = plotTotal - n;

  // Auto-scale to the data in view
  float lo = Float.MAX_VALUE, hi = -Float.MAX_VALUE;
  for (int c = 0; c < nCh; c++) {
    for (int k = 0; k < n; k++) {
      float v = sample(c, start + k);
      if (!Float.isNaN(v)) {
        if (v < lo) lo = v;
        if (v > hi) hi = v;
      }
    }
  }
  if (lo > hi) {                         // everything in view is a gap
    textFont(fontUI, 14);
    return;
  }
  if (hi - lo < 1e-9) {
    lo -= 1;
    hi += 1;
  } else {
    float padY = (hi - lo) * 0.05;
    lo -= padY;
    hi += padY;
  }

  // Grid lines and y-axis labels
  textAlign(RIGHT, CENTER);
  for (int i = 0; i <= 4; i++) {
    float gy = py + ph * i / 4.0;
    float val = lerp(hi, lo, i / 4.0);
    stroke(225);
    line(px, gy, px + pw, gy);
    noStroke();
    fill(90);
    text(fmt(val), px - 6, gy);
  }

  // Traces (decimated if there are many more samples than pixels)
  clip(px, py, pw, ph);
  noFill();
  strokeWeight(1.5);
  int stride = max(1, n / (2 * pw));
  for (int c = 0; c < nCh; c++) {
    stroke(chColor[c]);
    boolean drawing = false;
    int k = 0;
    while (true) {
      float v = sample(c, start + k);
      if (Float.isNaN(v)) {
        if (drawing) { endShape(); drawing = false; }
      } else {
        if (!drawing) { beginShape(); drawing = true; }
        vertex(px + pw * k / (float) max(1, win - 1), py + ph - (v - lo) / (hi - lo) * ph);
      }
      if (k >= n - 1) break;
      k = min(n - 1, k + stride);
    }
    if (drawing) endShape();
  }
  strokeWeight(1);
  noClip();

  // Legend with the latest value of each channel
  int lx = px + pw + 14;
  for (int c = 0; c < nCh; c++) {
    int ly = py + 10 + c * 26;
    stroke(chColor[c]);
    strokeWeight(3);
    line(lx, ly, lx + 14, ly);
    strokeWeight(1);
    float latest = sample(c, plotTotal - 1);
    String lbl = chName[c] + ": " + (Float.isNaN(latest) ? "-" : fmt(latest));
    noStroke();
    fill(30);
    textAlign(LEFT, CENTER);
    text(fit(lbl, winW - lx - 22 - 6), lx + 20, ly);
  }

  // Footer
  noStroke();
  fill(110);
  textAlign(LEFT, TOP);
  text("Window: " + win + " samples", px, py + ph + 6);
  textAlign(RIGHT, TOP);
  text("Samples received: " + plotTotal, px + pw, py + ph + 6);
  textFont(fontUI, 14);
}

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
  fill(plotCB.checked ? 30 : 150);
  text("Window:", 372, 56);
  text("samples", 532, 56);

  portDD.drawBox();
  rescanBtn.show();
  baudDD.drawBox();
  connectBtn.show();
  clearBtn.show();
  timeStampCB.show();
  autoScrollCB.show();
  plotCB.show();
  plotDD.drawBox();
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
  if (plotDD.enabled && plotDD.overBox()) { plotDD.open = true; return; }

  if (rescanBtn.enabled && rescanBtn.over()) { rescanPorts(); return; }
  if (connectBtn.over()) {
    if (connected) disconnect(); else connect();
    return;
  }
  if (clearBtn.over()) {
    log.clear();
    firstLine = 0;
    resetPlot(false);                    // keep channel names
    return;
  }
  if (timeStampCB.over()) { timeStampCB.checked = !timeStampCB.checked; return; }
  if (autoScrollCB.over()) {
    autoScrollCB.checked = !autoScrollCB.checked;
    if (autoScrollCB.checked) firstLine = maxFirst();
    return;
  }
  if (plotCB.over()) {
    plotCB.checked = !plotCB.checked;
    plotDD.enabled = plotCB.checked;
    updateLayout();
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
