unit RADE.Core;

interface

uses
  ToolsAPI, Vcl.Menus, Vcl.Dialogs, Vcl.Graphics, System.SysUtils, System.Classes, System.IniFiles, System.IOUtils, Vcl.ActnList;

type
  { Editor key binding. Shortcuts on a plain TAction only fire while focus is in the IDE's
    main window; an IOTAKeyboardBinding is what makes them work inside the code editor. }
  TRADEKeyBinding = class(TNotifierObject, IOTAKeyboardBinding)
  private
    FFormatXKey, FPDFKey, FSearchKey: TShortCut;
    FSnippet1Key, FSnippet2Key, FSnippet3Key: TShortCut;
    FOnFormatX, FOnPDF, FOnSearch: TNotifyEvent;
    FOnSnippet1, FOnSnippet2, FOnSnippet3: TNotifyEvent;
    procedure DoFormatX(const Context: IOTAKeyContext; KeyCode: TShortCut;
      var BindingResult: TKeyBindingResult);
    procedure DoPDF(const Context: IOTAKeyContext; KeyCode: TShortCut;
      var BindingResult: TKeyBindingResult);
    procedure DoSearch(const Context: IOTAKeyContext; KeyCode: TShortCut;
      var BindingResult: TKeyBindingResult);
    procedure DoSnippet1(const Context: IOTAKeyContext; KeyCode: TShortCut;
      var BindingResult: TKeyBindingResult);
    procedure DoSnippet2(const Context: IOTAKeyContext; KeyCode: TShortCut;
      var BindingResult: TKeyBindingResult);
    procedure DoSnippet3(const Context: IOTAKeyContext; KeyCode: TShortCut;
      var BindingResult: TKeyBindingResult);
  public
    constructor Create(AFormatXKey, APDFKey, ASearchKey, ASnippet1Key,
      ASnippet2Key, ASnippet3Key: TShortCut;
      const AOnFormatX, AOnPDF, AOnSearch, AOnSnippet1, AOnSnippet2,
      AOnSnippet3: TNotifyEvent);
    { IOTAKeyboardBinding }
    function GetBindingType: TBindingType;
    function GetDisplayName: string;
    function GetName: string;
    procedure BindKeyboard(const BindingServices: IOTAKeyBindingServices);
  end;

  TRADEWizard = class(TNotifierObject, IOTAWizard, IOTAMenuWizard)
  private
    FKeyBindingIndex: Integer;
    FActionFormatX: TAction;
    FActionPDF: TAction;
    FActionSearch: TAction;
    FActionSnippets: TAction;
    FActionSettings: TAction;
    FActionList: TActionList;
    FParentMenu: TMenuItem;
    FSplashBitmap: TBitmap;
    procedure CreateActionsAndMenus;
    procedure BindKeys(AFormatXKey, APDFKey, ASearchKey: TShortCut);
    procedure UnbindKeys;
    procedure RemoveMenus;
    procedure OnFormatXExecute(Sender: TObject);
    procedure OnPDFViewerExecute(Sender: TObject);
    procedure OnSearchExecute(Sender: TObject);
    procedure OnSnippetsExecute(Sender: TObject);
    procedure OnSnippetManagerSaved(Sender: TObject);
    procedure OnSnippet1Execute(Sender: TObject);
    procedure OnSnippet2Execute(Sender: TObject);
    procedure OnSnippet3Execute(Sender: TObject);
    procedure OnSettingsExecute(Sender: TObject);
    function GetIniPath: string;

    procedure AddSplashScreenInfo;
  public
    constructor Create;
    destructor Destroy; override;

    procedure RefreshShortcuts;

    { IOTAWizard }
    function GetIDString: string;
    function GetName: string;
    function GetState: TWizardState;
    procedure Execute;

    { IOTAMenuWizard }
    function GetMenuText: string;
  end;

procedure Register;
procedure Unregister;

implementation

