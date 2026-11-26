; Inno Setup script - builds LiveTV-Player-Windows-Setup-<version>.exe
; Compiled by the GitHub workflow:  ISCC /DMyAppVersion=1.0.x installer\windows-setup.iss

#define MyAppName "Live TV Player"
#define MyAppExe "live_tv_player.exe"
#ifndef MyAppVersion
  #define MyAppVersion "1.0.0"
#endif

[Setup]
AppId={{8B0F3C2E-6C1A-4C8E-9D2B-3A7E5F1C9D44}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher=Ukendt Software
AppPublisherURL=https://github.com/3obmarino/live-iptv-player
AppSupportURL=https://github.com/3obmarino/live-iptv-player/issues
AppUpdatesURL=https://github.com/3obmarino/live-iptv-player/releases/latest
AppCopyright=Copyright (C) 2026 Ukendt Software
VersionInfoCompany=Ukendt Software
VersionInfoProductName={#MyAppName}
VersionInfoVersion={#MyAppVersion}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=..\dist
OutputBaseFilename=LiveTV-Player-Windows-Setup-{#MyAppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequiredOverridesAllowed=dialog
UninstallDisplayIcon={app}\{#MyAppExe}
SetupIconFile=..\branding\icon.ico
CloseApplications=force
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "danish"; MessagesFile: "compiler:Languages\Danish.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExe}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall

[UninstallRun]
; Close the app first: a running app keeps its .exe and DLLs locked, and
; they were left behind in Program Files.
Filename: "{sys}\taskkill.exe"; Parameters: "/F /IM {#MyAppExe}"; Flags: runhidden; RunOnceId: "CloseLiveTV"

[UninstallDelete]
; Anything the app created next to itself, and downloaded update installers
Type: filesandordirs; Name: "{app}"
Type: files; Name: "{%TEMP}\LiveTV-update-*"

[CustomMessages]
english.RemoveData=Also remove your profiles, favourites, TV guide and channel logos from this PC?%n%nChoose No to keep them for a later reinstall.
danish.RemoveData=Skal dine profiler, favoritter, tv-guide og kanallogoer også fjernes fra denne pc?%n%nVælg Nej for at beholde dem til en senere geninstallation.

[Code]
// Clean uninstall: the app keeps its data (profiles with the encrypted
// login, channel list, TV guide, logo cache) in %APPDATA%\Ukendt Software\Live TV Player.
// Ask before deleting it; a silent uninstall keeps it.
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  DataDir, OldDir, CompanyDir: String;
begin
  if CurUninstallStep = usPostUninstall then
  begin
    CompanyDir := ExpandConstant('{userappdata}\Ukendt Software');
    DataDir := CompanyDir + '\Live TV Player';
    OldDir := ExpandConstant('{userappdata}\dk.livetvplayer'); // before 1.0.112
    if (DirExists(DataDir) or DirExists(OldDir)) and (not UninstallSilent) then
      if MsgBox(CustomMessage('RemoveData'), mbConfirmation, MB_YESNO) = IDYES then
      begin
        DelTree(DataDir, True, True, True);
        DelTree(OldDir, True, True, True);
        RemoveDir(CompanyDir); // only if no other Ukendt Software app uses it
      end;
  end;
end;
