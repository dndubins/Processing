// Serial logger (CSV format) for Arduino.
// Written by: David Dubins
// Last Updated: 04-Nov-2026
// Serial port selection menu drawPortList() added using Claude.AI Sonnet 5.5 Medium
// This sketch will save data collected on the selected com port in the same
// directory as this sketch. Make sure each line of your transmitted data ends with a
// new line (\n).

int timeOut=61;             // max #seconds to timeout the monitor. Set this to be
                            // greater than the largest interval you are expecting
                            // between measurements (at least 3xsampling interval 
                            // to be safe).
boolean timeStamp=false;    // if you'd like to add a timestamp to the incoming data
String portName = "";       // to store the port name.
                            // Make sure your Serial Monitor/Serial Plotter
                            // is closed before running. Only one device can access
                            // a COM port at a time.
boolean portSelected=false; // keep track of port being selected
int serialBaud=9600;        // change to match baud rate of device

import processing.serial.*; // import the serial library in Processing
Serial mySerial;            // declare a device called mySerial

PFont f;                    // to store the font type
int y=45;                   // y is used as an index variable for verticle position in the draw window.
int numPorts=0;             // to store the number of ports for drawing them
String filename;            // used to create a unique filename
long t=millis();            // to hold time, for measuring time-outs
String ts;                  // used to hold time stamp string
PrintWriter output;         // needed to print to a file
int yStep=20;               // vertical spacing between output lines
int xLim=700;               // width of Serial Monitor window
int yLim=650;               // height of Serial Monitor window

void settings(){
  size(xLim,yLim);          // If you declare window size in settings(),
}                           // you get to declare the dimensions as variables.

void setup() {
  f = createFont("Arial",16,true); // Arial, 16 point, anti-aliasing on
  textFont(f,16);           // set the font
  textAlign(LEFT);
  println("Available ports:");
  printArray(Serial.list());
  drawPortList("");
  /*
  background(255);          // set the background colour (0=black, 255=white)
  fill(50);                 // set text colour to dark grey (0=black, 255=white)
                            // you can use r,g,b colours in processing
                            // Use https://www.google.com/search?q=color+picker
                            // to pick your colours. e.g. fill(212,15,15) is red.
  y=0;                      // start at the top of the screen
  println("Available ports:");
  printArray(Serial.list());// to print list of available serial ports to black window
  text("Available ports:",10,y+=yStep);
  numPorts=Serial.list().length;
  for(int i=0;i<numPorts;i++){
    text("["+i+"] "+Serial.list()[i],10,y+=yStep);
  }
  if(numPorts==0){
    text("No serial ports found. Plug in your device and restart.",10,y+=2*yStep);
  }else{
    text("Press the number key of the port you want to log.",10,y+=2*yStep);
  }*/

}

void draw() {
  if(!portSelected) return;   // wait until a port has been chosen
  while(mySerial.available()>0) {
    String value="";
    char x=0;
    do {
      int val=mySerial.read();
      x=(char)val;
      if((' '<=x)&&(x<='~')){ // skip any non-printable characters
        value+=x;
      }
    }while(x!='\n'&&x!='\r'&&((millis()-t)<(timeOut*1000))); // stop when you get a new line, carriage return,
                                                             // or you've waited too long     
    if(value.length()>0){    // if you have something more than a blank line                                                        
      if(timeStamp){         // print timestamp if needed
        ts=nf(hour(),2)+":"+nf(minute(),2)+":"+nf(second(),2)+", "; //edit as required
        output.print(ts);
      }
      output.println(value); // Prints to file. Choose print or println here, depending on what you want
      if(y>yLim-yStep){ // If you get to the bottom, start again. Make this # match window length
        clearScreen();
      }
      y+=yStep;              // move down one space
      if(timeStamp){
        text(ts+value,10,y); // prints value to screen to coordinates x,y
      }else{
        text(value,10,y);    // prints value to screen to coordinates x,y
      }                      // end if (output.length()>0)
    }                        // end of printing to file and screen routine   
    t=millis();              //reset the timer for receiving data
}                            // end of receiving serial data routine
  if((millis()-t)>(timeOut*1000)){  // let user know if no info received
    if(y>yLim-yStep){
      clearScreen();         // clear screen when you reach the bottom
    }
    y+=yStep;                // move down to the next line
    text("Communications timed out. Check port connection.",10,y);
    t=millis();              //reset the timer
  }
}

void exit() {                //make sure the file closes
  if(output!=null){
    output.flush();
    output.close();
    println("Saved log file: "+sketchPath(filename+".csv")+". You may now close Processing.");
  }
  super.exit();
}

void keyPressed() {
  if(portSelected) return;
  int sel = key - '0';
  if(sel>=0 && sel<=9 && sel<numPorts){
    String candidate = Serial.list()[sel];
    try {
      mySerial = new Serial(this, candidate, serialBaud);
    } catch (Exception e) {
      mySerial = null;
      drawPortList("Could not open "+candidate+". Close any Serial Monitor/Plotter using it, then pick again.");
      return;
    }
    // Port opened successfully, so now create the file
    portName = candidate;
    filename = year() + nf(month(),2) + nf(day(),2) + "-" + nf(hour(),2) + nf(minute(),2) + nf(second(),2);
    output = createWriter(filename + ".csv");
    background(255);
    fill(50);
    y=0;
    text("Saving serial data from "+portName+" to "+filename+".csv at "+serialBaud+" bps.",10,y+=yStep);
    text("Log file path: "+sketchPath(filename+".csv"),10,y+=yStep);
    text("Close this window to stop logging.",10,y+=yStep);
    t=millis();
    portSelected=true;
  }else if(numPorts==0){
    drawPortList("");                 // any key rescans when no ports were found
  }
}

void clearScreen(){
  background(255);          // set the background colour (0=black, 255=white)
  fill(50);                 // set text colour to dark grey (0=black, 255=white)
  y=0;                      // go back to top of screen
  text("Saving serial data from "+ portName+" to " + filename + ".csv at "+serialBaud+" bps.",10,y+=yStep);
  text("Log file path: "+sketchPath(filename+".csv"),10,y+=yStep);
  text("Close this window to stop logging.",10,y+=yStep);
}

void drawPortList(String msg) {
  background(255);          // set the background colour (0=black, 255=white)
  fill(50);                 // set text colour to dark grey (0=black, 255=white)
                            // you can use r,g,b colours in processing
                            // Use https://www.google.com/search?q=color+picker
                            // to pick your colours. e.g. fill(212,15,15) is red.
  y=0;                      // start at the top of the screen
  numPorts=Serial.list().length;      // refresh, in case a device was plugged in
  text("Available ports:",10,y+=yStep);
  for(int i=0;i<numPorts;i++){
    text("["+i+"] "+Serial.list()[i],10,y+=yStep);
  }
  if(numPorts==0){
    text("No serial ports found. Plug in your device and press any key to rescan.",10,y+=2*yStep);
  }else{
    text("Press the number key of the port you want to log.",10,y+=2*yStep);
  }
  if(msg.length()>0){
    fill(200,0,0);                    // red error text
    text(msg,10,y+=2*yStep);
    fill(50);
  }
}
