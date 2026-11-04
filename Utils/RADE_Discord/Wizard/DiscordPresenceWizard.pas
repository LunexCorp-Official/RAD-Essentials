unit DiscordPresenceWizard;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  ToolsAPI,
  EditorNotifier,
  DiscordRPC,
  RADcordConfig,
  RADcordPresence,
  WinAPI.Windows,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.Dialogs,
  Vcl.Menus;

procedure RADcord_Initialize;
procedure RADcord_Refresh;
procedure RADcord_Shutdown;

type
  TDiscordWizard = class;

  TIDENotifier = class(TNotifierObject, IOTAIDENotifier)
  private
    FWizard: TDiscordWizard;
  public
    constructor Create(Wizard: TDiscordWizard);
    procedure Deactivate;
    procedure FileNotification(NotifyCode: TOTAFileNotification; const FileName: string; var Cancel: Boolean);
    procedure BeforeCompile(const Project: IOTAProject; var Cancel: Boolean);
    procedure AfterCompile(Succeeded: Boolean);
  end;

  TDiscordWizard = class(TNotifierObject)
      FEditorNotifiers: TList<TEditorNotifier>;
  private
    FEditors: TList<IOTASourceEditor>;
    FEditorNotifierIndices: TList<Integer>;
    FIDENotifier: TIDENotifier;
    FIDENotifierIndex: Integer;
    FDiscordRPC: TDiscordRPC;
    FLastFileName: string;
    procedure AttachEditorNotifier;
    procedure DetachEditorNotifier;
    procedure InitializeDiscordRPC;
    procedure EnsureInitialized;
    procedure RefreshConfiguration;
    procedure RefreshPresence;
    procedure UpdatePresenceFromView(const View: IOTAEditView);
    procedure UpdateIdlePresence;

  public
    constructor Create;
    destructor Destroy; override;
    procedure HandleFileNotification(NotifyCode: TOTAFileNotification;
      const FileName: string);
  end;

implementation

var
  GlobalDiscordWizard: TDiscordWizard = nil;

{ TIDENotifier }

constructor TIDENotifier.Create(Wizard: TDiscordWizard);
begin
  inherited Create;
  FWizard := Wizard;
end;

procedure TIDENotifier.FileNotification(NotifyCode: TOTAFileNotification;
  const FileName: string; var Cancel: Boolean);
begin
  if Assigned(FWizard) then
    FWizard.HandleFileNotification(NotifyCode, FileName);
end;

procedure TIDENotifier.Deactivate;
begin
  FWizard := nil;
end;

procedure TIDENotifier.BeforeCompile(const Project: IOTAProject; var Cancel: Boolean);
begin
  { Not used in this implementation }
end;

procedure TIDENotifier.AfterCompile(Succeeded: Boolean);
begin
  { Not used in this implementation }
end;

{ TDiscordWizard }

constructor TDiscordWizard.Create;
var
  IDEServices: IOTAServices;
begin
  inherited Create;
  FIDENotifierIndex := -1;
  FIDENotifier := nil;
  FEditors := TList<IOTASourceEditor>.Create;
  FEditorNotifierIndices := TList<Integer>.Create;
  FEditorNotifiers := TList<TEditorNotifier>.Create;
  FLastFileName := '';
  FDiscordRPC := nil;

  if Supports(BorlandIDEServices, IOTAServices, IDEServices) then
  begin
    FIDENotifier := TIDENotifier.Create(Self);
    FIDENotifierIndex := IDEServices.AddNotifier(FIDENotifier);
  end;

  EnsureInitialized;
  AttachEditorNotifier;
  RefreshPresence;
end;

destructor TDiscordWizard.Destroy;
var
  IDEServices: IOTAServices;
