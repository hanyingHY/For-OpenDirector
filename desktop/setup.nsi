Unicode true
!include "MUI2.nsh"
!include "x64.nsh"
!include "FileFunc.nsh"
!define /file OD_VERSION "VERSION"
Var updateParent
Var appGate
Name "OpenDirector"
OutFile "..\delivery\OpenDirector-${OD_VERSION}-x64-Setup.exe"
InstallDir "$LOCALAPPDATA\Programs\OpenDirector"
RequestExecutionLevel user
SetCompressor /SOLID lzma
!define ARP "Software\Microsoft\Windows\CurrentVersion\Uninstall\OpenDirectorDesktop"
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_INSTFILES
!define MUI_FINISHPAGE_RUN "$INSTDIR\app\OpenDirector.exe"
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"
!insertmacro MUI_LANGUAGE "SimpChinese"
!macro ReserveApp
  ; Atomic creation, not OpenMutex followed by an unprotected file exchange.
  ; Host (including desktop.4), installer and uninstaller share this gate.
  System::Call 'kernel32::CreateMutexW(p 0, i 0, w "Local\OpenDirectorDesktop.x64")p.r0 ?e'
  Pop $1
  ${If} $0 = 0
    MessageBox MB_OK|MB_ICONSTOP "Cannot reserve installation. Retry after closing OpenDirector. / 无法锁定安装目录，请退出应用后重试。" /SD IDOK
    Abort
  ${EndIf}
  ${If} $1 = 183
    System::Call 'kernel32::CloseHandle(p r0)'
    MessageBox MB_OK|MB_ICONSTOP "Quit OpenDirector from the tray and finish any other setup first. / 请先从托盘退出应用，并等待其他安装程序完成。" /SD IDOK
    Abort
  ${EndIf}
  StrCpy $appGate $0
!macroend
!macro ReleaseApp
  StrCpy $0 $appGate
  System::Call 'kernel32::CloseHandle(p r0)'
!macroend
Function .onInit
  ${GetParameters} $0
  ClearErrors
  ${GetOptions} $0 "/ODUPDATE=" $updateParent
  IfErrors normal
  ; Keep all files untouched until the old UI, Python, Agent and media job
  ; have shut down. The caller never terminates someone else's process.
  IntCmp $updateParent 0 invalid invalid waitParent
invalid:
  Abort "Invalid update parent"
waitParent:
  System::Call 'kernel32::OpenProcess(i 0x100000, i 0, i $updateParent)p.r1'
  ${If} $1 P<> 0
    System::Call 'kernel32::WaitForSingleObject(p r1, i 90000)i.r2'
    System::Call 'kernel32::CloseHandle(p r1)'
    ${If} $2 != 0
      MessageBox MB_OK|MB_ICONSTOP "OpenDirector is still running. Close it and retry. / 应用仍在运行，请关闭后重试。"
      Abort
    ${EndIf}
  ${EndIf}
  Goto checked
normal:
  StrCpy $updateParent ""
checked:
  ${IfNot} ${RunningX64}
    MessageBox MB_OK "64-bit Windows is required. / 需要 64 位 Windows。" /SD IDOK
    Abort
  ${EndIf}
  !insertmacro ReserveApp
FunctionEnd
Function .onInstSuccess
  ${If} $updateParent != ""
    SetOutPath "$INSTDIR\app"
    Exec '$\"$INSTDIR\app\OpenDirector.exe$\"'
    IfErrors 0 +2
    MessageBox MB_OK "Update installed. Reopen from the Start menu. / 更新已安装，请从开始菜单启动。"
  ${EndIf}
FunctionEnd
Function .onInstFailed
  ${If} $updateParent != ""
    MessageBox MB_OK|MB_ICONSTOP "Update failed. Check free space, close OpenDirector and retry the installer. Your workspace was not removed. / 更新失败，请检查剩余空间，关闭应用后重试安装。工作区未删除。"
  ${EndIf}