uses
  RADEGit.Integration, RADE.Refactor, RADE.PDFViewer, RADE.Settings,
  RADE.Search, RADE.CodeSnippets, DiscordPresenceWizard, Vcl.Forms,
  Winapi.Windows;

{$R 'Assets\Icons.res' 'Assets\Icons.rc'}

const
  RADE_WIZARD_ID = 'LunexCorp.RAD_Essentials.Wizard';

var
  GlobalWizardInstance: TRADEWizard = nil;
  GlobalWizardIndex: Integer = -1;

procedure Register;
var
  WizardServices: IOTAWizardServices;
begin
  if Assigned(GlobalWizardInstance) then
    Exit;

  try
    if Supports(BorlandIDEServices, IOTAWizardServices, WizardServices) then
    begin
      GlobalWizardInstance := TRADEWizard.Create;
      GlobalWizardIndex := WizardServices.AddWizard(GlobalWizardInstance);
    end;
  except
    on E: Exception do
      OutputDebugString(PChar('RAD Essentials Registration Error: ' + E.Message));
  end;
end;

procedure Unregister;
var
  WizardServices: IOTAWizardServices;
begin
  RADECodeSnippets_Shutdown;

  if (GlobalWizardIndex >= 0) and
    Supports(BorlandIDEServices, IOTAWizardServices, WizardServices) then
    WizardServices.RemoveWizard(GlobalWizardIndex);

  GlobalWizardIndex := -1;
  GlobalWizardInstance := nil;
end;

{ TRADEKeyBinding }

constructor TRADEKeyBinding.Create(AFormatXKey, APDFKey, ASearchKey,
  ASnippet1Key, ASnippet2Key, ASnippet3Key: TShortCut;
  const AOnFormatX, AOnPDF, AOnSearch, AOnSnippet1, AOnSnippet2,
  AOnSnippet3: TNotifyEvent);
begin
  inherited Create;
  FFormatXKey := AFormatXKey;
  FPDFKey := APDFKey;
  FSearchKey := ASearchKey;
  FSnippet1Key := ASnippet1Key;
  FSnippet2Key := ASnippet2Key;
  FSnippet3Key := ASnippet3Key;
  FOnFormatX := AOnFormatX;
  FOnPDF := AOnPDF;
  FOnSearch := AOnSearch;
  FOnSnippet1 := AOnSnippet1;
  FOnSnippet2 := AOnSnippet2;
  FOnSnippet3 := AOnSnippet3;
end;

function TRADEKeyBinding.GetBindingType: TBindingType;
begin
  Result := btPartial;
end;

function TRADEKeyBinding.GetDisplayName: string;
begin
  Result := 'RAD Essentials shortcuts';
end;

function TRADEKeyBinding.GetName: string;
begin
  Result := 'LunexCorp.RAD_Essentials.Keys';
end;

procedure TRADEKeyBinding.BindKeyboard(const BindingServices: IOTAKeyBindingServices);
begin
  if FFormatXKey <> 0 then
    BindingServices.AddKeyBinding([FFormatXKey], DoFormatX, nil);
  if FPDFKey <> 0 then
    BindingServices.AddKeyBinding([FPDFKey], DoPDF, nil);
  if FSearchKey <> 0 then
    BindingServices.AddKeyBinding([FSearchKey], DoSearch, nil);
  if FSnippet1Key <> 0 then
    BindingServices.AddKeyBinding([FSnippet1Key], DoSnippet1, nil);
  if FSnippet2Key <> 0 then
    BindingServices.AddKeyBinding([FSnippet2Key], DoSnippet2, nil);
  if FSnippet3Key <> 0 then
    BindingServices.AddKeyBinding([FSnippet3Key], DoSnippet3, nil);
end;

procedure TRADEKeyBinding.DoFormatX(const Context: IOTAKeyContext; KeyCode: TShortCut;
  var BindingResult: TKeyBindingResult);
begin
  BindingResult := krHandled;
  if Assigned(FOnFormatX) then
    FOnFormatX(nil);
end;

