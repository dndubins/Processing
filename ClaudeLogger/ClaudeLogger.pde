// ClaudeLogger.pde
// Serial logger (CSV format) with a scrolling monitor window, for Arduino.
// Written by Claude.AI Sonnet 5.5 Medium
// Additional beginner-friendly comments assisted by Perplexity AI
// Based on the original by David Dubins
// Created: 04-Nov-26
// Last Updated: 11-Nov-26
//
// Features:
//  - Port and baud rate dropdown menus (baud can be changed while connected)
//  - Connect / Disconnect and Rescan buttons
//  - Timestamp, Autoscroll and Plot tick boxes
//  - Scrollable history: mouse wheel, scrollbar (click/drag), Up/Down/PgUp/PgDn/Home/End
//  - Select text with click-drag (shift-click extends, double-click selects a line);
//    Ctrl/Cmd+C copies the selection, Ctrl/Cmd+A selects everything, and the Copy
//    button copies the selection (or all data lines if nothing is selected)
//  - Send box with a line-ending dropdown (No line ending / Newline / Carriage return /
//    Both NL & CR) for talking to devices that have a text menu. Sent text is echoed
//    in the log (blue, "> " prefix) and, by default, written to the CSV too, so the
//    file holds the whole transcript. Up/Down recall earlier messages.
//  - Live plot of numeric columns (up to 8 channels, auto-scaling, adjustable window);
//    click a legend entry to hide or show that channel (hidden channels are still logged)
//  - Drag the grip in the bottom-right corner to change the window height (width stays fixed)
//  - Each Connect creates a new timestamped .csv in this sketch's folder
//  - Everything received is written to the file, even lines that scroll out of the
//    on-screen history.
//  - Hover over a plot point (mouse still for a moment) to see its x and y
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

// These imports give the program extra tools it does not have by default.
import processing.serial.*;                  // Lets us talk to Arduino over USB (serial port)
import java.awt.Toolkit;                     // for the system clipboard
import java.awt.datatransfer.*;              // StringSelection, DataFlavor, Transferable

// ---------------- Settings you might want to change ----------------
int timeOut = 61;                 // seconds of silence before a "no data" notice is shown
boolean timeStampDefault = true;  // Should timestamps be turned on when the program starts?
boolean plotDefault = true;       // show the live plot at start-up

// Common speeds for serial communication. Both sides must use the same speed.
int[] baudRates = {300, 1200, 2400, 4800, 9600, 19200, 38400, 57600, 74880,
                   115200, 230400, 250000, 500000, 1000000, 2000000};
int defaultBaudIndex = 4;        // index into baudRates (4 = 9600)

int maxLines = 50000;            // lines kept on screen (the file keeps everything)

// Choices for how many past samples the plot shows.
int[] plotWindows = {100, 200, 500, 1000, 2000, 5000};  // selectable plot widths (samples)
int defaultPlotWindowIndex = 3;  // 3 = 1000 samples

boolean logSentToFile = true;    // also write text you send (with a "> " prefix) to the CSV
int defaultLineEnding = 1;       // 0 = none, 1 = Newline, 2 = Carriage return, 3 = both
int plotH = 280;                 // plot panel height in pixels
int hoverDelay = 250;            // how long (in milliseconds) the mouse must sit still before the tooltip appears
float hoverRadius = 14;          // how close (in pixels) the mouse must be to a data point to count as "on" it

// ---------------- Layout ----------------
// These numbers control where things appear on the screen, in pixels.
int winW = 900;  // width of window (adjust for your screen)
int winH = 700;  // starting height of window (drag the bottom-right grip to change it)
int toolbarH = 76;               // height of the top bar with buttons and menus
int statusH = 44;                // height of the bottom status bar
int sendH = 36;                  // height of the send bar that sits above the status bar
int sendY = winH - statusH - sendH;   // top of the send bar
int sendFieldW = 622;            // width of the text entry box
int pad = 10;                    // small space between the window edge and text
int lineH = 18;                  // height of one line of text in the log
int sbW = 14;                    // scrollbar width
int logTop = toolbarH;           // these two change when the plot is shown/hidden
int logH = winH - toolbarH - statusH - sendH;  // height of the scrolling log area
int logW = winW - sbW;           // width of the log area, leaving room for the scrollbar
int minWinH = min(winH, toolbarH + plotH + statusH + sendH + 5 * lineH);   // smallest allowed height

// ---------------- State ----------------
// "State" means information the program remembers while it is running.
Serial mySerial;                 // the connection to the Arduino/device
PrintWriter output;              // used to write data into the CSV file
String filename = "";            // name of the CSV file for this session
String portName = "";            // which USB port we are connected to
boolean connected = false;       // true when we are connected to a device

// This list stores every line shown in the log window.
ArrayList<LogLine> log = new ArrayList<LogLine>();
int firstLine = 0;               // index of the first visible line
StringBuilder rx = new StringBuilder();  // collects incoming characters until a full line arrives
int lastRx = 0;                  // time when we last received data

boolean draggingThumb = false;   // true while dragging the scrollbar
int dragOffset = 0;              // where the mouse grabbed the scrollbar
boolean resizing = false;        // true while the corner grip is being dragged
int grabDY = 0;                  // distance from the mouse to the window's bottom edge at grab time

// ---------------- Text selection ----------------
// A = where the selection started, B = where it currently ends (line index, character column).
int selAL = -1, selAC = 0, selBL = -1, selBC = 0;
boolean selecting = false;       // true while the mouse button is held down in the log
float charW = 8;                 // width of one monospace character (measured in setup)
String flashMsg = "";            // short message shown in the status bar (e.g. "Copied")
int flashUntil = 0;              // time when the short message should disappear

// ---------------- Sending to the device ----------------
String sendText = "";            // text currently typed in the send box
boolean sendFocus = false;       // true when the send box has keyboard focus
ArrayList<String> sendHistory = new ArrayList<String>();  // remembers messages you sent
int histPos = 0;                 // position while browsing history with Up/Down

// ---------------- Plot data ----------------
int maxCh = 8;                   // maximum number of lines/channels on the plot
int plotCap = 5000;              // must be >= the largest value in plotWindows

// A 2D array: one row per channel, storing that channel's past values.
float[][] plotBuf = new float[maxCh][plotCap];
long plotTotal = 0;              // total samples received (ring buffer position)
int nCh = 0;                     // number of channels seen so far
String[] chName = new String[maxCh];  // names shown in the plot legend

// Colors for each plotted channel, written in hexadecimal (base 16).
int[] chColor = {0xFF1F77B4, 0xFFFF7F0E, 0xFF2CA02C, 0xFFD62728,
                 0xFF9467BD, 0xFF8C564B, 0xFFE377C2, 0xFF7F7F7F};
boolean[] chHidden = new boolean[maxCh];   // channels hidden via the legend (kept across reconnects)
// Used to notice when the mouse has stopped moving (for the hover tooltip on the plot).
int lastMX = -1, lastMY = -1;    // where the mouse was on the previous frame
int lastMoveMs = 0;              // the time (in milliseconds) when the mouse last moved

PFont fontUI, fontMono;          // two fonts: one for buttons, one for log text

Dropdown portDD, baudDD, plotDD, lineEndDD;  // the four dropdown menus
Dropdown[] dds;                  // puts all dropdowns in one list so we can handle them together
Button rescanBtn, connectBtn, clearBtn, copyBtn, sendBtn;  // the clickable buttons
Checkbox timeStampCB, autoScrollCB, plotCB;  // the three tick boxes

