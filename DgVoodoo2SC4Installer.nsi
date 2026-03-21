!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "nsDialogs.nsh"
!include "StrFunc.nsh"
!include "x64.nsh"
!include "FileFunc.nsh"
!cd "${__FILEDIR__}"
${Using:StrFunc} StrStr

!define APP_NAME "dgVoodoo 2 for SC4"
!define APP_VERSION "v5.0"
!define APP_SUPPORT_SUBDIR "DgVoodoo2-SC4"
!define UNINSTALL_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\DgVoodoo2SC4"
!define APP_REG_KEY "Software\DgVoodoo2SC4"
;
; GPU detection is implemented as a generated temporary PowerShell script.
; This avoids NSIS string-length limits that can truncate large inline commands.
;
; The generated script:
; 1. Queries Win32_VideoController via Get-CimInstance.
; 2. Falls back to Get-WmiObject on older systems.
; 3. Falls back again to HKLM\SYSTEM\CurrentControlSet\Control\Video.
; 4. Collects adapter/vendor strings and reduces them to Intel, AMD, and NVIDIA.
; 5. Prints a comma-separated summary such as "Intel, NVIDIA" or "AMD".
;
; During install, the exact script text is also written to GPU-detect-script.ps1
; in the support folder for debugging and manual runs.
;
!ifndef WS_CHILD
  !define WS_CHILD 0x40000000
!endif
!ifndef WS_VISIBLE
  !define WS_VISIBLE 0x10000000
!endif
!ifndef WS_TABSTOP
  !define WS_TABSTOP 0x00010000
!endif
!ifndef WS_VSCROLL
  !define WS_VSCROLL 0x00200000
!endif
!ifndef WS_EX_CLIENTEDGE
  !define WS_EX_CLIENTEDGE 0x00000200
!endif
!ifndef ES_MULTILINE
  !define ES_MULTILINE 0x0004
!endif
!ifndef ES_AUTOVSCROLL
  !define ES_AUTOVSCROLL 0x0040
!endif
!ifndef ES_READONLY
  !define ES_READONLY 0x0800
!endif

Name "${APP_NAME} ${APP_VERSION}"
OutFile "DgVoodoo2-SC4-${APP_VERSION}-Setup.exe"
Unicode True
RequestExecutionLevel admin
ShowInstDetails show
ShowUninstDetails show

Var Dialog
Var GameRoot
Var AppsDir
Var InstallerDir
Var BackupRoot
Var GameExePath
Var DetectedGpuVendor
Var DetectedGpuSummary
Var GpuDetectExitCode
Var GpuDetectRawOutput
Var GpuDetectScriptPath
Var RequestedGpuVendor
Var EffectiveGpuVendor
Var Has4GBPatch
Var Apply4GBPatch
Var HGameRoot
Var HBrowseGameRoot
Var HGpuVendor
Var HPatchStatus
Var HPatchAuto
Var HPatchManual
Var HGpuNotes
Var HSummaryText
Var RelevantReadmePath
Var PatchStatusFont

!define MUI_ABORTWARNING
!define MUI_FINISHPAGE_RUN
!define MUI_FINISHPAGE_RUN_TEXT "Open relevant instructions in Notepad"
!define MUI_FINISHPAGE_RUN_FUNCTION OpenRelevantReadme
!define MUI_FINISHPAGE_RUN_CHECKED

!insertmacro MUI_PAGE_WELCOME
Page Custom ConfigureGamePage ConfigureGamePageLeave
Page Custom ConfigureOptionsPage ConfigureOptionsPageLeave
Page Custom ConfigureSummaryPage
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_UNPAGE_FINISH

!insertmacro MUI_LANGUAGE "English"

Function .onInit
  SetShellVarContext current
  InitPluginsDir
  StrCpy $GpuDetectScriptPath "$PLUGINSDIR\gpu-detect.ps1"
  SetOutPath "$PLUGINSDIR"
  File /oname=gpu-detect.ps1 "gpu-detect.ps1"
  Call DetectDefaultGameRoot
  Call UpdateDerivedPaths
  Call DetectPreferredGpuVendor
  StrCpy $RequestedGpuVendor "Manual"
  StrCpy $EffectiveGpuVendor "None"
  StrCpy $Has4GBPatch "0"
  StrCpy $Apply4GBPatch "1"
  StrCpy $GpuDetectExitCode "unknown"
  StrCpy $GpuDetectRawOutput ""
  ${If} $DetectedGpuVendor == "Intel"
  ${OrIf} $DetectedGpuVendor == "AMD"
  ${OrIf} $DetectedGpuVendor == "NVIDIA"
    StrCpy $RequestedGpuVendor "$DetectedGpuVendor"
    StrCpy $EffectiveGpuVendor "$DetectedGpuVendor"
  ${EndIf}
FunctionEnd

Function DetectDefaultGameRoot
  StrCpy $GameRoot "$PROGRAMFILES32\SimCity 4 Deluxe Edition"
  SetRegView 32
  ReadRegStr $0 HKLM "SOFTWARE\Maxis\SimCity 4" "Install Dir"
  ${If} $0 != ""
    StrCpy $GameRoot $0
  ${EndIf}
