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

' A non-zero exit code can mean two very different things:
'   1) Setup failed (R missing, packages could not install) - a real problem.
'   2) The app started fine and you just closed it - shiny::runApp also returns
'      a non-zero code on a normal shutdown.
' To tell them apart, read the log: it only prints "Listening on" once the
' dashboard has actually started. If that line is there, any non-zero exit is
' just a normal shutdown, so stay quiet. Only show the popup on a real failure.
Dim logText
logText = ""
If fso.FileExists(logFile) Then
  logText = fso.OpenTextFile(logFile, 1).ReadAll()
End If

If ret <> 0 And InStr(logText, "Listening on") = 0 Then
  msg = "Paco's Pricing Pipeline could not start." & vbCrLf & vbCrLf & logText
  MsgBox msg, vbExclamation, "Pricing Pipeline"
End If
