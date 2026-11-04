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

procedure Register;

type
  TDiscordWizard = class;

  TSettingsMenuClickHandler = class(TComponent)
  private
    FWizard: TDiscordWizard;
    FMenuItem: TMenuItem;
    procedure Click(Sender: TObject);
  public
    constructor CreateForWizard(Wizard: TDiscordWizard);
    procedure AttachMenuItem(MenuItem: TMenuItem);
    procedure Detach;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  end;

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

  TDiscordWizard = class(TNotifierObject, IOTAWizard)
  private
    FEditors: TList<IOTASourceEditor>;
    FEditorNotifierIndices: TList<Integer>;
    FIDENotifier: TIDENotifier;
    FIDENotifierIndex: Integer;
    FDiscordRPC: TDiscordRPC;
    FLastFileName: string;
    FSettingsMenuHandler: TSettingsMenuClickHandler;

    procedure AttachEditorNotifier;
    procedure DetachEditorNotifier;
    procedure InitializeDiscordRPC;
    procedure EnsureInitialized;
    procedure AddSettingsMenuItem;
    procedure RefreshPresence;
    procedure UpdatePresenceFromView(const View: IOTAEditView);
    procedure UpdateIdlePresence;

  public
    constructor Create;
    destructor Destroy; override;
    { IOTAWizard }
    function GetIDString: string;
    function GetName: string;
    function GetState: TWizardState;
    procedure Execute;
    procedure HandleFileNotification(NotifyCode: TOTAFileNotification;
      const FileName: string);
  end;

implementation

function ShowRADcordSettingsDialog(var Settings: TRADcordSettings): Boolean;
var
  Form: TForm;
  FileNameCheck: TCheckBox;
  ProjectNameCheck: TCheckBox;
  LineNumberCheck: TCheckBox;
  ElapsedTimeCheck: TCheckBox;
  IdlePresenceCheck: TCheckBox;
  OKButton: TButton;
  CancelButton: TButton;
begin
  Form := TForm.CreateNew(nil);
  try
    Form.Caption := 'RADcord Settings';
    Form.BorderStyle := bsDialog;
    Form.Position := poScreenCenter;
    Form.ClientWidth := 340;
    Form.ClientHeight := 235;

    FileNameCheck := TCheckBox.Create(Form);
    FileNameCheck.Parent := Form;
    FileNameCheck.Caption := 'File name';
    FileNameCheck.Left := 16;
    FileNameCheck.Top := 16;
    FileNameCheck.Checked := Settings.ShowFileName;

    ProjectNameCheck := TCheckBox.Create(Form);
    ProjectNameCheck.Parent := Form;
    ProjectNameCheck.Caption := 'Project name';
    ProjectNameCheck.Left := 16;
    ProjectNameCheck.Top := 48;
    ProjectNameCheck.Checked := Settings.ShowProjectName;

    LineNumberCheck := TCheckBox.Create(Form);
    LineNumberCheck.Parent := Form;
    LineNumberCheck.Caption := 'Line number';
    LineNumberCheck.Left := 16;
    LineNumberCheck.Top := 80;
    LineNumberCheck.Checked := Settings.ShowLineNumber;

    ElapsedTimeCheck := TCheckBox.Create(Form);
    ElapsedTimeCheck.Parent := Form;
    ElapsedTimeCheck.Caption := 'Elapsed time';
    ElapsedTimeCheck.Left := 16;
    ElapsedTimeCheck.Top := 112;
    ElapsedTimeCheck.Checked := Settings.ShowElapsedTime;

    IdlePresenceCheck := TCheckBox.Create(Form);
    IdlePresenceCheck.Parent := Form;
    IdlePresenceCheck.Caption := 'Idle presence';
    IdlePresenceCheck.Left := 16;
    IdlePresenceCheck.Top := 144;
    IdlePresenceCheck.Checked := Settings.ShowIdlePresence;

    OKButton := TButton.Create(Form);
    OKButton.Parent := Form;
    OKButton.Caption := 'OK';
    OKButton.Left := 164;
    OKButton.Top := 192;
    OKButton.Width := 75;
    OKButton.ModalResult := mrOk;
    OKButton.Default := True;

    CancelButton := TButton.Create(Form);
    CancelButton.Parent := Form;
    CancelButton.Caption := 'Cancel';
    CancelButton.Left := 245;
    CancelButton.Top := 192;
    CancelButton.Width := 75;
    CancelButton.ModalResult := mrCancel;
    CancelButton.Cancel := True;

    Result := Form.ShowModal = mrOk;
    if Result then
    begin
      Settings.ShowFileName := FileNameCheck.Checked;
      Settings.ShowProjectName := ProjectNameCheck.Checked;
      Settings.ShowLineNumber := LineNumberCheck.Checked;
      Settings.ShowElapsedTime := ElapsedTimeCheck.Checked;
      Settings.ShowIdlePresence := IdlePresenceCheck.Checked;
    end;
  finally
    Form.Free;
  end;
end;

{ TSettingsMenuClickHandler }

constructor TSettingsMenuClickHandler.CreateForWizard(Wizard: TDiscordWizard);
begin
  inherited Create(nil);
  FWizard := Wizard;
end;

procedure TSettingsMenuClickHandler.Click(Sender: TObject);
begin
  if Assigned(FWizard) then
    FWizard.Execute;
end;

procedure TSettingsMenuClickHandler.AttachMenuItem(MenuItem: TMenuItem);
begin
  FMenuItem := MenuItem;
  if Assigned(FMenuItem) then
    FMenuItem.FreeNotification(Self);
end;

procedure TSettingsMenuClickHandler.Detach;
var
  MenuItem: TMenuItem;
