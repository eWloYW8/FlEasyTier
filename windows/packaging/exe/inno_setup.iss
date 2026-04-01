#define MyAppName "FlEasyTier"
#define MyAppExeName "FlEasyTier.exe"
#define MyAppPublisher "eWloYW8"
#define MyAppURL "https://github.com/eWloYW8/FlEasyTier"

[Setup]
AppId={B8F5E3A1-7D2C-4E9F-A6B0-1C3D5E7F9A2B}
AppName={#MyAppName}
AppVersion={#GetEnv('APP_VERSION')}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DisableProgramGroupPage=yes
OutputDir={#GetEnv('OUTPUT_DIR')}
OutputBaseFilename={#GetEnv('OUTPUT_FILENAME')}
Compression=lzma
SolidCompression=yes
SetupIconFile={#GetEnv('ICON_FILE')}
WizardStyle=modern
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Code]
procedure KillProcesses;
var
  Processes: TArrayOfString;
  i: Integer;
  ResultCode: Integer;
begin
  Processes := ['FlEasyTier.exe', 'easytier-core.exe'];
  for i := 0 to GetArrayLength(Processes)-1 do
  begin
    Exec('taskkill', '/f /im ' + Processes[i], '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  end;
end;

function InitializeSetup(): Boolean;
begin
  KillProcesses;
  Result := True;
end;

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"
Name: "japanese"; MessagesFile: "compiler:Languages\Japanese.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: checkedonce

[Files]
Source: "{#GetEnv('SOURCE_DIR')}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: runascurrentuser nowait postinstall skipifsilent
