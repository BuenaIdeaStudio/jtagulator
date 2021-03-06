{{
┌─────────────────────────────────────────────────┐
│ JTAGulator                                      │
│                                                 │
│ Author: Joe Grand                               │                     
│ Copyright (c) 2013-2016 Grand Idea Studio, Inc. │
│ Web: http://www.grandideastudio.com             │
│                                                 │
│ Distributed under a Creative Commons            │
│ Attribution 3.0 United States license           │
│ http://creativecommons.org/licenses/by/3.0/us/  │
└─────────────────────────────────────────────────┘

Program Description:

The JTAGulator is a hardware tool that assists in identifying on-chip
debug/programming interfaces from test points, vias, component pads,
and/or connectors on a target device.

Refer to the project page for more details:

http://www.jtagulator.com

Each interface object contains the low-level routines and operational details
for that particular on-chip debugging interface. This keeps the main JTAGulator
object a bit cleaner. 

Command listing is available in the DAT section at the end of this file.

}}


CON
  _clkmode = xtal1 + pll16x
  _xinfreq = 5_000_000           ' 5 MHz clock * 16x PLL = 80 MHz system clock speed 
  _stack   = 256                 ' Ensure we have this minimum stack space available        

  ' Serial terminal
  ' Control characters
  LF    = 10  ''LF: Line Feed
  CR    = 13  ''CR: Carriage Return
  CAN   = 24  ''CAN: Cancel (Ctrl-X)


CON
  ' UI
  MAX_INPUT_LEN = 12   ' Maximum length of command
  
  ' JTAG/IEEE 1149.1
  MAX_NUM_JTAG  = 32   ' Maximum number of devices allowed in a single JTAG chain

  ' UART/Asynchronous Serial
  MAX_LEN_UART  = 16   ' Maximum number of bytes to receive from target

  ' Menu
  MENU_MAIN     = 0    ' Main/Top
  MENU_JTAG     = 1    ' JTAG
  MENU_UART     = 2    ' UART
  MENU_GPIO     = 3    ' General Purpose I/O
   
  
VAR                   ' Globally accessible variables
  byte vCmd[MAX_INPUT_LEN + 1]  ' Buffer for command input string
  long vTargetIO      ' Target I/O voltage (for example, 18 = 1.8V)
  
  long jTDI           ' JTAG pins (must stay in this order)
  long jTDO
  long jTCK
  long jTMS
  long jTRST
  long jIR            ' Most recent instruction (IR) and data (DR) for OPCODE_Known
  long jDR
  long jPinsKnown     ' Parameter for BYPASS_Scan
  long jIgnoreReg     ' Parameter for OPCODE_Discovery
  
  long uTXD           ' UART pins (as seen from the target) (must stay in this order)
  long uRXD
  long uBaud
  byte uSTR[MAX_INPUT_LEN + 1]    ' User text buffer for UART_Scan        
  long uBaudMin       ' Parameters for UART_Scan_TX
  long uBaudMax
  long uWaitPerBaud
  long uLoopPerChan
  long uLoopPause
  long uLocalEcho     ' Parameter for UART_Passthrough

  long gWriteValue    ' Parameter for Write_IO_Pins
  
  long chStart        ' Channel range for the current scan (specified by the user)
  long chEnd
  
  long idMenu         ' Menu ID of currently active menu
  
  
OBJ
  g             : "JTAGulatorCon"     ' JTAGulator global constants
  u             : "JTAGulatorUtil"    ' JTAGulator general purpose utilities
  ser           : "PropSerial"        ' Serial communication for user interface (modified version of built-in Parallax Serial Terminal)
  rr            : "RealRandom"        ' Random number generation (Chip Gracey, http://obex.parallax.com/object/498) 
  jtag          : "PropJTAG"          ' JTAG/IEEE 1149.1 low-level functions
  uart          : "JDCogSerial"       ' UART/Asynchronous Serial communication engine (Carl Jacobs, http://obex.parallax.com/object/298)
  
  
PUB main | cmd
  System_Init                   ' Initialize system/hardware
  JTAG_Init                     ' Initialize JTAG-specific items
  UART_Init                     ' Initialize UART-specific items
  GPIO_Init                     ' Initialize GPIO-specific items

  ser.CharIn                    ' Wait until the user presses a key before getting started
  ser.Str(@InitHeader)          ' Display header

  ' Start command receive/process cycle
  repeat
    UART.Stop                      ' Disable UART cog (if it was running)
    u.TXSDisable                   ' Disable level shifter outputs (high-impedance)
    u.LEDGreen                     ' Set status indicator to show that we're ready
    Display_Command_Prompt         ' Display command prompt
    ser.StrInMax(@vCmd,  MAX_INPUT_LEN) ' Wait here to receive a carriage return terminated string or one of MAX_INPUT_LEN bytes (the result is null terminated) 
    u.LEDRed                            ' Set status indicator to show that we're processing a command

    if (strsize(@vCmd) == 1)       ' Only single character commands are supported...
      cmd := vCmd[0]
      
      case idMenu
        MENU_MAIN:                    ' Main/Top
          Do_Main_Menu(cmd)
      
        MENU_JTAG:                    ' JTAG/IEEE 1149.1
          Do_JTAG_Menu(cmd)

        MENU_UART:                    ' UART/Asynchronous Serial
          Do_UART_Menu(cmd)

        MENU_GPIO:                    ' General Purpose I/O
          Do_GPIO_Menu(cmd)

        other:
          idMenu := MENU_MAIN
          Do_Main_Menu(cmd)

    else
      Display_Invalid_Command


CON {{ MENU METHODS }}

PRI Do_Main_Menu(cmd)
  case cmd
    "J", "j":                 ' Switch to JTAG submenu
      idMenu := MENU_JTAG

    "U", "u":                 ' Switch to UART submenu
      idMenu := MENU_UART

    "G", "g":                 ' Switch to GPIO submenu
      idMenu := MENU_GPIO

    "V", "v":                 ' Set target I/O voltage
      Set_Target_IO_Voltage
      
    "I", "i":                 ' Display JTAGulator version information
      ser.Str(@VersionInfo) 

    "H", "h":                 ' Display list of available commands
      Display_Menu_Text

    other:
      Display_Invalid_Command


PRI Do_JTAG_Menu(cmd)
  case cmd
    "I", "i":                 ' Identify JTAG pinout (IDCODE Scan)
      if (vTargetIO == -1)
        ser.Str(@ErrTargetIOVoltage)
      else
        IDCODE_Scan
         
    "B", "b":                 ' Identify JTAG pinout (BYPASS Scan)
      if (vTargetIO == -1)
       ser.Str(@ErrTargetIOVoltage)
      else
        BYPASS_Scan
            
    "D", "d":                 ' Get JTAG Device IDs (Pinout already known)
      if (vTargetIO == -1)
        ser.Str(@ErrTargetIOVoltage)
      else
        IDCODE_Known
         
    "T", "t":                 ' Test BYPASS (TDI to TDO) (Pinout already known)
      if (vTargetIO == -1)
        ser.Str(@ErrTargetIOVoltage)
      else
        BYPASS_Known

    "Y", "y":                 ' Instruction/Data Register discovery (Pinout already known, requires single device in the chain)
      if (vTargetIO == -1)
        ser.Str(@ErrTargetIOVoltage)
      else
        OPCODE_Discovery

    "X", "x":                 ' Transfer instruction/data (Pinout already known, requires single device in the chain)
      if (vTargetIO == -1)
        ser.Str(@ErrTargetIOVoltage)
      else
        OPCODE_Known
                
    other:
      Do_Shared_Menu(cmd)
                  

PRI Do_UART_Menu(cmd)
  case cmd
    "U", "u":                 ' Identify UART pinout
      if (vTargetIO == -1)
        ser.Str(@ErrTargetIOVoltage)
      else
        UART_Scan
        
    "T", "t":                 ' Identify UART pinout (TXD only, user configurable)
      if (vTargetIO == -1)
        ser.Str(@ErrTargetIOVoltage)
      else
        UART_Scan_TXD

    "P", "p":                 ' UART passthrough
      if (vTargetIO == -1)
        ser.Str(@ErrTargetIOVoltage)
      else
        UART_Passthrough

    other:
      Do_Shared_Menu(cmd)
                

PRI Do_GPIO_Menu(cmd)
  case cmd
    "R", "r":                 ' Read all channels (input, one shot)
      if (vTargetIO == -1)
        ser.Str(@ErrTargetIOVoltage)
      else
        Read_IO_Pins

    "C", "c":                 ' Read all channels (input, continuous)
      if (vTargetIO == -1)
        ser.Str(@ErrTargetIOVoltage)
      else
        Monitor_IO_Pins
         
    "W", "w":                 ' Write all channels (output)
      if (vTargetIO == -1)
        ser.Str(@ErrTargetIOVoltage)
      else
        Write_IO_Pins

    other:
      Do_Shared_Menu(cmd)


PRI Do_Shared_Menu(cmd)
  case cmd
    "V", "v":                 ' Set target I/O voltage
      Set_Target_IO_Voltage
          
    "H", "h":                 ' Display list of available commands
      Display_Menu_Text

    "M", "m":                 ' Return to main menu
      idMenu := MENU_MAIN
      
    other:
      Display_Invalid_Command
         

PRI Display_Menu_Text
  case idMenu
    MENU_MAIN:
      ser.Str(@MenuMain)

    MENU_JTAG:
      ser.Str(@MenuJTAG)

    MENU_UART:
      ser.Str(@MenuUART)

    MENU_GPIO:
      ser.Str(@MenuGPIO)

  if (idMenu <> MENU_MAIN)
    ser.Str(@MenuShared)

    
PRI Display_Command_Prompt 
  ser.Str(String(CR, LF, LF))
  
  case idMenu
    MENU_MAIN:             ' Main/Top, don't display any prefix/header 
      
    MENU_JTAG:             ' JTAG
      ser.Str(String("JTAG"))

    MENU_UART:             ' UART
      ser.Str(String("UART"))

    MENU_GPIO:             ' General Purpose I/O
      ser.Str(String("GPIO"))

    other:
      idMenu := MENU_MAIN
        
  ser.Str(String("> "))
  