procedure TRADEKeyBinding.DoPDF(const Context: IOTAKeyContext; KeyCode: TShortCut;
  var BindingResult: TKeyBindingResult);
begin
  BindingResult := krHandled;
  if Assigned(FOnPDF) then
    FOnPDF(nil);
end;

procedure TRADEKeyBinding.DoSearch(const Context: IOTAKeyContext; KeyCode: TShortCut;
  var BindingResult: TKeyBindingResult);
begin
  BindingResult := krHandled;
  if Assigned(FOnSearch) then
    FOnSearch(nil);
end;

procedure TRADEKeyBinding.DoSnippet1(const Context: IOTAKeyContext;
  KeyCode: TShortCut; var BindingResult: TKeyBindingResult);
begin
  BindingResult := krHandled;
  if Assigned(FOnSnippet1) then
    FOnSnippet1(nil);
end;

procedure TRADEKeyBinding.DoSnippet2(const Context: IOTAKeyContext;
  KeyCode: TShortCut; var BindingResult: TKeyBindingResult);
begin
  BindingResult := krHandled;
  if Assigned(FOnSnippet2) then
    FOnSnippet2(nil);
end;

procedure TRADEKeyBinding.DoSnippet3(const Context: IOTAKeyContext;
  KeyCode: TShortCut; var BindingResult: TKeyBindingResult);
begin
  BindingResult := krHandled;
  if Assigned(FOnSnippet3) then
    FOnSnippet3(nil);
end;

{ TRADEWizard }

procedure TRADEWizard.BindKeys(AFormatXKey, APDFKey, ASearchKey: TShortCut);
var
  KeyServices: IOTAKeyboardServices;
  Snippet1Key, Snippet2Key, Snippet3Key: TShortCut;
begin
  UnbindKeys;
  Snippet1Key := 0;
  Snippet2Key := 0;
  Snippet3Key := 0;
  try
    Snippet1Key := RADECodeSnippets_GetShortcut(1);
    Snippet2Key := RADECodeSnippets_GetShortcut(2);
    Snippet3Key := RADECodeSnippets_GetShortcut(3);
  except
    on E: Exception do
      MessageDlg('Could not load code snippet shortcuts: ' + E.Message,
        mtError, [mbOK], 0);
  end;
  if Supports(BorlandIDEServices, IOTAKeyboardServices, KeyServices) then
    FKeyBindingIndex := KeyServices.AddKeyboardBinding(
      TRADEKeyBinding.Create(AFormatXKey, APDFKey, ASearchKey,
        Snippet1Key, Snippet2Key, Snippet3Key, OnFormatXExecute,
        OnPDFViewerExecute, OnSearchExecute, OnSnippet1Execute,
        OnSnippet2Execute, OnSnippet3Execute));
end;

procedure TRADEWizard.UnbindKeys;
var
  KeyServices: IOTAKeyboardServices;
begin
  if FKeyBindingIndex < 0 then
    Exit;
  if Supports(BorlandIDEServices, IOTAKeyboardServices, KeyServices) then
    KeyServices.RemoveKeyboardBinding(FKeyBindingIndex);
  FKeyBindingIndex := -1;
end;

procedure TRADEWizard.AddSplashScreenInfo;
begin
  if Assigned(FSplashBitmap) then
    Exit;

  FSplashBitmap := Vcl.Graphics.TBitmap.Create;
  try
    FSplashBitmap.LoadFromResourceName(HInstance, 'ICONBMP');
    SplashScreenServices.AddPluginBitmap('RAD Essentials', FSplashBitmap.Handle, True);
  except
    FreeAndNil(FSplashBitmap);
    raise;
  end;
end;

constructor TRADEWizard.Create;
begin
  inherited Create;
  FKeyBindingIndex := -1;

  AddSplashScreenInfo;

  CreateActionsAndMenus;
  RADcord_Initialize;
end;

