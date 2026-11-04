unit RADcordConfig;

interface

type
  TRADcordSettings = record
    ShowFileName: Boolean;
    ShowProjectName: Boolean;
    ShowLineNumber: Boolean;
    ShowElapsedTime: Boolean;
    ShowIdlePresence: Boolean;
  end;

function ReadConfiguredClientId: string;
function DefaultRADcordSettings: TRADcordSettings;
function ReadConfiguredSettings: TRADcordSettings;
procedure WriteConfiguredSettings(const Settings: TRADcordSettings);

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.IniFiles;

function GetRADcordIniPath: string;
begin
  Result := IncludeTrailingPathDelimiter(TPath.GetHomePath) +
    'RADE_Essentials_Settings.ini';
end;

function DefaultRADcordSettings: TRADcordSettings;
begin
  Result.ShowFileName := True;
  Result.ShowProjectName := True;
  Result.ShowLineNumber := True;
  Result.ShowElapsedTime := True;
  Result.ShowIdlePresence := True;
end;

function ReadConfiguredClientId: string;
const
  DEFAULT_CLIENT_ID = '1524711983348449381';
begin
  Result := DEFAULT_CLIENT_ID;
end;

function ReadConfiguredSettings: TRADcordSettings;
var
  FileName: string;
  Ini: TMemIniFile;
  Defaults: TRADcordSettings;
begin
  Defaults := DefaultRADcordSettings;
  Result := Defaults;
  FileName := GetRADcordIniPath;
  if not FileExists(FileName) then
    Exit;

  Ini := TMemIniFile.Create(FileName);
  try
    Result.ShowFileName := Ini.ReadBool('RADcord', 'ShowFileName', Defaults.ShowFileName);
    Result.ShowProjectName := Ini.ReadBool('RADcord', 'ShowProjectName', Defaults.ShowProjectName);
    Result.ShowLineNumber := Ini.ReadBool('RADcord', 'ShowLineNumber', Defaults.ShowLineNumber);
    Result.ShowElapsedTime := Ini.ReadBool('RADcord', 'ShowElapsedTime', Defaults.ShowElapsedTime);
    Result.ShowIdlePresence := Ini.ReadBool('RADcord', 'ShowIdlePresence', Defaults.ShowIdlePresence);
  finally
    Ini.Free;
  end;
end;

procedure WriteConfiguredSettings(const Settings: TRADcordSettings);
var
  FileName: string;
  Ini: TMemIniFile;
begin
  FileName := GetRADcordIniPath;
  if not ForceDirectories(ExtractFileDir(FileName)) then
    raise Exception.CreateFmt('Could not create RADcord configuration directory: %s',
      [ExtractFileDir(FileName)]);
  Ini := TMemIniFile.Create(FileName);
  try
    Ini.WriteBool('RADcord', 'ShowFileName', Settings.ShowFileName);
    Ini.WriteBool('RADcord', 'ShowProjectName', Settings.ShowProjectName);
    Ini.WriteBool('RADcord', 'ShowLineNumber', Settings.ShowLineNumber);
    Ini.WriteBool('RADcord', 'ShowElapsedTime', Settings.ShowElapsedTime);
    Ini.WriteBool('RADcord', 'ShowIdlePresence', Settings.ShowIdlePresence);
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;
end;

end.