PRI Display_Invalid_Command
  ser.Str(String(CR, LF, "?"))
  
       
CON {{ JTAG METHODS }}

PRI JTAG_Init
  rr.start         ' Start RealRandom cog (used during BYPASS test)

  ' Set default parameters
  ' BYPASS_Scan
  jPinsKnown := 0

  ' OPCODE_Discovery
  jIgnoreReg := 1

  
PRI IDCODE_Scan | value, value_new, ctr, num, xtdo, xtck, xtms    ' Identify JTAG pinout (IDCODE Scan)
  if (Get_Channels(3) == -1)   ' Get the channel range to use
    return
  Display_Permutations((chEnd - chStart + 1), 3)  ' TDO, TCK, TMS
  
  ser.Str(@MsgPressSpacebarToBegin)
  if (ser.CharIn <> " ")
    ser.Str(@ErrIDCODEAborted)
    return

  ser.Str(@MsgJTAGulating)
  u.TXSEnable   ' Enable level shifter outputs

  ' We assume the IDCODE is the default DR after reset
  ' Pin enumeration logic based on JTAGenum (http://deadhacker.com/2010/02/03/jtag-enumeration/)
  jTDI := g#PROP_SDA    ' TDI isn't used when we're just shifting data from the DR. Set TDI to a temporary pin so it doesn't interfere with enumeration.

  num := 0      ' Counter of possible pinouts
  ctr := 0
  repeat jTDO from chStart to chEnd   ' For every possible pin permutation (except TDI and TRST)...
    repeat jTCK from chStart to chEnd
      if (jTCK == jTDO)
        next
      repeat jTMS from chStart to chEnd
        if (jTMS == jTCK) or (jTMS == jTDO)
          next
  
        if (ser.RxEmpty == 0)  ' Abort scan if any key is pressed
          JTAG_Scan_Cleanup(num, 0, xtdo, xtck, xtms)  ' TDI isn't used during an IDCODE Scan
          ser.RxFlush
          ser.Str(@ErrIDCODEAborted)
          return

        u.Set_Pins_High(chStart, chEnd)       ' Set current channel range to output HIGH (in case there are active low signals that may affect operation, like TRST# or SRST#)  
        jtag.Config(jTDI, jTDO, jTCK, jTMS)   ' Configure JTAG pins
        jtag.Get_Device_IDs(1, @value)        ' Try to get Device ID by reading the DR      
        if (value <> -1) and (value & 1)      ' Ignore if received Device ID is 0xFFFFFFFF or if bit 0 != 1
          Display_JTAG_Pins                   ' Display current JTAG pinout
          num += 1                            ' Increment counter  
          xtdo := jTDO                        ' Keep track of most recent detection results
          xtck := jTCK
          xtms := jTMS
          jPinsKnown := 1                     ' Enable known pins flag

          ' Now try to determine if the TRST# pin is being used on the target
          repeat jTRST from chStart to chEnd     ' For every remaining channel...
            if (jTRST == jTMS) or (jTRST == jTCK) or (jTRST == jTDO) or (jTMS == jTDI)
              next
              
            if (ser.RxEmpty == 0)  ' Abort scan if any key is pressed
              JTAG_Scan_Cleanup(num, 0, xtdo, xtck, xtms)  ' TDI isn't used during an IDCODE Scan
              ser.RxFlush
              ser.Str(@ErrIDCODEAborted)
              return
      
            dira[jTRST] := 1  ' Set current pin to output
            outa[jTRST] := 0  ' Output LOW
                 
            jtag.Get_Device_IDs(1, @value_new)  ' Try to get Device ID again by reading the DR
            if (value_new <> value)             ' If the new value doesn't match what we already have, then the current pin may be a reset line.
              ser.Str(String("TRST#: "))          ' So, display the pin number
              ser.Dec(jTRST)
              ser.Str(String(CR, LF))
                     
            outa[jTRST] := 1  ' Bring the current pin HIGH when done
        
        ' Progress indicator
        ++ctr
        Display_Progress(ctr, 100)

  if (num == 0)
    ser.Str(@ErrNoDeviceFound)  
  JTAG_Scan_Cleanup(num, 0, xtdo, xtck, xtms)  ' TDI isn't used during an IDCODE Scan
  
  ser.Str(String(CR, LF, "IDCODE scan complete."))

         
PRI BYPASS_Scan | value, value_new, ctr, num, data_in, data_out, xtdi, xtdo, xtck, xtms, tdiStart, tdiEnd, tdoStart, tdoEnd, tckStart, tckEnd, tmsStart, tmsEnd    ' Identify JTAG pinout (BYPASS Scan)
  if (Get_Channels(4) == -1)   ' Get the channel range to use
    return

  tdiStart := tdoStart := tmsStart := tckStart := chStart   ' Set default start and end channels
  tdiEnd := tdoEnd := tmsEnd := tckEnd := chEnd
  num := 4   ' Number of pins needed to locate (TDI, TDO, TCK, TMS)
    
  ser.Str(String(CR, LF, "Are any pins already known? ["))
  if (jPinsKnown == 0)
    ser.Str(String("y/N]: "))
  else
    ser.Str(String("Y/n]: "))  
  ser.StrInMax(@vCmd,  MAX_INPUT_LEN) ' Wait here to receive a carriage return terminated string or one of MAX_INPUT_LEN bytes (the result is null terminated) 
  if (strsize(@vCmd) =< 1)            ' We're only looking for a single character (or NULL, which will have a string size of 0)
    case vCmd[0]                        ' Check the first character of the input string
      0:                                ' The user only entered a CR, so keep the same value and pass through.
      "N", "n":
        jPinsKnown := 0                 ' Disable flag                
      "Y", "y":                         ' If the user wants to use a partial pinout
        jPinsKnown := 1                 ' Enable flag
      other:                            ' Any other key causes an error
        ser.Str(@ErrOutOfRange)
        return
  else
    ser.Str(@ErrOutOfRange)
    return

  if (jPinsKnown == 1)
    ser.Str(String(CR, LF, "Enter X for any unknown pin."))
    if (Set_JTAG_Partial == -1)       ' Ask user for any known JTAG pins
      return                            ' Abort if error

    ' If the user has entered a known pin, set it as both start and end to make it static during the scan
    if (jTDI <> -2)
      tdiStart := tdiEnd := jTDI
      num -= 1
    else
      jTDI := 0   ' Reset pin
          
    if (jTDO <> -2)
      tdoStart := tdoEnd := jTDO
      num -= 1
    else
      jTDO := 0
          
    if (jTMS <> -2)
      tmsStart := tmsEnd := jTMS
      num -= 1
    else
      jTMS := 0
          
    if (jTCK <> -2)
      tckStart := tckEnd := jTCK
      num -= 1
    else
      jTCK := 0
          
  Display_Permutations((chEnd - chStart + 1), num)
    
  ser.Str(@MsgPressSpacebarToBegin)
  if (ser.CharIn <> " ")
    ser.Str(@ErrBYPASSAborted)
    return

  ser.Str(@MsgJTAGulating)
  u.TXSEnable   ' Enable level shifter outputs

  num := 0  ' Counter of possible pinouts
  ctr := 0  
  repeat jTDI from tdiStart to tdiEnd        ' For every possible pin permutation (except TRST#)...
    repeat jTDO from tdoStart to tdoEnd
      if (jTDO == jTDI)  ' Ensure each pin number is unique
        next
      repeat jTCK from tckStart to tckEnd
        if (jTCK == jTDO) or (jTCK == jTDI)
          next
        repeat jTMS from tmsStart to tmsEnd
          if (jTMS == jTCK) or (jTMS == jTDO) or (jTMS == jTDI)
            next
                      
          if (ser.RxEmpty == 0)  ' Abort scan if any key is pressed
            JTAG_Scan_Cleanup(num, xtdi, xtdo, xtck, xtms)
            ser.RxFlush
            ser.Str(@ErrBYPASSAborted)
            return

          u.Set_Pins_High(chStart, chEnd)        ' Set current channel range to output HIGH (in case there is a signal on the target that needs to be held HIGH, like TRST# or SRST#)
          jtag.Config(jTDI, jTDO, jTCK, jTMS)    ' Configure JTAG pins
          value := jtag.Detect_Devices
  
          if (value > 0 and value =< MAX_NUM_JTAG)  ' Limit maximum possible number of devices in the chain
            ' Run a BYPASS test to ensure TDO is actually passing TDI
            data_in := rr.random                          ' Get 32-bit random number to use as the BYPASS pattern
            data_out := jtag.Bypass_Test(value, data_in)  ' Run the BYPASS instruction

            if (data_in == data_out)   ' If match, then continue with this current pinout  
              Display_JTAG_Pins          ' Display pinout
              num += 1                   ' Increment counter
              xtdi := jTDI               ' Keep track of most recent detection results
              xtdo := jTDO                        
              xtck := jTCK
              xtms := jTMS 

              ' Now try to determine if the TRST# pin is being used on the target
              repeat jTRST from chStart to chEnd     ' For every remaining channel...
                if (jTRST == jTMS) or (jTRST == jTCK) or (jTRST == jTDO) or (jTMS == jTDI)
                  next

                if (ser.RxEmpty == 0)  ' Abort scan if any key is pressed
                  JTAG_Scan_Cleanup(num, xtdi, xtdo, xtck, xtms)
                  ser.RxFlush
                  ser.Str(@ErrBYPASSAborted)
                  return
               
                dira[jTRST] := 1  ' Set current pin to output
                outa[jTRST] := 0  ' Output LOW
            
                value_new := jtag.Detect_Devices
                if (value_new <> value) and (value_new =< MAX_NUM_JTAG)    ' If the new value doesn't match what we already have, then the current pin may be a reset line.
                  ser.Str(String("TRST#: "))    ' So, display the pin number
                  ser.Dec(jTRST)
                  ser.Str(String(CR, LF))
                     
                outa[jTRST] := 1  ' Bring the current pin HIGH when done
            
              ser.Str(String("Number of devices detected: "))
              ser.Dec(value)
              ser.Str(String(CR, LF))
                  
        ' Progress indicator
          ++ctr
          Display_Progress(ctr, 10)

  if (num == 0)
    ser.Str(@ErrNoDeviceFound)
  JTAG_Scan_Cleanup(num, xtdi, xtdo, xtck, xtms)
    
  ser.Str(String(CR, LF, "BYPASS scan complete."))


