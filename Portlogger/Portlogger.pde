// Serial logger (CSV format) for Arduino.
// Written by: David Dubins
// Last Updated: 5-Jun-2020
// This sketch will save data collected on the selected com port in the same
// directory as this sketch. Make sure each line of your transmitted data ends with a
// new line (\n).

int timeOut=5;             // max #seconds to timeout the monitor. Set this to be
                           // greater than the largest interval you are expecting
                           // between measurements (at least 3xsampling interval 
                           // to be safe).
boolean timeStamp=false;   // if you'd like to add a timestamp to the incoming data
String portName = "COM4";  // to store the port name.
                           // Enter the port name that your MCU is connected to.
                           // Look in the Arduino IDE port list, or run this
                           // program once to see a listing of available ports.
                           // Make sure your Serial Monitor/Serial Plotter
                           // is closed before running. Only one device can access
                           // a COM port at a time.             
//int portNum=0;           // to store the port number (not used here, alternate method)

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
int yLim=600;               // height of Serial Monitor window

void settings(){
  size(xLim,yLim);          // If you declare window size in settings(),
}                           // you get to declare the dimensions as variables.

void setup() {
  filename = year() + nf(month(),2) + nf (day(),2) + "-" + nf(hour(),2) + nf(minute(),2) + nf(second(),2);
  output = createWriter( filename + ".csv" );  // can change to .CSV here
  f = createFont("Arial",16,true); // Arial, 16 point, anti-aliasing on
  textFont(f,16);           // set the font
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
    String pInfo="["+i+"] "+Serial.list()[i];
    if(Serial.list()[i].equals(portName)){
      pInfo+=" <- PORT SELECTED";
    }
    text(pInfo,10,y+=yStep);
  }
  if(checkPort(portName)){  // if portName is a valid port
    mySerial = new Serial(this, portName, 9600); // open the port
  }else{
    print("Could not open "+ portName+". "); // let user know stuff
    exit(); //leave the sketch
  }  
  //Alternately you can open up a Serial connection using the port number here:
  //portName=Serial.list()[portNum];  // get the name of the port
  //mySerial = new Serial( this, Serial.list()[portNum], 9600 ); // the number in square brackets is the port number
  text("Saving serial data from "+ portName+" to " + filename + ".csv",10,y+=2*yStep); // let user know stuff
  text("Close this window to stop logging.",10,y+=yStep);
  textAlign(LEFT); 
}

void draw() {
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
  output.flush();
  output.close();
  if(checkPort(portName)){   // if the portName is valid
    println("Saved log file: "+filename+".csv. You may now close Processing.");
  }else{
    println(" Please change portName to one of the ports listed above.");
    println("Make sure your Serial Monitor/Plotter is closed.");
  }
  super.exit();
}

/*void keyPressed() {  // uncomment for a "Press any key to stop logging" routine
  output.flush();
  output.close();
  println("Saved log file: "+filename+".csv. You may now close Processing.");
  super.exit();
}*/

void clearScreen(){
  background(255);          // set the background colour (0=black, 255=white)
  fill(50);                 // set text colour to dark grey (0=black, 255=white)
  y=0;                      // go back to top of screen
  text("Saving serial data from "+ portName+" to " + filename + ".csv",10,y+=yStep);
  text("Close this window to stop logging.",10,y+=yStep);
}

boolean checkPort(String pname){
  boolean found=false;
  for(int i=0;i<numPorts;i++){
    if(Serial.list()[i].equals(pname)){  //if pname exists, return true
      return true;          // .equals() command in processing compares two strings.
    }
  }
  return false;             // otherwise, return false
}