// A simple class: a template for one line in the log.
class LogLine {
  String text;                   // the words shown on that line
  boolean sys;                   // true = notice from this program, not device data
  boolean sent = false;          // true = text you sent to the device

  // Constructor: runs when we create a new LogLine.
  LogLine(String t, boolean s) { text = t; sys = s; }
}

// =====================================================================
// settings() runs once before setup(), to create the window.
// =====================================================================
void settings() {
  size(winW, winH);                       // make the window this many pixels wide and tall
  pixelDensity(displayDensity());         // make graphics look sharp on high-resolution screens
}

// setup() runs once when the program starts.
void setup() {
  surface.setTitle("Claude Logger");      // text shown in the window's title bar
  surface.setResizable(false);           // native resizing is off; the corner grip changes the height

  // Load the fonts we will use.
  fontUI = createFont("SansSerif", 14, true);
  fontMono = createFont("Monospaced.bold", 14, true);
  textFont(fontMono, 14);
  charW = textWidth("M");        // monospace, so every character is this wide
  textFont(fontUI, 14);

  // Create the dropdown menus at their screen positions.
  portDD = new Dropdown(50, 10, 240, 28);
  baudDD = new Dropdown(430, 10, 120, 28);
  plotDD = new Dropdown(435, 43, 90, 26);
  lineEndDD = new Dropdown(640, sendY + 5, 172, 26);
  lineEndDD.upward = true;               // the bar is at the bottom, so its list opens upward

  // Choices for what character is sent after your message.
  lineEndDD.setItems(new String[] { "No line ending", "Newline", "Carriage return", "Both NL & CR" });
  lineEndDD.sel = defaultLineEnding;     // choose the default option
  dds = new Dropdown[] { portDD, baudDD, plotDD, lineEndDD };

  // Turn the list of baud-rate numbers into text for the dropdown menu.
  String[] b = new String[baudRates.length];
  for (int i = 0; i < b.length; i++) b[i] = str(baudRates[i]);
  baudDD.setItems(b);
  baudDD.sel = defaultBaudIndex;

  // Same idea for the plot-window choices.
  String[] w = new String[plotWindows.length];
  for (int i = 0; i < w.length; i++) w[i] = str(plotWindows[i]);
  plotDD.setItems(w);
  plotDD.sel = defaultPlotWindowIndex;

  // Create the buttons: x, y, width, height, label.
  rescanBtn = new Button(298, 10, 70, 28, "Rescan");
  connectBtn = new Button(565, 10, 110, 28, "Connect");
  clearBtn = new Button(690, 10, 70, 28, "Clear");
  copyBtn = new Button(770, 10, 70, 28, "Copy");
  sendBtn = new Button(820, sendY + 5, 70, 26, "Send");

  // Create the tick boxes and set their starting values.
  timeStampCB = new Checkbox(10, 48, "Timestamp");
  timeStampCB.checked = timeStampDefault;
  autoScrollCB = new Checkbox(150, 48, "Autoscroll");
  autoScrollCB.checked = true;           // keep the view at the newest line by default
  plotCB = new Checkbox(290, 48, "Plot");
  plotCB.checked = plotDefault;
  plotDD.enabled = plotCB.checked;       // only allow plot-window choice when the plot is visible

  updateLayout();        // calculate the sizes of the screen areas
  rescanPorts();         // look for connected serial devices
  sysMsg("Pick a port and baud rate, then press Connect.");
}

// draw() runs many times per second; it redraws the whole screen.
void draw() {
  if (resizing) {                        // dragging the corner grip: change the height only
    int h = constrain(mouseY + grabDY, minWinH, displayHeight);  // keep height in a valid range
    if (h != winH) {
      surface.setSize(winW, h);          // change the actual window height
      applyHeight(h);                    // move bottom-anchored parts to match
    }
  }

  // Notice whether the mouse has moved since the last frame.
  if (mouseX != lastMX || mouseY != lastMY) {
    lastMX = mouseX;                     // remember where the mouse is now
    lastMY = mouseY;
    lastMoveMs = millis();               // and when it moved
  }

  readSerial();                          // check for new data from the device

  if (selecting) {                       // dragging a selection: scroll if the mouse leaves the log
    if (mouseY < logTop) scrollTo(firstLine - 1);
    else if (mouseY > logTop + logH) scrollTo(firstLine + 1);
    updateSelection();
  }

  // If autoscroll is on, always show the newest lines.
  if (autoScrollCB.checked) firstLine = maxFirst();

  background(255);                       // clear the screen with white
  textFont(fontUI, 14);

  // Draw each part of the interface, from back to front.
  drawPlot();
  drawLog();
  drawScrollbar();
  drawToolbar();
  drawStatus();
  drawSendBar();
  drawGrip();

  // Choose the mouse cursor: move, hand, text, or arrow.
  cursor((overGrip() || resizing) ? MOVE : (legendHit() >= 0 ? HAND : (sendFieldOver() ? TEXT : ARROW)));

  for (Dropdown d : dds) d.drawList();   // open lists are drawn last so they sit on top
}

// =====================================================================
// Serial handling
// =====================================================================

// Read any characters the device has sent us.
void readSerial() {
  if (!connected || mySerial == null) return;  // do nothing if not connected
  boolean got = false;                         // did we receive at least one full line?

  // Keep reading while there are unread characters.
  while (mySerial.available() > 0) {
    int v = mySerial.read();                   // read one character as a number
    if (v < 0) break;                          // no more data
    char c = (char) v;                         // convert the number into a letter/character

    // A newline or carriage return means "end of line".
    if (c == '\n' || c == '\r') {
      if (rx.length() > 0) {
        addDataLine(rx.toString());            // save the completed line
        rx.setLength(0);                       // empty the builder for the next line
        got = true;
      }
    } else if (c >= ' ' && c <= '~') {   // skip non-printable characters
      rx.append(c);                            // add the character to the current line

      if (rx.length() > 2000) {          // runaway line with no newline
        addDataLine(rx.toString());            // save it anyway so memory does not fill up
        rx.setLength(0);
        got = true;
      }
    }
    lastRx = millis();                         // remember when data last arrived
  }

  if (got) {
    if (output != null) output.flush();        // make sure saved data is written to the file
    trimLog();                                 // remove very old lines from the screen
  }

  // If no data has arrived for a while, warn the user.
  if (millis() - lastRx > timeOut * 1000) {
    sysMsg("No data received for " + timeOut + " s. Check port connection.");
    lastRx = millis();                         // reset the timer so the warning does not repeat instantly
  }
}

// Add one received line to the log, CSV file, and plot.
void addDataLine(String line) {
  parsePlot(line);                       // plot uses the raw line, without any timestamp

  String s = line;                       // start with the original text

  // Add a time like "12:34:56, " if the Timestamp box is checked.
  if (timeStampCB.checked) {
    s = nf(hour(), 2) + ":" + nf(minute(), 2) + ":" + nf(second(), 2) + ", " + line;
  }

  if (output != null) output.println(s);       // save the line to the CSV file
  log.add(new LogLine(s, false));              // show the line in the log window
}

// Add a message from this program, shown in orange with square brackets.
void sysMsg(String s) {
  log.add(new LogLine("[" + s + "]", true));
}