FunctionEnd

Function UpdateDerivedPaths
  StrCpy $AppsDir "$GameRoot\Apps"
  StrCpy $InstallerDir "$AppsDir\${APP_SUPPORT_SUBDIR}"
  StrCpy $BackupRoot "$InstallerDir\Backup"
FunctionEnd

Function DetectPreferredGpuVendor
  StrCpy $DetectedGpuVendor "Unknown"
  StrCpy $DetectedGpuSummary "Unknown"
  StrCpy $GpuDetectExitCode "unknown"
  StrCpy $GpuDetectRawOutput ""
  ClearErrors
  nsExec::ExecToStack '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$GpuDetectScriptPath"'
  Pop $0
  Pop $1
  StrCpy $GpuDetectExitCode $0
  StrCpy $GpuDetectRawOutput $1
  ${If} ${Errors}
    StrCpy $GpuDetectExitCode "nsExec error"
    StrCpy $GpuDetectRawOutput ""
    Return
  ${EndIf}
  ${If} $0 != "0"
    Return
  ${EndIf}
  ${If} $1 == ""
    Return
  ${EndIf}

  StrCpy $DetectedGpuSummary ""
  ${StrStr} $2 $1 "Intel"
  ${If} $2 != ""
    StrCpy $DetectedGpuSummary "Intel"
  ${EndIf}
  ${StrStr} $2 $1 "AMD"
  ${If} $2 != ""
    ${If} $DetectedGpuSummary == ""
      StrCpy $DetectedGpuSummary "AMD"
    ${Else}
      StrCpy $DetectedGpuSummary "$DetectedGpuSummary, AMD"
    ${EndIf}
  ${EndIf}
  ${StrStr} $2 $1 "NVIDIA"
  ${If} $2 != ""
    ${If} $DetectedGpuSummary == ""
      StrCpy $DetectedGpuSummary "NVIDIA"
    ${Else}
      StrCpy $DetectedGpuSummary "$DetectedGpuSummary, NVIDIA"
    ${EndIf}
  ${EndIf}

  ${If} $DetectedGpuSummary == ""
    StrCpy $DetectedGpuSummary "Unknown"
    Return
  ${EndIf}

  ${StrStr} $2 $DetectedGpuSummary "NVIDIA"
  ${If} $2 != ""
    StrCpy $DetectedGpuVendor "NVIDIA"
    Return
  ${EndIf}
  ${StrStr} $2 $DetectedGpuSummary "AMD"
  ${If} $2 != ""
    StrCpy $DetectedGpuVendor "AMD"
    Return
  ${EndIf}
  ${StrStr} $2 $DetectedGpuSummary "Intel"
  ${If} $2 != ""
    StrCpy $DetectedGpuVendor "Intel"
  ${EndIf}
FunctionEnd

Function ResolveGameExecutable
  StrCpy $GameExePath ""
  ${If} ${FileExists} "$AppsDir\SimCity 4.exe"
    StrCpy $GameExePath "$AppsDir\SimCity 4.exe"
  ${ElseIf} ${FileExists} "$AppsDir\SimCity4.exe"
    StrCpy $GameExePath "$AppsDir\SimCity4.exe"
  ${EndIf}
FunctionEnd

Function ValidateGameExecutable
  Call ResolveGameExecutable
  ${If} $GameExePath == ""
    MessageBox MB_OK|MB_ICONSTOP "Could not find SimCity 4 in '$AppsDir'.$\r$\n$\r$\nExpected either 'SimCity 4.exe' or 'SimCity4.exe' inside the Apps folder."
    Abort
  ${EndIf}

  ClearErrors
  GetDLLVersion "$GameExePath" $0 $1
  ${If} ${Errors}
    MessageBox MB_OK|MB_ICONSTOP "Could not read the version information from '$GameExePath'.$\r$\n$\r$\nThis installer requires the SimCity 4 1.1.641.x executable."
    Abort
  ${EndIf}

  IntOp $2 $0 >> 16
  IntOp $2 $2 & 0xFFFF
  IntOp $3 $0 & 0xFFFF
  IntOp $4 $1 >> 16
  IntOp $4 $4 & 0xFFFF
  IntOp $5 $1 & 0xFFFF

  ${If} $2 != 1
  ${OrIf} $3 != 1
  ${OrIf} $4 != 641
    MessageBox MB_OK|MB_ICONSTOP "Unsupported SimCity 4 version detected in '$GameExePath'.$\r$\n$\r$\nFound: $2.$3.$4.$5$\r$\nRequired: 1.1.641.x$\r$\n$\r$\nPlease update the game before continuing."
    Abort
  ${EndIf}
FunctionEnd