FunctionEnd
Function un.onInit
  !insertmacro ReserveApp
FunctionEnd
Section
  SetShellVarContext current
  SetRegView 64
  ; Stage completely before exchanging directories: a failed extraction leaves
  ; the installed app and the user workspace untouched.
  ; If a previous installer died between the two renames, restore the only
  ; intact copy BEFORE touching staging. Even a failed retry leaves it usable.
  IfFileExists "$INSTDIR\app\OpenDirector.exe" stage
  IfFileExists "$INSTDIR\previous\OpenDirector.exe" 0 stage
  ClearErrors
  Rename "$INSTDIR\previous" "$INSTDIR\app"
  IfErrors failed
stage:
  RMDir /r "$INSTDIR\incoming"
  IfFileExists "$INSTDIR\incoming" failed
  ClearErrors
  SetOutPath "$INSTDIR\incoming"
  IfErrors failed
  File /r "..\.work\app\*"
  IfErrors failed
  SetOutPath "$INSTDIR"
  RMDir /r "$INSTDIR\previous"
  IfFileExists "$INSTDIR\app\OpenDirector.exe" 0 activate
  ClearErrors
  Rename "$INSTDIR\app" "$INSTDIR\previous"
  IfErrors failed
activate:
  ClearErrors
  Rename "$INSTDIR\incoming" "$INSTDIR\app"
  IfErrors rollback
  ClearErrors
  WriteUninstaller "$INSTDIR\Uninstall.exe"
  IfErrors undoActivation
  CreateShortcut "$SMPROGRAMS\OpenDirector.lnk" "$INSTDIR\app\OpenDirector.exe"
  CreateShortcut "$DESKTOP\OpenDirector.lnk" "$INSTDIR\app\OpenDirector.exe"
  WriteRegStr HKCU "${ARP}" "DisplayName" "OpenDirector (Windows x64)"
  WriteRegStr HKCU "${ARP}" "DisplayVersion" "${OD_VERSION}"
  WriteRegStr HKCU "${ARP}" "UninstallString" '$\"$INSTDIR\Uninstall.exe$\"'
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\App Paths\OpenDirector.exe" "" "$INSTDIR\app\OpenDirector.exe"
  ; CLI shell registration is opt-in (tray); preserve it across upgrades.
  RMDir /r "$INSTDIR\previous"
  Goto done
undoActivation:
  ClearErrors
  Rename "$INSTDIR\app" "$INSTDIR\incoming"
  IfErrors failed
rollback:
  Rename "$INSTDIR\previous" "$INSTDIR\app"
failed:
  Abort "Installation failed. Check free space and close running programs. / 安装失败，请检查空间并关闭占用文件的程序。"
done:
  !insertmacro ReleaseApp
SectionEnd
Section "Uninstall"
  SetShellVarContext current
  SetRegView 64
  RMDir /r "$INSTDIR\app"
  RMDir /r "$INSTDIR\incoming"
  RMDir /r "$INSTDIR\previous"
  IfFileExists "$INSTDIR\app\*.*" unFailed
  IfFileExists "$INSTDIR\previous\*.*" unFailed
  IfFileExists "$INSTDIR\incoming\*.*" unFailed
  Delete "$SMPROGRAMS\OpenDirector.lnk"
  Delete "$DESKTOP\OpenDirector.lnk"
  ReadRegStr $0 HKCU "Software\Microsoft\Windows\CurrentVersion\App Paths\OpenDirector-CLI.exe" ""
  ${If} $0 == "$INSTDIR\app\OpenDirector-CLI.exe"
    DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\App Paths\OpenDirector-CLI.exe"
  ${EndIf}
  DeleteRegKey HKCU "${ARP}"
  DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\App Paths\OpenDirector.exe"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"
  !insertmacro ReleaseApp
  Goto unDone
unFailed:
  Abort "Close programs using OpenDirector and retry uninstall. / 请关闭占用文件的程序，再次卸载。"
unDone:
SectionEnd