// Keep the on-screen log from growing forever.
void trimLog() {
  if (log.size() > maxLines + 1000) {
    int k = log.size() - maxLines;             // how many old lines to remove
    log.subList(0, k).clear();                 // delete the oldest lines

    if (!autoScrollCB.checked) firstLine = max(0, firstLine - k);  // keep the view in place

    if (selAL >= 0) {                    // selection indexes shift with the removed lines
      selAL -= k;                              // move the selection start up by k lines
      selBL -= k;                              // move the selection end up by k lines
      if (selAL < 0 || selBL < 0) clearSel();  // selection was deleted, so clear it
    }
  }
}

// Look again for serial devices plugged into the computer.
void rescanPorts() {
  String prev = portDD.selected();             // remember the currently selected port
  String[] ports = Serial.list();              // get a list of available ports
  portDD.setItems(ports);                      // show them in the dropdown
  // If the old port is still there, keep it selected.
  boolean prevPort = false;
  for (int i = 0; i < ports.length; i++) {
    if (ports[i].equals(prev)){
      portDD.sel = i;
      prevPort = true;
    }
  }
  if (!prevPort && ports.length > 0) portDD.sel = ports.length - 1;  // default to the last port
  sysMsg("Found " + ports.length + " serial port(s).");
}

// Connect to the selected serial port.
void connect() {
  if (portDD.items.length == 0) {
    sysMsg("No port available. Plug in your device and press Rescan.");
    return;                                    // stop here; there is nothing to connect to
  }

  String p = portDD.selected();                // the chosen port name
  int baud = baudRates[baudDD.sel];            // the chosen communication speed

  try {
    mySerial = new Serial(this, p, baud);      // try to open the connection
  } catch (Exception e) {
    mySerial = null;
    sysMsg("Could not open " + p + ". Close any Serial Monitor/Plotter using it, then try again.");
    return;
  }

  portName = p;

  // Build a filename using the current date and time, e.g. 20261105-103000.
  filename = year() + nf(month(), 2) + nf(day(), 2) + "-" + nf(hour(), 2) + nf(minute(), 2) + nf(second(), 2);
  output = createWriter(filename + ".csv");    // create the CSV file

  rx.setLength(0);                             // start with no half-finished incoming line
  lastRx = millis();
  resetPlot(true);                       // new session = fresh plot
  connected = true;                            // remember that we are connected

  connectBtn.label = "Disconnect";             // the same button now disconnects
  portDD.enabled = false;                      // lock the port menu while connected
  rescanBtn.enabled = false;                   // no need to rescan while connected
  sysMsg("Connected to " + p + " at " + baud + " bps. Logging to " + filename + ".csv");
}

// Close the connection and save/close the CSV file.
void disconnect() {
  if (mySerial != null) {
    mySerial.stop();                           // close the serial connection
    mySerial = null;
  }

  if (output != null) {
    output.flush();                            // write any remaining data to disk
    output.close();                            // safely close the file
    output = null;
    sysMsg("Disconnected. Saved log file: " + sketchPath(filename + ".csv"));
  }

  connected = false;
  connectBtn.label = "Connect";
  portDD.enabled = true;
  rescanBtn.enabled = true;
}

// Change the serial speed while still connected.
void changeBaud() {
  if (!connected) return;                      // only works if already connected
  int baud = baudRates[baudDD.sel];            // get the newly chosen speed

  if (mySerial != null) mySerial.stop();       // close the old connection first

  try {
    mySerial = new Serial(this, portName, baud);  // reopen at the new speed
    rx.setLength(0);
    lastRx = millis();
    sysMsg("Baud rate changed to " + baud + " bps.");
  } catch (Exception e) {
    mySerial = null;
    sysMsg("Could not reopen " + portName + " at " + baud + " bps.");
    disconnect();                              // if it failed, disconnect cleanly
  }
}

// =====================================================================
// Plot data
// =====================================================================

// Clear the plot data. If clearNames is true, also forget channel names.
void resetPlot(boolean clearNames) {
  plotTotal = 0;                               // no samples received yet
  nCh = 0;                                     // no channels seen yet
  if (clearNames) {
    for (int c = 0; c < maxCh; c++) chName[c] = null;
  }
}

// Get one stored plot value.
// absIdx is the sample number; % wraps around the fixed-size buffer.
float sample(int c, long absIdx) {
  return plotBuf[c][(int) (absIdx % plotCap)];
}

// Turn one incoming text line into numbers for the plot.
void parsePlot(String line) {
  // Does the line use commas or semicolons to separate values?
  boolean delim = line.indexOf(',') >= 0 || line.indexOf(';') >= 0;

  // Split the line into pieces: either by comma/semicolon or by spaces.
  String[] tok = delim ? line.split("[,;]", -1) : line.trim().split("\\s+");
  int n = min(tok.length, maxCh);              // never use more than 8 channels
  float[] vals = new float[n];                 // the numeric values
  String[] names = new String[n];              // optional names, like "temp"
  boolean any = false;                         // did we find at least one number?

  // Look at each piece of text.
  for (int i = 0; i < n; i++) {
    String t = tok[i].trim();                  // remove spaces around the value
    int colon = t.indexOf(':');

    if (colon > 0) {                     // "name:value"
      names[i] = t.substring(0, colon).trim();  // text before the colon is the name
      t = t.substring(colon + 1).trim();        // text after the colon is the value
    }

    float v = Float.NaN;                       // NaN means "not a number" / no data
    if (t.length() > 0) {
      try {
        v = Float.parseFloat(t);               // try to convert text into a decimal number
      } catch (NumberFormatException e) {
        // not a number: leave as NaN
      }
    }

    if (Float.isInfinite(v)) v = Float.NaN;    // treat infinity as missing data
    if (!Float.isNaN(v)) any = true;           // we found at least one usable number
    vals[i] = v;                               // store the value for this channel
  }

  if (!any) {
    // A line of names before any data can serve as a header
    if (delim && plotTotal == 0 && tok.length <= maxCh) {
      for (int i = 0; i < tok.length; i++) {
        String h = tok[i].trim();
        if (h.length() > 0) chName[i] = h;     // use this text as the channel name
      }
    }
    return;                                    // nothing to plot on this line
  }

  int idx = (int) (plotTotal % plotCap);       // where to store this sample in the ring buffer

  // Save every channel's value; missing channels get NaN.
  for (int c = 0; c < maxCh; c++) {
    plotBuf[c][idx] = (c < n) ? vals[c] : Float.NaN;
  }

  // Give each channel a name if it does not already have one.
  for (int c = 0; c < n; c++) {
    if (names[c] != null) chName[c] = names[c];
    else if (chName[c] == null) chName[c] = "ch" + (c + 1);
  }

  nCh = max(nCh, n);                           // remember the largest number of channels seen
  plotTotal++;                                 // count this new sample
}

// =====================================================================
// Layout / scrolling helpers
// =====================================================================

// Height-only resizing. Processing can't lock one dimension of a native window, so the
// window itself is not resizable; you drag the grip in the bottom-right corner instead.

// Is the mouse over the small resize grip in the bottom-right corner?
boolean overGrip() {
  return mouseX >= winW - 24 && mouseX < winW && mouseY >= winH - 24 && mouseY < winH;
}

// Draw three diagonal lines to make the resize grip visible.
void drawGrip() {
  stroke(140);
  for (int i = 0; i < 3; i++) {
    int o = 5 + i * 5;                         // each line is a little farther from the corner
    line(winW - o, winH - 3, winW - 3, winH - o);
  }
  noStroke();
}

// When the window height changes, move the parts attached to the bottom.
void applyHeight(int h) {
  winH = h;                                    // update the remembered window height
  sendY = winH - statusH - sendH;              // recalculate the send bar position
  lineEndDD.y = sendY + 5;
  sendBtn.y = sendY + 5;
  updateLayout();
}