PRI IDCODE_Known | value, id[MAX_NUM_JTAG], i, xtdi   ' Get JTAG Device IDs (Pinout already known)
  xtdi := jTDI   ' Save current value, if it exists
  
  if (Set_JTAG(0) == -1)  ' Ask user for the known JTAG pinout
    return                  ' Abort if error

  u.TXSEnable                                 ' Enable level shifter outputs
  ser.Str(@MsgChannelsSetHigh)
  u.Set_Pins_High(0, g#MAX_CHAN)              ' In case there is a signal on the target that needs to be held HIGH, like TRST# or SRST#
  jtag.Config(jTDI, jTDO, jTCK, jTMS)         ' Configure JTAG pins

  ' Since we might not know how many devices are in the chain, try the maximum allowable number and verify the results afterwards
  jtag.Get_Device_IDs(MAX_NUM_JTAG, @id)      ' We assume the IDCODE is the default DR after reset

  repeat i from 0 to (MAX_NUM_JTAG-1)         ' For each device in the chain...
    value := id[i]
    if (value <> -1) and (value & 1)          ' Ignore if received Device ID is 0xFFFFFFFF or if bit 0 != 1
      Display_Device_ID(value, i + 1)           ' Display Device ID of current device
    else
      quit                                      ' Exit the loop at the first instance of an invalid Device ID
    
  if (i == 0)
    ser.Str(@ErrNoDeviceFound)
  else
    ser.Str(String(CR, LF))
         
  jTDI := xtdi   ' Set TDI back to its current value, if it exists (it was set to a temporary pin value to avoid contention)
  ser.Str(String(CR, LF, "IDCODE listing complete."))


PRI BYPASS_Known | num, dataIn, dataOut   ' Test BYPASS (TDI to TDO) (Pinout already known)
  if (Set_JTAG(1) == -1)  ' Ask user for the known JTAG pinout
    return                  ' Abort if error

  u.TXSEnable                                 ' Enable level shifter outputs
  ser.Str(@MsgChannelsSetHigh)
  u.Set_Pins_High(0, g#MAX_CHAN)              ' In case there is a signal on the target that needs to be held HIGH, like TRST# or SRST#
  jtag.Config(jTDI, jTDO, jTCK, jTMS)         ' Configure JTAG pins

  num := jtag.Detect_Devices                 ' Get number of devices in the chain
  ser.Str(String(CR, LF, "Number of devices detected: "))
  ser.Dec(num)
  if (num == 0)
    ser.Str(@ErrNoDeviceFound)
    return
  
  dataIn := rr.random                         ' Get 32-bit random number to use as the BYPASS pattern
  dataOut := jtag.Bypass_Test(num, dataIn)    ' Run the BYPASS instruction 
    
  ' Display input/output data and check if they match
  ser.Str(String(CR, LF, "Pattern in to TDI:    "))
  ser.Bin(dataIn, 32)   ' Display value as binary characters (0/1)

  ser.Str(String(CR, LF, "Pattern out from TDO: "))
  ser.Bin(dataOut, 32)  ' Display value as binary characters (0/1)

  if (dataIn == dataOut)
    ser.Str(String(CR, LF, "Match!"))
  else
    ser.Str(String(CR, LF, "No Match!"))


PRI OPCODE_Discovery | num, ctr, irLen, drLen, opcode_max, opcodeH, opcodeL, opcode   ' Discover DR length for every instruction (Pinout already known, requires single device in the chain)
  if (Set_JTAG(1) == -1)  ' Ask user for the known JTAG pinout
    return                  ' Abort if error

  ser.Str(String(CR, LF, "Ignore single-bit Data Registers? ["))   ' If DR is 1 bit, it's probably an unimplemented command (which usually defaults to BYPASS)
  if (jIgnoreReg == 0)
    ser.Str(String("y/N]: "))
  else
    ser.Str(String("Y/n]: "))  
  ser.StrInMax(@vCmd,  MAX_INPUT_LEN) ' Wait here to receive a carriage return terminated string or one of MAX_INPUT_LEN bytes (the result is null terminated) 
  if (strsize(@vCmd) =< 1)            ' We're only looking for a single character (or NULL, which will have a string size of 0)
    case vCmd[0]                        ' Check the first character of the input string
      0:                                ' The user only entered a CR, so keep the same value and pass through.
      "N", "n":
        jIgnoreReg := 0                 ' Disable flag                
      "Y", "y":                         ' If the user wants to use a partial pinout
        jIgnoreReg := 1                 ' Enable flag
      other:                            ' Any other key causes an error
        ser.Str(@ErrOutOfRange)
        return
  else
    ser.Str(@ErrOutOfRange)
    return
    
  u.TXSEnable                                 ' Enable level shifter outputs
  ser.Str(@MsgChannelsSetHigh)
  u.Set_Pins_High(0, g#MAX_CHAN)              ' In case there is a signal on the target that needs to be held HIGH, like TRST# or SRST#
  jtag.Config(jTDI, jTDO, jTCK, jTMS)         ' Configure JTAG pins

  num := jtag.Detect_Devices                  ' Get number of devices in the chain
  if (num == 0)
    ser.Str(@ErrNoDeviceFound)
    return
  elseif (num > 1)
    ser.Str(String(CR, LF, "Too many devices in the chain!"))
    return 
  ser.Str(String(CR, LF))
   
  ' Get instruction register length
  irLen := jtag.Detect_IR_Length 
  ser.Str(String("Instruction Register (IR) length: "))
  if (irLen == 0)
    ser.Str(String("N/A"))
    ser.Str(@ErrOutOfRange)
    return
  else
    ser.Dec(irLen)

  ser.Str(String(CR, LF, "Possible instructions: "))
  opcode_max := Bits_to_Value(irLen)   ' 2^n - 1
  ser.Dec(opcode_max + 1)

    ser.Str(String(CR, LF, "Ensure VADJ is NOT connected to target!"))
    
  ser.Str(@MsgPressSpacebarToBegin)
  if (ser.CharIn <> " ")
    ser.Str(@ErrDiscoveryAborted)
    return

  ser.Str(@MsgJTAGulating)          

  ctr := 0
  ' For every possible instruction...
  repeat opcodeH from 0 to opcode_max.WORD[1]         ' Propeller Spin performs all mathematic operations using 32-bit signed math (MSB is the sign bit)
    repeat opcodeL from 0 to opcode_max.WORD[0]         ' So, we need to nest two loops in order to support the full 32-bit maximum IR length (thanks to balrog, whixr, and atdiy of #tymkrs)
      opcode := (opcodeH << 16) | opcodeL
      drLen := jtag.Detect_DR_Length(opcode)              ' Get the DR length

      if (drLen > 1) or (drLen == 1 and jIgnoreReg == 0)                                      
        if (ctr > 1)
          ser.Str(@CharProgress)                            ' Include a progress marker if there's a gap between instructions (for easier readibility)
          ser.Str(String(CR, LF))
   
        Display_JTAG_IRDR(irLen, opcode, drLen)           ' Display the result
        ctr := 0    ' Clear counter for progress indicator

      if (ser.RxEmpty == 0)  ' Abort scan if any key is pressed
        ser.RxFlush
        ser.Str(@ErrDiscoveryAborted)
        return

      ' Progress indicator
      ++ctr
      Display_Progress(ctr, 32)

  jtag.Restore_Idle   ' Reset JTAG TAP to Run-Test-Idle state
  ser.Str(String(CR, LF, "IR/DR discovery complete."))
    

PRI OPCODE_Known | num, irLen, drLen, xir, xdr, data, i   ' Transfer instruction/data (Pinout already known, requires single device in the chain)
  if (Set_JTAG(1) == -1)  ' Ask user for the known JTAG pinout
    return                  ' Abort if error
  
  u.TXSEnable                                 ' Enable level shifter outputs
  ser.Str(@MsgChannelsSetHigh)
  u.Set_Pins_High(0, g#MAX_CHAN)              ' In case there is a signal on the target that needs to be held HIGH, like TRST# or SRST#
  jtag.Config(jTDI, jTDO, jTCK, jTMS)         ' Configure JTAG pins

  num := jtag.Detect_Devices                  ' Get number of devices in the chain
  if (num == 0)
    ser.Str(@ErrNoDeviceFound)
    return
  elseif (num > 1)
    ser.Str(String(CR, LF, "Too many devices in the chain!"))
    return 
  ser.Str(String(CR, LF))

  irLen := jtag.Detect_IR_Length              ' Get instruction register length
  ser.Str(String("Instruction Register (IR) length: "))
  if (irLen == 0)
    ser.Str(String("N/A"))
    ser.Str(@ErrOutOfRange)
    return
  else
    ser.Dec(irLen)
                  
  ser.Str(String(CR, LF, "Enter instruction/opcode to send (in hex) ["))   ' Receive instruction/opcode from the user
  ser.Hex(jIR, Round_Up(irLen) >> 2)
  ser.Str(String("]: ")) 
  ' Receive hexadecimal value from the user and perform input sanitization
  ' This has do be done directly in the object since we may need to handle user input up to 32 bits
  ser.StrInMax(@vCmd,  MAX_INPUT_LEN)
  if (vCmd[0]==0)   ' If carriage return was pressed...          
    xir := jIR & Bits_To_Value(irLen)    ' Keep current setting, but adjust for a possible change in IR length
  else
    if strsize(@vCmd) > (Round_Up(irLen) >> 2)  ' If value is larger than the actual IR length
      ser.Str(@ErrOutOfRange)
      return
    ' Make sure each character in the string is hexadecimal ("0"-"9","A"-"F","a"-"f")
    repeat i from 0 to strsize(@vCmd)-1
      data := vCmd[i]
      data := -15 + --data & %11011111 + 39*(data > 56)   ' Borrowed from the Parallax Serial Terminal (PST) StrToBase method     
      if (data < 0) or (data => 16)
        ser.Str(@ErrOutOfRange)
        return
    xir := ser.StrToBase(@vCmd, 16)   ' Convert valid string into actual value
  jIR := xir   ' Update global with new value

  drLen := jtag.Detect_DR_Length(xir)         ' Get data register length
  ser.Str(String(CR, LF, "Data Register (DR) length: "))
  if (drLen == 0)
    ser.Str(String("N/A"))
    ser.Str(@ErrOutOfRange)
    return
  else
    ser.Dec(drLen)

  if (drLen > 32)
    ser.Str(String(CR, LF, "Data input limited to 32 bits!"))
    drLen := 32
    
  ser.Str(String(CR, LF, "Enter data to send (in hex) ["))               ' Receive data from the user
  ser.Hex(jDR, Round_Up(drLen) >> 2)
  ser.Str(String("]: ")) 
  ' Receive hexadecimal value from the user and perform input sanitization
  ' This has do be done directly in the object since we may need to handle user input up to 32 bits
  ser.StrInMax(@vCmd,  MAX_INPUT_LEN)
  if (vCmd[0]==0)   ' If carriage return was pressed...          
    xdr := jDR & Bits_To_Value(drLen)    ' Keep current setting, but adjust for a possible change in DR length
  else
    if strsize(@vCmd) > (Round_Up(drLen) >> 2)  ' If value is larger than the actual DR length
      ser.Str(@ErrOutOfRange)
      return
    ' Make sure each character in the string is hexadecimal ("0"-"9","A"-"F","a"-"f")
    repeat i from 0 to strsize(@vCmd)-1
      data := vCmd[i]
      data := -15 + --data & %11011111 + 39*(data > 56)   ' Borrowed from the Parallax Serial Terminal (PST) StrToBase method     
      if (data < 0) or (data => 16)
        ser.Str(@ErrOutOfRange)
        return
    xdr := ser.StrToBase(@vCmd, 16)   ' Convert valid string into actual value
  jDR := xdr   ' Update global with new value

  jtag.Restore_Idle                       ' Reset JTAG TAP to Run-Test-Idle state
  jtag.Send_Instruction(xir, irLen)       ' Send instruction/opcode
  data := jtag.Send_Data(xdr, drLen)      ' Shift 1s into DR and receive result from prior instruction via TDO
              
  ' Display received value
  ser.Str(String(CR, LF, "Data received: "))
   
  ' ...as binary characters (0/1)
  Display_Binary(data, drLen)
 
  ' ...as hexadecimal
  ser.Str(String("(0x"))
  ser.Hex(data, Round_Up(drLen) >> 2) 
  ser.Str(String(")"))

  jtag.Restore_Idle   ' Reset JTAG TAP to Run-Test-Idle state

  
PRI Set_JTAG(getTDI) : err | xtdi, xtdo, xtck, xtms, buf, c     ' Set JTAG configuration to known values
  if (getTDI == 1)          
    ser.Str(String(CR, LF, "Enter TDI pin ["))
    ser.Dec(jTDI)             ' Display current value
    ser.Str(String("]: "))
    xtdi := Get_Decimal_Pin   ' Get new value from user
    if (xtdi == -1)           ' If carriage return was pressed...      
      xtdi := jTDI              ' Keep current setting
    if (xtdi < 0) or (xtdi > g#MAX_CHAN-1)  ' If entered value is out of range, abort
      ser.Str(@ErrOutOfRange)
      return -1
  else
    ser.Str(String(CR, LF, "TDI not needed to retrieve Device ID."))
    xtdi := g#PROP_SDA          ' Set TDI to a temporary pin so it doesn't interfere with enumeration

  ser.Str(String(CR, LF, "Enter TDO pin ["))
  ser.Dec(jTDO)               ' Display current value
  ser.Str(String("]: "))
  xtdo := Get_Decimal_Pin     ' Get new value from user
  if (xtdo == -1)             ' If carriage return was pressed...      
    xtdo := jTDO                ' Keep current setting
  if (xtdo < 0) or (xtdo > g#MAX_CHAN-1)  ' If entered value is out of range, abort
    ser.Str(@ErrOutOfRange)
    return -1

  ser.Str(String(CR, LF, "Enter TCK pin ["))
  ser.Dec(jTCK)               ' Display current value
  ser.Str(String("]: "))
  xtck := Get_Decimal_Pin     ' Get new value from user
  if (xtck == -1)             ' If carriage return was pressed...      
    xtck := jTCK                ' Keep current setting
  if (xtck < 0) or (xtck > g#MAX_CHAN-1)  ' If entered value is out of range, abort
    ser.Str(@ErrOutOfRange)
    return -1

  ser.Str(String(CR, LF, "Enter TMS pin ["))
  ser.Dec(jTMS)               ' Display current value
  ser.Str(String("]: "))
  xtms := Get_Decimal_Pin     ' Get new value from user
  if (xtms == -1)             ' If carriage return was pressed...      
    xtms := jTMS                ' Keep current setting
  if (xtms < 0) or (xtms > g#MAX_CHAN-1)  ' If entered value is out of range, abort
    ser.Str(@ErrOutOfRange)
    return -1       

  ' Make sure that the pin numbers are unique
  ' Set bit in a long corresponding to each pin number
  buf := 0
  buf |= (1 << xtdi)
  buf |= (1 << xtdo)
  buf |= (1 << xtck)
  buf |= (1 << xtms)
  
  ' Count the number of bits that are set in the long
  c := 0
  repeat 32
    c += (buf & 1)
    buf >>= 1

  if (c <> 4)         ' If there are not exactly 4 bits set (TDI, TDO, TCK, TMS), then we have a collision
    ser.Str(@ErrPinCollision)
    return -1
  else                ' If there are no collisions, update the globals with the new values
    jTDI := xtdi      
    jTDO := xtdo
    jTCK := xtck
    jTMS := xtms
    

PRI Set_JTAG_Partial : err | xtdi, xtdo, xtck, xtms, buf, num, c     ' Set JTAG configuration to known values (used w/ partially known pinout)
  ' An "X" or "x" character will be sent by the user for any pin that is unknown. This will result in Get_Pin returning a -2 value.     
  ser.Str(String(CR, LF, "Enter TDI pin ["))
  ser.Dec(jTDI)               ' Display current value
  ser.Str(String("]: "))
  xtdi := Get_Pin             ' Get new value from user
  if (xtdi == -1)             ' If carriage return was pressed...      
    xtdi := jTDI                ' Keep current setting
  if (xtdi < -2) or (xtdi > g#MAX_CHAN-1)   ' If entered value is out of range, abort
    ser.Str(@ErrOutOfRange)
    return -1

  ser.Str(String(CR, LF, "Enter TDO pin ["))
  ser.Dec(jTDO)               ' Display current value
  ser.Str(String("]: "))
  xtdo := Get_Pin             ' Get new value from user
  if (xtdo == -1)             ' If carriage return was pressed...      
    xtdo := jTDO                ' Keep current setting
  if (xtdo < -2) or (xtdo > g#MAX_CHAN-1)   ' If entered value is out of range, abort
    ser.Str(@ErrOutOfRange)
    return -1

  ser.Str(String(CR, LF, "Enter TCK pin ["))
  ser.Dec(jTCK)               ' Display current value
  ser.Str(String("]: "))
  xtck := Get_Pin             ' Get new value from user
  if (xtck == -1)             ' If carriage return was pressed...      
    xtck := jTCK                ' Keep current setting
  if (xtck < -2) or (xtck > g#MAX_CHAN-1)   ' If entered value is out of range, abort
    ser.Str(@ErrOutOfRange)
    return -1

  ser.Str(String(CR, LF, "Enter TMS pin ["))
  ser.Dec(jTMS)               ' Display current value
  ser.Str(String("]: "))
  xtms := Get_Pin             ' Get new value from user
  if (xtms == -1)             ' If carriage return was pressed...      
    xtms := jTMS                ' Keep current setting
  if (xtms < -2) or (xtms > g#MAX_CHAN-1)   ' If entered value is out of range, abort
    ser.Str(@ErrOutOfRange)
    return -1       

  ' Make sure that the pin numbers are unique
  buf := 0
  num := 4
  if (xtdi <> -2)
    buf |= (1 << xtdi)    ' Set bit in a long corresponding to each pin number
  else
    num -= 1              ' If pin is unknown, don't set the bit

  if (xtdo <> -2)
    buf |= (1 << xtdo)
  else
    num -= 1    

  if (xtck <> -2)
    buf |= (1 << xtck)
  else
    num -= 1

  if (xtms <> -2)
    buf |= (1 << xtms)
  else
    num -= 1
  
  ' Count the number of bits that are set in the long
  c := 0
  repeat 32
    c += (buf & 1)
    buf >>= 1

  if (c <> num)      ' If there are not exactly num bits set (depending on the number of known pins), then we have a collision
    ser.Str(@ErrPinCollision)
    return -1
  else                ' If there are no collisions, update the globals with the new values
    jTDI := xtdi      
    jTDO := xtdo
    jTCK := xtck
    jTMS := xtms


PRI JTAG_Scan_Cleanup(num, tdi, tdo, tck, tms)
  if (num == 0)    ' If no device(s) were found during the search
    longfill(@jTDI, 0, 5)  ' Clear JTAG pinout
  else             ' Update globals with the most recent detection results
    jTDI := tdi      
    jTDO := tdo
    jTCK := tck
    jTMS := tms

    
PRI Display_JTAG_Pins
  ser.Str(String(CR, LF, "TDI: "))
  if (jTDI => g#MAX_CHAN)   ' TDI isn't used during an IDCODE Scan (we're not shifting any data into the target), so it can't be determined
    ser.Str(String("N/A"))  
  else
    ser.Dec(jTDI)
    
  ser.Str(String(CR, LF, "TDO: "))
  ser.Dec(jTDO)

  ser.Str(String(CR, LF, "TCK: "))
  ser.Dec(jTCK)

  ser.Str(String(CR, LF, "TMS: "))
  ser.Dec(jTMS)
  
  ser.Str(String(CR, LF))


PRI Display_JTAG_IRDR(irLen, opcode, drLen)    ' Display IR/DR information
  ' Display current instruction
  ser.Str(String("IR: "))

  ' ...as binary characters (0/1)
  Display_Binary(opcode, irLen)
  
  ' ...as hexadecimal
  ser.Str(String("(0x"))
  ser.Hex(opcode, Round_Up(irLen) >> 2)
  ser.Str(String(")"))

  ' Display DR length as a decimal value
  ser.Str(String(" -> DR: "))             
  ser.Dec(drLen)
  ser.Str(String(CR, LF))

  
PRI Display_Device_ID(value, num)
  ser.Str(String(CR, LF, LF, "Device ID"))
  ser.Str(String(" #"))
  ser.Dec(num)
  ser.Str(String(": "))
   
  ' Display value as binary characters (0/1) based on IEEE Std. 1149.1 2001 Device Identification Register structure
  {{ IEEE Std. 1149.1 2001
     Device Identification Register
   
     MSB                                                                          LSB
     ┌───────────┬──────────────────────┬───────────────────────────┬──────────────┐
     │  Version  │      Part Number     │   Manufacturer Identity   │   Fixed (1)  │
     └───────────┴──────────────────────┴───────────────────────────┴──────────────┘
        31...28          27...12                  11...1                   0
  }}
  ser.Bin(Get_Bit_Field(value, 31, 28), 4)      ' Version
  ser.Char(" ")
  ser.Bin(Get_Bit_Field(value, 27, 12), 16)     ' Part Number
  ser.Char(" ")  
  ser.Bin(Get_Bit_Field(value, 11, 1), 11)      ' Manufacturer Identity
  ser.Char(" ")
  ser.Bin(Get_Bit_Field(value, 0, 0), 1)        ' Fixed (should always be 1)

  ' ...as hexadecimal
  ser.Str(String(" (0x"))
  ser.Hex(value, 8)
  ser.Str(String(")"))

  if (value <> -1) and (value & 1)      ' If Device ID value is valid
    ' Extended decoding
    ' Not all vendors use these fields as specified
    ser.Str(String(CR, LF, "-> Manufacturer ID: 0x"))
    ser.Hex(Get_Bit_Field(value, 11, 1), 3)
    ser.Str(String(CR, LF, "-> Part Number: 0x"))
    ser.Hex(Get_Bit_Field(value, 27, 12), 4)
    ser.Str(String(CR, LF, "-> Version: 0x"))
    ser.Hex(Get_Bit_Field(value, 31, 28), 1)
  else                                   
    ser.Str(String(CR, LF, "-> Invalid ID!"))  ' Otherwise, device ID is invalid (0xFFFFFFFF or if bit 0 != 1), so let the user know

  
CON {{ UART METHODS }}

PRI UART_Init
  bytefill (@uSTR, 0, MAX_INPUT_LEN + 1)  ' Clear input string buffer

  ' Set default parameters
  ' UART_Scan_TX
  uBaudMin := BaudRate[0]
  uBaudMax := BaudRate[(constant(BaudRateEnd - BaudRate) >> 2) - 1]
  uWaitPerBaud := 1000
  uLoopPerChan := 10
  uLoopPause := 1

  ' UART_Passthrough
  uLocalEcho := 0
  

PRI UART_Scan  | value, baud_idx, i, j, ctr, num, xval, xstr[MAX_INPUT_LEN >> 2 + 1], data[MAX_LEN_UART >> 2], xtxd, xrxd, xbaud    ' Identify UART pinout
  ser.Str(@UARTPinoutMessage)

 ' Get user string to send during UART discovery
  ser.Str(String(CR, LF, "Enter text string to output (prefix with \x for hex) ["))
  if (uSTR[0] == 0)
    ser.Str(String("CR"))  ' Default to a CR if string hasn't been set yet  
  else
    ser.Str(@uSTR)         ' If a previous string exists, display it
  ser.Str(String("]: "))

  ser.StrInMax(@xstr, MAX_INPUT_LEN) ' Get input from user
  i := strsize(@xstr)
  if (i <> 0)                        ' If input was anything other than a CR
    ' Make sure each character in the string is printable ASCII
    repeat j from 0 to (i-1)
      if (byte[@xstr][j] < $20) or (byte[@xstr][j] > $7E)
        ser.Str(@ErrOutOfRange)  ' If the string contains invalid (non-printable) characters, abort
        return
             
    bytemove(@uSTR, @xstr, i)             ' Move the new string into the uSTR global
    bytefill(@uSTR+i, 0, MAX_INPUT_LEN-i) ' Fill the remainder of the string with NULL, in case it's shorter than the last 

  ' Check string for the \x escape sequence. If it exists, the desired string is a series of hex bytes
  if (byte[@uSTR][0] == "\" and byte[@uSTR][1] == "x")
    if (byte[@uSTR][10] <> 0) or (ser.StrToBase(@uSTR+2, 16) == 0)  ' If the string is too long or it's a NULL byte
      ser.Str(@ErrOutOfRange)  ' If the hex string is too long, abort
      return    
    xval := ser.StrToBase(@uSTR+2, 16)
  else
    xval := 0
               
  if (Get_Channels(2) == -1)   ' Get the channel range to use
    return 
  Display_Permutations((chEnd - chStart + 1), 2) ' TXD, RXD 

  ser.Str(@MsgPressSpacebarToBegin)
  if (ser.CharIn <> " ")
    ser.Str(@ErrUARTAborted)
    return

  ser.Str(@MsgJTAGulating)
  u.TXSEnable   ' Enable level shifter outputs

  num := 0   ' Counter of possible pinouts
  ctr := 0
  repeat uTXD from chStart to chEnd   ' For every possible pin permutation...
    repeat uRXD from chStart to chEnd
      if (uRXD == uTXD)
        next

      repeat baud_idx from 0 to (constant(BaudRateEnd - BaudRate) >> 2) - 1   ' For every possible baud rate in BaudRate table...
        if (ser.RxEmpty == 0)        ' Abort scan if any key is pressed
          UART_Scan_Cleanup(num, xtxd, xrxd, xbaud)
          ser.RxFlush
          ser.Str(@ErrUARTAborted)
          return
        uBaud := BaudRate[baud_idx]        ' Store current baud rate into uBaud variable
        UART.Start(|<uTXD, |<uRXD, uBaud)  ' Configure UART
        UART.RxFlush                       ' Flush receive buffer

        if (xval == 0)                     ' If the user string is ASCII
          UART.str(@uSTR)                    ' Send string to target
          UART.tx(CR)                        ' Send carriage return to target
        else                               ' Otherwise, send hex characters one at a time
          if (xval & $ff000000)              ' Ignore MSBs if they are NULL
            UART.tx(xval >> 24)
            UART.tx(xval >> 16)
            UART.tx(xval >> 8)
            UART.tx(xval & $ff)
          elseif (xval & $ff0000)
            UART.tx(xval >> 16)
            UART.tx(xval >> 8)
            UART.tx(xval & $ff)
          elseif (xval & $ff00)            
            UART.tx(xval >> 8)
            UART.tx(xval & $ff)
          else
            UART.tx(xval & $ff)                    

        i := 0
        repeat while (i < MAX_LEN_UART)    ' Check for a response from the target and grab up to MAX_LEN_UART bytes
          value := UART.RxTime(20)           ' Wait up to 20ms to receive a byte from the target
          if (value < 0)                     ' If there's no data, exit the loop
            quit
          byte[@data][i++] := value          ' Store the byte in our array and try for more!

        repeat until (UART.RxTime(20) < 0)   ' Wait here until the target has stopped sending data
        
        if (i > 0)                           ' If we've received any data...
          Display_UART_Pins                    ' Display current UART pinout
          ser.Str(String("Data: "))            ' Display the data in ASCII
          repeat value from 0 to (i-1)                  
            if (byte[@data][value] < $20) or (byte[@data][value] > $7E) ' If the byte is an unprintable character 
              ser.Char(".")                                               ' Print a . instead
            else
              ser.Char(byte[@data][value])

          ser.Str(String(" [ "))
          repeat value from 0 to (i-1)        ' Display the data in hexadecimal
            ser.Hex(byte[@data][value], 2)
            ser.Char(" ")
          ser.Str(String("]", CR, LF))
          num += 1                            ' Increment counter
          xtxd := uTXD                        ' Keep track of most recent detection results
          xrxd := uRXD
          xbaud := uBaud

    ' Progress indicator
      ++ctr
      Display_Progress(ctr, 1)

  if (num == 0)
    ser.Str(@ErrNoDeviceFound)
  UART_Scan_Cleanup(num, xtxd, xrxd, xbaud)
  
  ser.Str(String(CR, LF, "UART scan complete."))  


PRI UART_Scan_TXD  | value, baud_idx, i, t, ctr, num, data[MAX_LEN_UART >> 2], xtxd, xbaud, loopquit, loopnum, numbaud    ' Identify UART pinout (TXD only, user configurable)
  ser.Str(@UARTPinoutMessage)

  if (Get_Channels(1) == -1)   ' Get the channel range to use
    return 
  
  ser.Str(String(CR, LF, "Enter minimum baud rate ("))
  ser.Dec(BaudRate[0])
  ser.Str(String(" - "))
  ser.Dec(BaudRate[(constant(BaudRateEnd - BaudRate) >> 2) - 1])
  ser.Str(String(") ["))
  ser.Dec(uBaudMin)
  ser.Str(String("]: "))
  value := Get_Decimal_Pin      ' Get new value from user
  if (value <> -1)              ' If carriage return was not pressed...
    ctr := 0
    repeat i from 0 to (constant(BaudRateEnd - BaudRate) >> 2)
      if (value == BaudRate[i])  ' If entered value is an acceptable baud rate
        ctr := 1
    if (ctr == 0)  ' Otherwise, abort
      ser.Str(@ErrOutOfRange)
      return    
    uBaudMin := value
                 
  ser.Str(String(CR, LF, "Enter maximum baud rate ("))
  ser.Dec(uBaudMin)
  ser.Str(String(" - "))
  ser.Dec(BaudRate[(constant(BaudRateEnd - BaudRate) >> 2) - 1])
  ser.Str(String(") ["))
  ser.Dec(uBaudMax)
  ser.Str(String("]: "))
  value := Get_Decimal_Pin      ' Get new value from user
  if (value <> -1)              ' If carriage return was not pressed... 
    ctr := 0
    repeat i from 0 to (constant(BaudRateEnd - BaudRate) >> 2)
      if (value == BaudRate[i])  ' If entered value is an acceptable baud rate
        ctr := 1
    if (ctr == 0)  ' Otherwise, abort
      ser.Str(@ErrOutOfRange)
      return
    uBaudMax := value

  ' Calculate the number of baud rates we'll be trying
  numbaud := 0
  repeat baud_idx from 0 to (constant(BaudRateEnd - BaudRate) >> 2) - 1
    if(BaudRate[baud_idx] => uBaudMin and BaudRate[baud_idx] =< uBaudMax)
      numbaud++
  if(numbaud == 0)
    ser.Str(@ErrOutOfRange)
    return
                  
  ser.Str(String(CR, LF, "Enter maximum wait time for data per baud rate (in ms, 100 - 10000) ["))
  ser.Dec(uWaitPerBaud)         ' Display current value
  ser.Str(String("]: "))
  value := Get_Decimal_Pin      ' Get new value from user
  if (value <> -1)              ' If carriage return was not pressed...    
    if (value < 100) or (value > 10000)  ' If entered value is out of range, abort
      ser.Str(@ErrOutOfRange)
      return
    uWaitPerBaud := value

  ser.Str(String(CR, LF, "Enter number of loops per channel (1 - 1000) ["))
  ser.Dec(uLoopPerChan)         ' Display current value
  ser.Str(String("]: "))
  value := Get_Decimal_Pin      ' Get new value from user
  if (value <> -1)              ' If carriage return was pressed...
    if (value < 1) or (value > 1000)  ' If entered value is out of range, abort
      ser.Str(@ErrOutOfRange)
      return
    uLoopPerChan := value

  ser.Str(String(CR, LF, "Total time per channel: "))
  value := numbaud * uWaitPerBaud * uLoopPerChan
  if (value < 1000)                   ' Display time in milliseconds
    ser.Dec(value)
    ser.Str(String(" ms"))
  else                                ' Display time in seconds (x.yz or x.y depending on length)
    ser.Dec(value / 1000)
    if (value := (value // 1000) / 100) <> 0
      ser.Char(".")
      ser.Dec(value)
    ser.Str(String(" sec"))
    
  if(chEnd - chStart <> 0)   ' If we will be searching more than one channel...
    ser.Str(String(CR, LF, "Pause after each channel? ["))
    if (uLoopPause == 0)
      ser.Str(String("y/N]: "))
    else
      ser.Str(String("Y/n]: "))  
    ser.StrInMax(@vCmd,  MAX_INPUT_LEN) ' Wait here to receive a carriage return terminated string or one of MAX_INPUT_LEN bytes (the result is null terminated) 
    if (strsize(@vCmd) =< 1)            ' We're only looking for a single character (or NULL, which will have a string size of 0)
      case vCmd[0]                        ' Check the first character of the input string
          0:                                ' The user only entered a CR, so keep the same value and pass through.
          "N", "n":                         
            uLoopPause := 0                 ' Disable flag
          "Y", "y":
            uLoopPause := 1                 ' Enable flag
          other:
            ser.Str(@ErrOutOfRange)
            return
    else
      ser.Str(@ErrOutOfRange)
      return

  ser.Str(@MsgPressSpacebarToBegin)
  if (ser.CharIn <> " ")
    ser.Str(@ErrUARTAborted)
    return

  ser.Str(@MsgJTAGulating)
  u.TXSEnable   ' Enable level shifter outputs

  uRXD := g#PROP_SDA  ' RXD isn't used in this command, so set it to a temporary pin so it doesn't interfere with enumeration
  
  num := 0   ' Counter of possible pinouts
  ctr := 0
  repeat uTXD from chStart to chEnd  ' For every possible pin permutation...
    loopnum := 0
    loopquit := 0
    ser.Str(string(CR, LF, "Scanning channel: "))
    ser.Dec(uTXD)
    ser.Str(string(CR, LF))
    
    repeat until (loopquit == 1)
      repeat baud_idx from 0 to (constant(BaudRateEnd - BaudRate) >> 2) - 1   ' For every possible baud rate in BaudRate table...
        if((BaudRate[baud_idx] < uBaudMin) or (BaudRate[baud_idx] > uBaudMax))   ' Only use the baud rates within range defined by the user
          next
      
        uBaud := BaudRate[baud_idx]        ' Store current baud rate into uBaud variable
        UART.Start(|<uTXD, |<uRXD, uBaud)  ' Configure UART
        UART.RxFlush                       ' Flush receive buffer
     
        i := 0
        t := cnt
        repeat while (i < MAX_LEN_UART) and ((cnt - t) / (clkfreq / 1000) =< uWaitPerBaud)    ' Check for a response from the target and grab up to MAX_LEN_UART bytes
          value := UART.RxTime(20)         ' Wait to receive a byte from the target
          if (value => 0)                      
            byte[@data][i++] := value          ' Store the byte in our array and try for more!

          ' Progress indicator
          ++ctr
          Display_Progress(ctr, 50)
      
          if (ser.RxEmpty == 0)                 ' Abort scan if any key is pressed
            UART_Scan_Cleanup(num, xtxd, 0, xbaud)  ' RXD isn't used in this command
            ser.RxFlush
            ser.Str(@ErrUARTAborted)
            return

        repeat until (UART.RxTime(20) < 0)   ' Wait here until the target has stopped sending data
        
        if (i > 0)                           ' If we've received any data...
          Display_UART_Pins                    ' Display current UART pinout (TXD only)
          ser.Str(String("Data: "))            ' Display the data in ASCII
          repeat value from 0 to (i-1)                  
            if (byte[@data][value] < $20) or (byte[@data][value] > $7E) ' If the byte is an unprintable character 
              ser.Char(".")                                               ' Print a . instead
            else
              ser.Char(byte[@data][value])
     
          ser.Str(String(" [ "))
          repeat value from 0 to (i-1)        ' Display the data in hexadecimal
            ser.Hex(byte[@data][value], 2)
            ser.Char(" ")
          ser.Str(String("]", CR, LF))
          
          num += 1                            ' Increment counter
          xtxd := uTXD                        ' Keep track of most recent detection results
          xbaud := uBaud
      
      loopnum++
      if(loopnum => uLoopPerChan)
        loopquit := 1
      
    if (uLoopPause == 1) and (uTXD < chEnd)
      ser.Str(string(CR, LF, "Press spacebar to scan next channel (any other key to abort)..."))
      if (ser.CharIn <> " ")
        UART_Scan_Cleanup(num, xtxd, 0, xbaud)  ' RXD isn't used in this command
        ser.RxFlush
        ser.Str(@ErrUARTAborted)
        return
        
  if (num == 0)
    ser.Str(@ErrNoDeviceFound)
  UART_Scan_Cleanup(num, xtxd, 0, xbaud)  ' RXD isn't used in this command

  ser.Str(String(CR, LF, "UART TXD scan complete."))
  
    
PRI UART_Passthrough | value    ' UART/terminal passthrough
  ser.Str(@UARTPinoutMessage)

  ser.Str(String(CR, LF, "Enter X to disable either pin, if desired."))
  if (Set_UART == -1)     ' Ask user for the known UART configuration
    return                ' Abort if error

  ' If the user has selected to disable one of the pins, set it to a temporary pin so it doesn't interfere 
  if (uTXD == -2)
    uTXD := g#PROP_SDA
  elseif (uRXD == -2)
    uRXD := g#PROP_SDA

  ser.Str(String(CR, LF, "Enable local echo? ["))
  if (uLocalEcho == 0)
    ser.Str(String("y/N]: "))
  else
    ser.Str(String("Y/n]: "))  
  ser.StrInMax(@vCmd,  MAX_INPUT_LEN) ' Wait here to receive a carriage return terminated string or one of MAX_INPUT_LEN bytes (the result is null terminated) 
  if (strsize(@vCmd) =< 1)            ' We're only looking for a single character (or NULL, which will have a string size of 0)
    case vCmd[0]                        ' Check the first character of the input string
        0:                                ' The user only entered a CR, so keep the same value and pass through.
        "N", "n":                      
          uLocalEcho := 0                   ' Disable flag
        "Y", "y":
          uLocalEcho := 1                   ' Enable flag
        other:
          ser.Str(@ErrOutOfRange)
          return
  else
    ser.Str(@ErrOutOfRange)
    return
      
  u.TXSEnable                        ' Enable level shifter outputs
  UART.Start(|<uTXD, |<uRXD, uBaud)  ' Configure UART

  ser.Str(String(CR, LF, "Entering UART passthrough! Press Ctrl-X to abort...", CR, LF))

  repeat until (value == CAN)  ' stay in terminal passthrough until cancel value is received
    repeat while ((value := UART.rxcheck) => 0) ' if the target buffer contains data...
      ser.Char(value)                             ' ...display it

    repeat while (ser.RxEmpty == 0)             ' if the JTAGulator buffer contains data...
      if (uLocalEcho == 0)                        ' if local echo is off...
        value := ser.CharInNoEcho                   ' ...get the data (but don't echo it)
      else
        value := ser.CharIn                         ' ...get the data (and echo it)
               
      if (value <> CAN)                             
        UART.tx(value)                            ' send to the target (as long as it isn't the cancel value)

  ser.RxFlush
  UART.RxFlush

  ' Reset pin if it was disabled
  if (uTXD => g#MAX_CHAN)
    uTXD := 0 
  elseif (uRXD => g#MAX_CHAN)
    uRXD := 0
      
  ser.Str(String(CR, LF, "UART passthrough complete."))
    

PRI Set_UART : err | xtxd, xrxd, xbaud            ' Set UART configuration to known values
  ' An "X" or "x" character may be sent by the user to disable the TXD or RXD pin. This will result in Get_Pin returning a -2 value.
  ser.Str(String(CR, LF, "Enter TXD pin ["))
  ser.Dec(uTXD)               ' Display current value
  ser.Str(String("]: "))
  xtxd := Get_Pin             ' Get new value from user
  if (xtxd == -1)             ' If carriage return was pressed...      
    xtxd := uTXD                ' Keep current setting
  if (xtxd < -2) or (xtxd > g#MAX_CHAN-1)  ' If entered value is out of range, abort
    ser.Str(@ErrOutOfRange)
    return -1
    
  ser.Str(String(CR, LF, "Enter RXD pin ["))
  ser.Dec(uRXD)               ' Display current value
  ser.Str(String("]: "))
  xrxd := Get_Pin             ' Get new value from user
  if (xrxd == -1)             ' If carriage return was pressed...      
    xrxd := uRXD                ' Keep current setting
  if (xrxd < -2) or (xrxd > g#MAX_CHAN-1)  ' If entered value is out of range, abort
    ser.Str(@ErrOutOfRange)
    return -1

  ' Make sure that the pin numbers are unique
  if (xtxd == xrxd)  ' If we have a collision
    ser.Str(@ErrPinCollision)
    return -1                 ' Then exit
    
  ser.Str(String(CR, LF, "Enter baud rate ["))
  ser.Dec(uBaud)              ' Display current value
  ser.Str(String("]: "))
  xbaud := Get_Decimal_Pin    ' Get new value from user
  if (xbaud == -1)            ' If carriage return was pressed...      
    xbaud := uBaud              ' Keep current setting
  if (xbaud < BaudRate[0]) or (xbaud > BaudRate[(constant(BaudRateEnd - BaudRate) >> 2) - 1])  ' If entered value is out of range, abort
    ser.Str(@ErrOutOfRange)
    return -1

  ' Update the globals with the new values
  uTXD := xtxd      
  uRXD := xrxd
  uBaud := xbaud


PRI UART_Scan_Cleanup(num, txd, rxd, baud)
  if (num == 0)   ' If no device(s) were found during the search
    longfill(@uTXD, 0, 3)  ' Clear UART pinout + settings
  else             ' Update globals with the most recent detection results
    uTXD := txd
    uRXD := rxd
    uBaud := 0       ' For a given UART interface, multiple baud rates could return potentially valid data. So, have the user decide which is the best/most likely choice for the given target. 


PRI Display_UART_Pins
  ser.Str(String(CR, LF, "TXD: "))
  ser.Dec(uTXD)
  
  ser.Str(String(CR, LF, "RXD: "))
  if (uRXD => g#MAX_CHAN)   ' RXD isn't used during UART_Scan_TXD (we're not sending any data to the target), so it can't be determined
    ser.Str(String("N/A"))  
  else
    ser.Dec(uRXD)

  ser.Str(String(CR, LF, "Baud: "))
  ser.Dec(uBaud)

  ser.Str(String(CR, LF))
          

CON {{ GPIO METHODS }}

PRI GPIO_Init
  ' Set default parameters
  ' Write_IO_Pins
  gWriteValue := $FFFFFF

  
PRI Read_IO_Pins | value            ' Read all channels (input, one shot)  
  ser.Char(CR)
  
  u.TXSEnable                       ' Enable level shifter outputs
  dira[g#MAX_CHAN-1..0]~            ' Set all channels as inputs
  value := ina[g#MAX_CHAN-1..0]     ' Read all channels
  
  Display_IO_Pins(value)            ' Display value   


PRI Monitor_IO_Pins | value, prev   ' Read all channels (input, continuous)
  ser.Str(String(CR, LF, "Reading all channels! Press any key to abort...", CR, LF))

  u.TXSEnable                       ' Enable level shifter outputs
  dira[g#MAX_CHAN-1..0]~            ' Set all channels as inputs
  prev := -1
  
  repeat until (ser.RxEmpty == 0)
    value := ina[g#MAX_CHAN-1..0]     ' Read all channels
    if (value <> prev)                ' If there's a change in state...
      prev := value                   ' Save new value
      Display_IO_Pins(value)          ' Display value
      !outa[g#LED_G]                  ' Toggle LED between red and yellow

  ser.RxFlush

  
PRI Write_IO_Pins : err | value, i, data     ' Write all channels (output)
  ser.Str(String(CR, LF, "Enter value to output (in hex) ["))
  ser.Hex(gWriteValue, g#MAX_CHAN >> 2)  ' Display current value
  ser.Str(String("]: "))

  ' Receive hexadecimal value from the user and perform input sanitization
  ' This has do be done directly in the object since we may need to handle user input up to 32 bits
  ser.StrInMax(@vCmd,  MAX_INPUT_LEN)
  if (vCmd[0]==0)   ' If carriage return was pressed...          
     value := gWriteValue
  else
    if strsize(@vCmd) > (g#MAX_CHAN >> 2)  ' If value is larger than the our number of channels
      ser.Str(@ErrOutOfRange)
      return -1
    ' Make sure each character in the string is hexadecimal ("0"-"9","A"-"F","a"-"f")
    repeat i from 0 to strsize(@vCmd)-1
      data := vCmd[i]
      data := -15 + --data & %11011111 + 39*(data > 56)   ' Borrowed from the Parallax Serial Terminal (PST) StrToBase method     
      if (data < 0) or (data => 16)
        ser.Str(@ErrOutOfRange)
        return -1
    value := ser.StrToBase(@vCmd, 16)   ' Convert valid string into actual value
  gWriteValue := value   ' Update global with new value
 
  u.TXSEnable                       ' Enable level shifter outputs
  dira[g#MAX_CHAN-1..0]~~           ' Set all channels as outputs
  outa[g#MAX_CHAN-1..0] := value    ' Write value to output

  Display_IO_Pins(value)            ' Display value

  ser.Str(String(CR, LF, "Press any key when done..."))
  ser.CharIn       ' Wait for any key to be pressed before finishing routine (and disabling level translators)


PRI Display_IO_Pins(value) | count
  ser.Str(String(CR, LF, "CH"))
  ser.Dec(g#MAX_CHAN-1)
  ser.Str(String("..CH0: "))

  ' ...as binary characters (0/1)
  repeat count from (g#MAX_CHAN-8) to 0 step 8
    ser.Bin(value >> count, 8)
    ser.Char(" ")
    
  ' ...as hexadecimal
  ser.Str(String(" (0x"))
  ser.Hex(value, g#MAX_CHAN >> 2)
  ser.Str(String(")"))

  
CON {{ OTHER METHODS }}

PRI System_Init
  ' Set direction of I/O pins
  ' Output
  dira[g#TXS_OE] := 1
  dira[g#LED_R]  := 1        
  dira[g#LED_G]  := 1
   
  ' Set I/O pins to the proper initialization values
  u.TXSDisable    ' Disable level shifter outputs (high impedance)
  u.LedYellow     ' Yellow = system initialization

  ' Set up PWM channel for DAC output
  ' Based on Andy Lindsay's PropBOE D/A Converter (http://learn.parallax.com/node/107)
  ctra[30..26]  := %00110       ' Set CTRMODE to PWM/duty cycle (single ended) mode
  ctra[5..0]    := g#DAC_OUT    ' Set APIN to desired pin
  dira[g#DAC_OUT] := 1          ' Set pin as output
  DACOutput(0)                  ' DAC output off 

  idMenu := MENU_MAIN           ' Set default menu
  vTargetIO := -1               ' Target voltage is undefined 
  ser.Start(115_200)            ' Start serial communications                                                                                    

    
PRI Set_Target_IO_Voltage | value
  ser.Str(String(CR, LF, "Current target I/O voltage: "))
  Display_Target_IO_Voltage

  ser.Str(String(CR, LF, "Enter new target I/O voltage (1.2 - 3.3, 0 for off): "))
  value := Get_Decimal_Pin  ' Receive decimal value (including 0)
  if (value == 0)                              
    vTargetIO := -1
    DACOutput(0)               ' DAC output off 
    ser.Str(String(CR, LF, "Target I/O voltage off."))
  elseif (value < 12) or (value > 33)
    ser.Str(@ErrOutOfRange)
  else
    vTargetIO := value
    DACOutput(VoltageTable[vTargetIO - 12])    ' Look up value that corresponds to the actual desired voltage and set DAC output
    ser.Str(String(CR, LF, "New target I/O voltage set: "))
    Display_Target_IO_Voltage                  ' Print a confirmation of newly set voltage
    ser.Str(String(CR, LF, "Ensure VADJ is NOT connected to target!"))


PRI Get_Channels(min_chan) : err | xstart, xend
{
  Ask user for the range of JTAGulator channels actually hooked up
  
  Parameters: min_chan = Minimum number of pins/channels required (varies with on-chip debug interface)
}
  ser.Str(String(CR, LF, "Enter starting channel ["))
  ser.Dec(chStart)               ' Display current value
  ser.Str(String("]: "))
  xstart := Get_Decimal_Pin      ' Get new value from user
  if (xstart == -1)              ' If carriage return was pressed...      
    xstart := chStart              ' Keep current setting
  if (xstart < 0) or (xstart > g#MAX_CHAN-1)  ' If entered value is out of range, abort
    ser.Str(@ErrOutOfRange)
    return -1

  ser.Str(String(CR, LF, "Enter ending channel ["))
  if (chEnd < xstart)            ' If ending channel is less than starting channel...
    ser.Dec(xstart)
  else  
    ser.Dec(chEnd)                 ' Display current value
  ser.Str(String("]: "))
  xend := Get_Decimal_Pin        ' Get new value from user
  if (xend == -1)                ' If carriage return was pressed...
    if (chEnd < xstart)
      xend := xstart
    else     
      xend := chEnd                  ' Keep current setting
  if (xend < xstart + min_chan - 1) or (xend > g#MAX_CHAN-1)  ' If entered value is out of range, abort (channel must be greater than the minimum required for a scan)
    ser.Str(@ErrOutOfRange)
    return -1

  ' Update the globals with the new values
  chStart := xstart
  chEnd := xend


PRI Get_Pin : value | i       ' Get a number (or single character) from the user (including number 0, which prevents us from using standard Parallax Serial Terminal routines)
  ser.StrInMax(@vCmd,  MAX_INPUT_LEN)
  if (vCmd[0] == 0)
    value := -1         ' Empty string, which means a carriage return was pressed
  elseif (vCmd[0] == "X" or vCmd[0] == "x")    ' If X was entered...
    if (strsize(@vCmd) > 1)   ' If the string is longer than a single character...
      value := -3               ' ...then it's invalid
    else
      value := -2
  else
    repeat i from 0 to strsize(@vCmd)-1
      case vCmd[i]
        "0".."9":                       ' If the byte entered is an actual number...
          value *= 10                     ' ...then keep converting into a decimal value
          value += (vCmd[i] - "0")
        ".", ",":                       ' Ignore decimal point
        other:
          value := -3                   ' Invalid character(s)       
          quit

          
PRI Get_Decimal_Pin : value | i       ' Get a decimal number from the user (including number 0, which prevents us from using standard Parallax Serial Terminal routines)
  ser.StrInMax(@vCmd,  MAX_INPUT_LEN)
  if (vCmd[0] == 0)
    value := -1         ' Empty string, which means a carriage return was pressed
  else
    repeat i from 0 to strsize(@vCmd)-1
      case vCmd[i]
        "0".."9":                       ' If the byte entered is an actual number...
          value *= 10                     ' ...then keep converting into a decimal value
          value += (vCmd[i] - "0")
        ".", ",":                       ' Ignore decimal point
        other:
          value := -3                   ' Invalid character       
          quit


PRI Get_Bit_Field(value, highBit, lowBit) : fieldVal | mask, bitnum    ' Return the bit field within a specified range. Based on a fork by Bob Heinemann (https://github.com/BobHeinemann/jtagulator/blob/master/JTAGulator.spin)
  repeat bitNum from lowBit to highBit
    mask |= |<bitNum

  fieldVal := (value & mask) >> (highBit - (highBit - lowBit))


PRI Round_Up(n) : r         ' Round up value n to the nearest divisible by 4 in order for ser.Hex to display the correct number of nibbles
  case n
    1..4:    r := 4
    5..8:    r := 8
    9..12:   r := 12
    13..16:  r := 16
    17..20:  r := 20
    21..24:  r := 24
    25..28:  r := 28
    29..32:  r := 32

    
PRI Bits_to_Value(n) : r    ' r = 2^n - 1, the value when all n bits are set high (for example, n = 8, r = 0b11111111 or 255d)  
  r := 1
  repeat (n - 1)
    r <<= 1
    r |= 1
    

PRI DACOutput(dacval)
  spr[10] := dacval * 16_777_216    ' Set counter A frequency (scale = 2^32 / 256)


PRI Display_Target_IO_Voltage
  if (vTargetIO == -1)
    ser.Str(String("Undefined"))
  else
    ser.Dec(vTargetIO / 10)      ' Display vTargetIO as an x.y value
    ser.Char(".")
    ser.Dec(vTargetIO // 10)


PRI Display_Progress(ctr, mod)      ' Display a progress indicator during JTAGulation (every mod counts)
  if ((ctr // mod) == 0)   
    ser.Str(@CharProgress)    ' Print character
    !outa[g#LED_G]            ' Toggle LED between red and yellow


PRI Display_Binary(data, len) | mod, count 
  if (len < 8)                        ' Handle any length fewer than 8
    ser.Bin(data, len)
    ser.Char(" ")
  else
    if (mod := len // 8)              ' Handle any bits not divisible by 8                                      
      ser.Bin(data >> 8, mod)
      ser.Char(" ")

    repeat count from (len - mod - 8) to 0 step 8   ' Display remaining bits in groups of 8 for easier reading
      ser.Bin(data >> count, 8)
      ser.Char(" ")


PRI Display_Permutations(n, r) | value, i
{{  http://www.mathsisfun.com/combinatorics/combinations-permutations-calculator.html

    Order important, no repetition
    Total pins (n)
    Number of pins needed (r)
    Number of permutations: n! / (n-r)!
}}
  ser.Str(String(CR, LF, "Possible permutations: "))

  ' Thanks to Rednaxela of #tymkrs for the optimized calculation
  value := 1
  if (r <> 0)
    repeat i from (n - r + 1) to n
      value *= i    

  ser.Dec(value)

                           
DAT
InitHeader    byte CR, LF, LF
              byte "                                    UU  LLL", CR, LF                                     
              byte " JJJ  TTTTTTT AAAAA  GGGGGGGGGGG   UUUU LLL   AAAAA TTTTTTTT OOOOOOO  RRRRRRRRR", CR, LF 
              byte " JJJJ TTTTTTT AAAAAA GGGGGGG       UUUU LLL  AAAAAA TTTTTTTT OOOOOOO  RRRRRRRR", CR, LF  
              byte " JJJJ  TTTT  AAAAAAA GGG      UUU  UUUU LLL  AAA AAA   TTT  OOOO OOO  RRR RRR", CR, LF   
              byte " JJJJ  TTTT  AAA AAA GGG  GGG UUUU UUUU LLL AAA  AAA   TTT  OOO  OOO  RRRRRRR", CR, LF   
              byte " JJJJ  TTTT  AAA  AA GGGGGGGGG UUUUUUUU LLLLLLLL AAAA  TTT OOOOOOOOO  RRR RRR", CR, LF   
              byte "  JJJ  TTTT AAA   AA GGGGGGGGG UUUUUUUU LLLLLLLLL AAA  TTT OOOOOOOOO  RRR RRR", CR, LF   
              byte "  JJJ  TT                  GGG             AAA                         RR RRR", CR, LF   
              byte " JJJ                        GG             AA                              RRR", CR, LF   
              byte "JJJ                          G             A                                 RR", CR, LF, LF, LF 
              byte "           Welcome to JTAGulator. Press 'H' for available commands.", CR, LF
              byte "         Warning: Use of this tool may affect target system behavior!", 0

VersionInfo   byte CR, LF, "JTAGulator FW 1.4", CR, LF
              byte "Designed by Joe Grand, Grand Idea Studio, Inc.", CR, LF
              byte "Main: jtagulator.com", CR, LF
              byte "Source: github.com/grandideastudio/jtagulator", CR, LF
              byte "Support: www.parallax.com/support", 0

MenuMain      byte CR, LF, "Target Interfaces:", CR, LF
              byte "J   JTAG/IEEE 1149.1", CR, LF
              byte "U   UART/Asynchronous Serial", CR, LF
              byte "G   GPIO", CR, LF, LF
              byte "General Commands:", CR, LF
              byte "V   Set target I/O voltage (1.2V to 3.3V)", CR, LF
              byte "I   Display version information", CR, LF
              byte "H   Display available commands", 0
              
MenuJTAG      byte CR, LF, "JTAG Commands:", CR, LF
              byte "I   Identify JTAG pinout (IDCODE Scan)", CR, LF
              byte "B   Identify JTAG pinout (BYPASS Scan)", CR, LF
              byte "D   Get Device ID(s)", CR, LF
              byte "T   Test BYPASS (TDI to TDO)", CR, LF
              byte "Y   Instruction/Data Register (IR/DR) discovery", CR, LF
              byte "X   Transfer instruction/data", 0

MenuUART      byte CR, LF, "UART Commands:", CR, LF
              byte "U   Identify UART pinout", CR, LF
              byte "T   Identify UART pinout (TXD only)", CR, LF
              byte "P   UART passthrough", 0

MenuGPIO      byte CR, LF, "GPIO Commands:", CR, LF     
              byte "R   Read all channels (input, one shot)", CR, LF
              byte "C   Read all channels (input, continuous)", CR, LF  
              byte "W   Write all channels (output)", 0
                          
MenuShared    byte CR, LF, LF, "General Commands:", CR, LF
              byte "V   Set target I/O voltage (1.2V to 3.3V)", CR, LF
              byte "H   Display available commands", CR, LF
              byte "M   Return to main menu", 0

CharProgress  byte "-", 0   ' Character used for progress indicator

' Any messages repeated more than once are placed here to save space
MsgPressSpacebarToBegin     byte CR, LF, "Press spacebar to begin (any other key to abort)...", 0
MsgJTAGulating              byte CR, LF, "JTAGulating! Press any key to abort...", CR, LF, 0
MsgChannelsSetHigh          byte CR, LF, "All other channels set to output HIGH.", 0

UARTPinoutMessage           byte CR, LF, "UART pin naming is from the target's perspective.", 0

ErrTargetIOVoltage          byte CR, LF, "Target I/O voltage must be defined!", 0
ErrOutOfRange               byte CR, LF, "Value out of range!", 0
ErrPinCollision             byte CR, LF, "Pin numbers must be unique!", 0
ErrNoDeviceFound            byte CR, LF, "No target device(s) found!", 0
ErrIDCODEAborted            byte CR, LF, "IDCODE scan aborted!", 0
ErrBYPASSAborted            byte CR, LF, "BYPASS scan aborted!", 0
ErrDiscoveryAborted         byte CR, LF, "IR/DR discovery aborted!", 0
ErrUARTAborted              byte CR, LF, "UART scan aborted!", 0
                                                               
' Look-up table to correlate actual I/O voltage (1.2V to 3.3V) to DAC value
' Full DAC range is 0 to 3.3V @ 256 steps = 12.89mV/step
'                  1.2  1.3  1.4  1.5  1.6  1.7  1.8  1.9  2.0  2.1  2.2  2.3  2.4  2.5  2.6  2.7  2.8  2.9  3.0  3.1  3.2  3.3           
VoltageTable  byte  93, 101, 109, 116, 124, 132, 140, 147, 155, 163, 171, 179, 186, 194, 202, 210, 217, 225, 233, 241, 248, 255

' Look-up table of accepted values for use with UART identification
BaudRate      long  75, 110, 150, 300, 900, 1200, 1800, 2400, 3600, 4800, 7200, 9600, 14400, 19200, 28800, 31250 {MIDI}, 38400, 57600, 76800, 115200, 153600, 230400, 250000 {DMX}, 307200
BaudRateEnd

      