begin
  DetachEditorNotifier;

  if (FIDENotifierIndex <> -1) and
     Supports(BorlandIDEServices, IOTAServices, IDEServices) then
  begin
    try
      IDEServices.RemoveNotifier(FIDENotifierIndex);
    except
      on E: Exception do
        OutputDebugString(PChar('RADcord: failed to remove IDE notifier during shutdown: ' + E.Message));
    end;
  end;
  FIDENotifierIndex := -1;

  if Assigned(FIDENotifier) then
    FIDENotifier.Deactivate;
  FIDENotifier := nil;

  if Assigned(FEditors) then
    FEditors.Free;
  if Assigned(FEditorNotifierIndices) then
    FEditorNotifierIndices.Free;
  if Assigned(FEditorNotifiers) then
    FEditorNotifiers.Free;
  if FDiscordRPC <> nil then
  begin
      FDiscordRPC.Shutdown;
    FDiscordRPC.Release;
    FDiscordRPC := nil;
  end;
  inherited;
end;

procedure TDiscordWizard.InitializeDiscordRPC;
begin
  if Trim(ReadConfiguredClientId) = '' then
    Exit;
  try
    FDiscordRPC := TDiscordRPC.Create(ReadConfiguredClientId);
    FDiscordRPC.Initialize;
  except
    on E: Exception do
    begin
      OutputDebugString(PChar('Failed to initialize Discord RPC: ' + E.Message));
      FreeAndNil(FDiscordRPC);
    end;
  end;
end;

procedure TDiscordWizard.EnsureInitialized;
begin
  if FDiscordRPC = nil then
    InitializeDiscordRPC;
end;

procedure TDiscordWizard.AttachEditorNotifier;
var
  ModuleServices: IOTAModuleServices;
  Module: IOTAModule;
  Editor: IOTASourceEditor;
  I, J: Integer;
  Index: Integer;
  Notifier: IOTAEditorNotifier;
  NotifierObject: TEditorNotifier;
begin
  // Detach any existing notifiers first
  DetachEditorNotifier;

  if (FDiscordRPC = nil) then
    Exit;

  if Supports(BorlandIDEServices, IOTAModuleServices, ModuleServices) then
  begin
    for I := 0 to ModuleServices.ModuleCount - 1 do
    begin
      Module := ModuleServices.Modules[I];
      if Module = nil then
        Continue;

      for J := 0 to Module.ModuleFileCount - 1 do
      begin
        if Supports(Module.ModuleFileEditors[J], IOTASourceEditor, Editor) and
           (Editor.FileName <> '') then
        begin
            NotifierObject := TEditorNotifier.Create(FDiscordRPC);
            Notifier := NotifierObject as IOTAEditorNotifier;
            Index := Editor.AddNotifier(Notifier);
            FEditors.Add(Editor);
            FEditorNotifierIndices.Add(Index);
            FEditorNotifiers.Add(NotifierObject);
            OutputDebugString(PChar('RADcord: Attached notifier to editor: ' + Editor.FileName));
        end;
      end;
    end;
    OutputDebugString(PChar('RADcord: AttachEditorNotifier completed. Notifiers attached: ' + IntToStr(FEditors.Count)));
  end;
end;

procedure TDiscordWizard.DetachEditorNotifier;
var
  I: Integer;
  Index: Integer;
begin
  if (FEditors = nil) or (FEditorNotifierIndices = nil) then
    Exit;

  for I := FEditors.Count - 1 downto 0 do
  begin
    Index := FEditorNotifierIndices[I];
    if Index <> -1 then
    begin
      try
        FEditorNotifiers[I].DetachEditViewNotifier;
        FEditors[I].RemoveNotifier(Index);
      except
        on E: Exception do
          OutputDebugString(PChar('RADcord: failed to remove editor notifier: ' + E.Message));
      end;
    end;
  end;

  FEditors.Clear;
  FEditorNotifierIndices.Clear;
  FEditorNotifiers.Clear;
end;

procedure TDiscordWizard.RefreshPresence;
var
  EditorServices: IOTAEditorServices;
  TopView: IOTAEditView;
begin
  if (FDiscordRPC = nil) or (not FDiscordRPC.IsReady) then
    Exit;

  if Supports(BorlandIDEServices, IOTAEditorServices, EditorServices) then
  begin
    TopView := EditorServices.TopView;
    if Assigned(TopView) then
      UpdatePresenceFromView(TopView);
    if not Assigned(TopView) then
      UpdateIdlePresence;
  end
  else
    UpdateIdlePresence;