destructor TRADEWizard.Destroy;
begin
  RADcord_Shutdown;
  UnbindKeys;
  FreeAndNil(FSplashBitmap);
  RemoveMenus;
  RadeGit_Done;
  if GlobalWizardInstance = Self then
  begin
    GlobalWizardInstance := nil;
    GlobalWizardIndex := -1;
  end;
  inherited Destroy;
end;

function TRADEWizard.GetIniPath: string;
begin
  Result := IncludeTrailingPathDelimiter(TPath.GetHomePath) + 'RAD_Essentials_Settings.ini';
end;

procedure TRADEWizard.RefreshShortcuts;
var
  Ini: TIniFile;
  FormatXSc, PDFSc, SearchSc: string;
  FormatXKey, PDFKey, SearchKey: TShortCut;
begin
  Ini := TIniFile.Create(GetIniPath);
  try
    FormatXSc := Ini.ReadString('Shortcuts', 'FormatX', 'Ctrl+Alt+F');
    PDFSc := Ini.ReadString('Shortcuts', 'PDFViewer', 'Ctrl+Alt+P');
    SearchSc := Ini.ReadString('Shortcuts', 'Search', 'Ctrl+Shift+A');
  finally
    Ini.Free;
  end;

  FormatXKey := TextToShortCut(Trim(FormatXSc));
  PDFKey := TextToShortCut(Trim(PDFSc));
  SearchKey := TextToShortCut(Trim(SearchSc));

  // menu items / IDE main window
  if Assigned(FActionFormatX) then
    FActionFormatX.ShortCut := FormatXKey;
  if Assigned(FActionPDF) then
    FActionPDF.ShortCut := PDFKey;
  if Assigned(FActionSearch) then
    FActionSearch.ShortCut := SearchKey;

  // code editor (a TAction shortcut alone never fires there). Re-bound on every refresh so
  // changes from the settings window apply immediately, no IDE restart needed.
  BindKeys(FormatXKey, PDFKey, SearchKey);
end;

function TRADEWizard.GetIDString: string;
begin
  Result := RADE_WIZARD_ID;
end;

function TRADEWizard.GetName: string;
begin
  Result := 'RAD Essentials';
end;

function TRADEWizard.GetMenuText: string;
begin
  Result := 'RAD Essentials';
end;

function TRADEWizard.GetState: TWizardState;
begin
  Result := [wsEnabled];
end;

procedure TRADEWizard.Execute;
begin
  TRADEPDFViewerEditorHost.ShowViewer;
end;

procedure TRADEWizard.CreateActionsAndMenus;
var
  NTAServices: INTAServices;
  MainMenu: TMainMenu;
  SubItem: TMenuItem;
