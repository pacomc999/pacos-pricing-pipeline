' Hidden launcher for Paco's Pricing Pipeline.
' Double-click this file to start the dashboard with NO console window.
' If something goes wrong, it shows a popup explaining what to do.
' (If your computer blocks .vbs files, double-click start.bat instead.)
Option Explicit
Dim sh, fso, here, bat, logFile, q, cmdline, ret, msg, tempDir, stamp, n, oldFile
Set sh = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
here = fso.GetParentFolderName(WScript.ScriptFullName)
bat = here & "\engine\start.bat"
q = Chr(34)
tempDir = sh.ExpandEnvironmentStrings("%TEMP%")

' Sweep any leftover logs from previous runs (e.g. after an abnormal shutdown)
' so they never accumulate. A log still held open by a running instance stays
' locked and is simply skipped.
On Error Resume Next
For Each oldFile In fso.GetFolder(tempDir).Files
  If LCase(Left(oldFile.Name, 12)) = "pppp_launch_" Then fso.DeleteFile oldFile.Path, True
Next
On Error GoTo 0

' Unique log file per launch. A single shared log was held open for the whole
' time the tool ran, so relaunching within the self-shutdown grace collided on
' that one file and the new launch silently failed. A per-launch name avoids it.
Randomize
n = Now
stamp = Year(n) & Right("0" & Month(n), 2) & Right("0" & Day(n), 2) & "_" & _
        Right("0" & Hour(n), 2) & Right("0" & Minute(n), 2) & Right("0" & Second(n), 2) & _
        "_" & Int(Rnd * 100000)
logFile = tempDir & "\pppp_launch_" & stamp & ".txt"

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

' Remove this launch's log now that it has been read, so logs do not pile up.
On Error Resume Next
If fso.FileExists(logFile) Then fso.DeleteFile logFile
On Error GoTo 0