end;

procedure TDiscordWizard.HandleFileNotification(NotifyCode: TOTAFileNotification;
  const FileName: string);
begin
  if NotifyCode in [ofnFileOpened, ofnProjectOpenedFromTemplate,
    ofnActiveProjectChanged] then
  begin
    EnsureInitialized;
    AttachEditorNotifier;
    RefreshPresence;
  end
  else if NotifyCode = ofnBeginProjectGroupClose then
  begin
    DetachEditorNotifier;
    UpdateIdlePresence;
  end
  else if (NotifyCode = ofnEndProjectGroupClose) or
          ((NotifyCode = ofnFileClosing) and SameText(FileName, FLastFileName)) then
    UpdateIdlePresence;
end;

procedure TDiscordWizard.UpdatePresenceFromView(const View: IOTAEditView);
var
  FileName: string;
  LineNumber: Integer;
  ProjectName: string;
  ModuleServices: IOTAModuleServices;
  ActiveProject: IOTAProject;
  Presence: TDiscordRichPresence;
  Settings: TRADcordSettings;
begin
  if (FDiscordRPC = nil) or (not FDiscordRPC.IsReady) or (View = nil) then
    Exit;

  FileName := '';
  if Assigned(View.Buffer) then
    FileName := View.Buffer.FileName;

  if FileName = '' then
  begin
    UpdateIdlePresence;
    Exit;
  end;

  if FileName <> FLastFileName then
  begin
    FLastFileName := FileName;
  end;

  LineNumber := 0;
  if Assigned(View.Position) then
    LineNumber := View.Position.GetRow;

  ProjectName := '';
  if Supports(BorlandIDEServices, IOTAModuleServices, ModuleServices) then
  begin
    ActiveProject := ModuleServices.GetActiveProject;
    if Assigned(ActiveProject) then
      ProjectName := ExtractFileName(ActiveProject.FileName);
  end;

  Settings := ReadConfiguredSettings;
  Presence := CreateEditorPresence(FileName, ProjectName, LineNumber,
    ActivityStartTimestamp, Settings);

  try
    OutputDebugString(PChar('RADcord: UpdatePresenceFromView -> ' + Presence.Details));
    FDiscordRPC.UpdatePresence(Presence);
  except
    on E: Exception do
      OutputDebugString(PChar('RADcord: UpdatePresenceFromView exception: ' + E.Message));
  end;
end;

procedure TDiscordWizard.UpdateIdlePresence;
var
  Settings: TRADcordSettings;
  Presence: TDiscordRichPresence;
begin
  if (FDiscordRPC = nil) or (not FDiscordRPC.IsReady) then
    Exit;

  FLastFileName := '';

  Settings := ReadConfiguredSettings;
  if not Settings.ShowIdlePresence then
  begin
    FDiscordRPC.ClearPresence;
    Exit;
  end;

  Presence := CreateIdlePresence(ActivityStartTimestamp, Settings);
  try
    FDiscordRPC.UpdatePresence(Presence);
  except
    on E: Exception do
      OutputDebugString(PChar('RADcord: UpdateIdlePresence exception: ' + E.Message));
  end;
end;

procedure RADcord_Initialize;
begin
  if not Assigned(GlobalDiscordWizard) then
    GlobalDiscordWizard := TDiscordWizard.Create;
end;

procedure TDiscordWizard.RefreshConfiguration;
begin
  DetachEditorNotifier;
  if Assigned(FDiscordRPC) then
  begin
    FDiscordRPC.Shutdown;
    FDiscordRPC.Release;
    FDiscordRPC := nil;
  end;
  EnsureInitialized;
  AttachEditorNotifier;
  RefreshPresence;
end;

procedure RADcord_Refresh;
begin
  if Assigned(GlobalDiscordWizard) then
    GlobalDiscordWizard.RefreshConfiguration;
end;

procedure RADcord_Shutdown;
begin
  FreeAndNil(GlobalDiscordWizard);
end;

end.
