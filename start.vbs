' Hidden launcher for Paco's Pricing Pipeline.
' Double-click this file to start the dashboard with NO console window.
' If something goes wrong, it shows a popup explaining what to do.
' (If your computer blocks .vbs files, double-click start.bat instead.)
Option Explicit
Dim sh, fso, here, bat, logFile, q, cmdline, ret, msg
Set sh = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
here = fso.GetParentFolderName(WScript.ScriptFullName)
bat = here & "\engine\start.bat"
q = Chr(34)
logFile = sh.ExpandEnvironmentStrings("%TEMP%") & "\pppp_launch_log.txt"

' Call start.bat by full path (the current directory is excluded from command
' search on some secure machines), capture its output to a log, run it with a
' hidden window (0), and wait for it to finish (True).
cmdline = "cmd /c call " & q & bat & q & " hidden > " & q & logFile & q & " 2>&1"
ret = sh.Run(cmdline, 0, True)

' A non-zero exit means setup failed (R missing, packages could not install).
' Show the captured messages so the user is not left guessing.
If ret <> 0 Then
  msg = "Paco's Pricing Pipeline could not start." & vbCrLf & vbCrLf
  If fso.FileExists(logFile) Then
    msg = msg & fso.OpenTextFile(logFile, 1).ReadAll()
  End If
  MsgBox msg, vbExclamation, "Pricing Pipeline"
End If
