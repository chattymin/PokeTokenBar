; Inno Setup script for the Windows build of PokeTokenBar.
; Per-user install (no admin) to %LOCALAPPDATA%\Programs\PokeTokenBar, Start-menu shortcut (so it is
; searchable), Add/Remove Programs uninstaller, and launch-after-install. Built by scripts via:
;   ISCC /DSrcDir=<portable folder> /DAppVer=<x.y.z.w> /DOutDir=<out> installer\PokeTokenBar.iss
; The three /D defines are required.

#ifndef SrcDir
  #error "Define SrcDir (the portable build folder) with /DSrcDir=..."
#endif
#ifndef AppVer
  #define AppVer "0.0.0.0"
#endif
#ifndef OutDir
  #define OutDir "."
#endif

[Setup]
; A stable AppId keeps upgrades replacing the same install (and one Add/Remove Programs entry).
AppId={{7C1B9F3A-2E4D-4B6A-9C21-PKTKNBARWIN01}}
AppName=PokeTokenBar
AppVersion={#AppVer}
AppPublisher=jhpark3975
DefaultDirName={localappdata}\Programs\PokeTokenBar
DefaultGroupName=PokeTokenBar
DisableProgramGroupPage=yes
DisableDirPage=yes
PrivilegesRequired=lowest
OutputDir={#OutDir}
OutputBaseFilename=PokeTokenBar-Setup-{#AppVer}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayName=PokeTokenBar
UninstallDisplayIcon={app}\PokeTokenBar.ico
; Pokémon-egg icon for the installer itself (relative to this .iss).
SetupIconFile=PokeTokenBar.ico
; Detect / close a running instance (matches the app's single-instance mutex) so files can be replaced.
AppMutex=Local\PokeTokenBar-SingleInstance
CloseApplications=yes
RestartApplications=no

[Files]
Source: "{#SrcDir}\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion
Source: "PokeTokenBar.ico"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
; Start-menu shortcut → shows up in Windows Search. Desktop shortcut is opt-in. Egg icon for both.
Name: "{userprograms}\PokeTokenBar"; Filename: "{app}\PokeTokenBar.exe"; IconFilename: "{app}\PokeTokenBar.ico"; Comment: "PokeTokenBar — AI token usage in the tray"
Name: "{userdesktop}\PokeTokenBar"; Filename: "{app}\PokeTokenBar.exe"; IconFilename: "{app}\PokeTokenBar.ico"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional shortcuts:"

[Run]
; Launch after install — runs in silent mode too (no 'postinstall'), so an auto-update relaunches the app.
Filename: "{app}\PokeTokenBar.exe"; Description: "Launch PokeTokenBar"; Flags: nowait