// Recalculate the log area whenever the plot or window size changes.
void updateLayout() {
  logTop = toolbarH + (plotCB.checked ? plotH : 0);  // plot takes space only when visible
  logH = winH - logTop - statusH - sendH;            // remaining space is for the log
  firstLine = constrain(firstLine, 0, maxFirst());   // keep scrolling position valid
  if (autoScrollCB.checked) firstLine = maxFirst();  // jump to the bottom if autoscrolling
}

// How many log lines fit on the screen right now?
int visibleLines() {
  return max(1, (logH - 8) / lineH);
}

// The largest valid value for firstLine (the bottom of the log).
int maxFirst() {
  return max(0, log.size() - visibleLines());
}

// Scroll to a particular line, but do not scroll past the ends.
void scrollTo(int v) {
  firstLine = constrain(v, 0, maxFirst());
  autoScrollCB.checked = (firstLine >= maxFirst());   // scrolling to the bottom re-enables autoscroll
}

// Height of the scrollbar handle: smaller handle means more lines exist.
int thumbH() {
  int n = log.size(), v = visibleLines();
  if (n <= v) return logH;                     // everything fits; use the full bar
  return max(24, (int) ((float) logH * v / n));
}

// Vertical position of the scrollbar handle.
int thumbY() {
  int mf = maxFirst();
  if (mf == 0) return logTop;                  // no scrolling needed
  return logTop + (int) ((logH - thumbH()) * (float) firstLine / mf);
}

// =====================================================================
// Drawing
// =====================================================================

// Choose how many decimal places to show, based on the size of the number.
String fmt(float v) {
  float a = abs(v);                            // ignore whether the number is negative
  if (a >= 1000) return String.format("%.0f", v);  // large numbers: no decimals
  if (a >= 100) return String.format("%.1f", v);   // medium numbers: one decimal
  return String.format("%.2f", v);                  // small numbers: two decimals
}

// Draw the live graph.
void drawPlot() {
  if (!plotCB.checked) return;                 // do nothing if the Plot box is unchecked

  int top = toolbarH;                          // plot starts below the toolbar
  noStroke();
  fill(248);
  rect(0, top, winW, plotH);                   // light-grey background for the plot

  stroke(190);
  line(0, top + plotH, winW, top + plotH);     // line under the plot

  // Position and size of the graph area.
  int px = 64, py = top + 14;
  int pw = winW - px - 130, ph = plotH - 14 - 28;
  stroke(150);
  noFill();
  rect(px, py, pw, ph);                        // draw the graph border

  textFont(fontUI, 12);
  int win = plotWindows[plotDD.sel];           // how many samples to display
  int n = (int) min((long) win, plotTotal);    // cannot show more samples than we have

  if (n == 0 || nCh == 0) {
    noStroke();
    fill(140);
    textAlign(CENTER, CENTER);
    text("Waiting for numeric data...", px + pw / 2, py + ph / 2);
    textFont(fontUI, 14);
    return;
  }

  long start = plotTotal - n;                  // first sample number to draw

  // Auto-scale to the data in view
  float lo = Float.MAX_VALUE, hi = -Float.MAX_VALUE;  // smallest and largest values found

  // Look through visible values to find the lowest and highest.
  for (int c = 0; c < nCh; c++) {
    if (chHidden[c]) continue;           // hidden channels don't affect the Y scale
    for (int k = 0; k < n; k++) {
      float v = sample(c, start + k);
      if (!Float.isNaN(v)) {
        if (v < lo) lo = v;                    // new lowest value
        if (v > hi) hi = v;                    // new highest value
      }
    }
  }

  if (lo > hi) {                         // everything in view is a gap
    noStroke();
    fill(140);
    textAlign(CENTER, CENTER);
    text(allChannelsHidden() ? "All channels hidden. Click a legend entry to show it."
                             : "No data in view.", px + pw / 2, py + ph / 2);
    drawLegend();
    textFont(fontUI, 14);
    return;
  }

  if (hi - lo < 1e-9) {                        // all values are almost identical
    lo -= 1;                                   // add a little space so the line is visible
    hi += 1;
  } else {
    float padY = (hi - lo) * 0.05;             // add 5% space above and below the data
    lo -= padY;
    hi += padY;
  }

  // Grid lines and y-axis labels
  textAlign(RIGHT, CENTER);
  for (int i = 0; i <= 4; i++) {
    float gy = py + ph * i / 4.0;              // y position of this grid line
    float val = lerp(hi, lo, i / 4.0);         // value that belongs at this height
    stroke(225);
    line(px, gy, px + pw, gy);                 // draw a horizontal grid line
    noStroke();
    fill(90);
    text(fmt(val), px - 6, gy);                // label the grid line
  }

  // Traces (decimated if there are many more samples than pixels)
  clip(px, py, pw, ph);                        // keep drawing inside the graph box
  noFill();
  strokeWeight(1.5);

  int stride = max(1, n / (2 * pw));           // skip samples if there are too many to draw

  // Draw one colored line for each visible channel.
  for (int c = 0; c < nCh; c++) {
    if (chHidden[c]) continue;                 // skip hidden channels
    stroke(chColor[c]);                        // use this channel's color
    boolean drawing = false;                   // are we currently drawing a line?
    int k = 0;

    while (true) {
      float v = sample(c, start + k);          // get one value

      if (Float.isNaN(v)) {
        if (drawing) { endShape(); drawing = false; }  // missing value ends the line
      } else {
        if (!drawing) { beginShape(); drawing = true; }  // start a new line segment

        // Convert the data value into an x,y position on the screen.
        vertex(px + pw * k / (float) max(1, win - 1), py + ph - (v - lo) / (hi - lo) * ph);
      }

      if (k >= n - 1) break;                   // reached the newest sample
      k = min(n - 1, k + stride);              // move ahead, possibly skipping samples
    }

    if (drawing) endShape();                   // finish the final line segment
  }

  strokeWeight(1);
  noClip();                                    // stop limiting drawing to the graph box

  drawLegend();                          // latest value of each channel; click to hide/show
  drawHoverTip(px, py, pw, ph, lo, hi, start, n, win);   // tooltip for the point under the mouse

  // Footer
  noStroke();
  fill(110);
  textAlign(LEFT, TOP);
  text("Window: " + win + " samples", px, py + ph + 6);
  textAlign(RIGHT, TOP);
  text("Samples received: " + plotTotal, px + pw, py + ph + 6);
  textFont(fontUI, 14);
}

