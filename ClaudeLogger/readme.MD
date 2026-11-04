# ClaudeLogger

A serial data logger, scrolling monitor and live plotter for Arduino (and any other device that prints lines of text over a serial port), written in [Processing](https://processing.org/).

I uploaded PortLogger to Claude.AI and said "how nuts can we go?" The results are this incredibly useful logging program.

With a few prompts, you can select ports, scroll through logging output, auto scroll, and plot the data in real time.

<!-- TODO: add a screenshot of the window with a couple of channels plotting, e.g. ![ClaudeLogger screenshot](screenshot.png) -->

## Features

- **Port and baud rate dropdowns.** Pick your port from a list (with a Rescan button) and choose a baud rate from 300 to 2,000,000. The baud rate can be changed while connected.
- **CSV logging.** Every time you press Connect, a new timestamped `.csv` file is created in the sketch folder. The full path is shown at the bottom of the window.
- **Scrollable history.** Scroll back through everything received with the mouse wheel, the scrollbar, or the keyboard. Autoscroll follows new data and turns itself off when you scroll up (and back on when you reach the bottom), like the Arduino IDE's Serial Monitor.
- **Timestamp tick box.** Optionally add a `HH:MM:SS` timestamp to every line, on screen and in the file.
- **Select and copy.** Click and drag to select text from the log, then copy it to paste into a spreadsheet or document.
- **Live plot.** Numeric columns are plotted in real time, up to 8 channels, with automatic Y scaling and an adjustable window (100 to 5000 samples). Click a legend entry to hide or show a channel.

## Requirements

- [Processing 4](https://processing.org/download) (the Serial library is included with Processing, so there is nothing else to install)
- A device that sends text lines over a serial port, such as an Arduino

## Quick start

1. Download `ClaudeLogger.pde` and put it in a folder named `ClaudeLogger`. Processing requires the folder name to match the `.pde` file name.
2. Open the file in Processing and press Run.
3. Choose your port and baud rate (match the `Serial.begin()` value in your Arduino sketch) and press **Connect**.
4. **Close the Arduino IDE's Serial Monitor and Serial Plotter first.** Only one program can use a port at a time.

Each line your device sends should end with a newline, which `Serial.println()` does for you.

## Controls

| Action | How |
|---|---|
| Scroll the log | Mouse wheel, drag the scrollbar, or Up / Down / Page Up / Page Down / Home / End |
| Resume following new data | Tick **Autoscroll**, or scroll to the bottom |
| Select text | Click and drag in the log (Shift-click extends, double-click selects a line) |
| Copy | Ctrl+C (Cmd+C on a Mac) copies the selection |
| Select all | Ctrl+A (Cmd+A on a Mac) |
| Copy button | Copies the selection, or every data line if nothing is selected |
| Clear | Clears the screen and the plot (the CSV file is not affected) |
| Hide / show a plot channel | Click its entry in the legend |

## What the plot understands

The plot reads one sample per line. These formats all work:

```
12.5,30,7.1            comma or semicolon separated columns
12.5 30 7.1            space separated columns
temp:12.5,hum:30       name:value pairs (the names appear in the legend)
temp,hum,pressure      a header line of names, before the first line of data
```

Columns that are not numbers leave a gap in that channel's line, and lines with no numbers at all (such as start-up messages) are logged but not plotted. The timestamp option never affects the plot.

Tip: if one channel has a much larger range than the others (for example a counter that keeps increasing), click its legend entry to hide it and the plot will rescale to the rest. Hidden channels are still logged.

## Try it without any sensors

Upload this to an Arduino to get two smoothly changing channels:

```cpp
void setup() {
  Serial.begin(9600);
}

void loop() {
  Serial.print("temp:");
  Serial.print(20 + 2 * sin(millis() / 2000.0));
  Serial.print(",hum:");
  Serial.println(40 + 5 * cos(millis() / 3000.0));
  delay(100);
}
```

## Good to know

- The window keeps the most recent 50,000 lines. The CSV file keeps everything.
- If no data arrives for 5 seconds, a notice appears in the log (notices are shown in orange and are never written to the file).
- Non-printable characters, including tabs, are dropped from incoming lines.
- A few settings (default baud rate, timeout, number of lines kept, plot sizes) are near the top of the sketch.

### Mac and Linux notes

- On Apple Silicon Macs, use Processing 4.
- Macs list each board twice, as `/dev/cu.usbmodem...` and `/dev/tty.usbmodem...`. Choose the `cu` one.
- Keep the sketch folder somewhere you can write to, such as `Documents/Processing`, since the CSV files are saved next to the sketch.
- Some low-cost Arduino clones need a CH340 USB driver before their port appears.

If something doesn't work on your system, please open an issue and include the text from Processing's console, your operating system, and your Processing version.

## Credits

Written by Claude.AI (Sonnet 5.5), prompted by and tested with a real Arduino. Based on the original serial logger by David Dubins.

## License

<!-- TODO: choose a license and state it here. Check the licensing of the original sketch this is based on. -->
