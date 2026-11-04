unit RADE.CodeSnippets;

interface

uses
  System.SysUtils, System.Classes, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls,
  Vcl.Controls, Vcl.Dialogs, Vcl.Graphics, Vcl.ComCtrls,
  System.Generics.Collections, System.JSON, System.IOUtils, Vcl.Menus;

type
  TRADESnippet = record
    ID: string;
    Name: string;
    Category: string;
    Location: string;
    Code: string;
    Shortcut: string;
  end;

function RADECodeSnippets_GetAll: TArray<TRADESnippet>;
function RADECodeSnippets_GetCategories: TArray<string>;
function RADECodeSnippets_GetShortcut(ASlot: Integer): TShortCut;
function RADECodeSnippets_CaptureSelection(out ACode, ALocation: string): Boolean;
function RADECodeSnippets_CaptureSelectionEx(out ACode, ALocation,
  ARangeID: string): Boolean;
function RADECodeSnippets_InsertByID(const AID: string): Boolean;
function RADECodeSnippets_InsertByShortcut(ASlot: Integer): Boolean;
procedure RADECodeSnippets_ShowManager(const AInitialCode, ALocation: string;
  AOnSaved: TNotifyEvent = nil);
procedure RADECodeSnippets_Shutdown;

implementation

uses
  ToolsAPI, Winapi.Windows, Winapi.Messages;

const
  CSnippetFileName = 'RADECodeSnippets.json';
  CMaximumShortcuts = 3;

function SnippetFilePath: string;
begin
  Result := TPath.Combine(TPath.GetHomePath, CSnippetFileName);
end;

function StringListToArray(const AList: TStrings): TArray<string>;
var
  I: Integer;
begin
  SetLength(Result, AList.Count);
  for I := 0 to AList.Count - 1 do
    Result[I] := AList[I];
end;

function SnippetToJSON(const ASnippet: TRADESnippet): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('id', ASnippet.ID);
  Result.AddPair('name', ASnippet.Name);
  Result.AddPair('category', ASnippet.Category);
  Result.AddPair('location', ASnippet.Location);
  Result.AddPair('code', ASnippet.Code);
  Result.AddPair('shortcut', ASnippet.Shortcut);
end;

function JSONToSnippet(AValue: TJSONValue): TRADESnippet;
var
  Obj: TJSONObject;
begin
  if not (AValue is TJSONObject) then
    raise Exception.Create('Each snippet in the JSON file must be an object.');
  Obj := TJSONObject(AValue);
  if (Obj.GetValue('id') = nil) or (Obj.GetValue('name') = nil) or
    (Obj.GetValue('category') = nil) or (Obj.GetValue('location') = nil) or
    (Obj.GetValue('code') = nil) or (Obj.GetValue('shortcut') = nil) then
    raise Exception.Create('A snippet is missing one or more required fields.');
  Result.ID := Obj.GetValue<string>('id');
  Result.Name := Obj.GetValue<string>('name');
  Result.Category := Obj.GetValue<string>('category');
  Result.Location := Obj.GetValue<string>('location');
  Result.Code := Obj.GetValue<string>('code');
  Result.Shortcut := Obj.GetValue<string>('shortcut');
end;

procedure ValidateSnippets(const ASnippets: TArray<TRADESnippet>);
var
  I, J, ShortcutCount: Integer;
  Shortcut: TShortCut;
begin
  ShortcutCount := 0;
  for I := 0 to High(ASnippets) do
  begin
    if (Trim(ASnippets[I].ID) = '') or (Trim(ASnippets[I].Name) = '') then
      raise Exception.Create('Every snippet must have an ID and a name.');
    if Trim(ASnippets[I].Category) = '' then
      raise Exception.CreateFmt('Enter a category for "%s".', [ASnippets[I].Name]);
    if Trim(ASnippets[I].Code) = '' then
      raise Exception.CreateFmt('Enter code for "%s".', [ASnippets[I].Name]);
    for J := 0 to I - 1 do
      if SameText(ASnippets[J].ID, ASnippets[I].ID) then
        raise Exception.CreateFmt('Duplicate snippet ID for "%s".', [ASnippets[I].Name]);
    if Trim(ASnippets[I].Shortcut) <> '' then
    begin
      Shortcut := TextToShortCut(ASnippets[I].Shortcut);
      if Shortcut = 0 then
        raise Exception.CreateFmt('Invalid shortcut for "%s".', [ASnippets[I].Name]);
      Inc(ShortcutCount);
      for J := 0 to I - 1 do
        if (ASnippets[J].Shortcut <> '') and
          (TextToShortCut(ASnippets[J].Shortcut) = Shortcut) then
          raise Exception.CreateFmt('The shortcut "%s" is assigned more than once.',
            [ASnippets[I].Shortcut]);
    end;
  end;
  if ShortcutCount > CMaximumShortcuts then
    raise Exception.CreateFmt('The snippet library can have at most %d shortcuts.',
      [CMaximumShortcuts]);
end;

function ParseSnippetFile(const AFileName: string;
  out ACategories: TArray<string>): TArray<TRADESnippet>;
var
  Root: TJSONValue;
  Obj: TJSONObject;
  Items: TJSONArray;
  I: Integer;
  Snippets: TList<TRADESnippet>;
  Categories: TJSONArray;
  CategoryList: TList<string>;
begin
  ACategories := nil;
  Root := TJSONObject.ParseJSONValue(TFile.ReadAllText(AFileName));
  if Root = nil then
    raise Exception.CreateFmt('The snippet file "%s" contains invalid JSON.', [AFileName]);
  try
    if not (Root is TJSONObject) then
      raise Exception.Create('The snippet JSON root must be an object.');
    Obj := TJSONObject(Root);
    if (Obj.GetValue('formatVersion') = nil) or
      (Obj.GetValue<Integer>('formatVersion') <> 1) then
      raise Exception.Create('Unsupported snippet JSON format version.');
    if not (Obj.GetValue('snippets') is TJSONArray) then
      raise Exception.Create('The snippet JSON file must contain a snippets array.');
    Items := TJSONArray(Obj.GetValue('snippets'));
    Snippets := TList<TRADESnippet>.Create;
    CategoryList := TList<string>.Create;
    try
      for I := 0 to Items.Count - 1 do
        Snippets.Add(JSONToSnippet(Items.Items[I]));
      Result := Snippets.ToArray;
      if Obj.GetValue('categories') <> nil then
      begin
        if not (Obj.GetValue('categories') is TJSONArray) then
          raise Exception.Create('The snippet JSON categories field must be an array.');
        Categories := TJSONArray(Obj.GetValue('categories'));
        for I := 0 to Categories.Count - 1 do
        begin
          if not (Categories.Items[I] is TJSONString) then
            raise Exception.Create('Every snippet category must be a string.');
          if Trim(Categories.Items[I].Value) <> '' then
            CategoryList.Add(Categories.Items[I].Value);
        end;
      end;
      ACategories := CategoryList.ToArray;
    finally
      CategoryList.Free;
      Snippets.Free;
    end;
  finally
    Root.Free;
  end;
  ValidateSnippets(Result);
end;

function RADECodeSnippets_GetAll: TArray<TRADESnippet>;
var
  Categories: TArray<string>;
begin
  if not TFile.Exists(SnippetFilePath) then
    Exit(nil);
  Result := ParseSnippetFile(SnippetFilePath, Categories);
end;

function RADECodeSnippets_GetCategories: TArray<string>;
begin
  if not TFile.Exists(SnippetFilePath) then
    Exit(nil);
  ParseSnippetFile(SnippetFilePath, Result);
end;

procedure SaveSnippets(const ASnippets: TArray<TRADESnippet>; const AFileName: string;
  const ACategories: TArray<string> = nil);
var
  Root: TJSONObject;
  Items, CategoryItems: TJSONArray;
  Snippet: TRADESnippet;
  Category: string;
begin
  ValidateSnippets(ASnippets);
  Root := TJSONObject.Create;
  try
    Root.AddPair('formatVersion', TJSONNumber.Create(1));
    Items := TJSONArray.Create;
    Root.AddPair('snippets', Items);
    if Length(ACategories) > 0 then
    begin
      CategoryItems := TJSONArray.Create;
      Root.AddPair('categories', CategoryItems);
      for Category in ACategories do
        if Trim(Category) <> '' then
          CategoryItems.Add(Category);
    end;
    for Snippet in ASnippets do
      Items.AddElement(SnippetToJSON(Snippet));
    TFile.WriteAllText(AFileName, Root.Format(2), TEncoding.UTF8);
  finally
    Root.Free;
  end;
end;

function RADECodeSnippets_GetShortcut(ASlot: Integer): TShortCut;
var
  Snippets: TArray<TRADESnippet>;
  I, Slot: Integer;
begin
  Result := 0;
  if (ASlot < 1) or (ASlot > CMaximumShortcuts) then
    Exit;
  Snippets := RADECodeSnippets_GetAll;
  Slot := 0;
  for I := 0 to High(Snippets) do
    if Trim(Snippets[I].Shortcut) <> '' then
    begin
      Inc(Slot);
      if Slot = ASlot then
        Exit(TextToShortCut(Snippets[I].Shortcut));
    end;
end;

function FindShortcutSnippet(ASlot: Integer; out ASnippet: TRADESnippet): Boolean;
var
  Snippets: TArray<TRADESnippet>;
  I, Slot: Integer;