Function Detect4GBPatchState
  StrCpy $Has4GBPatch "0"
  ${If} $GameExePath == ""
    Return
  ${EndIf}

  ClearErrors
  FileOpen $0 "$GameExePath" r
  ${If} ${Errors}
    Return
  ${EndIf}

  FileSeek $0 60 SET
  ClearErrors
  FileReadByte $0 $1
  FileReadByte $0 $2
  FileReadByte $0 $3
  FileReadByte $0 $4
  ${If} ${Errors}
    FileClose $0
    Return
  ${EndIf}

  IntOp $5 $2 << 8
  IntOp $5 $5 + $1
  IntOp $6 $3 << 16
  IntOp $5 $5 + $6
  IntOp $6 $4 << 24
  IntOp $5 $5 + $6

  IntOp $5 $5 + 22
  FileSeek $0 $5 SET
  ClearErrors
  FileReadByte $0 $1
  FileReadByte $0 $2
  ${If} ${Errors}
    FileClose $0
    Return
  ${EndIf}
  FileClose $0

  IntOp $3 $2 << 8
  IntOp $3 $3 + $1
  IntOp $3 $3 & 0x20

  ${If} $3 != 0
    StrCpy $Has4GBPatch "1"
  ${EndIf}
FunctionEnd

Function ConfigureGamePage
  nsDialogs::Create 1018
  Pop $Dialog
  ${If} $Dialog == error
    Abort
  ${EndIf}

  ${NSD_CreateLabel} 0u 0u 100% 24u "Choose the SimCity 4 game folder. The installer will copy dgVoodoo files into the game root and Apps folder, backing up any replaced files first."
  ${NSD_CreateLabel} 0u 32u 100% 10u "SimCity 4 game root (contains Apps):"
  ${NSD_CreateDirRequest} 0u 44u 82% 12u "$GameRoot"
  Pop $HGameRoot
  ${NSD_CreateButton} 84% 44u 16% 12u "Browse..."
  Pop $HBrowseGameRoot
  ${NSD_OnClick} $HBrowseGameRoot OnBrowseGameRoot

  nsDialogs::Show
FunctionEnd

Function OnBrowseGameRoot
  Pop $0
  nsDialogs::SelectFolderDialog "Select SimCity 4 game root folder" "$GameRoot"
  Pop $0
  ${If} $0 != error
    StrCpy $GameRoot $0
    Call UpdateDerivedPaths
    ${NSD_SetText} $HGameRoot $GameRoot
  ${EndIf}
FunctionEnd

Function ConfigureGamePageLeave
  ${NSD_GetText} $HGameRoot $GameRoot
  ${If} $GameRoot == ""
    MessageBox MB_OK|MB_ICONEXCLAMATION "Game root cannot be empty."
    Abort
  ${EndIf}

  Call UpdateDerivedPaths

  ${IfNot} ${FileExists} "$AppsDir\*.*"
    MessageBox MB_OK|MB_ICONSTOP "Could not find '$AppsDir'.$\r$\n$\r$\nPlease select your SimCity 4 game root folder."
    Abort
  ${EndIf}

  Call ValidateGameExecutable
  Call Detect4GBPatchState

  ${If} $Has4GBPatch == "1"
    StrCpy $Apply4GBPatch "0"
  ${Else}
    StrCpy $Apply4GBPatch "1"
  ${EndIf}
FunctionEnd

Function RefreshOptionsPage
  ${NSD_GetText} $HGpuVendor $0
  ${If} $0 == "Intel"
    StrCpy $RequestedGpuVendor "Intel"
    StrCpy $EffectiveGpuVendor "Intel"
  ${ElseIf} $0 == "AMD"
    StrCpy $RequestedGpuVendor "AMD"
    StrCpy $EffectiveGpuVendor "AMD"
  ${ElseIf} $0 == "NVIDIA"
    StrCpy $RequestedGpuVendor "NVIDIA"
    StrCpy $EffectiveGpuVendor "NVIDIA"
  ${Else}
    StrCpy $RequestedGpuVendor "Manual"
    StrCpy $EffectiveGpuVendor "None"
  ${EndIf}

  ${If} $Has4GBPatch == "1"
    ${NSD_SetText} $HPatchStatus "4GB patch status: ALREADY APPLIED"
    SetCtlColors $HPatchStatus "008000" "transparent"
    EnableWindow $HPatchAuto 0
    EnableWindow $HPatchManual 0
    ${NSD_Check} $HPatchManual
    StrCpy $Apply4GBPatch "0"
  ${Else}
    ${NSD_SetText} $HPatchStatus "4GB patch status: NOT DETECTED"
    SetCtlColors $HPatchStatus "CC0000" "transparent"
    EnableWindow $HPatchAuto 1
    EnableWindow $HPatchManual 1
    ${If} $Apply4GBPatch == "1"
      ${NSD_Check} $HPatchAuto
    ${Else}
      ${NSD_Check} $HPatchManual
    ${EndIf}
  ${EndIf}

  ${If} $EffectiveGpuVendor == "AMD"
    ${NSD_SetText} $HGpuNotes "Detected GPU adapters (best effort): $DetectedGpuSummary.$\r$\n$\r$\nSelected GPU profile: AMD.$\r$\nInstaller action: set dgVoodoo FPSLimit to 300.$\r$\nManual follow-up: review the AMD GPU Fix readme for the remaining Adrenalin settings."
  ${ElseIf} $EffectiveGpuVendor == "NVIDIA"
    ${NSD_SetText} $HGpuNotes "Detected GPU adapters (best effort): $DetectedGpuSummary.$\r$\n$\r$\nSelected GPU profile: NVIDIA.$\r$\nInstaller action: set Windows GPU preference to High Performance for SimCity 4 and dgVoodooCpl.$\r$\nManual follow-up: review the NVIDIA GPU Fix readme for the remaining settings."
  ${ElseIf} $EffectiveGpuVendor == "Intel"
    ${NSD_SetText} $HGpuNotes "Detected GPU adapters (best effort): $DetectedGpuSummary.$\r$\n$\r$\nSelected GPU profile: Intel.$\r$\nNo vendor-specific automation will be applied for Intel.$\r$\nManual follow-up: review the Intel GPU Fix readme and update Intel graphics drivers if needed."
  ${Else}
    ${NSD_SetText} $HGpuNotes "Detected GPU adapters (best effort): $DetectedGpuSummary.$\r$\n$\r$\nSelected GPU profile: Manual only.$\r$\nNo vendor-specific automation will be applied.$\r$\nPick Intel, AMD, or NVIDIA manually if you want the installer to apply the safe vendor-specific step for that profile."
  ${EndIf}