begin
  FWizard := nil;
  MenuItem := FMenuItem;
  FMenuItem := nil;
  if Assigned(MenuItem) then
  begin
    MenuItem.RemoveFreeNotification(Self);
    MenuItem.Free;
  end;
end;

procedure TSettingsMenuClickHandler.Notification(AComponent: TComponent;
  Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FMenuItem) then
    FMenuItem := nil;
end;

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
  FLastFileName := '';
  FDiscordRPC := nil;
  FSettingsMenuHandler := TSettingsMenuClickHandler.CreateForWizard(Self);

  if Supports(BorlandIDEServices, IOTAServices, IDEServices) then
  begin
    FIDENotifier := TIDENotifier.Create(Self);
    FIDENotifierIndex := IDEServices.AddNotifier(FIDENotifier);
  end;

  EnsureInitialized;
  AttachEditorNotifier;
  RefreshPresence;
  AddSettingsMenuItem;
end;

destructor TDiscordWizard.Destroy;
var
  IDEServices: IOTAServices;
begin
  if Assigned(FSettingsMenuHandler) then
  begin
    FSettingsMenuHandler.Detach;
    FreeAndNil(FSettingsMenuHandler);
  end;

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
  if FDiscordRPC <> nil then
  begin
    FDiscordRPC.Release;
    FDiscordRPC := nil;
  end;
  inherited;
end;

procedure TDiscordWizard.InitializeDiscordRPC;
begin
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

procedure TDiscordWizard.AddSettingsMenuItem;
var
  IDEMenuServices: INTAServices;
  MainMenu: TMainMenu;
  ToolsMenu: TMenuItem;
  MenuItem: TMenuItem;
  I: Integer;
  CaptionText: string;
begin
  if not Assigned(FSettingsMenuHandler) then
    FSettingsMenuHandler := TSettingsMenuClickHandler.CreateForWizard(Self);

  if not Supports(BorlandIDEServices, INTAServices, IDEMenuServices) then
  begin
    OutputDebugString('RADcord: IDE main menu service is unavailable.');
    Exit;
  end;

  MainMenu := IDEMenuServices.MainMenu;
  if not Assigned(MainMenu) then
  begin
    OutputDebugString('RADcord: IDE main menu is unavailable.');
    Exit;
  end;

  ToolsMenu := nil;
  for I := 0 to MainMenu.Items.Count - 1 do
  begin
    CaptionText := StringReplace(MainMenu.Items[I].Caption, '&', '', [rfReplaceAll]);
    if SameText(CaptionText, 'Tools') or
       SameText(MainMenu.Items[I].Name, 'ToolsMenu') then
    begin
      ToolsMenu := MainMenu.Items[I];
      Break;
    end;
  end;

  if not Assigned(ToolsMenu) then
  begin
    OutputDebugString('RADcord: Could not find the IDE Tools menu.');
    Exit;
  end;

  for I := 0 to ToolsMenu.Count - 1 do
    if SameText(ToolsMenu.Items[I].Name, 'RADcordSettingsMenuItem') then
    begin
      ToolsMenu.Items[I].OnClick := FSettingsMenuHandler.Click;
      FSettingsMenuHandler.AttachMenuItem(ToolsMenu.Items[I]);
      Exit;
    end;

  MenuItem := TMenuItem.Create(MainMenu);
  MenuItem.Name := 'RADcordSettingsMenuItem';
  MenuItem.Caption := 'RADcord Settings';
  MenuItem.OnClick := FSettingsMenuHandler.Click;
  ToolsMenu.Add(MenuItem);
  FSettingsMenuHandler.AttachMenuItem(MenuItem);
end;

function TDiscordWizard.GetIDString: string;
begin
  Result := 'com.janconel.discordpresence';
end;

function TDiscordWizard.GetName: string;
begin
  Result := 'RADcord Discord Presence';
end;

function TDiscordWizard.GetState: TWizardState;
begin
  Result := [wsEnabled];
end;

procedure TDiscordWizard.AttachEditorNotifier;
var
  ModuleServices: IOTAModuleServices;
  Module: IOTAModule;
  Editor: IOTASourceEditor;
  I, J: Integer;
  Index: Integer;
  Notifier: IOTAEditorNotifier;
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
            Notifier := TEditorNotifier.Create(FDiscordRPC) as IOTAEditorNotifier;
            Index := Editor.AddNotifier(Notifier);
            FEditors.Add(Editor);
            FEditorNotifierIndices.Add(Index);
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
        FEditors[I].RemoveNotifier(Index);
      except
        on E: Exception do
          OutputDebugString(PChar('RADcord: failed to remove editor notifier: ' + E.Message));
      end;
    end;
  end;

  FEditors.Clear;
  FEditorNotifierIndices.Clear;
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

procedure TDiscordWizard.Execute;
var
  Settings: TRADcordSettings;
begin
  Settings := ReadConfiguredSettings;
  if ShowRADcordSettingsDialog(Settings) then
  begin
    try
      WriteConfiguredSettings(Settings);
      EnsureInitialized;
      AttachEditorNotifier;
      RefreshPresence;
    except
      on E: Exception do
        MessageDlg('Could not save RADcord settings: ' + E.Message,
          mtError, [mbOK], 0);
    end;
  end
end;

procedure TDiscordWizard.HandleFileNotification(NotifyCode: TOTAFileNotification;
  const FileName: string);
begin
  AddSettingsMenuItem;

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
  ProjectGroup: IOTAProjectGroup;
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
  if Supports(BorlandIDEServices, IOTAProjectGroup, ProjectGroup) then
  begin
    ActiveProject := ProjectGroup.ActiveProject;
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

procedure Register;
var
  Wizard: IOTAWizard;
begin
  Wizard := TDiscordWizard.Create as IOTAWizard;
  RegisterPackageWizard(Wizard);
end;

end.