begin
  if not Supports(BorlandIDEServices, INTAServices, NTAServices) then Exit;

  RadeGit_Init;

  RemoveMenus;

  MainMenu := NTAServices.MainMenu;
  if MainMenu = nil then Exit;
  FActionList := TActionList.Create(MainMenu.Owner);

  FActionFormatX := TAction.Create(nil);
  FActionFormatX.ActionList := FActionList;
  FActionFormatX.Name := 'RADEActionFormatX';
  FActionFormatX.Caption := 'Format Code';
  FActionFormatX.OnExecute := OnFormatXExecute;

  FActionPDF := TAction.Create(nil);
  FActionPDF.ActionList := FActionList;
  FActionPDF.Name := 'RADEActionPDF';
  FActionPDF.Caption := 'PDF Viewer';
  FActionPDF.OnExecute := OnPDFViewerExecute;

  FActionSearch := TAction.Create(nil);
  FActionSearch.ActionList := FActionList;
  FActionSearch.Name := 'RADEActionSearch';
  FActionSearch.Caption := 'Search';
  FActionSearch.OnExecute := OnSearchExecute;

  FActionSnippets := TAction.Create(nil);
  FActionSnippets.ActionList := FActionList;
  FActionSnippets.Name := 'RADEActionCodeSnippets';
  FActionSnippets.Caption := 'Code Snippets Manager';
  FActionSnippets.OnExecute := OnSnippetsExecute;

  FActionSettings := TAction.Create(nil);
  FActionSettings.ActionList := FActionList;
  FActionSettings.Name := 'RADEActionSettings';
  FActionSettings.Caption := 'Settings';
  FActionSettings.OnExecute := OnSettingsExecute;

  FParentMenu := TMenuItem.Create(MainMenu);
  FParentMenu.Name := 'RADEssentialsMainMenu';
  FParentMenu.Caption := 'RAD Essentials';

  // Add the Git integration's own submenu item to RAD Essentials.
  // RadeGit_Init must run before this call.
  RadeGit_AddMenuItem(FParentMenu);

  SubItem := TMenuItem.Create(FParentMenu);
  SubItem.Action := FActionSearch;
  FParentMenu.Add(SubItem);

  SubItem := TMenuItem.Create(FParentMenu);
  SubItem.Action := FActionSnippets;
  FParentMenu.Add(SubItem);

  SubItem := TMenuItem.Create(FParentMenu);
  SubItem.Action := FActionFormatX;
  FParentMenu.Add(SubItem);

  SubItem := TMenuItem.Create(FParentMenu);
  SubItem.Action := FActionPDF;
  FParentMenu.Add(SubItem);

  SubItem := TMenuItem.Create(FParentMenu);
  SubItem.Caption := '-';
  FParentMenu.Add(SubItem);

  SubItem := TMenuItem.Create(FParentMenu);
  SubItem.Action := FActionSettings;
  FParentMenu.Add(SubItem);

  MainMenu.Items.Insert(MainMenu.Items.Count - 1, FParentMenu);

  // Also expose the Git integration from the IDE's Help menu.
  RadeGit_AddHelpMenuItem;

  RefreshShortcuts;
end;

procedure TRADEWizard.RemoveMenus;
begin
  if Assigned(FParentMenu) then
  begin
    FParentMenu.Free;
    FParentMenu := nil;
  end;

  FreeAndNil(FActionFormatX);
  FreeAndNil(FActionPDF);
  FreeAndNil(FActionSearch);
  FreeAndNil(FActionSnippets);
  FreeAndNil(FActionSettings);
  FreeAndNil(FActionList);
end;

procedure TRADEWizard.OnFormatXExecute(Sender: TObject);
begin
  TRADEFormatEditor.FormatActive;
end;

procedure TRADEWizard.OnPDFViewerExecute(Sender: TObject);
begin
  TRADEPDFViewerEditorHost.ShowViewer;
end;

procedure TRADEWizard.OnSearchExecute(Sender: TObject);
begin
  RADESearch_Show;
end;

procedure TRADEWizard.OnSnippetsExecute(Sender: TObject);
var
  SelectedCode, Location: string;
begin
  try
    RADECodeSnippets_CaptureSelection(SelectedCode, Location);
    RADECodeSnippets_ShowManager(SelectedCode, Location, OnSnippetManagerSaved);
  except
    on E: Exception do
      MessageDlg('Could not open the code snippets manager: ' + E.Message,
        mtError, [mbOK], 0);
  end;
end;

procedure TRADEWizard.OnSnippetManagerSaved(Sender: TObject);
begin
  RefreshShortcuts;
end;

procedure TRADEWizard.OnSnippet1Execute(Sender: TObject);
begin
  RADECodeSnippets_InsertByShortcut(1);
end;

procedure TRADEWizard.OnSnippet2Execute(Sender: TObject);
begin
  RADECodeSnippets_InsertByShortcut(2);
end;

procedure TRADEWizard.OnSnippet3Execute(Sender: TObject);
begin
  RADECodeSnippets_InsertByShortcut(3);
end;

procedure TRADEWizard.OnSettingsExecute(Sender: TObject);
begin
  TRADESettingsForm.ShowSettings;
  if Assigned(GlobalWizardInstance) then
    GlobalWizardInstance.RefreshShortcuts;
  RADcord_Refresh;
end;

end.