// Show the (x, y) of the data point under the mouse, once the mouse has stopped moving.
// x = the sample number (1 = the first sample after you pressed Connect), y = the value.
void drawHoverTip(int px, int py, int pw, int ph, float lo, float hi, long start, int n, int win) {
  if (millis() - lastMoveMs < hoverDelay) return;   // mouse still moving? wait until it stops

  // Only when the mouse is over the graph box.
  if (mouseX < px || mouseX > px + pw || mouseY < py || mouseY > py + ph) return;

  for (Dropdown d : dds) {
    if (d.listOpen) return;                         // an open menu is in the way, so stay quiet
  }
  if (resizing || draggingThumb || selecting) return;   // busy dragging something else

  float dx = pw / (float) max(1, win - 1);          // pixels between neighbouring samples
  int kMid = round((mouseX - px) / dx);             // the sample (in view) nearest the mouse sideways
  int span = min(n, ceil(hoverRadius / dx));        // how many samples either side could be close enough

  float best = hoverRadius;                         // closest distance found so far, in pixels
  int bestC = -1, bestK = -1;                       // which channel and sample won (-1 = nothing yet)
  float bestX = 0, bestY = 0, bestV = 0;            // where that point is on screen, and its value

  // Check the samples near the mouse, in every visible channel.
  for (int k = max(0, kMid - span); k <= min(n - 1, kMid + span); k++) {
    float x = px + dx * k;                          // screen x of this sample
    for (int c = 0; c < nCh; c++) {
      if (chHidden[c]) continue;                    // hidden channels can't be hovered
      float v = sample(c, start + k);               // the stored value
      if (Float.isNaN(v)) continue;                 // skip gaps
      float y = py + ph - (v - lo) / (hi - lo) * ph;    // screen y of this value
      float gap = dist(mouseX, mouseY, x, y);       // how far is the mouse from this point?
      if (gap < best) {                             // closer than anything so far?
        best = gap;
        bestC = c;
        bestK = k;
        bestX = x;
        bestY = y;
        bestV = v;
      }
    }
  }
  if (bestC < 0) return;                            // nothing close enough, so no tooltip

  // Draw a ring around the point, so you can see which one it is.
  noFill();
  stroke(chColor[bestC]);
  strokeWeight(2);
  ellipse(bestX, bestY, 11, 11);
  strokeWeight(1);

  // The words for the tooltip.
  String l1 = chName[bestC];                                  // the channel name
  String l2 = "x: " + (start + bestK + 1) + "   y: " + fmt(bestV);   // sample number and value
  float tw = max(textWidth(l1) + 32, textWidth(l2) + 16);     // box width, based on the longer line
  float th = 38;                                              // box height (two lines of text)

  // Put the box up and to the right of the point, but keep it inside the graph.
  float bx = bestX + 12;
  float by = bestY - th - 8;
  if (bx + tw > px + pw) bx = bestX - 12 - tw;      // no room on the right? flip to the left
  bx = max(px, bx);
  if (by < py) by = bestY + 12;                     // no room above? go below
  by = min(by, py + ph - th);

  // The box itself.
  fill(255, 255, 255, 240);
  stroke(120);
  rect(bx, by, tw, th, 4);

  // A little colour swatch next to the name.
  stroke(chColor[bestC]);
  strokeWeight(3);
  line(bx + 8, by + 11, bx + 20, by + 11);
  strokeWeight(1);

  // And the text.
  noStroke();
  fill(30);
  textAlign(LEFT, CENTER);
  text(l1, bx + 26, by + 11);
  text(l2, bx + 8, by + 27);
}

// ---------------- Plot legend (click an entry to hide/show that channel) ----------------

// Left edge of the legend, near the right side of the window.
int legendX() {
  return winW - 116;                     // right-hand margin of the plot panel
}

// Vertical position of one legend entry.
int legendY(int c) {
  return toolbarH + 24 + c * 26;
}

// Returns the channel under the mouse in the legend, or -1.
int legendHit() {
  if (!plotCB.checked) return -1;              // no legend if the plot is hidden

  for (int c = 0; c < nCh; c++) {
    if (mouseX >= legendX() - 4 && mouseX <= winW - 2 && abs(mouseY - legendY(c)) <= 12) return c;
  }
  return -1;                                   // mouse is not over any legend entry
}

// Are all channels currently hidden?
boolean allChannelsHidden() {
  for (int c = 0; c < nCh; c++) {
    if (!chHidden[c]) return false;            // found one visible channel
  }
  return true;                                 // none are visible
}

// Draw the list of channel names and their latest values.
void drawLegend() {
  int lx = legendX();
  int hov = legendHit();                       // which entry is the mouse over?

  for (int c = 0; c < nCh; c++) {
    int ly = legendY(c);

    if (c == hov) {                      // hover highlight
      noStroke();
      fill(228, 236, 248);
      rect(lx - 4, ly - 12, winW - lx - 2, 24, 4);
    }

    float latest = plotTotal > 0 ? sample(c, plotTotal - 1) : Float.NaN;  // newest value
    String lbl = chName[c] + ": " + (Float.isNaN(latest) ? "-" : fmt(latest));

    if (chHidden[c]) {
      stroke(190);                       // hollow swatch and greyed text = hidden
      noFill();
      strokeWeight(1);
      rect(lx, ly - 4, 14, 8, 2);
      noStroke();
      fill(160);
    } else {
      stroke(chColor[c]);                        // draw a colored line matching the plot
      strokeWeight(3);
      line(lx, ly, lx + 14, ly);
      strokeWeight(1);
      noStroke();
      fill(30);
    }

    textAlign(LEFT, CENTER);
    String t = fit(lbl, winW - lx - 26);         // shorten the text if it is too long
    text(t, lx + 20, ly);

    if (chHidden[c]) {                   // strike-through
      stroke(160);
      line(lx + 20, ly, lx + 20 + textWidth(t), ly);
      noStroke();
    }
  }
}

// Draw the scrolling text log.
void drawLog() {
  clip(0, logTop, logW, logH);                 // keep text inside the log area
  textFont(fontMono, 14);
  textAlign(LEFT, CENTER);
  noStroke();

  int n = log.size();                          // total number of stored lines
  int last = min(n, firstLine + visibleLines() + 1);  // first line we do NOT need to draw
  boolean sel = hasSelection();
  int[] r = sel ? selRange() : null;           // selection range, if one exists

  // Draw only the visible lines, not every stored line.
  for (int i = firstLine; i < last; i++) {
    LogLine ln = log.get(i);                   // get one stored line
    int y = logTop + 4 + (i - firstLine) * lineH;  // screen position of this line

    if (sel && i >= r[0] && i <= r[2]) {          // highlight the selected part of this line
      int len = ln.text.length();
      int a = (i == r[0]) ? min(r[1], len) : 0;  // first selected character
      int b = (i == r[2]) ? min(r[3], len) : len;  // last selected character
      float wd = (b - a) * charW + (i < r[2] ? charW * 0.5 : 0);  // width of highlight
      if (wd > 0) {
        fill(176, 208, 255);
        rect(pad + a * charW, y, wd, lineH);   // draw the blue selection background
      }
    }

    // Use different colors for system messages, sent text, and received data.
    if (ln.sys) fill(170, 90, 0); else if (ln.sent) fill(20, 90, 170); else fill(30);
    text(ln.text, pad, y + lineH / 2);         // draw the actual text
  }

  noClip();
  textFont(fontUI, 14);
}

// Draw the vertical scrollbar beside the log.
void drawScrollbar() {
  int x = winW - sbW;                          // scrollbar is at the right edge
  noStroke();
  fill(240);
  rect(x, logTop, sbW, logH);                  // scrollbar background

  if (log.size() > visibleLines()) {           // only show a handle if scrolling is possible
    fill(draggingThumb ? 120 : 175);           // darker while being dragged
    rect(x + 2, thumbY(), sbW - 4, thumbH(), 4);
  }
}

// Draw the top toolbar.
void drawToolbar() {
  noStroke();
  fill(235);
  rect(0, 0, winW, toolbarH);                  // toolbar background
  stroke(190);
  line(0, toolbarH, winW, toolbarH);           // line below the toolbar

  fill(30);
  noStroke();
  textAlign(LEFT, CENTER);
  text("Port:", pad, 24);
  text("Baud:", 385, 24);

  // Make the "Window" label grey when the plot is hidden.
  fill(plotCB.checked ? 30 : 150);
  text("Window:", 372, 56);
  text("samples", 532, 56);

  // Draw all toolbar controls.
  portDD.drawBox();
  rescanBtn.show();
  baudDD.drawBox();
  connectBtn.show();
  clearBtn.show();
  copyBtn.show();
  timeStampCB.show();
  autoScrollCB.show();
  plotCB.show();
  plotDD.drawBox();
}