FunctionEnd

Function OnGpuVendorChange
  Pop $0
  Call RefreshOptionsPage
FunctionEnd

Function ConfigureOptionsPage
  nsDialogs::Create 1018
  Pop $Dialog
  ${If} $Dialog == error
    Abort
  ${EndIf}

  ${NSD_CreateLabel} 0u 0u 100% 14u "Choose how the installer should handle the 4GB patch, then select the GPU profile you want to use for the remaining automation and instructions."
  ${NSD_CreateLabel} 0u 16u 100% 10u ""
  Pop $HPatchStatus
  CreateFont $PatchStatusFont "$(^Font)" "8" "700"
  SendMessage $HPatchStatus ${WM_SETFONT} $PatchStatusFont 1

  ${NSD_CreateRadioButton} 0u 30u 100% 10u "If the 4GB patch is missing, try to apply it automatically"
  Pop $HPatchAuto

  ${NSD_CreateRadioButton} 0u 44u 100% 10u "Leave the 4GB patch step manual"
  Pop $HPatchManual

  ${NSD_CreateLabel} 0u 60u 100% 10u "GPU profile to use:"
  ${NSD_CreateDropList} 0u 72u 100% 70u ""
  Pop $HGpuVendor
  ${NSD_CB_AddString} $HGpuVendor "Intel"
  ${NSD_CB_AddString} $HGpuVendor "AMD"
  ${NSD_CB_AddString} $HGpuVendor "NVIDIA"
  ${NSD_CB_AddString} $HGpuVendor "Manual only"
  ${If} $RequestedGpuVendor == "Intel"
    ${NSD_CB_SelectString} $HGpuVendor "Intel"
  ${ElseIf} $RequestedGpuVendor == "AMD"
    ${NSD_CB_SelectString} $HGpuVendor "AMD"
  ${ElseIf} $RequestedGpuVendor == "NVIDIA"
    ${NSD_CB_SelectString} $HGpuVendor "NVIDIA"
  ${ElseIf} $RequestedGpuVendor == "Manual"
    ${NSD_CB_SelectString} $HGpuVendor "Manual only"
  ${Else}
    ${NSD_CB_SelectString} $HGpuVendor "Manual only"
  ${EndIf}
  ${NSD_OnChange} $HGpuVendor OnGpuVendorChange

  nsDialogs::CreateControl "EDIT" ${WS_CHILD}|${WS_VISIBLE}|${WS_TABSTOP}|${WS_VSCROLL}|${ES_MULTILINE}|${ES_AUTOVSCROLL}|${ES_READONLY}|${ES_WANTRETURN} ${WS_EX_CLIENTEDGE} 0u 92u 100% -2u ""
  Pop $HGpuNotes

  Call RefreshOptionsPage
  nsDialogs::Show
FunctionEnd

Function ConfigureOptionsPageLeave
  Call RefreshOptionsPage

  ${NSD_GetState} $HPatchAuto $0
  ${If} $0 == ${BST_CHECKED}
    StrCpy $Apply4GBPatch "1"
  ${Else}
    StrCpy $Apply4GBPatch "0"
  ${EndIf}
FunctionEnd

