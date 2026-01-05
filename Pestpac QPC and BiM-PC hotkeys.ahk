#Persistent
#SingleInstance Force

SetTimer, UpdatePreview, 300

; --- 1. HANDLE INSPECTOR LIST EXTERNAL FILE ---
inspectorFile := A_ScriptDir . "\inspectors.txt"

; If the file doesn't exist, create it with your current default list
if !FileExist(inspectorFile) {
    defaultList =
    (
Sol Tucker
John Gray
Rich Seymour
Tim Lyons
James Mcclain
Rick Nischan
James Gray
Sean Reynolds
Kris Grice
Kris Bradley
Scott Morgan
Michael Southerland
    )
    FileAppend, %defaultList%, %inspectorFile%
}

; Read the file and format it for the dropdown (replace newlines with |)
FileRead, rawList, %inspectorFile%
StringReplace, techList, rawList, `r`n, |, All
StringReplace, techList, techList, `n, |, All
; -----------------------------------------------

Gui, Add, Button, w100 h20 gEditInspectors, ✏️ Edit Inspectors
Gui, Add, Text,, Inspector Name:
; Note: We use the variable TechName here
Gui, Add, ComboBox, vTechName w250, %techList%

Gui, Add, Text,, Select Service Plan:
Gui, Add, Radio, vPlanType, QPC
Gui, Add, Radio,, Bi-Monthly
Gui, Add, Edit, vCustomPlan w200, Custom Label

Gui, Add, Text,, Covered Pests:
Gui, Add, CheckBox, vRodents gUpdatePreview, Rodents
Gui, Add, CheckBox, vRoaches gUpdatePreview, Roaches

Gui, Add, Text,, Extra Details:
Gui, Add, Edit, vExtraDetails w300 gUpdatePreview

Gui, Add, Text,, Initial Price:
Gui, Add, Edit, vPrice w100 gUpdatePreview

Gui, Add, Text,, Monthly Amount:
Gui, Add, Edit, vMonthly w100 gUpdatePreview

Gui, Add, Text,, Quarterly Amount:
Gui, Add, Edit, vQuarterly w100 gUpdatePreview hwndQuarterlyHwnd

Gui, Add, Text,, 🪞 Live Preview:
Gui, Add, Edit, vPreviewOutput w600 r3 ReadOnly

Gui, Add, Button, Default gBuildString, Generate
Gui, Add, Button, x+10 gClearForm, Clear

Gui, Show,, Service Description Builder
return

UpdatePreview:
Gui, Submit, NoHide
gosub, RefreshPreview
return

RefreshPreview:
plan := ""
if (PlanType = 1)
    plan := "QPC"
else if (PlanType = 2)
    plan := "Bi-Monthly"
else if (CustomPlan != "")
    plan := CustomPlan

pestDetail := ""
if (Rodents)
    pestDetail .= "rodents"
if (Roaches)
    pestDetail .= (pestDetail ? ", " : "") . "roaches"
if (ExtraDetails != "")
    pestDetail .= (pestDetail ? ", " : "") . ExtraDetails

pestSection := (pestDetail != "") ? "w/" . pestDetail : ""

priceString := "$" . Price
if (Monthly != "") {
    if (plan = "QPC")
        multiplier := 3
    else if (plan = "Bi-Monthly")
        multiplier := 2
    else
        multiplier := 1
    multiplied := Round(Monthly * multiplier)
    priceString := "$" . Price . "/$" . multiplied . " (billed $" . Monthly . " monthly)"
}
else if (Quarterly != "") {
    priceString := "$" . Price . "/$" . Quarterly . " (billed $" . Quarterly . " quarterly)"
}

FormatTime, today,, M/d/yyyy
output := ""
if (TechName != "")
    output := today . " " . TechName . " SOLD " . plan . (pestSection ? " (" . pestSection . ") " : " ") . priceString

GuiControl,, PreviewOutput, %output%
return

BuildString:
Gui, Submit, NoHide
if (Monthly != "" && Quarterly != "") {
    MsgBox, Please enter either monthly or quarterly — not both.
    return
}
Clipboard := PreviewOutput
MsgBox, % "Formatted service text copied to clipboard:`n`n" . PreviewOutput
return

ClearForm:
; Force clear the ComboBox by unselecting AND wiping text
GuiControl, Choose, TechName, 0
GuiControl,, TechName, % ""

GuiControl,, PlanType, 0
GuiControl,, CustomPlan
GuiControl,, Rodents, 0
GuiControl,, Roaches, 0
GuiControl,, ExtraDetails
GuiControl,, Price
GuiControl,, Monthly
GuiControl,, Quarterly
GuiControl,, PreviewOutput
gosub, UpdatePreview
return

EditInspectors:
Run, notepad.exe "%inspectorFile%"
MsgBox, 4, Reload Required, After you save your changes to the inspector list, click Yes to reload the script.
IfMsgBox Yes
    Reload
return

; F8 -> Paste Preview
F8::
Gui, Submit, NoHide
if (PreviewOutput != "")
    SendInput, %PreviewOutput%
return

F9::
Gui, Submit, NoHide
FormatTime, today,, MM/dd/yyyy
FormatTime, billLater,, MM/20/yyyy
FormatTime, month,, M

; Determine plan type
if (PlanType = 1) {
    planCode := "PC-Q"
    if (month ~= "^(1|4|7|10)$")
        cycle := "QJAN1SUN"
    else if (month ~= "^(2|5|8|11)$")
        cycle := "QFEB1SUN"
    else
        cycle := "QMAR1SUN"
    multiplier := 3
} else if (PlanType = 2) {
    planCode := "PC B"
    if (month ~= "^(1|3|5|7|9|11)$")
        cycle := "BJAN1SUN"
    else
        cycle := "BFEB1SUN"
    multiplier := 2
} else {
    planCode := "PC Custom"
    cycle := "UnknownCycle"
    multiplier := 1
}

monthlyAmount := Round(Monthly)
total := Round(monthlyAmount * multiplier)

SendInput, %planCode%
Sleep, 2000
SendInput, {Tab 3}
SendInput, {Backspace 10}
SendInput, %total%
SendInput, {Tab 4}
SendInput, %cycle%
SendInput, {Tab 8}
SendInput, {Down 5}
SendInput, {Tab}
SendInput, %today%
SendInput, {Tab 8}
SendInput, %billLater%
SendInput, {Tab 27}
SendInput, Monthly 12
SendInput, {Tab}
SendInput, %monthlyAmount%
SendInput, {Tab 2}
SendInput, %billLater%
SendInput, {Tab}
return