begin
  Result := False;
  if (ASlot < 1) or (ASlot > CMaximumShortcuts) then
    Exit;
  Snippets := RADECodeSnippets_GetAll;
  Slot := 0;
  for I := 0 to High(Snippets) do
    if Trim(Snippets[I].Shortcut) <> '' then
    begin
      Inc(Slot);
      if Slot = ASlot then
      begin
        ASnippet := Snippets[I];
        Exit(True);
      end;
    end;
end;

function ReadEditorRange(const SourceEditor: IOTASourceEditor;
  StartOffset, EndOffset: Integer): string;
var
  Reader: IOTAEditReader;
  Buffer: AnsiString;
  BytesRead, BytesRequested, TotalBytes: Integer;
begin
  Result := '';
  TotalBytes := EndOffset - StartOffset;
  if TotalBytes <= 0 then
    Exit;
  SetLength(Buffer, TotalBytes);
  Reader := SourceEditor.CreateReader;
  BytesRead := 0;
  while BytesRead < TotalBytes do
  begin
    BytesRequested := Reader.GetText(StartOffset + BytesRead,
      PAnsiChar(Buffer) + BytesRead, TotalBytes - BytesRead);
    if BytesRequested <= 0 then
      raise Exception.Create('Could not read the selected editor text.');
    Inc(BytesRead, BytesRequested);
  end;
  Result := UTF8ToString(UTF8String(Buffer));
end;

function CaptureEditorSelection(out ACode, ALocation, ARangeID: string): Boolean;
var
  ModuleServices: IOTAModuleServices;
  Module: IOTAModule;
  Editor: IOTAEditor;
  SourceEditor: IOTASourceEditor;
  EditView: IOTAEditView;
  Block: IOTAEditBlock;
  Position: TOTAEditPos;
  CharPosition: TOTACharPos;
  StartOffset, EndOffset: Integer;
begin
  ACode := '';
  ALocation := '';
  ARangeID := '';
  Result := False;
  if not Supports(BorlandIDEServices, IOTAModuleServices, ModuleServices) then
    Exit;
  Module := ModuleServices.CurrentModule;
  if Module = nil then
    Exit;
  Editor := Module.CurrentEditor;
  if (Editor = nil) or not Supports(Editor, IOTASourceEditor, SourceEditor) or
    (SourceEditor.EditViewCount = 0) then
    Exit;
  EditView := SourceEditor.EditViews[0];
  Block := EditView.Block;
  if (Block = nil) or (Block.Size = 0) then
    Exit;
  Position.Line := Block.StartingRow;
  Position.Col := Block.StartingColumn;
  EditView.ConvertPos(True, Position, CharPosition);
  StartOffset := EditView.CharPosToPos(CharPosition);
  Position.Line := Block.EndingRow;
  Position.Col := Block.EndingColumn;
  EditView.ConvertPos(True, Position, CharPosition);
  EndOffset := EditView.CharPosToPos(CharPosition);
  if EndOffset <= StartOffset then
    Exit;
  ACode := ReadEditorRange(SourceEditor, StartOffset, EndOffset);
  ALocation := Module.FileName;
  ARangeID := Format('%s|%d:%d-%d:%d', [ALocation, Block.StartingRow,
    Block.StartingColumn, Block.EndingRow, Block.EndingColumn]);
  Result := ACode <> '';
end;

function RADECodeSnippets_CaptureSelection(out ACode, ALocation: string): Boolean;
var
  RangeID: string;
begin
  Result := CaptureEditorSelection(ACode, ALocation, RangeID);
end;

function RADECodeSnippets_CaptureSelectionEx(out ACode, ALocation,
  ARangeID: string): Boolean;
begin
  Result := CaptureEditorSelection(ACode, ALocation, ARangeID);
end;

function ExpandSnippetFields(const AText, ASelection: string): string;
var
  NowValue: TDateTime;
