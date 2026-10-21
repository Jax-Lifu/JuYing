; Inno Setup 6.x Script for 聚映 (JuYing) Windows x64 Installer
; 遵循 ADR-009 (GPL-3.0) 与《聚映项目指导文档 v0.2》第 3.3 节与 Q9 规范

#define MyAppName "聚映"
#define MyAppEnglishName "JuYing"
#define MyAppVersion "0.2.0"
#define MyAppPublisher "FlyTech"
#define MyAppURL "https://github.com/flytech/juying"
#define MyAppExeName "juying.exe"
#define SourceBuildDir "..\..\..\build\windows\x64\runner\Release"

[Setup]
AppId={{D374B39A-3620-41C2-82EB-F3A66A467B98}
AppName={#MyAppName} ({#MyAppEnglishName})
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\JuYing
DefaultGroupName={#MyAppName}
AllowNoIcons=yes
LicenseFile=..\..\..\..\LICENSE
OutputDir=..\..\..\..\dist\windows
OutputBaseFilename=JuYing-v{#MyAppVersion}-windows-x64-setup
SetupIconFile=..\runner\resources\app_icon.ico
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
CloseApplications=force

[Languages]
Name: "chinesesimp"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
Name: "firewallrule"; Description: "自动添加 Windows 防火墙入站放行规则 (DLNA 投屏与 AirPlay 必需)"; GroupDescription: "系统网络配置:"
Name: "startup"; Description: "开机自动在后台启动接收端服务 (可选)"; GroupDescription: "系统启动选项:"; Flags: unchecked

[Files]
Source: "{#SourceBuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; 示例预设配置文件与开源许可
Source: "..\..\..\..\LICENSE"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon
Name: "{userstartup}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Parameters: "--minimized"; Tasks: startup

[Run]
; 安装完成后配置防火墙入站规则放行投屏与代理端口 (1900 SSDP, 9978 Range Proxy, 7000/7001 AirPlay)
Filename: "netsh.exe"; Parameters: "advfirewall firewall add rule name=""JuYing Media Player"" dir=in action=allow program=""{app}\{#MyAppExeName}"" enable=yes"; Flags: runhidden; Tasks: firewallrule
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
; 卸载时清理防火墙入站规则
Filename: "netsh.exe"; Parameters: "advfirewall firewall delete rule name=""JuYing Media Player"""; Flags: runhidden

[Code]
// 检测系统是否已安装 Visual C++ 2015-2022 x64 Redistributable
function VCRedistInstalled: Boolean;
var
  Installed: Cardinal;
begin
  Result := RegQueryDWordValue(HKLM, 'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\X64', 'Installed', Installed) and (Installed = 1);
end;

function InitializeSetup(): Boolean;
begin
  Result := True;
  if not VCRedistInstalled then
  begin
    if MsgBox('检测到系统可能未安装 Visual C++ 2015-2022 运行库（libmpv 与 Flutter 原生组件运行必需）。' + #13#10 + #13#10 +
              '是否继续安装？若运行报错请前往微软官网下载安装 VC_redist.x64.exe。', mbConfirmation, MB_YESNO) = IDNO then
    begin
      Result := False;
    end;
  end;
end;