// Draw the bottom status bar.
void drawStatus() {
  int y0 = winH - statusH;                     // top of the status bar
  noStroke();
  fill(225);
  rect(0, y0, winW, statusH);
  stroke(190);
  line(0, y0, winW, y0);
  noStroke();
  fill(30);
  textAlign(LEFT, CENTER);

  // Show connection information, or "Not connected".
  String l1 = connected ? "Connected: " + portName + " @ " + baudRates[baudDD.sel] + " bps"
                        : "Not connected";

  // Show the CSV file being written, or explain that none exists yet.
  String l2 = filename.length() == 0 ? "Log file: (created when you connect)"
            : (connected ? "Logging to: " : "Last log file: ") + sketchPath(filename + ".csv");

  text(l1, pad, y0 + 13);

  if (millis() < flashUntil) {           // short-lived feedback such as "Copied selection"
    fill(0, 110, 0);
    textAlign(RIGHT, CENTER);
    text(flashMsg, winW - pad, y0 + 13);
    fill(30);
    textAlign(LEFT, CENTER);
  }

  text(fit(l2, winW - pad - 30), pad, y0 + 31);  // draw the file path, shortened if needed
}

// Shorten a string with "..." if it is too wide for the available space.
String fit(String s, float maxW) {
  if (textWidth(s) <= maxW) return s;          // it already fits

  while (s.length() > 1 && textWidth(s + "...") > maxW) s = s.substring(0, s.length() - 1);
  return s + "...";                            // remove characters until it fits
}

// =====================================================================
// Input
// =====================================================================

// Runs once every time the user presses the mouse button.
void mousePressed() {
  // An open dropdown gets the first claim on any click
  for (Dropdown d : dds) {
    if (d.listOpen) {
      int r = d.overRow();                     // which menu item was clicked?

      if (r >= 0) {
        d.sel = r;                             // choose that item
        if (d == baudDD) changeBaud();         // changing baud needs a new serial connection
      }
      d.listOpen = false;                      // close the dropdown
      return;
    }
  }

  // Corner grip: start changing the window height
  if (overGrip()) {
    resizing = true;
    grabDY = winH - mouseY;                    // remember where the user grabbed
    sendFocus = false;
    return;
  }

  // Send bar: clicking anywhere outside it drops keyboard focus from the text box
  boolean inSendBar = mouseY >= sendY && mouseY < sendY + sendH;
  if (!inSendBar) sendFocus = false;

  if (sendFieldOver()) { sendFocus = true; return; }         // clicked in the typing box
  if (lineEndDD.overBox()) { lineEndDD.listOpen = true; return; }
  if (sendBtn.enabled && sendBtn.over()) { sendLine(); return; }

  if (portDD.enabled && portDD.overBox()) { portDD.listOpen = true; return; }
  if (baudDD.overBox()) { baudDD.listOpen = true; return; }
  if (plotDD.enabled && plotDD.overBox()) { plotDD.listOpen = true; return; }

  if (rescanBtn.enabled && rescanBtn.over()) { rescanPorts(); return; }

  if (connectBtn.over()) {
    if (connected) disconnect(); else connect();  // one button does both jobs
    return;
  }

  if (copyBtn.over()) { doCopy(); return; }

  if (clearBtn.over()) {
    log.clear();                               // remove all lines from the screen
    clearSel();
    firstLine = 0;
    resetPlot(false);                    // keep channel names
    return;
  }

  if (timeStampCB.over()) { timeStampCB.checked = !timeStampCB.checked; return; }  // toggle

  if (autoScrollCB.over()) {
    autoScrollCB.checked = !autoScrollCB.checked;
    if (autoScrollCB.checked) firstLine = maxFirst();  // jump to newest lines
    return;
  }

  if (plotCB.over()) {
    plotCB.checked = !plotCB.checked;          // turn the plot on or off
    plotDD.enabled = plotCB.checked;
    updateLayout();                            // give the freed space to the log
    return;
  }

  // Plot legend: click an entry to hide or show that channel
  int hit = legendHit();
  if (hit >= 0) {
    chHidden[hit] = !chHidden[hit];            // switch hidden/visible
    return;
  }

  // Scrollbar
  if (mouseX >= winW - sbW && mouseY >= logTop && mouseY < logTop + logH) {
    if (log.size() > visibleLines()) {
      int ty = thumbY();                       // top of the scrollbar handle

      if (mouseY >= ty && mouseY <= ty + thumbH()) {
        draggingThumb = true;                  // start dragging the handle
        dragOffset = mouseY - ty;
      } else if (mouseY < ty) {
        scrollTo(firstLine - visibleLines());  // click above: scroll up one page
      } else {
        scrollTo(firstLine + visibleLines());  // click below: scroll down one page
      }
    }
    return;
  }

  // Click inside the log text area: start a selection
  if (mouseX < logW && mouseY >= logTop && mouseY < logTop + logH) {
    startSelection();
  }
}

// Runs repeatedly while the mouse is held down and moved.
void mouseDragged() {
  if (draggingThumb) {
    int range = logH - thumbH();               // how far the handle can move

    if (range > 0) {
      float r = (mouseY - dragOffset - logTop) / (float) range;  // 0 at top, 1 at bottom
      scrollTo(round(r * maxFirst()));         // move the log to match the handle
    }
  }
}

// Runs when the mouse button is released.
void mouseReleased() {
  draggingThumb = false;
  resizing = false;
  selecting = false;
}

// =====================================================================
// Text selection and copying
// =====================================================================

// Converts a mouse position to {line index, character column}, clamped to the log.
int[] posAt(int mx, int my) {
  int n = log.size();
  if (n == 0) return new int[] { -1, 0 };      // no lines exist

  // Work out which line the mouse is over.
  int ln = constrain(firstLine + floor((my - logTop - 4) / (float) lineH), 0, n - 1);

  // Work out which character in that line the mouse is over.
  int col = constrain(round((mx - pad) / charW), 0, log.get(ln).text.length());
  return new int[] { ln, col };
}

// Start selecting text when the user clicks in the log.
void startSelection() {
  int[] p = posAt(mouseX, mouseY);             // where did the click happen?
  if (p[0] < 0) return;                        // no text to select

  if (mouseEvent != null && mouseEvent.getCount() == 2) {      // double-click: select the whole line
    selAL = p[0]; selAC = 0;
    selBL = p[0]; selBC = log.get(p[0]).text.length();
    return;
  }

  if (keyPressed && key == CODED && keyCode == SHIFT && selAL >= 0) {   // shift-click extends
    selBL = p[0];                              // move only the end of the selection
    selBC = p[1];
  } else {
    selAL = p[0]; selAC = p[1];                // start a brand-new selection
    selBL = p[0]; selBC = p[1];
  }
  selecting = true;
}

// Update the end of the selection while dragging.
void updateSelection() {
  int[] p = posAt(mouseX, mouseY);
  if (p[0] >= 0) {
    selBL = p[0];                              // new ending line
    selBC = p[1];                              // new ending character
  }
}

// Is there currently a selection?
boolean hasSelection() {
  return selAL >= 0 && selBL >= 0 && selAL < log.size() && selBL < log.size()
      && (selAL != selBL || selAC != selBC);   // start and end must not be the same place
}

