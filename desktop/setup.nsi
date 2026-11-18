Unicode true
!include "MUI2.nsh"
!include "x64.nsh"
!include "FileFunc.nsh"
!define /file OD_VERSION "VERSION"
Var updateParent
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
!macro CheckClosed
  System::Call 'kernel32::OpenMutexW(i 0x100000, i 0, w "Local\OpenDirectorDesktop.x64")p.r0'
  ${If} $0 P<> 0
    System::Call 'kernel32::CloseHandle(p r0)'
    MessageBox MB_OK|MB_ICONSTOP "Quit OpenDirector from the tray before continuing. / 请先从托盘退出 OpenDirector。" /SD IDOK
    Abort
  ${EndIf}
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
  !insertmacro CheckClosed
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
  !insertmacro CheckClosed
FunctionEnd
Section
  SetShellVarContext current
  SetRegView 64
  ; Stage completely before exchanging directories: a failed extraction leaves
  ; the installed app and the user workspace untouched.
  RMDir /r "$INSTDIR\incoming"
  ClearErrors
  SetOutPath "$INSTDIR\incoming"
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
  WriteUninstaller "$INSTDIR\Uninstall.exe"
  CreateShortcut "$SMPROGRAMS\OpenDirector.lnk" "$INSTDIR\app\OpenDirector.exe"
  CreateShortcut "$DESKTOP\OpenDirector.lnk" "$INSTDIR\app\OpenDirector.exe"
  WriteRegStr HKCU "${ARP}" "DisplayName" "OpenDirector (Windows x64)"
  WriteRegStr HKCU "${ARP}" "DisplayVersion" "${OD_VERSION}"
  WriteRegStr HKCU "${ARP}" "UninstallString" '$\"$INSTDIR\Uninstall.exe$\"'
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\App Paths\OpenDirector.exe" "" "$INSTDIR\app\OpenDirector.exe"
  ; CLI shell registration is opt-in (tray); preserve it across upgrades.
  RMDir /r "$INSTDIR\previous"
  Goto done
rollback:
  Rename "$INSTDIR\previous" "$INSTDIR\app"
failed:
  Abort "Installation failed. Check free space and close running programs. / 安装失败，请检查空间并关闭占用文件的程序。"
done:
SectionEnd
Section "Uninstall"
  SetShellVarContext current
  SetRegView 64
  Delete "$SMPROGRAMS\OpenDirector.lnk"
  Delete "$DESKTOP\OpenDirector.lnk"
  ReadRegStr $0 HKCU "Software\Microsoft\Windows\CurrentVersion\App Paths\OpenDirector-CLI.exe" ""
  ${If} $0 == "$INSTDIR\app\OpenDirector-CLI.exe"
    DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\App Paths\OpenDirector-CLI.exe"
  ${EndIf}
  DeleteRegKey HKCU "${ARP}"
  DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\App Paths\OpenDirector.exe"
  RMDir /r "$INSTDIR\app"
  RMDir /r "$INSTDIR\incoming"
  RMDir /r "$INSTDIR\previous"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"
SectionEnd
