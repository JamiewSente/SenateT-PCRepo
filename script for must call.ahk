#Requires AutoHotkey v1.1+
#SingleInstance Force
SendMode Input
SetKeyDelay, 10, 10

F3::
{
    ; 1) Copy selected phone cell
    Clipboard := ""
    Send, ^c
    ClipWait, 0.5
    phoneRaw := Clipboard
    if (!phoneRaw) {
        MsgBox, 48, Error, No phone number found in the selected cell.
        return
    }

    ; 2) Clean number (digits and + only)
    phoneClean := RegExReplace(phoneRaw, "[^\d+]")

    ; 3) Navigate to log column (Ctrl+Right ×5, Ctrl+Left ×1, Right ×1)
    Loop, 5 {
        Send, ^{Right}
        Sleep, 50
    }
    Send, ^{Left}
    Sleep, 50
    Send, {Right}
    Sleep, 50

    ; 4) Type today’s date MM/DD/YYYY
    date := A_MM "/" A_DD "/" A_YYYY
    SendInput, %date%
    Sleep, 100

    ; 5) Insert note "JC LVM" via Shift+F2
    Send, +{F2}
    Sleep, 100
    SendInput, JC LVM
    Sleep, 100
    Send, {Enter}
    Sleep, 100

    ; 6) Finally dial the number
    Run, tel:%phoneClean%

    return
}