// Returns {startLine, startCol, endLine, endCol} with start before end.
int[] selRange() {
  boolean aFirst = selAL < selBL || (selAL == selBL && selAC <= selBC);

  // The user may drag upward or downward, so put the earlier point first.
  return aFirst ? new int[] { selAL, selAC, selBL, selBC }
                : new int[] { selBL, selBC, selAL, selAC };
}

// Build one string containing the selected text.
String selectedText() {
  int[] r = selRange();
  StringBuilder sb = new StringBuilder();      // efficient way to build a long string

  for (int i = r[0]; i <= r[2] && i < log.size(); i++) {
    String t = log.get(i).text;
    int a = (i == r[0]) ? min(r[1], t.length()) : 0;  // first character on this line
    int b = (i == r[2]) ? min(r[3], t.length()) : t.length(); // last character on this line
    sb.append(t.substring(a, b));              // add the selected part

    if (i < r[2]) sb.append('\n');             // add a newline between selected lines
  }
  return sb.toString();
}

// Select every line in the log.
void selectAll() {
  int n = log.size();
  if (n == 0) return;                          // nothing to select

  selAL = 0;                                   // first line
  selAC = 0;
  selBL = n - 1;                               // last line
  selBC = log.get(n - 1).text.length();        // end of the last line
}

// Remove the current selection.
void clearSel() {
  selAL = -1;                                  // -1 means "no selection"
  selBL = -1;
  selecting = false;
}

// Show a short status message for 2.5 seconds.
void flash(String s) {
  flashMsg = s;
  flashUntil = millis() + 2500;                // current time plus 2500 milliseconds
}

// Put text on the computer's clipboard.
void copyToClipboard(String s) {
  try {
    Toolkit.getDefaultToolkit().getSystemClipboard().setContents(new StringSelection(s), null);
  } catch (Exception e) {
    flash("Could not access the clipboard.");
  }
}

// Copy button: the selection if there is one, otherwise every data line (notices excluded).
void doCopy() {
  if (hasSelection()) {
    copyToClipboard(selectedText());           // copy only the highlighted text
    flash("Copied selection");
  } else {
    StringBuilder sb = new StringBuilder();
    int count = 0;

    // Copy every data line, but skip orange system messages.
    for (LogLine l : log) {
      if (!l.sys) {
        sb.append(l.text).append('\n');
        count++;
      }
    }
    copyToClipboard(sb.toString());
    flash("Copied " + count + " data lines");
  }
}

// Runs when the user rolls the mouse wheel.
void mouseWheel(processing.event.MouseEvent e) {
  scrollTo(firstLine + e.getCount() * 3);      // scroll 3 lines per wheel click
}

// Runs when the user presses any keyboard key.
void keyPressed() {
  if (sendFocus) {                       // typing goes to the send box
    handleSendKey();
    return;
  }

  // Ctrl+C (Windows/Linux) or Cmd+C (Mac) copies selected text.
  if (keyEvent != null && (keyEvent.isControlDown() || keyEvent.isMetaDown())) {
    if (keyCode == 67) {                                            // Ctrl/Cmd+C
      if (hasSelection()) {
        copyToClipboard(selectedText());
        flash("Copied selection");
      } else {
        flash("Nothing selected. The Copy button copies all data lines.");
      }
    } else if (keyCode == 65) {                                     // Ctrl/Cmd+A
      selectAll();
    }
    return;
  }

  if (key == CODED) {                          // arrow keys and other special keys
    if (keyCode == UP) scrollTo(firstLine - 1);
    else if (keyCode == DOWN) scrollTo(firstLine + 1);
    else if (keyCode == 33) scrollTo(firstLine - visibleLines());   // Page Up
    else if (keyCode == 34) scrollTo(firstLine + visibleLines());   // Page Down
    else if (keyCode == 36) scrollTo(0);                            // Home
    else if (keyCode == 35) scrollTo(maxFirst());                   // End
  }
}

// =====================================================================
// Sending text to the device
// =====================================================================

// Is the mouse over the text box where the user types?
boolean sendFieldOver() {
  return mouseX >= 10 && mouseX <= 10 + sendFieldW && mouseY >= sendY + 5 && mouseY <= sendY + 31;
}

// Draw the bar used to type and send messages.
void drawSendBar() {
  noStroke();
  fill(235);
  rect(0, sendY, winW, sendH);                 // send-bar background
  stroke(190);
  line(0, sendY, winW, sendY);                 // line above the send bar

  int fy = sendY + 5;

  // Blue border means the box is active and ready for typing.
  stroke(sendFocus ? color(30, 120, 200) : color(120));
  fill(255);
  rect(10, fy, sendFieldW, 26, 4);
  noStroke();
  textFont(fontMono, 14);
  textAlign(LEFT, CENTER);

  if (sendText.length() == 0 && !sendFocus) {
    fill(150);
    text(connected ? "Type text to send to the device, then press Enter"
                   : "Connect to a port to send text", 18, fy + 12);
  } else {
    String disp = sendText;

    // If the typed text is too long, hide the oldest characters.
    while (disp.length() > 0 && textWidth(disp) > sendFieldW - 20) disp = disp.substring(1);

    fill(30);
    text(disp, 18, fy + 12);

    if (sendFocus && (millis() / 500) % 2 == 0) {      // blinking caret
      float cx = 18 + textWidth(disp);         // position just after the typed text
      stroke(30);
      line(cx + 1, fy + 5, cx + 1, fy + 21);
      noStroke();
    }
  }

  textFont(fontUI, 14);

  lineEndDD.drawBox();
  sendBtn.enabled = connected;                 // can only send while connected
  sendBtn.show();
}

// Send the typed text to the serial device.
void sendLine() {
  if (!connected || mySerial == null) {
    flash("Connect to a port first.");
    return;
  }

  // Choose the end-of-line characters based on the dropdown setting.
  String eol = "";
  switch (lineEndDD.sel) {
    case 1: eol = "\n"; break;                 // newline
    case 2: eol = "\r"; break;                 // carriage return
    case 3: eol = "\r\n"; break;               // both
  }

  if (sendText.length() == 0 && eol.length() == 0) return;     // nothing to send

  try {
    mySerial.write(sendText + eol);            // send the message to the device
  } catch (Exception e) {
    sysMsg("Could not send. Check the connection.");
    return;
  }

  // Echo into the log (and file) so the transcript shows both directions
  String s = "> " + sendText;                  // "> " marks a message you sent

  if (timeStampCB.checked) {
    s = nf(hour(), 2) + ":" + nf(minute(), 2) + ":" + nf(second(), 2) + ", " + s;
  }

  LogLine l = new LogLine(s, false);
  l.sent = true;                               // mark it as sent, so it appears blue
  log.add(l);

  if (logSentToFile && output != null) {
    output.println(s);                         // save the sent message in the CSV too
    output.flush();
  }

  // Save this message in history, unless it is the same as the last one.
  if (sendText.length() > 0
      && (sendHistory.size() == 0 || !sendHistory.get(sendHistory.size() - 1).equals(sendText))) {
    sendHistory.add(sendText);
  }

  histPos = sendHistory.size();                // ready to look backward through history
  sendText = "";                               // clear the typing box
}

