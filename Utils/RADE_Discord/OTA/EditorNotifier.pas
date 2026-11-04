unit EditorNotifier;

interface

uses
  System.SysUtils,
  System.Classes,
  ToolsAPI,
  Winapi.Windows,
  Vcl.Graphics,
  DiscordRPC,
  RADcordConfig,
  RADcordPresence;

type
  TEditorNotifier = class(TNotifierObject, IOTAEditorNotifier, INTAEditViewNotifier)
  private
    FDiscordRPC: TDiscordRPC;
    FLastFileName: string;
    FEditView: IOTAEditView;
    FEditViewNotifierIndex: Integer;
    procedure AttachEditViewNotifier(const View: IOTAEditView);
    procedure UpdateDiscordPresence(const FileName: string; const View: IOTAEditView);
  public
    constructor Create(DiscordRPC: TDiscordRPC);
    destructor Destroy; override;
    procedure DetachEditViewNotifier;
    { IOTAEditorNotifier }
    procedure ViewActivated(const View: IOTAEditView);
    procedure ViewNotification(const View: IOTAEditView; Operation: TOperation);
    procedure EditorIdle(const View: IOTAEditView);
    procedure BeginPaint(const View: IOTAEditView; var FullRepaint: Boolean);
    procedure PaintLine(const View: IOTAEditView; LineNumber: Integer;
      const LineText: PAnsiChar; const TextWidth: Word;
      const LineAttributes: TOTAAttributeArray; const Canvas: TCanvas;
      const TextRect, LineRect: TRect; const CellSize: TSize);
    procedure EndPaint(const View: IOTAEditView);
  end;

implementation

{ TEditorNotifier }

constructor TEditorNotifier.Create(DiscordRPC: TDiscordRPC);
begin
  inherited Create;
  FDiscordRPC := DiscordRPC;
  FEditViewNotifierIndex := -1;
  if FDiscordRPC <> nil then
    FDiscordRPC.AddRef;
  FLastFileName := '';
end;

destructor TEditorNotifier.Destroy;
begin
  DetachEditViewNotifier;
  if FDiscordRPC <> nil then
    FDiscordRPC.Release;
  inherited;
end;

procedure TEditorNotifier.AttachEditViewNotifier(const View: IOTAEditView);
begin
  if View = nil then
    Exit;
  if FEditView = View then
    Exit;

  DetachEditViewNotifier;
  FEditView := View;
  FEditViewNotifierIndex := View.AddNotifier(Self as INTAEditViewNotifier);
end;

procedure TEditorNotifier.DetachEditViewNotifier;
var
  EditView: IOTAEditView;
  NotifierIndex: Integer;
begin
  EditView := FEditView;
  NotifierIndex := FEditViewNotifierIndex;
  FEditView := nil;
  FEditViewNotifierIndex := -1;
  if Assigned(EditView) and (NotifierIndex >= 0) then
  begin
    try
      EditView.RemoveNotifier(NotifierIndex);
    except
      on E: Exception do
        OutputDebugString(PChar('RADcord: failed to remove edit view notifier: ' + E.Message));
    end;
  end;
end;

procedure TEditorNotifier.UpdateDiscordPresence(const FileName: string; const View: IOTAEditView);
var
  Presence: TDiscordRichPresence;
  LineNumber: Integer;
  ProjectName: string;
  ModuleServices: IOTAModuleServices;
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
  if Supports(BorlandIDEServices, IOTAModuleServices, ModuleServices) then begin
    ActiveProject := ModuleServices.GetActiveProject;
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
    AttachEditViewNotifier(View);
    FileName := View.Buffer.FileName;
    if FileName <> '' then begin
      OutputDebugString(PChar('Editor activated: ' + FileName));
      UpdateDiscordPresence(FileName, View);
    end;
  end;
end;

procedure TEditorNotifier.ViewNotification(const View: IOTAEditView; Operation: TOperation);
begin
  if Operation = opInsert then
    AttachEditViewNotifier(View)
  else if (Operation = opRemove) and (FEditView = View) then
    DetachEditViewNotifier;
end;

procedure TEditorNotifier.EditorIdle(const View: IOTAEditView);
begin
  if (View <> nil) and (FEditView = View) and (View.Buffer <> nil) then
    UpdateDiscordPresence(View.Buffer.FileName, View);
end;

procedure TEditorNotifier.BeginPaint(const View: IOTAEditView;
  var FullRepaint: Boolean);
begin
end;

procedure TEditorNotifier.PaintLine(const View: IOTAEditView;
  LineNumber: Integer; const LineText: PAnsiChar; const TextWidth: Word;
  const LineAttributes: TOTAAttributeArray; const Canvas: TCanvas;
  const TextRect, LineRect: TRect; const CellSize: TSize);
begin
end;

procedure TEditorNotifier.EndPaint(const View: IOTAEditView);
begin
end;

end.