Function ConfigureSummaryPage
  nsDialogs::Create 1018
  Pop $Dialog
  ${If} $Dialog == error
    Abort
  ${EndIf}

  ${If} $Has4GBPatch == "1"
    StrCpy $0 "Already applied"
  ${Else}
    StrCpy $0 "Not detected"
  ${EndIf}
  ${If} $Apply4GBPatch == "1"
    StrCpy $1 "Automatic if missing"
  ${ElseIf} $Has4GBPatch == "1"
    StrCpy $1 "No action needed"
  ${Else}
    StrCpy $1 "Manual"
  ${EndIf}
  ${If} $RequestedGpuVendor == "Manual"
    StrCpy $2 "Manual only"
  ${Else}
    StrCpy $2 "$EffectiveGpuVendor"
  ${EndIf}
  ${If} $EffectiveGpuVendor == "AMD"
    StrCpy $3 "Set dgVoodoo FPSLimit to 300"
  ${ElseIf} $EffectiveGpuVendor == "NVIDIA"
    StrCpy $3 "Set Windows GPU preference to High Performance"
  ${Else}
    StrCpy $3 "None"
  ${EndIf}

  ${NSD_CreateLabel} 0u 0u 100% 10u "Review settings before installation:"
  nsDialogs::CreateControl "EDIT" ${WS_CHILD}|${WS_VISIBLE}|${WS_TABSTOP}|${WS_VSCROLL}|${ES_MULTILINE}|${ES_AUTOVSCROLL}|${ES_READONLY}|${ES_WANTRETURN} ${WS_EX_CLIENTEDGE} 0u 14u 100% -2u "Game root:$\r$\n$GameRoot$\r$\n$\r$\nGame executable:$\r$\n$GameExePath$\r$\n$\r$\nDetected GPU adapters (best effort): $DetectedGpuSummary$\r$\nSuggested GPU profile: $DetectedGpuVendor$\r$\nSelected GPU profile: $2$\r$\nVendor-specific automation: $3$\r$\n$\r$\n4GB patch status: $0$\r$\n4GB patch handling: $1$\r$\n$\r$\nFiles will be installed into:$\r$\n$GameRoot$\r$\n$AppsDir$\r$\n$\r$\nBackups and uninstall files will be stored in:$\r$\n$InstallerDir"
  Pop $HSummaryText

  nsDialogs::Show
FunctionEnd

