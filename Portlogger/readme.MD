Portlogger.pde evolved as a sketch in the Processing language to receive data from the serial monitor and print it to a screen window, as well as write it to a log file in the same directory as the sketch.

There is a little bit of an interface in the sketch to list the active ports if the port in the sketch is not found.

Make sure you select the correct COM port in the sketch, and that your transmitted data ends with a new line code (\n).
This is taken care of in the Arduino IDE if you use the Serial.println() command.
