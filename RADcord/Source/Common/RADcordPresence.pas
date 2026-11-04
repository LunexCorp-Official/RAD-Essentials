unit RADcordPresence;

interface

uses
  RADcordConfig,
  DiscordRPC;

function CreateEditorPresence(const FileName, ProjectName: string;
  LineNumber: Integer; StartTimestamp: Int64;
  const Settings: TRADcordSettings): TDiscordRichPresence;
function CreateIdlePresence(StartTimestamp: Int64;
  const Settings: TRADcordSettings): TDiscordRichPresence;
function CurrentUnixTimestamp: Int64;
function ActivityStartTimestamp: Int64;

implementation

uses
  System.SysUtils,
  System.DateUtils;

var
  FActivityStartTimestamp: Int64;

function CreateEditorPresence(const FileName, ProjectName: string;
  LineNumber: Integer; StartTimestamp: Int64;
  const Settings: TRADcordSettings): TDiscordRichPresence;
begin
  Result := Default(TDiscordRichPresence);
  if Settings.ShowFileName then
    Result.State := ExtractFileName(FileName);

  if Settings.ShowProjectName and (ProjectName <> '') then
    Result.Details := ProjectName;

  if Settings.ShowLineNumber and (LineNumber > 0) then
  begin
    if Result.Details <> '' then
      Result.Details := Result.Details + ' • ';
    Result.Details := Result.Details + Format('line %d', [LineNumber]);
  end;

  if Settings.ShowElapsedTime then
    Result.StartTimestamp := StartTimestamp;
  Result.LargeImageText := 'RAD Studio';
end;

function CreateIdlePresence(StartTimestamp: Int64;
  const Settings: TRADcordSettings): TDiscordRichPresence;
begin
  Result := Default(TDiscordRichPresence);
  Result.State := 'Idle in RAD Studio';
  if Settings.ShowElapsedTime then
    Result.StartTimestamp := StartTimestamp;
  Result.LargeImageText := 'RAD Studio';
end;

function CurrentUnixTimestamp: Int64;
begin
  Result := DateTimeToUnix(Now, False);
end;

function ActivityStartTimestamp: Int64;
begin
  if FActivityStartTimestamp = 0 then
    FActivityStartTimestamp := CurrentUnixTimestamp;
  Result := FActivityStartTimestamp;
end;

end.