begin
  NowValue := Now;
  Result := StringReplace(AText, '{{DATE}}', FormatDateTime('yyyy-mm-dd', NowValue),
    [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, '{{TIME}}', FormatDateTime('hh:nn:ss', NowValue),
    [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, '{{YEAR}}', FormatDateTime('yyyy', NowValue),
    [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, '{{SELECTION}}', ASelection,
    [rfReplaceAll, rfIgnoreCase]);
end;

function AddManagerButton(AOwner: TComponent; AParent: TWinControl;
  const ACaption: string; AWidth: Integer; AAlign: TAlign;
  AOnClick: TNotifyEvent): TPanel;
var
  LabelControl: TLabel;
begin
  Result := TPanel.Create(AOwner);
  Result.Parent := AParent;
  Result.Align := AAlign;
  Result.Width := AWidth;
  Result.BevelOuter := bvNone;
  Result.Color := RGB(43, 47, 52);
  Result.Cursor := crHandPoint;
  Result.OnClick := AOnClick;
  LabelControl := TLabel.Create(AOwner);
  LabelControl.Parent := Result;
  LabelControl.Align := alClient;
  LabelControl.Alignment := taCenter;
  LabelControl.Layout := tlCenter;
  LabelControl.Caption := ACaption;
  LabelControl.Font.Name := 'Segoe UI';
  LabelControl.Font.Size := 9;
  LabelControl.Font.Color := RGB(224, 226, 228);
  LabelControl.Cursor := crHandPoint;
  LabelControl.OnClick := AOnClick;
end;

function InsertSnippetText(const AText: string): Boolean;
var
  ModuleServices: IOTAModuleServices;
  Module: IOTAModule;
  Editor: IOTAEditor;
  SourceEditor: IOTASourceEditor;
  EditView: IOTAEditView;
  Writer: IOTAEditWriter;
  EditPosition, StartPosition, EndPosition: TOTAEditPos;
  CharPosition: TOTACharPos;
  StartOffset, EndOffset, CaretOffset: Integer;
  UTF8Text: UTF8String;
  Block: IOTAEditBlock;
  SelectionText: string;
begin
  Result := False;
  if not Supports(BorlandIDEServices, IOTAModuleServices, ModuleServices) then
    raise Exception.Create('The RAD Studio editor services are unavailable.');
  Module := ModuleServices.CurrentModule;
  if Module = nil then
  begin
    MessageDlg('Open a source file before inserting a code snippet.',
      mtInformation, [mbOK], 0);
    Exit;
  end;
  Editor := Module.CurrentEditor;
  if (Editor <> nil) and Supports(Editor, IOTASourceEditor, SourceEditor) and
    (SourceEditor.EditViewCount > 0) then
  begin
    Editor.Show;
    EditView := SourceEditor.EditViews[0];
    EditPosition := EditView.CursorPos;
    Block := EditView.Block;
    if (Block <> nil) and (Block.Size > 0) then
    begin
      StartPosition.Line := Block.StartingRow;
      StartPosition.Col := Block.StartingColumn;
      EndPosition.Line := Block.EndingRow;
      EndPosition.Col := Block.EndingColumn;
      EditView.ConvertPos(True, StartPosition, CharPosition);
      StartOffset := EditView.CharPosToPos(CharPosition);
      EditView.ConvertPos(True, EndPosition, CharPosition);
      EndOffset := EditView.CharPosToPos(CharPosition);
      SelectionText := ReadEditorRange(SourceEditor, StartOffset, EndOffset);
    end
    else
    begin
      EditView.ConvertPos(True, EditPosition, CharPosition);
      StartOffset := EditView.CharPosToPos(CharPosition);
      EndOffset := StartOffset;
      SelectionText := '';
    end;
    UTF8Text := UTF8String(ExpandSnippetFields(AText, SelectionText));
    Writer := SourceEditor.CreateUndoableWriter;
    Writer.CopyTo(StartOffset);
    if EndOffset > StartOffset then
      Writer.DeleteTo(EndOffset);
    Writer.Insert(UTF8Text);
    Writer := nil;
    CaretOffset := StartOffset + Length(UTF8Text);
    CharPosition := EditView.PosToCharPos(CaretOffset);
    EditView.ConvertPos(False, EditPosition, CharPosition);
    EditView.CursorPos := EditPosition;
    Exit(True);
  end;
  MessageDlg('The active file does not have a source editor.',
    mtInformation, [mbOK], 0);
end;

function RADECodeSnippets_InsertByID(const AID: string): Boolean;
var
  Snippet: TRADESnippet;
begin
  try
    for Snippet in RADECodeSnippets_GetAll do
      if SameText(Snippet.ID, AID) then
        Exit(InsertSnippetText(Snippet.Code));
    raise Exception.Create('The selected snippet could not be found in the snippet library.');
  except
    on E: Exception do
    begin
      MessageDlg('Could not insert the selected snippet: ' + E.Message,
        mtError, [mbOK], 0);
      Result := False;
    end;
  end;
end;

function RADECodeSnippets_InsertByShortcut(ASlot: Integer): Boolean;
var
  Snippet: TRADESnippet;
begin
  try
    if not FindShortcutSnippet(ASlot, Snippet) then
      Exit(False);
    Result := InsertSnippetText(Snippet.Code);
  except
    on E: Exception do
    begin
      MessageDlg('Could not insert the shortcut snippet: ' + E.Message,
        mtError, [mbOK], 0);
      Result := False;
    end;
  end;
end;

type
  TRADESnippetManager = class(TForm)
  private
    FSnippets: TList<TRADESnippet>;
    FVisibleIndexes: TList<Integer>;
    FSearchEdit: TEdit;
    FCategoryList: TListBox;
    FSnippetList: TListBox;
    FNameEdit: TEdit;
    FCategories: TStringList;
    FLocationEdit: TEdit;
    FShortcutEdit: TEdit;
    FCodeMemo: TRichEdit;
    FPreviewMemo: TMemo;
    FStatusLabel: TLabel;
    FSelectionTimer: TTimer;
    FHighlighting: Boolean;
    FPickerForm: TForm;
    FPickerBaselineID: string;
    FWaitingForSelection: Boolean;
    FClosedByUser: Boolean;
    FOnSaved: TNotifyEvent;
    FEditingID: string;
    FInitialSelection: string;
    FActiveCategory: string;
    FEditingCategory: string;
    procedure HeaderMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure ManagerShown(Sender: TObject);
    procedure ManagerClosing(Sender: TObject; var Action: TCloseAction);
    procedure SearchKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure SelectionKeyUp(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure DrawSnippetItem(Control: TWinControl; Index: Integer; Rect: TRect;
      State: TOwnerDrawState);
    procedure DrawCategoryItem(Control: TWinControl; Index: Integer; Rect: TRect;
      State: TOwnerDrawState);
    procedure SnippetListMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure SnippetListMouseMove(Sender: TObject; Shift: TShiftState;
      X, Y: Integer);
    procedure CategoryDragOver(Sender, Source: TObject; X, Y: Integer;
      State: TDragState; var Accept: Boolean);
    procedure CategoryDragDrop(Sender, Source: TObject; X, Y: Integer);
    procedure ShortcutKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure CategoryChanged(Sender: TObject);
    procedure InsertSnippetClick(Sender: TObject);
    procedure CloseClick(Sender: TObject);
    procedure RefreshCategories;
    procedure RefreshList;
    procedure SearchChanged(Sender: TObject);
    procedure SelectionChanged(Sender: TObject);
    procedure CodeChanged(Sender: TObject);
    procedure InsertDateFieldClick(Sender: TObject);
    procedure InsertTimeFieldClick(Sender: TObject);
    procedure InsertYearFieldClick(Sender: TObject);
    procedure InsertSelectionFieldClick(Sender: TObject);
    procedure PickLinesClick(Sender: TObject);
    procedure SelectionTimerTick(Sender: TObject);
    procedure UseSelectionClick(Sender: TObject);
    procedure CancelPickClick(Sender: TObject);
    procedure PickerClosing(Sender: TObject; var Action: TCloseAction);
    procedure CancelLinePicker;
    procedure ApplyPickedSelection(const ACode, ALocation: string);
    procedure InsertField(const AField: string);
    procedure AddCategory(const ACategory: string);
    procedure NewCategoryClick(Sender: TObject);
    procedure AssignSnippetCategory(const ASnippetID, ACategory: string);
    procedure HighlightCode;
    procedure NewClick(Sender: TObject);
    procedure SaveClick(Sender: TObject);
    procedure DeleteClick(Sender: TObject);
    procedure ImportClick(Sender: TObject);
    procedure ExportClick(Sender: TObject);
    procedure ShowError(const AMessage: string);
    function CurrentSnippet: TRADESnippet;
    procedure LoadSnippet(const ASnippet: TRADESnippet);
  public
    constructor Create(AOwner: TComponent; const AInitialCode, ALocation: string;
      AOnSaved: TNotifyEvent); reintroduce;
    destructor Destroy; override;
  end;

var
  GSnippetManager: TRADESnippetManager;

constructor TRADESnippetManager.Create(AOwner: TComponent;
  const AInitialCode, ALocation: string; AOnSaved: TNotifyEvent);
var
  BorderPanel, Header, SearchBar, Body, LeftPanel, LeftHeader, RightPanel,
    MetaPanel, CodePanel, CodeHeader, PreviewPanel, Footer,
    CategoryHeader, SnippetHeader: TPanel;
  LabelControl: TLabel;
  Snippet: TRADESnippet;
    Category: string;
begin
  inherited CreateNew(AOwner);
  FOnSaved := AOnSaved;
  Caption := 'Code Snippets Manager';
  BorderStyle := bsNone;
  FormStyle := fsStayOnTop;
  KeyPreview := True;
  Position := poScreenCenter;
  Width := 980;
  Height := 640;
  Constraints.MinWidth := 820;
  Constraints.MinHeight := 520;
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  Color := RGB(32, 35, 39);
  FInitialSelection := AInitialCode;
  FSnippets := TList<TRADESnippet>.Create;
  FVisibleIndexes := TList<Integer>.Create;
  FCategories := TStringList.Create;
  FCategories.CaseSensitive := False;
  FCategories.Sorted := True;
  FCategories.Duplicates := dupIgnore;

  BorderPanel := TPanel.Create(Self);
  BorderPanel.Parent := Self;
  BorderPanel.Align := alClient;
  BorderPanel.BevelOuter := bvNone;
  BorderPanel.Color := RGB(32, 35, 39);
  BorderPanel.Padding.Left := 1;
  BorderPanel.Padding.Top := 1;
  BorderPanel.Padding.Right := 1;
  BorderPanel.Padding.Bottom := 1;
  OnKeyDown := SearchKeyDown;
  OnShow := ManagerShown;
  OnClose := ManagerClosing;
  FSelectionTimer := TTimer.Create(Self);
  FSelectionTimer.Enabled := False;
  FSelectionTimer.Interval := 100;
  FSelectionTimer.OnTimer := SelectionTimerTick;

  Header := TPanel.Create(Self);
  Header.Parent := BorderPanel;
  Header.Align := alTop;
  Header.Height := 82;
  Header.BevelOuter := bvNone;
  Header.Color := RGB(32, 35, 39);
  Header.OnMouseDown := HeaderMouseDown;
  LabelControl := TLabel.Create(Self);
  LabelControl.Parent := Header;
  LabelControl.SetBounds(16, 5, 400, 22);
  LabelControl.Caption := 'Code Snippets';
  LabelControl.Font.Size := 11;
  LabelControl.Font.Color := RGB(236, 239, 242);
  LabelControl.Font.Style := [fsBold];
  LabelControl.OnMouseDown := HeaderMouseDown;
  LabelControl := TLabel.Create(Self);
  LabelControl.Parent := Header;
  LabelControl.SetBounds(16, 27, 560, 18);
  LabelControl.Caption := 'Reusable code for every project';
  LabelControl.Font.Color := RGB(155, 158, 161);
  LabelControl.OnMouseDown := HeaderMouseDown;

  SearchBar := TPanel.Create(Self);
  SearchBar.Parent := Header;
  SearchBar.SetBounds(10, 50, 958, 26);
  SearchBar.Anchors := [akLeft, akTop, akRight];
  SearchBar.BevelOuter := bvNone;
  SearchBar.Color := RGB(43, 47, 52);
  LabelControl := TLabel.Create(Self);
  LabelControl.Parent := SearchBar;
  LabelControl.Align := alLeft;
  LabelControl.Width := 82;
  LabelControl.Alignment := taCenter;
  LabelControl.Layout := tlCenter;
  LabelControl.Caption := 'SNIPPETS';
  LabelControl.Font.Color := RGB(213, 225, 237);
  LabelControl.Font.Size := 8;
  LabelControl.Font.Style := [fsBold];
  FSearchEdit := TEdit.Create(Self);
  FSearchEdit.Parent := SearchBar;
  FSearchEdit.Align := alClient;
  FSearchEdit.BorderStyle := bsNone;
  FSearchEdit.Color := RGB(43, 47, 52);
  FSearchEdit.Font.Name := 'Segoe UI';
  FSearchEdit.Font.Size := 10;
  FSearchEdit.Font.Color := RGB(235, 236, 238);
  FSearchEdit.Margins.Left := 8;
  FSearchEdit.Margins.Right := 8;
  FSearchEdit.AlignWithMargins := True;
  FSearchEdit.TextHint := 'Search names, categories, locations, and code...';
  FSearchEdit.OnChange := SearchChanged;
  FSearchEdit.OnKeyDown := SearchKeyDown;

  Body := TPanel.Create(Self);
  Body.Parent := BorderPanel;
  Body.Align := alClient;
  Body.BevelOuter := bvNone;
  Body.Color := RGB(32, 35, 39);

  LeftPanel := TPanel.Create(Self);
  LeftPanel.Parent := Body;
  LeftPanel.Align := alLeft;
  LeftPanel.Width := 250;
  LeftPanel.BevelOuter := bvNone;
  LeftPanel.Color := RGB(28, 31, 35);
  LeftHeader := TPanel.Create(Self);
  LeftHeader.Parent := LeftPanel;
  LeftHeader.Align := alTop;
  LeftHeader.Height := 42;
  LeftHeader.BevelOuter := bvNone;
  LeftHeader.Color := RGB(28, 31, 35);
  LabelControl := TLabel.Create(Self);
  LabelControl.Parent := LeftHeader;
  LabelControl.Align := alClient;
  LabelControl.Margins.Left := 14;
  LabelControl.AlignWithMargins := True;
  LabelControl.Layout := tlCenter;
  LabelControl.Caption := 'LIBRARY';
  LabelControl.Font.Size := 8;
  LabelControl.Font.Style := [fsBold];
  LabelControl.Font.Color := RGB(155, 158, 161);
  AddManagerButton(Self, LeftHeader, '+ New', 66, alRight, NewClick);

  CategoryHeader := TPanel.Create(Self);
  CategoryHeader.Parent := LeftPanel;
  CategoryHeader.Align := alTop;
  CategoryHeader.Height := 27;
  CategoryHeader.BevelOuter := bvNone;
  CategoryHeader.Color := RGB(28, 31, 35);
  LabelControl := TLabel.Create(Self);
  LabelControl.Parent := CategoryHeader;
  LabelControl.Align := alClient;
  LabelControl.Margins.Left := 14;
  LabelControl.AlignWithMargins := True;
  LabelControl.Layout := tlCenter;
  LabelControl.Caption := 'CATEGORIES';
  LabelControl.Font.Size := 8;
  LabelControl.Font.Style := [fsBold];
  LabelControl.Font.Color := RGB(115, 120, 128);
  AddManagerButton(Self, CategoryHeader, '+', 32, alRight, NewCategoryClick);

  FCategoryList := TListBox.Create(Self);
  FCategoryList.Parent := LeftPanel;
  FCategoryList.Align := alTop;
  FCategoryList.Height := 142;
  FCategoryList.Style := lbOwnerDrawFixed;
  FCategoryList.ItemHeight := 27;
  FCategoryList.BorderStyle := bsNone;
  FCategoryList.Color := RGB(28, 31, 35);
  FCategoryList.Font.Name := 'Segoe UI';
  FCategoryList.Font.Size := 9;
  FCategoryList.Font.Color := RGB(190, 194, 200);
  FCategoryList.OnDrawItem := DrawCategoryItem;
  FCategoryList.OnClick := CategoryChanged;
  FCategoryList.OnDragOver := CategoryDragOver;
  FCategoryList.OnDragDrop := CategoryDragDrop;

  SnippetHeader := TPanel.Create(Self);
  SnippetHeader.Parent := LeftPanel;
  SnippetHeader.Align := alTop;
  SnippetHeader.Height := 30;
  SnippetHeader.BevelOuter := bvNone;
  SnippetHeader.Color := RGB(28, 31, 35);
  LabelControl := TLabel.Create(Self);
  LabelControl.Parent := SnippetHeader;
  LabelControl.Align := alClient;
  LabelControl.Margins.Left := 14;
  LabelControl.AlignWithMargins := True;
  LabelControl.Layout := tlCenter;
  LabelControl.Caption := 'SNIPPETS';
  LabelControl.Font.Size := 8;
  LabelControl.Font.Style := [fsBold];
  LabelControl.Font.Color := RGB(115, 120, 128);
  FSnippetList := TListBox.Create(Self);
  FSnippetList.Parent := LeftPanel;
  FSnippetList.Align := alClient;
  FSnippetList.Style := lbOwnerDrawFixed;
  FSnippetList.ItemHeight := 50;
  FSnippetList.BorderStyle := bsNone;
  FSnippetList.Color := RGB(28, 31, 35);
  FSnippetList.Font.Name := 'Segoe UI';
  FSnippetList.Font.Size := 9;
  FSnippetList.Font.Color := RGB(224, 226, 228);
  FSnippetList.OnDrawItem := DrawSnippetItem;
  FSnippetList.OnClick := SelectionChanged;
  FSnippetList.OnDblClick := InsertSnippetClick;
  FSnippetList.OnKeyDown := SearchKeyDown;
  FSnippetList.OnKeyUp := SelectionKeyUp;
  FSnippetList.OnMouseDown := SnippetListMouseDown;
  FSnippetList.OnMouseMove := SnippetListMouseMove;
  FSnippetList.DragMode := dmAutomatic;

  RightPanel := TPanel.Create(Self);
  RightPanel.Parent := Body;
  RightPanel.Align := alClient;
  RightPanel.BevelOuter := bvNone;
  RightPanel.Color := RGB(32, 35, 39);

  PreviewPanel := TPanel.Create(Self);
  PreviewPanel.Parent := RightPanel;
  PreviewPanel.Align := alBottom;
  PreviewPanel.Height := 126;
  PreviewPanel.BevelOuter := bvNone;
  PreviewPanel.Color := RGB(32, 35, 39);
  LabelControl := TLabel.Create(Self);
  LabelControl.Parent := PreviewPanel;
  LabelControl.Align := alTop;
  LabelControl.Height := 24;
  LabelControl.Margins.Left := 12;
  LabelControl.AlignWithMargins := True;
  LabelControl.Layout := tlCenter;
  LabelControl.Caption := 'PREVIEW  |  LIVE VALUES';
  LabelControl.Font.Size := 8;
  LabelControl.Font.Style := [fsBold];
  LabelControl.Font.Color := RGB(155, 158, 161);
  FPreviewMemo := TMemo.Create(Self);
  FPreviewMemo.Parent := PreviewPanel;
  FPreviewMemo.Align := alClient;
  FPreviewMemo.AlignWithMargins := True;
  FPreviewMemo.Margins.Left := 12;
  FPreviewMemo.Margins.Top := 4;
  FPreviewMemo.Margins.Right := 12;
  FPreviewMemo.Margins.Bottom := 6;
  FPreviewMemo.BorderStyle := bsNone;
  FPreviewMemo.ReadOnly := True;
  FPreviewMemo.Color := RGB(28, 31, 35);
  FPreviewMemo.Font.Name := 'Consolas';
  FPreviewMemo.Font.Size := 9;
  FPreviewMemo.Font.Color := RGB(213, 225, 237);
  FPreviewMemo.ScrollBars := ssNone;
  FPreviewMemo.WordWrap := True;

  CodePanel := TPanel.Create(Self);
  CodePanel.Parent := RightPanel;
  CodePanel.Align := alClient;
  CodePanel.BevelOuter := bvNone;
  CodePanel.Color := RGB(32, 35, 39);
  CodeHeader := TPanel.Create(Self);
  CodeHeader.Parent := CodePanel;
  CodeHeader.Align := alTop;
  CodeHeader.Height := 36;
  CodeHeader.BevelOuter := bvNone;
  CodeHeader.Color := RGB(32, 35, 39);
  LabelControl := TLabel.Create(Self);
  LabelControl.Parent := CodeHeader;
  LabelControl.Align := alLeft;
  LabelControl.Width := 115;
  LabelControl.Margins.Left := 12;
  LabelControl.AlignWithMargins := True;
  LabelControl.Layout := tlCenter;
  LabelControl.Caption := 'CODE TEMPLATE';
  LabelControl.Font.Size := 8;
  LabelControl.Font.Style := [fsBold];
  LabelControl.Font.Color := RGB(155, 158, 161);
  AddManagerButton(Self, CodeHeader, 'Pick lines...', 110, alRight, PickLinesClick);
  AddManagerButton(Self, CodeHeader, '{{SELECTION}}', 128, alRight,
    InsertSelectionFieldClick);
  AddManagerButton(Self, CodeHeader, '{{YEAR}}', 88, alRight, InsertYearFieldClick);
  AddManagerButton(Self, CodeHeader, '{{TIME}}', 88, alRight, InsertTimeFieldClick);
  AddManagerButton(Self, CodeHeader, '{{DATE}}', 88, alRight, InsertDateFieldClick);
  FCodeMemo := TRichEdit.Create(Self);
  FCodeMemo.Parent := CodePanel;
  FCodeMemo.Align := alClient;
  FCodeMemo.AlignWithMargins := True;
  FCodeMemo.Margins.Left := 12;
  FCodeMemo.Margins.Top := 6;
  FCodeMemo.Margins.Right := 12;
  FCodeMemo.Margins.Bottom := 6;
  FCodeMemo.BorderStyle := bsNone;
  FCodeMemo.PlainText := True;
  FCodeMemo.Color := RGB(28, 31, 35);
  FCodeMemo.Font.Name := 'Consolas';
  FCodeMemo.Font.Size := 10;
  FCodeMemo.Font.Color := RGB(212, 212, 212);
  FCodeMemo.ScrollBars := ssVertical;
  FCodeMemo.WordWrap := True;
  FCodeMemo.OnChange := CodeChanged;

  MetaPanel := TPanel.Create(Self);
  MetaPanel.Parent := RightPanel;
  MetaPanel.Align := alTop;
  MetaPanel.Height := 106;
  MetaPanel.BevelOuter := bvNone;
  MetaPanel.Color := RGB(32, 35, 39);
  LabelControl := TLabel.Create(Self);
  LabelControl.Parent := MetaPanel;
  LabelControl.SetBounds(12, 8, 150, 16);
  LabelControl.Caption := 'SNIPPET NAME';
  LabelControl.Font.Size := 8;
  LabelControl.Font.Style := [fsBold];
  LabelControl.Font.Color := RGB(155, 158, 161);
  FNameEdit := TEdit.Create(Self);
  FNameEdit.Parent := MetaPanel;
  FNameEdit.SetBounds(12, 27, 390, 26);
  FNameEdit.Anchors := [akLeft, akTop, akRight];
  FNameEdit.Color := RGB(43, 47, 52);
  FNameEdit.Font.Color := RGB(235, 236, 238);
  FNameEdit.BorderStyle := bsNone;
  LabelControl := TLabel.Create(Self);
  LabelControl.Parent := MetaPanel;
  LabelControl.SetBounds(418, 8, 180, 16);
  LabelControl.Caption := 'SNIPPET SHORTCUT  |  3 MAX';
  LabelControl.Font.Size := 8;
  LabelControl.Font.Style := [fsBold];
  LabelControl.Font.Color := RGB(155, 158, 161);
  FShortcutEdit := TEdit.Create(Self);
  FShortcutEdit.Parent := MetaPanel;
  FShortcutEdit.SetBounds(418, 27, 180, 26);
  FShortcutEdit.Anchors := [akTop, akRight];
  FShortcutEdit.Color := RGB(43, 47, 52);
  FShortcutEdit.Font.Color := RGB(235, 236, 238);
  FShortcutEdit.BorderStyle := bsNone;
  FShortcutEdit.TextHint := 'e.g. Ctrl+Alt+1';
  FShortcutEdit.OnKeyDown := ShortcutKeyDown;

  LabelControl := TLabel.Create(Self);
  LabelControl.Parent := MetaPanel;
  LabelControl.SetBounds(12, 61, 190, 16);
  LabelControl.Caption := 'LOCATION';
  LabelControl.Font.Size := 8;
  LabelControl.Font.Style := [fsBold];
  LabelControl.Font.Color := RGB(155, 158, 161);
  FLocationEdit := TEdit.Create(Self);
  FLocationEdit.Parent := MetaPanel;
  FLocationEdit.SetBounds(12, 79, 586, 24);
  FLocationEdit.Anchors := [akLeft, akTop, akRight];
  FLocationEdit.Color := RGB(43, 47, 52);
  FLocationEdit.Font.Color := RGB(235, 236, 238);
  FLocationEdit.BorderStyle := bsNone;
  LabelControl := TLabel.Create(Self);
  LabelControl.Parent := MetaPanel;
  Footer := TPanel.Create(Self);
  Footer.Parent := BorderPanel;
  Footer.Align := alBottom;
  Footer.Height := 42;
  Footer.BevelOuter := bvNone;
  Footer.Color := RGB(28, 31, 35);
  FStatusLabel := TLabel.Create(Self);
  FStatusLabel.Parent := Footer;
  FStatusLabel.Align := alClient;
  FStatusLabel.Margins.Left := 12;
  FStatusLabel.AlignWithMargins := True;
  FStatusLabel.Layout := tlCenter;
  FStatusLabel.Font.Color := RGB(155, 158, 161);
  FStatusLabel.Caption := 'Select a snippet, search the library, or create one';
  AddManagerButton(Self, Footer, 'Insert', 88, alRight, InsertSnippetClick);
  AddManagerButton(Self, Footer, 'Save', 76, alRight, SaveClick);
  AddManagerButton(Self, Footer, 'Delete', 76, alRight, DeleteClick);
  AddManagerButton(Self, Footer, 'Import', 82, alRight, ImportClick);
  AddManagerButton(Self, Footer, 'Export', 82, alRight, ExportClick);
  AddManagerButton(Self, Footer, 'Close', 74, alRight, CloseClick);

  try
    FSnippets.AddRange(RADECodeSnippets_GetAll);
  except
    on E: Exception do
    begin
      ShowError('Could not load the snippet library: ' + E.Message);
      raise;
    end;
  end;
  for Snippet in FSnippets do
    AddCategory(Snippet.Category);
  for Category in RADECodeSnippets_GetCategories do
    AddCategory(Category);
  RefreshCategories;
  RefreshList;
  if FInitialSelection <> '' then
  begin
    AddCategory('General');
    FActiveCategory := 'General';
    RefreshCategories;
    NewClick(nil);
    FNameEdit.Text := ChangeFileExt(ExtractFileName(ALocation), '') +
      ' selection';
    if FNameEdit.Text = ' selection' then
      FNameEdit.Text := 'New snippet';
    FLocationEdit.Text := ALocation;
    FCodeMemo.Text := FInitialSelection;
    FStatusLabel.Caption := 'Editor selection captured - name and save the snippet';
  end;
end;

destructor TRADESnippetManager.Destroy;
begin
  if FSelectionTimer <> nil then
    FSelectionTimer.Enabled := False;
  if GSnippetManager = Self then
    GSnippetManager := nil;
  FVisibleIndexes.Free;
  FCategories.Free;
  FSnippets.Free;
  inherited Destroy;
end;

procedure TRADESnippetManager.ShowError(const AMessage: string);
begin
  MessageDlg(AMessage, mtError, [mbOK], 0);
end;

function TRADESnippetManager.CurrentSnippet: TRADESnippet;
begin
  Result.ID := FEditingID;
  Result.Name := Trim(FNameEdit.Text);
  Result.Category := Trim(FEditingCategory);
  Result.Location := Trim(FLocationEdit.Text);
  Result.Code := FCodeMemo.Text;
  Result.Shortcut := Trim(FShortcutEdit.Text);
end;

procedure TRADESnippetManager.LoadSnippet(const ASnippet: TRADESnippet);
begin
  FEditingID := ASnippet.ID;
  FNameEdit.Text := ASnippet.Name;
  FEditingCategory := ASnippet.Category;
  FLocationEdit.Text := ASnippet.Location;
  FShortcutEdit.Text := ASnippet.Shortcut;
  FCodeMemo.Text := ASnippet.Code;
  FPreviewMemo.Text := ExpandSnippetFields(ASnippet.Code, FInitialSelection);
end;

procedure TRADESnippetManager.RefreshList;
var
  Query, SearchText: string;
  I, SelectedVisible: Integer;
  Snippet: TRADESnippet;
begin
  Query := Trim(FSearchEdit.Text);
  FVisibleIndexes.Clear;
  SelectedVisible := -1;
  FSnippetList.Items.BeginUpdate;
  try
    FSnippetList.Clear;
    for I := 0 to FSnippets.Count - 1 do
    begin
      Snippet := FSnippets[I];
      SearchText := Snippet.Name + ' ' + Snippet.Category + ' ' +
        Snippet.Location + ' ' + Snippet.Code;
      if (Query <> '') and (Pos(LowerCase(Query), LowerCase(SearchText)) = 0) then
        Continue;
      if (FActiveCategory <> '') and
        not SameText(Snippet.Category, FActiveCategory) then
        Continue;
      FVisibleIndexes.Add(I);
      FSnippetList.Items.Add(Snippet.Name + '  [' + Snippet.Category + ']');
      if SameText(Snippet.ID, FEditingID) then
        SelectedVisible := FVisibleIndexes.Count - 1;
    end;
  finally
    FSnippetList.Items.EndUpdate;
  end;
  if (FEditingID <> '') and (SelectedVisible >= 0) then
  begin
    FSnippetList.ItemIndex := SelectedVisible;
    LoadSnippet(FSnippets[FVisibleIndexes[SelectedVisible]]);
  end
  else
    FSnippetList.ItemIndex := -1;
  if FVisibleIndexes.Count = 0 then
    FStatusLabel.Caption := 'No snippets match this search'
  else
    FStatusLabel.Caption := Format('%d snippets  |  Enter to select  |  Double-click to insert',
      [FVisibleIndexes.Count]);
end;

procedure TRADESnippetManager.RefreshCategories;
var
  I, SelectedIndex: Integer;
begin
  SelectedIndex := 0;
  FCategoryList.Items.BeginUpdate;
  try
    FCategoryList.Items.Clear;
    FCategoryList.Items.Add('All snippets');
    for I := 0 to FCategories.Count - 1 do
      if not SameText(FCategories[I], 'All snippets') then
      begin
        FCategoryList.Items.Add(FCategories[I]);
        if SameText(FCategories[I], FActiveCategory) then
          SelectedIndex := FCategoryList.Items.Count - 1;
      end;
    FCategoryList.ItemIndex := SelectedIndex;
  finally
    FCategoryList.Items.EndUpdate;
  end;
end;

procedure TRADESnippetManager.AddCategory(const ACategory: string);
var
  Category: string;
begin
  Category := Trim(ACategory);
  if (Category <> '') and not SameText(Category, 'All snippets') and
    (FCategories.IndexOf(Category) < 0) then
    FCategories.Add(Category);
end;

procedure TRADESnippetManager.NewCategoryClick(Sender: TObject);
var
  Category: string;
  CategoryIndex: Integer;
begin
  Category := '';
  if not InputQuery('New snippet category', 'Category name:', Category) then
    Exit;
  Category := Trim(Category);
  if Category = '' then
    Exit;
  if SameText(Category, 'All snippets') then
  begin
    MessageDlg('"All snippets" is reserved for the library view.',
      mtInformation, [mbOK], 0);
    Exit;
  end;
  CategoryIndex := FCategories.IndexOf(Category);
  if CategoryIndex >= 0 then
  begin
    FActiveCategory := FCategories[CategoryIndex];
    RefreshCategories;
    RefreshList;
    NewClick(nil);
    Exit;
  end;
  AddCategory(Category);
  try
    SaveSnippets(FSnippets.ToArray, SnippetFilePath, StringListToArray(FCategories));
  except
    on E: Exception do
    begin
      FCategories.Delete(FCategories.IndexOf(Category));
      ShowError('Could not create category: ' + E.Message);
      Exit;
    end;
  end;
  FActiveCategory := Category;
  RefreshCategories;
  RefreshList;
  NewClick(nil);
end;

procedure TRADESnippetManager.DrawCategoryItem(Control: TWinControl; Index: Integer;
  Rect: TRect; State: TOwnerDrawState);
var
  Canvas: TCanvas;
  Selected: Boolean;
  CategoryText: string;
begin
  if (Index < 0) or (Index >= FCategoryList.Items.Count) then
    Exit;
  Canvas := TListBox(Control).Canvas;
  Selected := odSelected in State;
  if Selected then
    Canvas.Brush.Color := RGB(51, 78, 99)
  else
    Canvas.Brush.Color := RGB(28, 31, 35);
  Canvas.FillRect(Rect);
  Canvas.Font.Name := 'Segoe UI';
  Canvas.Font.Size := 9;
  if Selected then
    Canvas.Font.Color := RGB(235, 239, 244)
  else
    Canvas.Font.Color := RGB(190, 194, 200);
  CategoryText := FCategoryList.Items[Index];
  if Index > 0 then
  begin
    Canvas.Pen.Color := Canvas.Font.Color;
    Canvas.Rectangle(Rect.Left + 12, Rect.Top + 9, Rect.Left + 25,
      Rect.Top + 19);
    Canvas.MoveTo(Rect.Left + 12, Rect.Top + 9);
    Canvas.LineTo(Rect.Left + 17, Rect.Top + 9);
    Canvas.LineTo(Rect.Left + 19, Rect.Top + 7);
    Canvas.LineTo(Rect.Left + 25, Rect.Top + 7);
    Canvas.LineTo(Rect.Left + 25, Rect.Top + 9);
    Canvas.TextOut(Rect.Left + 34, Rect.Top + 6, CategoryText);
  end
  else
    Canvas.TextOut(Rect.Left + 14, Rect.Top + 6, CategoryText);
end;

procedure TRADESnippetManager.CategoryChanged(Sender: TObject);
begin
  if FCategoryList.ItemIndex <= 0 then
    FActiveCategory := ''
  else
    FActiveCategory := FCategoryList.Items[FCategoryList.ItemIndex];
  RefreshList;
end;

procedure TRADESnippetManager.CategoryDragOver(Sender, Source: TObject; X,
  Y: Integer; State: TDragState; var Accept: Boolean);
var
  TargetIndex: Integer;
begin
  Accept := False;
  if Source <> FSnippetList then
    Exit;
  TargetIndex := FCategoryList.ItemAtPos(Point(X, Y), True);
  Accept := (TargetIndex > 0) and
    (FSnippetList.ItemIndex >= 0) and
    (FSnippetList.ItemIndex < FVisibleIndexes.Count);
end;

procedure TRADESnippetManager.CategoryDragDrop(Sender, Source: TObject; X,
  Y: Integer);
var
  TargetIndex, SnippetIndex: Integer;
  SnippetID, Category: string;
begin
  if Source <> FSnippetList then
    Exit;
  TargetIndex := FCategoryList.ItemAtPos(Point(X, Y), True);
  if (TargetIndex <= 0) or (FSnippetList.ItemIndex < 0) or
    (FSnippetList.ItemIndex >= FVisibleIndexes.Count) then
    Exit;
  SnippetIndex := FVisibleIndexes[FSnippetList.ItemIndex];
  SnippetID := FSnippets[SnippetIndex].ID;
  Category := FCategoryList.Items[TargetIndex];
  AssignSnippetCategory(SnippetID, Category);
end;

procedure TRADESnippetManager.AssignSnippetCategory(const ASnippetID,
  ACategory: string);
var
  I: Integer;
  Original, Updated: TRADESnippet;
  Snippets: TArray<TRADESnippet>;
begin
  for I := 0 to FSnippets.Count - 1 do
    if SameText(FSnippets[I].ID, ASnippetID) then
    begin
      Original := FSnippets[I];
      Updated := Original;
      Updated.Category := ACategory;
      FSnippets[I] := Updated;
      Snippets := FSnippets.ToArray;
      try
        SaveSnippets(Snippets, SnippetFilePath, StringListToArray(FCategories));
      except
        on E: Exception do
        begin
          FSnippets[I] := Original;
          ShowError('Could not move snippet to category: ' + E.Message);
          Exit;
        end;
      end;
      FEditingID := ASnippetID;
      FEditingCategory := ACategory;
      FActiveCategory := ACategory;
      RefreshCategories;
      RefreshList;
      FStatusLabel.Caption := 'Moved snippet to ' + ACategory;
      Exit;
    end;
end;

procedure TRADESnippetManager.ShortcutKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  if Key = VK_ESCAPE then
  begin
    FShortcutEdit.Clear;
    Key := 0;
  end;
end;

procedure TRADESnippetManager.SearchChanged(Sender: TObject);
begin
  RefreshList;
end;

procedure TRADESnippetManager.SelectionChanged(Sender: TObject);
var
  VisibleIndex, SnippetIndex: Integer;
begin
  VisibleIndex := FSnippetList.ItemIndex;
  if (VisibleIndex < 0) or (VisibleIndex >= FVisibleIndexes.Count) then
    Exit;
  SnippetIndex := FVisibleIndexes[VisibleIndex];
  LoadSnippet(FSnippets[SnippetIndex]);
end;

procedure TRADESnippetManager.CodeChanged(Sender: TObject);
begin
  if FHighlighting then
    Exit;
  FPreviewMemo.Text := ExpandSnippetFields(FCodeMemo.Text, FInitialSelection);
  HighlightCode;
  FStatusLabel.Caption := Format('Preview refreshed  |  %d lines  |  Use the field buttons above',
    [FCodeMemo.Lines.Count]);
end;

procedure TRADESnippetManager.HighlightCode;
const
  CKeywords =
    ' ABSOLUTE ABSTRACT AND ARRAY AS ASM BEGIN CASE CLASS CONST CONSTRUCTOR ' +
    'DESTRUCTOR DISPINTERFACE DIV DO DOWNTO ELSE END EXCEPT EXPORTS FILE FINAL ' +
    'FINALIZATION FINALLY FOR FUNCTION GOTO IF IMPLEMENTATION IN INHERITED ' +
    'INITIALIZATION INLINE INTERFACE IS LABEL LIBRARY MOD NIL NOT OBJECT OF OR ' +
    'OUT PACKED PROCEDURE PROGRAM PROPERTY RAISE RECORD REPEAT RESOURCESTRING ' +
    'SET SHL SHR STRING THEN THREADVAR TO TRY TYPE UNIT UNTIL USES VAR WHILE ' +
    'WITH XOR PRIVATE PROTECTED PUBLIC PUBLISHED STRICT';
var
  Text: string;
  I, Start, SavedStart, SavedLength: Integer;
  Token, UpperToken: string;
  TokenColor: TColor;
  IsKeyword: Boolean;
begin
  if FHighlighting then
    Exit;
  FHighlighting := True;
  try
  Text := FCodeMemo.Text;
  SavedStart := FCodeMemo.SelStart;
  SavedLength := FCodeMemo.SelLength;
  FCodeMemo.SelStart := 0;
  FCodeMemo.SelLength := Length(Text);
  FCodeMemo.SelAttributes.Color := RGB(212, 212, 212);
  FCodeMemo.SelAttributes.Style := [];
  I := 1;
  while I <= Length(Text) do
  begin
    Start := I;
    TokenColor := clNone;
    if Copy(Text, I, 8) = '{{DATE}}' then
    begin
      TokenColor := RGB(78, 201, 176);
      Inc(I, 8);
    end
    else if Copy(Text, I, 8) = '{{TIME}}' then
    begin
      TokenColor := RGB(78, 201, 176);
      Inc(I, 8);
    end
    else if Copy(Text, I, 8) = '{{YEAR}}' then
    begin
      TokenColor := RGB(78, 201, 176);
      Inc(I, 8);
    end
    else if Copy(Text, I, 13) = '{{SELECTION}}' then
    begin
      TokenColor := RGB(78, 201, 176);
      Inc(I, 13);
    end
    else if (Text[I] = '/') and (I < Length(Text)) and (Text[I + 1] = '/') then
    begin
      TokenColor := RGB(106, 153, 85);
      while (I <= Length(Text)) and not CharInSet(Text[I], [#10, #13]) do
        Inc(I);
    end
    else if Text[I] = '{' then
    begin
      TokenColor := RGB(106, 153, 85);
      while (I <= Length(Text)) and (Text[I] <> '}') do
        Inc(I);
      if I <= Length(Text) then
        Inc(I);
    end
    else if (Text[I] = '(') and (I < Length(Text)) and (Text[I + 1] = '*') then
    begin
      TokenColor := RGB(106, 153, 85);
      Inc(I, 2);
      while (I < Length(Text)) and not
        ((Text[I] = '*') and (Text[I + 1] = ')')) do
        Inc(I);
      if I < Length(Text) then
        Inc(I, 2);
    end
    else if Text[I] = '''' then
    begin
      TokenColor := RGB(206, 145, 120);
      Inc(I);
      while I <= Length(Text) do
      begin
        if Text[I] = '''' then
        begin
          Inc(I);
          if (I <= Length(Text)) and (Text[I] = '''') then
            Inc(I)
          else
            Break;
        end
        else
          Inc(I);
      end;
    end
    else if CharInSet(Text[I], ['A'..'Z', 'a'..'z', '_']) then
    begin
      Inc(I);
      while (I <= Length(Text)) and
        CharInSet(Text[I], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
        Inc(I);
      Token := Copy(Text, Start, I - Start);
      UpperToken := ' ' + UpperCase(Token) + ' ';
      IsKeyword := Pos(UpperToken, CKeywords) > 0;
      if IsKeyword then
        TokenColor := RGB(86, 156, 214);
    end
    else if CharInSet(Text[I], ['0'..'9']) then
    begin
      TokenColor := RGB(181, 206, 168);
      Inc(I);
      while (I <= Length(Text)) and
        CharInSet(Text[I], ['0'..'9', 'A'..'F', 'a'..'f', 'x', 'X', '.']) do
        Inc(I);
    end
    else
      Inc(I);

    if TokenColor <> clNone then
    begin
      FCodeMemo.SelStart := Start - 1;
      FCodeMemo.SelLength := I - Start;
      FCodeMemo.SelAttributes.Color := TokenColor;
    end;
  end;
  FCodeMemo.SelStart := SavedStart;
  FCodeMemo.SelLength := SavedLength;
  finally
    FHighlighting := False;
  end;
end;

procedure TRADESnippetManager.InsertField(const AField: string);
begin
  if FCodeMemo.CanFocus then
    FCodeMemo.SetFocus;
  FCodeMemo.SelText := AField;
end;

procedure TRADESnippetManager.InsertDateFieldClick(Sender: TObject);
begin
  InsertField('{{DATE}}');
end;

procedure TRADESnippetManager.InsertTimeFieldClick(Sender: TObject);
begin
  InsertField('{{TIME}}');
end;

procedure TRADESnippetManager.InsertYearFieldClick(Sender: TObject);
begin
  InsertField('{{YEAR}}');
end;

procedure TRADESnippetManager.InsertSelectionFieldClick(Sender: TObject);
begin
  InsertField('{{SELECTION}}');
end;

procedure TRADESnippetManager.PickLinesClick(Sender: TObject);
var
  Code, Location: string;
  PickerLabel: TLabel;
  PickerActions: TPanel;
begin
  if FWaitingForSelection then
    Exit;
  RADECodeSnippets_CaptureSelectionEx(Code, Location, FPickerBaselineID);
  FWaitingForSelection := True;
  if FPickerForm = nil then
  begin
    FPickerForm := TForm.CreateNew(Self);
    FPickerForm.BorderStyle := bsToolWindow;
    FPickerForm.FormStyle := fsStayOnTop;
    FPickerForm.Position := poDesigned;
    FPickerForm.Width := 360;
    FPickerForm.Height := 112;
    FPickerForm.Left := Screen.Width - FPickerForm.Width - 24;
    FPickerForm.Top := Screen.Height - FPickerForm.Height - 80;
    FPickerForm.Caption := 'Select snippet lines';
    FPickerForm.Color := RGB(32, 35, 39);
    FPickerForm.Font.Name := 'Segoe UI';
    FPickerForm.OnClose := PickerClosing;
    PickerLabel := TLabel.Create(Self);
    PickerLabel.Parent := FPickerForm;
    PickerLabel.SetBounds(12, 8, 334, 56);
    PickerLabel.WordWrap := True;
    PickerLabel.Font.Color := RGB(224, 226, 228);
    PickerLabel.Caption := 'Select code in the RAD Studio editor; it is added when you release the selection.';
    PickerActions := TPanel.Create(Self);
    PickerActions.Parent := FPickerForm;
    PickerActions.Align := alBottom;
    PickerActions.Height := 34;
    PickerActions.BevelOuter := bvNone;
    PickerActions.Color := RGB(32, 35, 39);
    AddManagerButton(Self, PickerActions, 'Cancel', 90, alRight, CancelPickClick);
    AddManagerButton(Self, PickerActions, 'Use current selection', 150, alRight,
      UseSelectionClick);
  end;
  FStatusLabel.Caption := 'Select lines in the RAD Studio editor...';
  FSelectionTimer.Enabled := True;
  Hide;
  FPickerForm.Show;
  FPickerForm.BringToFront;
end;

procedure TRADESnippetManager.SelectionTimerTick(Sender: TObject);
var
  Code, Location, RangeID: string;
begin
  if not FWaitingForSelection then
    Exit;
  if not RADECodeSnippets_CaptureSelectionEx(Code, Location, RangeID) or
    (RangeID = '') or (RangeID = FPickerBaselineID) then
    Exit;
  if (GetAsyncKeyState(VK_LBUTTON) and $8000) <> 0 then
    Exit;
  FSelectionTimer.Enabled := False;
  FWaitingForSelection := False;
  ApplyPickedSelection(Code, Location);
end;

procedure TRADESnippetManager.UseSelectionClick(Sender: TObject);
var
  Code, Location, RangeID: string;
begin
  if not RADECodeSnippets_CaptureSelectionEx(Code, Location, RangeID) or
    (RangeID = '') then
  begin
    MessageDlg('Select one or more lines in the RAD Studio editor first.',
      mtInformation, [mbOK], 0);
    Exit;
  end;
  FSelectionTimer.Enabled := False;
  FWaitingForSelection := False;
  ApplyPickedSelection(Code, Location);
end;

procedure TRADESnippetManager.ApplyPickedSelection(const ACode, ALocation: string);
begin
  FPickerForm.Hide;
  Show;
  BringToFront;
  FCodeMemo.SelText := ACode;
  if FLocationEdit.Text = '' then
    FLocationEdit.Text := ALocation;
  FStatusLabel.Caption := 'Added selected code from ' + ExtractFileName(ALocation);
  if FCodeMemo.CanFocus then
    FCodeMemo.SetFocus;
end;

procedure TRADESnippetManager.CancelPickClick(Sender: TObject);
begin
  CancelLinePicker;
end;

procedure TRADESnippetManager.PickerClosing(Sender: TObject;
  var Action: TCloseAction);
begin
  Action := caHide;
  CancelLinePicker;
end;

procedure TRADESnippetManager.CancelLinePicker;
begin
  FSelectionTimer.Enabled := False;
  FWaitingForSelection := False;
  if FPickerForm <> nil then
    FPickerForm.Hide;
  Show;
  BringToFront;
  if FCodeMemo.CanFocus then
    FCodeMemo.SetFocus;
end;

procedure TRADESnippetManager.HeaderMouseDown(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if Button = mbLeft then
  begin
    ReleaseCapture;
    SendMessage(Handle, WM_NCLBUTTONDOWN, HTCAPTION, 0);
  end;
end;

procedure TRADESnippetManager.ManagerShown(Sender: TObject);
begin
  if FInitialSelection <> '' then
  begin
    if FNameEdit.CanFocus then
      FNameEdit.SetFocus;
  end
  else if FSearchEdit.CanFocus then
    FSearchEdit.SetFocus;
end;

procedure TRADESnippetManager.ManagerClosing(Sender: TObject;
  var Action: TCloseAction);
begin
  FSelectionTimer.Enabled := False;
  FWaitingForSelection := False;
  FClosedByUser := True;
  if FPickerForm <> nil then
    FPickerForm.Hide;
  Action := caHide;
end;

procedure TRADESnippetManager.SearchKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  if Key = VK_ESCAPE then
  begin
    Close;
    Key := 0;
  end
  else if Key = VK_DOWN then
  begin
    if FSnippetList.Items.Count > 0 then
    begin
      FSnippetList.SetFocus;
      if FSnippetList.ItemIndex < 0 then
        FSnippetList.ItemIndex := 0;
      SelectionChanged(FSnippetList);
    end;
    Key := 0;
  end
  else if Key = VK_RETURN then
  begin
    if Sender = FSnippetList then
      InsertSnippetClick(Sender)
    else if FSnippetList.ItemIndex >= 0 then
      SelectionChanged(FSnippetList);
    Key := 0;
  end;
end;

procedure TRADESnippetManager.SelectionKeyUp(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  if (Sender = FSnippetList) and (Key in [VK_UP, VK_DOWN]) then
    SelectionChanged(Sender);
end;

procedure TRADESnippetManager.DrawSnippetItem(Control: TWinControl; Index: Integer;
  Rect: TRect; State: TOwnerDrawState);
var
  Snippet: TRADESnippet;
  Canvas: TCanvas;
  TextRect: TRect;
  Selected: Boolean;
  SnippetIndex: Integer;
begin
  if (Index < 0) or (Index >= FVisibleIndexes.Count) then
    Exit;
  Canvas := TListBox(Control).Canvas;
  SnippetIndex := FVisibleIndexes[Index];
  Snippet := FSnippets[SnippetIndex];
  Selected := odSelected in State;
  if Selected then
    Canvas.Brush.Color := RGB(51, 78, 99)
  else
    Canvas.Brush.Color := RGB(28, 31, 35);
  Canvas.FillRect(Rect);
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Name := 'Segoe UI';
  Canvas.Font.Size := 9;
  Canvas.Font.Style := [fsBold];
  if Selected then
    Canvas.Font.Color := clWhite
  else
    Canvas.Font.Color := RGB(224, 226, 228);
  TextRect := Rect;
  InflateRect(TextRect, -12, 0);
  TextRect.Right := Rect.Right - 64;
  Canvas.TextRect(TextRect, TextRect.Left, TextRect.Top + 7, Snippet.Name);
  Canvas.Font.Size := 8;
  Canvas.Font.Style := [];
  Canvas.Font.Color := RGB(155, 158, 161);
  Canvas.TextRect(TextRect, TextRect.Left, TextRect.Top + 27,
    Snippet.Category + '  |  ' + ExtractFileName(Snippet.Location));
  Canvas.Pen.Width := 1;
  Canvas.Pen.Color := RGB(125, 185, 225);
  Canvas.MoveTo(Rect.Right - 48, Rect.Top + 25);
  Canvas.LineTo(Rect.Right - 40, Rect.Top + 25);
  Canvas.LineTo(Rect.Right - 44, Rect.Top + 21);
  Canvas.MoveTo(Rect.Right - 40, Rect.Top + 25);
  Canvas.LineTo(Rect.Right - 44, Rect.Top + 29);
  Canvas.Pen.Color := RGB(220, 125, 125);
  Canvas.MoveTo(Rect.Right - 27, Rect.Top + 20);
  Canvas.LineTo(Rect.Right - 13, Rect.Top + 20);
  Canvas.MoveTo(Rect.Right - 24, Rect.Top + 18);
  Canvas.LineTo(Rect.Right - 16, Rect.Top + 18);
  Canvas.Rectangle(Rect.Right - 25, Rect.Top + 21, Rect.Right - 15,
    Rect.Top + 33);
  Canvas.MoveTo(Rect.Right - 22, Rect.Top + 24);
  Canvas.LineTo(Rect.Right - 22, Rect.Top + 30);
  Canvas.MoveTo(Rect.Right - 18, Rect.Top + 24);
  Canvas.LineTo(Rect.Right - 18, Rect.Top + 30);
  Canvas.Pen.Width := 1;
  Canvas.Brush.Style := bsSolid;
end;

procedure TRADESnippetManager.SnippetListMouseDown(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  ItemIndex, SnippetIndex: Integer;
begin
  if Button <> mbLeft then
    Exit;
  ItemIndex := FSnippetList.ItemAtPos(Point(X, Y), True);
  if ItemIndex < 0 then
    Exit;
  FSnippetList.ItemIndex := ItemIndex;
  SelectionChanged(FSnippetList);
  if ItemIndex >= FVisibleIndexes.Count then
    Exit;
  SnippetIndex := FVisibleIndexes[ItemIndex];
  if X >= FSnippetList.ClientWidth - 30 then
  begin
    FEditingID := FSnippets[SnippetIndex].ID;
    LoadSnippet(FSnippets[SnippetIndex]);
    DeleteClick(Sender);
  end
  else if X >= FSnippetList.ClientWidth - 58 then
  begin
    FEditingID := FSnippets[SnippetIndex].ID;
    LoadSnippet(FSnippets[SnippetIndex]);
    InsertSnippetClick(Sender);
  end;
end;

procedure TRADESnippetManager.SnippetListMouseMove(Sender: TObject;
  Shift: TShiftState; X, Y: Integer);
begin
  if X >= FSnippetList.ClientWidth - 58 then
    FSnippetList.Cursor := crHandPoint
  else
    FSnippetList.Cursor := crDefault;
end;

procedure TRADESnippetManager.InsertSnippetClick(Sender: TObject);
begin
  if FEditingID = '' then
  begin
    FStatusLabel.Caption := 'Save this snippet before inserting it';
    Exit;
  end;
  RADECodeSnippets_InsertByID(FEditingID);
end;

procedure TRADESnippetManager.CloseClick(Sender: TObject);
begin
  Close;
end;

procedure TRADESnippetManager.NewClick(Sender: TObject);
begin
  FSnippetList.ItemIndex := -1;
  FEditingID := '';
  FEditingCategory := FActiveCategory;
  FNameEdit.Clear;
  FLocationEdit.Clear;
  FShortcutEdit.Clear;
  FCodeMemo.Clear;
  FPreviewMemo.Clear;
  if Visible then
    FNameEdit.SetFocus;
end;

procedure TRADESnippetManager.SaveClick(Sender: TObject);
var
  Snippet: TRADESnippet;
  Snippets: TArray<TRADESnippet>;
  I, ExistingIndex: Integer;
  OriginalSnippet: TRADESnippet;
  HadOriginal: Boolean;
  NewID: TGUID;
  Category: string;
begin
  Snippet := CurrentSnippet;
  if Snippet.Name = '' then
  begin
    ShowError('Enter a snippet name before saving.');
    Exit;
  end;
  if Snippet.Category = '' then
  begin
    ShowError('Select a category folder before creating a snippet.');
    Exit;
  end;
  if Trim(Snippet.Code) = '' then
  begin
    ShowError('Enter snippet code before saving.');
    Exit;
  end;
  if Trim(Snippet.Shortcut) <> '' then
  begin
    Snippet.Shortcut := ShortCutToText(TextToShortCut(Snippet.Shortcut));
    if Snippet.Shortcut = '' then
    begin
      ShowError('Enter a valid shortcut, such as Ctrl+Alt+1.');
      Exit;
    end;
  end;
  Category := Snippet.Category;
  AddCategory(Category);
  if Snippet.ID = '' then
  begin
    if CreateGUID(NewID) <> 0 then
    begin
      ShowError('Could not generate a unique snippet ID.');
      Exit;
    end;
    Snippet.ID := GUIDToString(NewID);
  end;
  ExistingIndex := -1;
  for I := 0 to FSnippets.Count - 1 do
    if SameText(FSnippets[I].ID, Snippet.ID) then
    begin
      ExistingIndex := I;
      Break;
    end;
  HadOriginal := ExistingIndex >= 0;
  if HadOriginal then
    OriginalSnippet := FSnippets[ExistingIndex];
  if ExistingIndex < 0 then
    FSnippets.Add(Snippet)
  else
    FSnippets[ExistingIndex] := Snippet;
  Snippets := FSnippets.ToArray;
  try
    ValidateSnippets(Snippets);
    SaveSnippets(Snippets, SnippetFilePath, StringListToArray(FCategories));
  except
    on E: Exception do
    begin
      if not HadOriginal then
        FSnippets.Delete(FSnippets.Count - 1)
      else
        FSnippets[ExistingIndex] := OriginalSnippet;
      ShowError(E.Message);
      Exit;
    end;
  end;
  FEditingID := Snippet.ID;
  FEditingCategory := Snippet.Category;
  FActiveCategory := Snippet.Category;
  FSearchEdit.Clear;
  RefreshCategories;
  RefreshList;
  for I := 0 to FVisibleIndexes.Count - 1 do
    if SameText(FSnippets[FVisibleIndexes[I]].ID, Snippet.ID) then
    begin
      FSnippetList.ItemIndex := I;
      Break;
    end;
  FStatusLabel.Caption := 'Snippet saved to ' + SnippetFilePath;
  FInitialSelection := '';
  if Assigned(FOnSaved) then
    FOnSaved(Self);
end;

procedure TRADESnippetManager.DeleteClick(Sender: TObject);
var
  I, DeletedIndex: Integer;
  Snippets: TArray<TRADESnippet>;
  DeletedSnippet: TRADESnippet;
begin
  if FEditingID = '' then
    Exit;
  if MessageDlg('Delete this snippet from the shared library?',
    mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
    Exit;
  DeletedIndex := -1;
  for I := 0 to FSnippets.Count - 1 do
    if SameText(FSnippets[I].ID, FEditingID) then
    begin
      DeletedIndex := I;
      DeletedSnippet := FSnippets[I];
      FSnippets.Delete(I);
      Break;
    end;
  if DeletedIndex < 0 then
  begin
    ShowError('Could not delete the snippet because it is no longer in the library.');
    Exit;
  end;
  Snippets := FSnippets.ToArray;
  try
    SaveSnippets(Snippets, SnippetFilePath, StringListToArray(FCategories));
  except
    on E: Exception do
    begin
      FSnippets.Insert(DeletedIndex, DeletedSnippet);
      RefreshList;
      ShowError('Could not delete snippet: ' + E.Message);
      Exit;
    end;
  end;
  NewClick(nil);
  RefreshList;
  FStatusLabel.Caption := 'Snippet deleted from the shared library';
  if Assigned(FOnSaved) then
    FOnSaved(Self);
end;

procedure TRADESnippetManager.ImportClick(Sender: TObject);
var
  Dialog: TOpenDialog;
  Imported: TArray<TRADESnippet>;
  ImportedCategories: TArray<string>;
  Snippet: TRADESnippet;
  Category: string;
begin
  Dialog := TOpenDialog.Create(Self);
  try
    Dialog.Filter := 'Snippet libraries (*.json)|*.json|All files (*.*)|*.*';
    Dialog.Title := 'Import code snippets';
    if not Dialog.Execute then
      Exit;
    if (FSnippets.Count > 0) and
      (MessageDlg('Importing replaces the current snippet library. Continue?',
        mtWarning, [mbYes, mbNo], 0) <> mrYes) then
      Exit;
    try
      Imported := ParseSnippetFile(Dialog.FileName, ImportedCategories);
      SaveSnippets(Imported, SnippetFilePath, ImportedCategories);
      FSnippets.Clear;
      for Snippet in Imported do
        FSnippets.Add(Snippet);
      FCategories.Clear;
      for Category in ImportedCategories do
        AddCategory(Category);
      FActiveCategory := '';
      for Snippet in Imported do
        AddCategory(Snippet.Category);
      RefreshCategories;
      NewClick(nil);
      RefreshList;
    except
      on E: Exception do
        ShowError('Could not import snippets: ' + E.Message);
    end;
  finally
    Dialog.Free;
  end;
end;

procedure TRADESnippetManager.ExportClick(Sender: TObject);
var
  Dialog: TSaveDialog;
begin
  Dialog := TSaveDialog.Create(Self);
  try
    Dialog.Filter := 'Snippet libraries (*.json)|*.json|All files (*.*)|*.*';
    Dialog.DefaultExt := 'json';
    Dialog.FileName := CSnippetFileName;
    Dialog.Title := 'Export code snippets';
    if Dialog.Execute then
      try
        SaveSnippets(FSnippets.ToArray, Dialog.FileName,
          StringListToArray(FCategories));
        FStatusLabel.Caption := 'Exported snippets to ' + Dialog.FileName;
      except
        on E: Exception do
          ShowError('Could not export snippets: ' + E.Message);
      end;
  finally
    Dialog.Free;
  end;
end;

procedure RADECodeSnippets_ShowManager(const AInitialCode, ALocation: string;
  AOnSaved: TNotifyEvent);
var
  Manager: TRADESnippetManager;
begin
  if GSnippetManager <> nil then
  begin
    if not GSnippetManager.FClosedByUser then
    begin
      GSnippetManager.Show;
      GSnippetManager.BringToFront;
      Exit;
    end;
    FreeAndNil(GSnippetManager);
  end;
  Manager := TRADESnippetManager.Create(Application, AInitialCode, ALocation,
    AOnSaved);
  GSnippetManager := Manager;
  try
    Manager.Show;
  except
    GSnippetManager := nil;
    Manager.Free;
    raise;
  end;
end;

procedure RADECodeSnippets_Shutdown;
var
  Manager: TRADESnippetManager;
begin
  Manager := GSnippetManager;
  GSnippetManager := nil;
  if Manager <> nil then
    Manager.Free;
end;

initialization

finalization
  RADECodeSnippets_Shutdown;

end.
