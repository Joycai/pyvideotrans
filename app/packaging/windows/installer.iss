; 字幕工具 Windows 安装包（Inno Setup 6）。
; 安装向导、安装包 exe、开始菜单与「应用和功能」里的图标统一用
; windows\runner\resources\app_icon.ico —— 与应用本体同一个文件。
;
; 用法（在 app 目录下）：
;   flutter build windows --release
;   iscc packaging\windows\installer.iss
; 产物：build\dist\字幕工具-<版本>-setup.exe

#define AppName "字幕工具"
#define ExeName "subtitle_studio.exe"
#define AppPublisher "pyvideotrans"
#define AppId "{{A8F5F2C9-7E4B-4C0D-9B3A-52B1F0E6D3A1}"
#define SourceDir "..\..\build\windows\x64\runner\Release"
#define IconFile "..\..\windows\runner\resources\app_icon.ico"
#ifndef AppVersion
  #define AppVersion GetVersionNumbersString(SourceDir + "\" + ExeName)
#endif

[Setup]
AppId={#AppId}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
UninstallDisplayName={#AppName}
UninstallDisplayIcon={app}\{#ExeName}
SetupIconFile={#IconFile}
OutputDir=..\..\build\dist
OutputBaseFilename={#AppName}-{#AppVersion}-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequiredOverridesAllowed=dialog

[Languages]
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#ExeName}"; IconFilename: "{app}\{#ExeName}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#ExeName}"; IconFilename: "{app}\{#ExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#ExeName}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
