Unicode true
!include "MUI2.nsh"
!include "x64.nsh"
Name "OpenDirector"
OutFile "..\delivery\OpenDirector-0.1.4-desktop.2-x64-Setup.exe"
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
    MessageBox MB_OK|MB_ICONSTOP "Close OpenDirector before continuing. / 请先关闭 OpenDirector。" /SD IDOK
    Abort
  ${EndIf}
!macroend
Function .onInit
  ${IfNot} ${RunningX64}
    MessageBox MB_OK "64-bit Windows is required. / 需要 64 位 Windows。" /SD IDOK
    Abort
  ${EndIf}
  !insertmacro CheckClosed
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
  WriteRegStr HKCU "${ARP}" "DisplayVersion" "0.1.4-desktop.2"
  WriteRegStr HKCU "${ARP}" "UninstallString" '$\"$INSTDIR\Uninstall.exe$\"'
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\App Paths\OpenDirector.exe" "" "$INSTDIR\app\OpenDirector.exe"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\App Paths\OpenDirector-CLI.exe" "" "$INSTDIR\app\OpenDirector-CLI.exe"
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
  DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\App Paths\OpenDirector-CLI.exe"
  DeleteRegKey HKCU "${ARP}"
  DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\App Paths\OpenDirector.exe"
  RMDir /r "$INSTDIR\app"
  RMDir /r "$INSTDIR\incoming"
  RMDir /r "$INSTDIR\previous"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"
SectionEnd
