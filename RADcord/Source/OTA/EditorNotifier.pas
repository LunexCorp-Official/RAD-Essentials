unit EditorNotifier;

interface

uses
  System.SysUtils,
  System.Classes,
  ToolsAPI,
  Winapi.Windows,
  DiscordRPC,
  RADcordConfig,
  RADcordPresence;

type
  TEditorNotifier = class(TNotifierObject, IOTAEditorNotifier)
  private
    FDiscordRPC: TDiscordRPC;
    FLastFileName: string;
    procedure UpdateDiscordPresence(const FileName: string; const View: IOTAEditView);
  public
    constructor Create(DiscordRPC: TDiscordRPC);
    destructor Destroy; override;
    { IOTAEditorNotifier }
    procedure ViewActivated(const View: IOTAEditView);
    procedure ViewNotification(const View: IOTAEditView; Operation: TOperation);
  end;

implementation

{ TEditorNotifier }

constructor TEditorNotifier.Create(DiscordRPC: TDiscordRPC);
begin
  inherited Create;
  FDiscordRPC := DiscordRPC;
  if FDiscordRPC <> nil then
    FDiscordRPC.AddRef;
  FLastFileName := '';
end;

destructor TEditorNotifier.Destroy;
begin
  if FDiscordRPC <> nil then
    FDiscordRPC.Release;
  inherited;
end;

procedure TEditorNotifier.UpdateDiscordPresence(const FileName: string; const View: IOTAEditView);
var
  Presence: TDiscordRichPresence;
  LineNumber: Integer;
  ProjectName: string;
  ProjectGroup: IOTAProjectGroup;
  ActiveProject: IOTAProject;
  Settings: TRADcordSettings;
begin
  if (FDiscordRPC = nil) then begin
    OutputDebugString(PChar('RADcord: UpdateDiscordPresence called but FDiscordRPC = nil for file: ' + FileName));
    Exit;
  end;

  if (not FDiscordRPC.IsReady) then begin
    OutputDebugString(PChar('RADcord: UpdateDiscordPresence called but Discord RPC not ready for file: ' + FileName));
    Exit;
  end;

  if FileName <> FLastFileName then
    FLastFileName := FileName;

  LineNumber := 0;
  if Assigned(View) and Assigned(View.Position) then begin
    LineNumber := View.Position.GetRow;
  end;

  ProjectName := '';
  if Supports(BorlandIDEServices, IOTAProjectGroup, ProjectGroup) then begin
    ActiveProject := ProjectGroup.ActiveProject;
    if Assigned(ActiveProject) then
      ProjectName := ExtractFileName(ActiveProject.FileName);
  end;

  Settings := ReadConfiguredSettings;
  Presence := CreateEditorPresence(FileName, ProjectName, LineNumber,
    ActivityStartTimestamp, Settings);

  OutputDebugString(PChar('RADcord: UpdateDiscordPresence sending - ' + Presence.Details));
  try
    FDiscordRPC.UpdatePresence(Presence);
  except
    on E: Exception do
      OutputDebugString(PChar('RADcord: UpdatePresence exception: ' + E.Message));
  end;
end;

procedure TEditorNotifier.ViewActivated(const View: IOTAEditView);
var
  FileName: string;
begin
  if View <> nil then begin
    FileName := View.Buffer.FileName;
    if FileName <> '' then begin
      OutputDebugString(PChar('Editor activated: ' + FileName));
      UpdateDiscordPresence(FileName, View);
    end;
  end;
end;

procedure TEditorNotifier.ViewNotification(const View: IOTAEditView; Operation: TOperation);
var
  Msg: string;
  FileName: string;
begin
  if View = nil then
    Exit;

  FileName := View.Buffer.FileName;

  // Use integer values for the operation enum
  case Integer(Operation) of
    0:
      Msg := 'Insert operation';
    1:
      Msg := 'Remove operation';
    2:
      Msg := 'Modify operation';
  else
    Msg := 'Unknown operation (value: ' + IntToStr(Integer(Operation)) + ')';
  end;

  OutputDebugString(PChar(Format('Editor notification: %s - %s', [FileName, Msg])));

  // Update presence on file modifications
  if Integer(Operation) in [0, 2] then
    UpdateDiscordPresence(FileName, View);
end;

end.