Section "Install"
  SetShellVarContext current
  CreateDirectory "$InstallerDir"
  CreateDirectory "$BackupRoot"
  CreateDirectory "$BackupRoot\Apps"

  ${If} ${FileExists} "$GameRoot\Graphics Rules.sgr"
    ${IfNot} ${FileExists} "$BackupRoot\Graphics Rules.sgr"
      CopyFiles /SILENT "$GameRoot\Graphics Rules.sgr" "$BackupRoot"
      DetailPrint "Backed up Graphics Rules.sgr"
    ${EndIf}
  ${EndIf}
  ${If} ${FileExists} "$GameRoot\Video Cards.sgr"
    ${IfNot} ${FileExists} "$BackupRoot\Video Cards.sgr"
      CopyFiles /SILENT "$GameRoot\Video Cards.sgr" "$BackupRoot"
      DetailPrint "Backed up Video Cards.sgr"
    ${EndIf}
  ${EndIf}
  ${If} ${FileExists} "$AppsDir\D3D8.dll"
    ${IfNot} ${FileExists} "$BackupRoot\Apps\D3D8.dll"
      CopyFiles /SILENT "$AppsDir\D3D8.dll" "$BackupRoot\Apps"
      DetailPrint "Backed up D3D8.dll"
    ${EndIf}
  ${EndIf}
  ${If} ${FileExists} "$AppsDir\D3D9.dll"
    ${IfNot} ${FileExists} "$BackupRoot\Apps\D3D9.dll"
      CopyFiles /SILENT "$AppsDir\D3D9.dll" "$BackupRoot\Apps"
      DetailPrint "Backed up D3D9.dll"
    ${EndIf}
  ${EndIf}
  ${If} ${FileExists} "$AppsDir\D3DImm.dll"
    ${IfNot} ${FileExists} "$BackupRoot\Apps\D3DImm.dll"
      CopyFiles /SILENT "$AppsDir\D3DImm.dll" "$BackupRoot\Apps"
      DetailPrint "Backed up D3DImm.dll"
    ${EndIf}
  ${EndIf}
  ${If} ${FileExists} "$AppsDir\DDraw.dll"
    ${IfNot} ${FileExists} "$BackupRoot\Apps\DDraw.dll"
      CopyFiles /SILENT "$AppsDir\DDraw.dll" "$BackupRoot\Apps"
      DetailPrint "Backed up DDraw.dll"
    ${EndIf}
  ${EndIf}
  ${If} ${FileExists} "$AppsDir\dgVoodoo.conf"
    ${IfNot} ${FileExists} "$BackupRoot\Apps\dgVoodoo.conf"
      CopyFiles /SILENT "$AppsDir\dgVoodoo.conf" "$BackupRoot\Apps"
      DetailPrint "Backed up dgVoodoo.conf"
    ${EndIf}
  ${EndIf}
  ${If} ${FileExists} "$AppsDir\dgVoodooCpl.exe"
    ${IfNot} ${FileExists} "$BackupRoot\Apps\dgVoodooCpl.exe"
      CopyFiles /SILENT "$AppsDir\dgVoodooCpl.exe" "$BackupRoot\Apps"
      DetailPrint "Backed up dgVoodooCpl.exe"
    ${EndIf}
  ${EndIf}
  ${If} ${FileExists} "$AppsDir\4gb_patch.exe"
    ${IfNot} ${FileExists} "$BackupRoot\Apps\4gb_patch.exe"
      CopyFiles /SILENT "$AppsDir\4gb_patch.exe" "$BackupRoot\Apps"
      DetailPrint "Backed up 4gb_patch.exe"
    ${EndIf}
  ${EndIf}

  SetOutPath "$GameRoot"
  File "SimCity 4\Graphics Rules.sgr"
  File "SimCity 4\Video Cards.sgr"

  SetOutPath "$AppsDir"
  File "SimCity 4\Apps\D3D8.dll"
  File "SimCity 4\Apps\D3D9.dll"
  File "SimCity 4\Apps\D3DImm.dll"
  File "SimCity 4\Apps\DDraw.dll"
  File "SimCity 4\Apps\dgVoodoo.conf"
  File "SimCity 4\Apps\dgVoodooCpl.exe"
  File "SimCity 4\Apps\4gb_patch.exe"

  SetOutPath "$InstallerDir"
  File "01 - Installation guide.txt"
  File "3a - Intel GPU Fix.txt"
  File "3b - AMD GPU Fix.txt"
  File "3c - NVIDIA GPU Fix.txt"
  CopyFiles /SILENT "$GpuDetectScriptPath" "$InstallerDir\GPU-detect-script.ps1"

  WriteUninstaller "$InstallerDir\Uninstall-DgVoodoo2-SC4.exe"

  WriteRegStr HKCU "${APP_REG_KEY}" "GameRoot" "$GameRoot"
  WriteRegStr HKCU "${APP_REG_KEY}" "AppsDir" "$AppsDir"
  WriteRegStr HKCU "${APP_REG_KEY}" "InstallerDir" "$InstallerDir"
  WriteRegStr HKCU "${APP_REG_KEY}" "BackupRoot" "$BackupRoot"
  WriteRegStr HKCU "${APP_REG_KEY}" "GameExePath" "$GameExePath"

  Delete "$InstallerDir\GPU-detect-debug.txt"
  FileOpen $0 "$InstallerDir\GPU-detect-debug.txt" w
  FileWrite $0 'GPU detect debug log$\r$\n'
  FileWrite $0 'Script path at runtime: $GpuDetectScriptPath$\r$\n'
  FileWrite $0 'Exit code: $GpuDetectExitCode$\r$\n'
  FileWrite $0 'Raw output: $GpuDetectRawOutput$\r$\n'
  FileWrite $0 'Normalized summary: $DetectedGpuSummary$\r$\n'
  FileWrite $0 'Suggested profile: $DetectedGpuVendor$\r$\n'
  FileWrite $0 'Selected profile: $EffectiveGpuVendor$\r$\n'
  FileClose $0

  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayName" "${APP_NAME} ${APP_VERSION}"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayVersion" "${APP_VERSION}"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "Publisher" "SimCity 4 Community"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "InstallLocation" "$GameRoot"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "UninstallString" "$\"$InstallerDir\Uninstall-DgVoodoo2-SC4.exe$\""
  WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoModify" 1
  WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoRepair" 1

  ${If} $Apply4GBPatch == "1"
    DetailPrint "Attempting to apply the bundled 4GB patch to $GameExePath"
    nsExec::ExecToLog '"$AppsDir\4gb_patch.exe" "$GameExePath"'
    Pop $0
    DetailPrint "4GB patch tool exit code: $0"
    Call Detect4GBPatchState
    ${If} $Has4GBPatch != "1"
      MessageBox MB_OK|MB_ICONEXCLAMATION "Automatic 4GB patching did not complete successfully.$\r$\n$\r$\nPlease open '$AppsDir' and drag '$GameExePath' onto 4gb_patch.exe manually before launching the game."
    ${EndIf}
  ${EndIf}

  ${If} $EffectiveGpuVendor == "AMD"
    WriteINIStr "$AppsDir\dgVoodoo.conf" "GeneralExt" "FPSLimit" "300"
    DetailPrint "Set dgVoodoo FPSLimit to 300 for AMD."
  ${EndIf}

  ${If} $EffectiveGpuVendor == "NVIDIA"
    ReadRegStr $0 HKCU "${APP_REG_KEY}" "GpuPrefGameHadValue"
    ${If} $0 == ""
      ReadRegStr $1 HKCU "Software\Microsoft\DirectX\UserGpuPreferences" "$GameExePath"
      ${If} $1 == ""
        WriteRegStr HKCU "${APP_REG_KEY}" "GpuPrefGameHadValue" "0"
      ${Else}
        WriteRegStr HKCU "${APP_REG_KEY}" "GpuPrefGameHadValue" "1"
        WriteRegStr HKCU "${APP_REG_KEY}" "GpuPrefGameValue" "$1"
      ${EndIf}
    ${EndIf}

    StrCpy $2 "$AppsDir\dgVoodooCpl.exe"
    ReadRegStr $0 HKCU "${APP_REG_KEY}" "GpuPrefCplHadValue"
    ${If} $0 == ""
      ReadRegStr $1 HKCU "Software\Microsoft\DirectX\UserGpuPreferences" "$2"
      ${If} $1 == ""
        WriteRegStr HKCU "${APP_REG_KEY}" "GpuPrefCplHadValue" "0"
      ${Else}
        WriteRegStr HKCU "${APP_REG_KEY}" "GpuPrefCplHadValue" "1"
        WriteRegStr HKCU "${APP_REG_KEY}" "GpuPrefCplValue" "$1"
      ${EndIf}
    ${EndIf}

    WriteRegStr HKCU "Software\Microsoft\DirectX\UserGpuPreferences" "$GameExePath" "GpuPreference=2;"
    WriteRegStr HKCU "Software\Microsoft\DirectX\UserGpuPreferences" "$2" "GpuPreference=2;"
    DetailPrint "Set Windows GPU preference to High Performance for SimCity 4 and dgVoodooCpl."
  ${EndIf}