// Handle keys typed while the send box is active.
void handleSendKey() {
  boolean mod = keyEvent != null && (keyEvent.isControlDown() || keyEvent.isMetaDown());

  if (key == ESC) {                      // Esc leaves the box instead of quitting the sketch
    key = 0;
    sendFocus = false;
    return;
  }

  if (key == ENTER || key == RETURN) {
    sendLine();                                // Enter sends the message
    return;
  }

  if (key == BACKSPACE) {
    if (sendText.length() > 0) sendText = sendText.substring(0, sendText.length() - 1);  // delete one character
    return;
  }

  if (key == CODED) {
    if (keyCode == UP) historyBack();          // see an earlier sent message
    else if (keyCode == DOWN) historyForward();  // see a later sent message
    return;
  }

  if (mod) {
    if (keyCode == 86) pasteIntoField();                        // Ctrl/Cmd+V
    return;
  }

  if (key >= ' ' && key <= '~') sendText += key;  // add normal typed characters
}

// Move backward through previously sent messages.
void historyBack() {
  if (sendHistory.size() == 0) return;         // no history yet
  histPos = max(0, histPos - 1);               // move one item older
  sendText = sendHistory.get(histPos);         // put that old message in the box
}

// Move forward through previously sent messages.
void historyForward() {
  if (histPos < sendHistory.size() - 1) {
    histPos++;                                 // move one item newer
    sendText = sendHistory.get(histPos);
  } else {
    histPos = sendHistory.size();              // past the newest item
    sendText = "";                             // show an empty box again
  }
}

// Paste text from the clipboard into the send box.
void pasteIntoField() {
  try {
    Transferable t = Toolkit.getDefaultToolkit().getSystemClipboard().getContents(null);

    if (t != null && t.isDataFlavorSupported(DataFlavor.stringFlavor)) {
      String s = (String) t.getTransferData(DataFlavor.stringFlavor);  // get clipboard text
      int nl = s.indexOf('\n');
      int cr = s.indexOf('\r');
      int cut = (nl < 0) ? cr : (cr < 0 ? nl : min(nl, cr));

      if (cut >= 0) {                    // a send is one line; keep only the first
        s = s.substring(0, cut);
        flash("Only the first line was pasted.");
      }

      StringBuilder clean = new StringBuilder();

      // Keep only normal visible characters.
      for (int i = 0; i < s.length(); i++) {
        char c = s.charAt(i);
        if (c >= ' ' && c <= '~') clean.append(c);
      }
      sendText += clean.toString();              // add the cleaned text to the box
    }
  } catch (Exception e) {
    flash("Could not read the clipboard.");
  }
}

// Runs when the program is about to close.
void exit() {                    // make sure the file closes
  disconnect();                                  // safely close the serial port and CSV file

  if (filename.length() > 0) {
    println("Saved log file: " + sketchPath(filename + ".csv") + ". You may now close Processing.");
  }
  super.exit();                                  // let Processing finish closing
}

// =====================================================================
// Minimal widgets
// =====================================================================

// A dropdown menu, such as the Port or Baud menu.
class Dropdown {
  int x, y, w, h;                              // position and size
  String[] items = new String[0];              // choices in the menu
  int sel = 0;                                 // which choice is selected
  boolean listOpen = false;                    // is the menu currently open?
  boolean enabled = true;                      // can the user click it?
  int rowH = 24;                               // height of one menu choice
  boolean upward = false;        // true = list opens above the box (for widgets at the bottom)

  // Where should the open menu start?
  int listTop() {
    return upward ? y - items.length * rowH : y + h;
  }

  // Constructor: set the dropdown's position and size.
  Dropdown(int x, int y, int w, int h) {
    this.x = x; this.y = y; this.w = w; this.h = h;
  }

  // Replace the menu choices.
  void setItems(String[] it) {
    items = it;
    if (sel >= items.length) sel = max(0, items.length - 1);  // keep selection valid
  }

  // Return the text of the currently selected choice.
  String selected() {
    return items.length > 0 ? items[sel] : "";
  }

  // Draw the closed dropdown box.
  void drawBox() {
    stroke(enabled ? 120 : 190);
    fill(enabled ? 255 : 240);
    rect(x, y, w, h, 4);
    noStroke();
    fill(enabled ? 30 : 150);
    textAlign(LEFT, CENTER);
    String s = items.length > 0 ? items[sel] : "(no ports found)";
    text(fit(s, w - 34), x + 8, y + h / 2 - 1);
    triangle(x + w - 20, y + h / 2 - 3, x + w - 10, y + h / 2 - 3, x + w - 15, y + h / 2 + 4);  // little arrow
  }

  // Draw the open list of choices.
  void drawList() {
    if (!listOpen) return;                     // nothing to draw if closed
    int r = overRow();                         // item under the mouse

    for (int i = 0; i < items.length; i++) {
      int ry = listTop() + i * rowH;           // y position of this choice
      stroke(120);
      fill(i == r ? color(200, 220, 245) : (i == sel ? color(235, 242, 250) : 255));
      rect(x, ry, w, rowH);
      noStroke();
      fill(30);
      textAlign(LEFT, CENTER);
      text(fit(items[i], w - 16), x + 8, ry + rowH / 2 - 1);
    }
  }

  // Is the mouse over the closed dropdown box?
  boolean overBox() {
    return mouseX >= x && mouseX <= x + w && mouseY >= y && mouseY <= y + h;
  }

  // Which open-menu row is under the mouse? Returns -1 if none.
  int overRow() {
    if (!listOpen || mouseX < x || mouseX > x + w) return -1;
    int top = listTop();
    if (mouseY < top) return -1;
    int r = (mouseY - top) / rowH;             // calculate the row number
    return (r >= 0 && r < items.length) ? r : -1;
  }
}

// A simple clickable button.
class Button {
  int x, y, w, h;                              // position and size
  String label;                                // text shown on the button
  boolean enabled = true;                      // can it be clicked?

  Button(int x, int y, int w, int h, String label) {
    this.x = x; this.y = y; this.w = w; this.h = h; this.label = label;
  }

  // Draw the button.
  void show() {
    boolean hov = enabled && over();           // is the mouse hovering over it?

    stroke(enabled ? 120 : 190);
    fill(!enabled ? 238 : (hov ? (mousePressed ? 190 : 215) : 247));  // darker when pressed
    rect(x, y, w, h, 4);
    noStroke();
    fill(enabled ? 30 : 150);
    textAlign(CENTER, CENTER);
    text(label, x + w / 2, y + h / 2 - 1);
  }

  // Is the mouse over this button?
  boolean over() {
    return mouseX >= x && mouseX <= x + w && mouseY >= y && mouseY <= y + h;
  }
}

// A tick box that can be checked or unchecked.
class Checkbox {
  int x, y;                                    // position
  String label;                                // text beside the box
  boolean checked = false;                     // true when ticked

  Checkbox(int x, int y, String label) {
    this.x = x; this.y = y; this.label = label;
  }

  // Draw the checkbox and its label.
  void show() {
    stroke(120);
    fill(255);
    rect(x, y, 16, 16, 3);                     // empty box

    if (checked) {
      stroke(30, 120, 200);
      strokeWeight(2);
      line(x + 3, y + 8, x + 7, y + 12);       // first half of the check mark
      line(x + 7, y + 12, x + 13, y + 4);      // second half of the check mark
      strokeWeight(1);
    }

    noStroke();
    fill(30);
    textAlign(LEFT, CENTER);
    text(label, x + 24, y + 7);
  }

  // Is the mouse over the checkbox or its label?
  boolean over() {
    return mouseX >= x && mouseX <= x + 24 + textWidth(label) && mouseY >= y && mouseY <= y + 16;
  }
}
