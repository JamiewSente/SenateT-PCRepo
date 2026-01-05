#SingleInstance Force
SetTitleMatchMode, 2

; ==============================
; 🔧 GLOBAL STATE & GUI
; ==============================
global toggle := true      ; Master switch
global dashMode := false   ; Confirmation Mode switch
global CCM_Mode := false   ; CCM Mode switch

Gui, +Resize +MinSize300x230
Gui, Add, Button, gToggleAll w200 h45 center vMainToggleBtn, Disable All Hotkeys
Gui, Add, Button, gToggleDashMode w200 h30 center vDashModeBtn, Enable Confirmation Mode
Gui, Add, Button, gToggleCCMMode w200 h30 center vCCMModeBtn, Enable CCM Mode
Gui, Show, w300 h200, AHK Controller
return

ToggleAll:
    toggle := !toggle
    GuiControl,, MainToggleBtn, % toggle ? "Disable All Hotkeys" : "Enable All Hotkeys"
    TrayTip, AHK, % toggle ? "Hotkeys ENABLED" : "Hotkeys DISABLED (Passthrough ON)"
return

ToggleDashMode:
    dashMode := !dashMode
    if (dashMode) {
        CCM_Mode := false
        GuiControl,, CCMModeBtn, Enable CCM Mode
    }
    GuiControl,, DashModeBtn, % dashMode ? "Disable Confirmation Mode" : "Enable Confirmation Mode"
    TrayTip, Mode, % dashMode ? "Confirmation Mode: ON" : "Confirmation Mode: OFF"
return

ToggleCCMMode:
    CCM_Mode := !CCM_Mode
    if (CCM_Mode) {
        dashMode := false
        GuiControl,, DashModeBtn, Enable Confirmation Mode
    }
    GuiControl,, CCMModeBtn, % CCM_Mode ? "Disable CCM Mode" : "Enable CCM Mode"
    TrayTip, Mode, % CCM_Mode ? "CCM Mode: ON" : "CCM Mode: OFF"
return

GuiClose:
    ExitApp

; =========================================================
; 🛑 CONTEXT: The keys below ONLY work when 'toggle' is TRUE
; =========================================================
#If (toggle)

; -----------------------------------------------------------
; 📞 [ HOTKEY – Nextiva Switch
; -----------------------------------------------------------
$[::  
    DetectHiddenWindows, Off
    if WinExist("Nextiva") {
        WinActivate
        WinWaitActive, Nextiva,, 2
    }
    if !WinActive("Nextiva") {
        WinGet, idList, List, ahk_exe Nextiva.exe
        Loop, %idList% {
            this_id := idList%A_Index%
            WinGetTitle, thisTitle, ahk_id %this_id%
            if InStr(thisTitle, "Nextiva") {
                WinActivate, ahk_id %this_id%
                WinWaitActive, ahk_id %this_id%,, 2
                if WinActive("ahk_id " . this_id)
                    break
            }
        }
    }
    if !WinActive("Nextiva") {
        MsgBox, Could not find Nextiva window.
        return
    }
    Send !+e
    Sleep, 150
    Send !{Tab}
return

; -----------------------------------------------------------
; ☎ ] HOTKEY – Log First, Then Call
; -----------------------------------------------------------
]::  
    Clipboard := ""
    Send ^c
    ClipWait, 1
    if ErrorLevel {
        MsgBox, Couldn't copy number.
        return
    }
    Sleep, 100

    phone := RegExReplace(Clipboard, "[^\d]", "")
    if (StrLen(phone) < 7) {
        MsgBox, Invalid number: %Clipboard%
        return
    }

    ; --- STEP 1: DATA ENTRY ---
    if (!dashMode) {
        
        if (CCM_Mode) {
            ; >>> CCM MODE INPUTS <<<
            
            ; 1. Move to Column A (Input 1 Location)
            Send {Home}
            Sleep, 100 
            
            ; 2. Copy current number to do math
            Clipboard := ""
            Send ^c
            ClipWait, 0.5
            
            ; 3. Calculate New Value (Current + 1)
            oldVal := RegExReplace(Clipboard, "[^\d]", "") 
            if (oldVal == "")
                oldVal := 0
            
            newVal := oldVal + 1
            
            ; 4. Generate Today's Date
            FormatTime, TodayDate,, M/d/yyyy
            
            ; 5. Type Sequence:
            ; Input 1: newVal
            ; Input 2: TodayDate
            ; Input 3: JC
            SendInput, %newVal%{Tab}%TodayDate%{Tab}JC{Down}
        } 
        else {
            ; >>> STANDARD MODE INPUTS <<<
            Send ^{Right}
            Sleep, 50
            Send {Right}
            Sleep, 50
            Send ^+`;  ; Date Stamp
            Sleep, 100
            Send ^{Left}
            Sleep, 50
            Send {Right}
            Sleep, 50
            Send {Down}
            Sleep, 100

            ; Log to text file (Standard Mode only)
            logFile := A_ScriptDir . "\call_log.txt"
            FormatTime, timestamp,, yyyy-MM-dd HH:mm:ss
            FileAppend, %timestamp% - Called: %phone%`n, %logFile%
        }
    }

    ; --- STEP 2: MAKE THE CALL (Run Last) ---
    Run, tel:%phone%
return

; -----------------------------------------------------------
; 🔊 F1 – SoundShow (Only works in DashMode)
; -----------------------------------------------------------
$F1::
    if (dashMode) {
        if WinExist("ahk_exe SoundShow.exe") {
            WinActivate
            WinWaitActive, ahk_exe SoundShow.exe,, 2
            Send 1
        } else {
            MsgBox, Could not find SoundShow.exe
        }
    } else {
        SendInput {F1}
    }
return

; -----------------------------------------------------------
; 🗓 Date Stamps
; -----------------------------------------------------------
$`::
    FormatTime, d,, M/d/yy
    SendInput JC LVM %d%
return

$\::
    FormatTime, d,, M/d/yy
    SendInput JC Confirmed %d%
return

#If 

; ==============================
; 🔧 F2 – Special Context
; ==============================
#If (toggle && !GetKeyState("Shift","P"))
F2::Send ^#t
#If