SectionEnd

Function .onInstSuccess
  ${If} $Has4GBPatch == "1"
    StrCpy $0 "4GB patch status: applied."
  ${Else}
    StrCpy $0 "4GB patch status: still needs manual attention."
  ${EndIf}

  ${If} $EffectiveGpuVendor == "AMD"
    StrCpy $1 "AMD follow-up: review the AMD GPU Fix notes in '$InstallerDir' for the remaining Adrenalin changes."
  ${ElseIf} $EffectiveGpuVendor == "NVIDIA"
    StrCpy $1 "NVIDIA follow-up: Windows GPU preference has been set, then review the NVIDIA GPU Fix notes in '$InstallerDir'."
  ${ElseIf} $EffectiveGpuVendor == "Intel"
    StrCpy $1 "Intel follow-up: review the Intel GPU Fix notes in '$InstallerDir' and update Intel graphics drivers if needed."
  ${Else}
    StrCpy $1 "GPU follow-up: open the matching GPU fix note in '$InstallerDir' and apply the remaining manual steps."
  ${EndIf}

  MessageBox MB_OK|MB_ICONINFORMATION "Installation completed.$\r$\n$\r$\n$0$\r$\n$\r$\n$1$\r$\n$\r$\nSupport files and uninstall data are stored in:$\r$\n$InstallerDir"
FunctionEnd

Function ResolveRelevantReadmePath
  ${If} $Has4GBPatch != "1"
    StrCpy $RelevantReadmePath "$InstallerDir\01 - Installation guide.txt"
  ${ElseIf} $EffectiveGpuVendor == "Intel"
    StrCpy $RelevantReadmePath "$InstallerDir\3a - Intel GPU Fix.txt"
  ${ElseIf} $EffectiveGpuVendor == "AMD"
    StrCpy $RelevantReadmePath "$InstallerDir\3b - AMD GPU Fix.txt"
  ${ElseIf} $EffectiveGpuVendor == "NVIDIA"
    StrCpy $RelevantReadmePath "$InstallerDir\3c - NVIDIA GPU Fix.txt"
  ${Else}
    StrCpy $RelevantReadmePath "$InstallerDir\01 - Installation guide.txt"
  ${EndIf}
FunctionEnd

Function OpenRelevantReadme
  Call ResolveRelevantReadmePath
  ${If} ${FileExists} "$RelevantReadmePath"
    Exec '"$SYSDIR\notepad.exe" "$RelevantReadmePath"'
  ${Else}
    ExecShell "open" "$InstallerDir"
  ${EndIf}
FunctionEnd

Function un.onInit
  SetShellVarContext current
  ReadRegStr $GameRoot HKCU "${APP_REG_KEY}" "GameRoot"
  ${If} $GameRoot == ""
    StrCpy $GameRoot "$PROGRAMFILES32\SimCity 4 Deluxe Edition"
    SetRegView 32
    ReadRegStr $0 HKLM "SOFTWARE\Maxis\SimCity 4" "Install Dir"
    ${If} $0 != ""
      StrCpy $GameRoot $0
    ${EndIf}
  ${EndIf}
  StrCpy $AppsDir "$GameRoot\Apps"
  StrCpy $InstallerDir "$AppsDir\${APP_SUPPORT_SUBDIR}"
  StrCpy $BackupRoot "$InstallerDir\Backup"
  ReadRegStr $AppsDir HKCU "${APP_REG_KEY}" "AppsDir"
  ReadRegStr $InstallerDir HKCU "${APP_REG_KEY}" "InstallerDir"
  ReadRegStr $BackupRoot HKCU "${APP_REG_KEY}" "BackupRoot"
  ReadRegStr $GameExePath HKCU "${APP_REG_KEY}" "GameExePath"
  ${If} $AppsDir == ""
    StrCpy $AppsDir "$GameRoot\Apps"
  ${EndIf}
  ${If} $InstallerDir == ""
    StrCpy $InstallerDir "$AppsDir\${APP_SUPPORT_SUBDIR}"
  ${EndIf}
  ${If} $BackupRoot == ""
    StrCpy $BackupRoot "$InstallerDir\Backup"
  ${EndIf}
  ${If} $GameExePath == ""
    ${If} ${FileExists} "$AppsDir\SimCity 4.exe"
      StrCpy $GameExePath "$AppsDir\SimCity 4.exe"
    ${ElseIf} ${FileExists} "$AppsDir\SimCity4.exe"
      StrCpy $GameExePath "$AppsDir\SimCity4.exe"
    ${EndIf}
  ${EndIf}
