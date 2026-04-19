; File: windows_setup.iss
; This script builds the installer for Digital Signage Enterprise

#define MyAppName "Digital Signage"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "Your Company Name"
#define MyAppExeName "digital_signage.exe"

[Setup]
; App Information
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}

; Where the app will be installed on the client's PC (Program Files)
DefaultDirName={autopf}\{#MyAppName}

; The name of the Start Menu folder
DefaultGroupName={#MyAppName}

; Where to save the final Setup.exe file
OutputDir=Output
OutputBaseFilename=DigitalSignage_Setup_v1.0.0

; Icon for the installer itself (Optional: replace with path to your .ico if you have one)
; SetupIconFile=windows\runner\resources\app_icon.ico

Compression=lzma
SolidCompression=yes
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64

[Tasks]
; Gives the user a checkbox to create a desktop icon
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; This tells Inno Setup to grab ALL files and folders inside your Flutter Release folder
Source: "build\windows\x64\runner\Release\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
; Creates the Start Menu shortcut
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
; Creates the Desktop shortcut if the user checked the box
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

; 🌟 PRO KIOSK MOVE: Optionally create a shortcut in the Windows Startup folder!
; Remove the semicolon (;) at the start of the next line if you want the app to auto-start when Windows boots.
; Name: "{userstartup}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"

[Run]
; Gives the user a checkbox to launch the app immediately after installation finishes
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent