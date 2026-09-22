; Joycai Subtitle Studio Windows 安装包（Inno Setup 7）。
; 安装向导、安装包 exe、开始菜单与「应用和功能」里的图标统一用
; windows\runner\resources\app_icon.ico —— 与应用本体同一个文件。
;
; 应用名跟安装语言走（[CustomMessages] 里的 AppName）：选中文装出来叫
; Joycai字幕工具，选英文叫 Joycai Subtitle Studio。安装目录与安装包文件名
; 不跟语言走 —— 落盘的路径换语言就变，升级和脚本都会找不到。
;
; 用法（在 app 目录下）：
;   flutter build windows --release
;   iscc packaging\windows\installer.iss
; 产物：build\dist\JoycaiSubtitleStudio-<版本>-setup.exe

#define AppNameEn "Joycai Subtitle Studio"
#define AppNameZh "Joycai字幕工具"
#define OutputName "JoycaiSubtitleStudio"
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
AppName={cm:AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={autopf}\{#AppNameEn}
DefaultGroupName={cm:AppName}
UninstallDisplayName={cm:AppName}
UninstallDisplayIcon={app}\{#ExeName}
SetupIconFile={#IconFile}
OutputDir=..\..\build\dist
OutputBaseFilename={#OutputName}-{#AppVersion}-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequiredOverridesAllowed=dialog

[Languages]
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[CustomMessages]
; LaunchApp 不写成 {cm:LaunchProgram,{cm:AppName}} —— 常量套常量在参数里解析不可靠，
; 整句各写一份省事也保险。
chinesesimplified.AppName={#AppNameZh}
chinesesimplified.LaunchApp=运行 {#AppNameZh}
english.AppName={#AppNameEn}
english.LaunchApp=Launch {#AppNameEn}

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{cm:AppName}"; Filename: "{app}\{#ExeName}"; IconFilename: "{app}\{#ExeName}"
Name: "{autodesktop}\{cm:AppName}"; Filename: "{app}\{#ExeName}"; IconFilename: "{app}\{#ExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#ExeName}"; Description: "{cm:LaunchApp}"; Flags: nowait postinstall skipifsilent