FunctionEnd

Section "Uninstall"
  SetShellVarContext current

  Delete "$GameRoot\Graphics Rules.sgr"
  ${If} ${FileExists} "$BackupRoot\Graphics Rules.sgr"
    Rename "$BackupRoot\Graphics Rules.sgr" "$GameRoot\Graphics Rules.sgr"
  ${EndIf}

  Delete "$GameRoot\Video Cards.sgr"
  ${If} ${FileExists} "$BackupRoot\Video Cards.sgr"
    Rename "$BackupRoot\Video Cards.sgr" "$GameRoot\Video Cards.sgr"
  ${EndIf}

  Delete "$AppsDir\D3D8.dll"
  ${If} ${FileExists} "$BackupRoot\Apps\D3D8.dll"
    Rename "$BackupRoot\Apps\D3D8.dll" "$AppsDir\D3D8.dll"
  ${EndIf}

  Delete "$AppsDir\D3D9.dll"
  ${If} ${FileExists} "$BackupRoot\Apps\D3D9.dll"
    Rename "$BackupRoot\Apps\D3D9.dll" "$AppsDir\D3D9.dll"
  ${EndIf}

  Delete "$AppsDir\D3DImm.dll"
  ${If} ${FileExists} "$BackupRoot\Apps\D3DImm.dll"
    Rename "$BackupRoot\Apps\D3DImm.dll" "$AppsDir\D3DImm.dll"
  ${EndIf}

  Delete "$AppsDir\DDraw.dll"
  ${If} ${FileExists} "$BackupRoot\Apps\DDraw.dll"
    Rename "$BackupRoot\Apps\DDraw.dll" "$AppsDir\DDraw.dll"
  ${EndIf}

  Delete "$AppsDir\dgVoodoo.conf"
  ${If} ${FileExists} "$BackupRoot\Apps\dgVoodoo.conf"
    Rename "$BackupRoot\Apps\dgVoodoo.conf" "$AppsDir\dgVoodoo.conf"
  ${EndIf}

  Delete "$AppsDir\dgVoodooCpl.exe"
  ${If} ${FileExists} "$BackupRoot\Apps\dgVoodooCpl.exe"
    Rename "$BackupRoot\Apps\dgVoodooCpl.exe" "$AppsDir\dgVoodooCpl.exe"
  ${EndIf}

  Delete "$AppsDir\4gb_patch.exe"
  ${If} ${FileExists} "$BackupRoot\Apps\4gb_patch.exe"
    Rename "$BackupRoot\Apps\4gb_patch.exe" "$AppsDir\4gb_patch.exe"
  ${EndIf}

  ReadRegStr $0 HKCU "${APP_REG_KEY}" "GpuPrefGameHadValue"
  ${If} $0 == "1"
    ReadRegStr $1 HKCU "${APP_REG_KEY}" "GpuPrefGameValue"
    WriteRegStr HKCU "Software\Microsoft\DirectX\UserGpuPreferences" "$GameExePath" "$1"
  ${ElseIf} $0 == "0"
    DeleteRegValue HKCU "Software\Microsoft\DirectX\UserGpuPreferences" "$GameExePath"
  ${EndIf}

  StrCpy $2 "$AppsDir\dgVoodooCpl.exe"
  ReadRegStr $0 HKCU "${APP_REG_KEY}" "GpuPrefCplHadValue"
  ${If} $0 == "1"
    ReadRegStr $1 HKCU "${APP_REG_KEY}" "GpuPrefCplValue"
    WriteRegStr HKCU "Software\Microsoft\DirectX\UserGpuPreferences" "$2" "$1"
  ${ElseIf} $0 == "0"
    DeleteRegValue HKCU "Software\Microsoft\DirectX\UserGpuPreferences" "$2"
  ${EndIf}

  Delete "$InstallerDir\01 - Installation guide.txt"
  Delete "$InstallerDir\3a - Intel GPU Fix.txt"
  Delete "$InstallerDir\3b - AMD GPU Fix.txt"
  Delete "$InstallerDir\3c - NVIDIA GPU Fix.txt"
  Delete "$InstallerDir\GPU-detect-script.ps1"
  Delete "$InstallerDir\GPU-detect-debug.txt"
  Delete "$InstallerDir\Uninstall-DgVoodoo2-SC4.exe"

  DeleteRegKey HKCU "${UNINSTALL_KEY}"
  DeleteRegKey HKCU "${APP_REG_KEY}"

  RMDir "$BackupRoot\Apps"
  RMDir "$BackupRoot"
  RMDir "$InstallerDir"
SectionEnd
