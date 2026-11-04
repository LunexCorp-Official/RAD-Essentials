unit RADE.PDFViewer;

{ Self-contained: no .dfm needed. Drop this file and RADE.PDFium.pas into the
  package and call TRADEPDFViewerEditorHost.ShowViewer from your menu item.

  Layout (top to bottom):
    tab strip   - document tabs with close buttons, "+" opens a PDF
                  (right-click "+" = recent files)
    toolbar     - thumbnails toggle, prev/next, page box "/ N" ...... zoom out,
                  zoom pill (click = presets), zoom in, fit width
    content     - thumbnail strip | PDF view
    status bar  - "Page 3 of 24 | 100%"

  Icons are drawn with GDI (supersampled), so no icon font is needed. }

interface

uses
  Winapi.Windows, Winapi.Messages, Winapi.UxTheme, System.SysUtils,
  System.Classes, System.Types, System.IOUtils, System.Math,
  System.Generics.Collections, Vcl.Graphics, Vcl.Controls, Vcl.Forms,
  Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Menus, ToolsAPI, RADE.PDFium;

type
  TRADEIcon = (icThumbs, icPrev, icNext, icZoomOut, icZoomIn, icFitWidth,
    icClose, icPlus);

  TRADETabEvent = procedure(Sender: TObject; AIndex: Integer) of object;
  TRADEPageEvent = procedure(Sender: TObject; APage: Integer) of object;

  { Flat, hover-aware icon button. }
  TRADEIconButton = class(TGraphicControl)
  private
    FKind: TRADEIcon;
    FActive, FHot, FDown: Boolean;
    FBack: TColor;
    procedure SetKind(AValue: TRADEIcon);
    procedure SetActive(AValue: Boolean);
    procedure CMMouseEnter(var Msg: TMessage); message CM_MOUSEENTER;
    procedure CMMouseLeave(var Msg: TMessage); message CM_MOUSELEAVE;
    procedure CMEnabledChanged(var Msg: TMessage); message CM_ENABLEDCHANGED;
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    property Kind: TRADEIcon read FKind write SetKind;
    { Blue "toggled on" state (fit width, thumbnails shown). }
    property Active: Boolean read FActive write SetActive;
    property OnClick;
  end;

  { Edit with centred text and no border. }
  TRADECenterEdit = class(TEdit)
  protected
    procedure CreateParams(var Params: TCreateParams); override;
  end;

  { Rounded box: either an editable number box or a clickable text pill. }
  TRADEPill = class(TCustomControl)
  private
    FEdit: TRADECenterEdit;
    FText: string;
    FHot, FFocused: Boolean;
    FOnEditExit: TNotifyEvent;
    function GetPillText: string;
    procedure SetPillText(const AValue: string);
    procedure UpdateEditBounds;
    procedure EditFocusEnter(Sender: TObject);
    procedure EditFocusExit(Sender: TObject);
    procedure CMMouseEnter(var Msg: TMessage); message CM_MOUSEENTER;
    procedure CMMouseLeave(var Msg: TMessage); message CM_MOUSELEAVE;
  protected
    procedure Paint; override;
    procedure Resize; override;
  public
    constructor Create(AOwner: TComponent; AEditable: Boolean); reintroduce;
    property Edit: TRADECenterEdit read FEdit;
    property Text: string read GetPillText write SetPillText;
    property OnEditExit: TNotifyEvent read FOnEditExit write FOnEditExit;
    property OnClick;
  end;

  TRADETabItem = record
    Caption, Hint: string;
    Data: TObject;
  end;

  { Document tab strip with an accent line on the active tab. }
  TRADETabBar = class(TCustomControl)
  private
    FTabs: TList<TRADETabItem>;
    FActive, FHotTab: Integer;
    FHotClose, FHotPlus, FPlusDown: Boolean;
    FOnActivate: TNotifyEvent;
    FOnCloseTab: TRADETabEvent;
    FOnAddClick: TNotifyEvent;
    FOnAddMenu: TNotifyEvent;
    function GetCount: Integer;
    procedure SetActiveIndex(AValue: Integer);
    procedure CalcWidths(out AWidths: TArray<Integer>);
    function CloseRectOf(const ATab: TRect): TRect;
    function PlusRectAt(ALeft: Integer): TRect;
    function HitTest(X, Y: Integer; out AClose, APlus: Boolean): Integer;
    procedure UpdateHot(X, Y: Integer);
    procedure CMMouseLeave(var Msg: TMessage); message CM_MOUSELEAVE;
  protected
    procedure Paint; override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function AddTab(const ACaption, AHint: string; AData: TObject): Integer;
    procedure RemoveTab(AIndex: Integer);
    function TabData(AIndex: Integer): TObject;
    function TabHint(AIndex: Integer): string;
    property Count: Integer read GetCount;
    { Setting this does not fire OnActivate; only user clicks do. }
    property ActiveIndex: Integer read FActive write SetActiveIndex;
    property OnActivate: TNotifyEvent read FOnActivate write FOnActivate;
    property OnCloseTab: TRADETabEvent read FOnCloseTab write FOnCloseTab;
    property OnAddClick: TNotifyEvent read FOnAddClick write FOnAddClick;
    property OnAddMenu: TNotifyEvent read FOnAddMenu write FOnAddMenu;
  end;

  { Scrollable page thumbnails; rendered lazily when they scroll into view. }
  TRADEThumbStrip = class(TCustomControl)
  private
    FView: TRADEPdfView;
    FTops, FThumbW, FThumbH: TArray<Integer>;
    FTotalH, FPos, FSelected, FLabelH: Integer;
    FCache: TObjectDictionary<Integer, TBitmap>;
    FOnPageClick: TRADEPageEvent;
    function BoxW: Integer;
    function BoxH: Integer;
    function CellHeight(I: Integer): Integer;
    function GetThumb(I: Integer): TBitmap;
    procedure Relayout;
    procedure UpdateScrollBar;
    procedure SetPos(AValue: Integer);
    procedure EnsureVisible(AIndex: Integer);
    procedure WMVScroll(var Msg: TWMVScroll); message WM_VSCROLL;
    procedure WMEraseBkgnd(var Msg: TMessage); message WM_ERASEBKGND;
  protected
    procedure CreateParams(var Params: TCreateParams); override;
    procedure CreateWnd; override;
    procedure Paint; override;
    procedure Resize; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure SetView(AView: TRADEPdfView);
    { 1-based page number; 0 = none. }
    procedure SetSelected(APage: Integer);
    property OnPageClick: TRADEPageEvent read FOnPageClick write FOnPageClick;
  end;

  TRADEPDFViewerFrame = class(TPanel)
  private
    TabBar: TRADETabBar;
    PanelToolbar, PanelContent, PanelPages, PanelWelcome, PanelStatus,
      PanelThumbLine: TPanel;
    Strip: TRADEThumbStrip;
    BtnThumbs, BtnPrev, BtnNext, BtnZoomOut, BtnZoomIn,
      BtnFit: TRADEIconButton;
    PageBox, ZoomPill, BtnWelcomeOpen: TRADEPill;
    LblTotal, LblStatus, LblWelcome, LblWelcomeSub: TLabel;
    FRecentLabels: TObjectList<TLabel>;
    FRecentFiles: TStringList;
    FRecentMenu, FZoomMenu: TPopupMenu;
    function MakePanel(AParent: TWinControl; AAlign: TAlign;
      AColor: TColor): TPanel;
    function MakeLine(AParent: TWinControl; AAlign: TAlign): TPanel;
    function MakeButton(AKind: TRADEIcon; const AHint: string;
      AOnClick: TNotifyEvent): TRADEIconButton;
    function MakeLabel(AParent: TWinControl; ASize: Integer;
      AColor: TColor): TLabel;
    function GetActiveView: TRADEPdfView;
    function FindTab(const APath: string): Integer;
    function GetRecentListPath: string;
    procedure LoadRecentList;
    procedure AddToRecentList(const AFileName: string);
    procedure RefreshRecentLinks;
    procedure SwitchToActive;
    procedure UpdateUI;
    procedure SetStatus(const AText: string);
    procedure ArrangeToolbar;
    procedure ArrangeWelcome;
    procedure ToolbarResize(Sender: TObject);
    procedure WelcomeResize(Sender: TObject);
    procedure BtnOpenPDFClick(Sender: TObject);
    procedure ShowRecentMenu(Sender: TObject);
    procedure RecentMenuClick(Sender: TObject);
    procedure RecentLabelClick(Sender: TObject);
    procedure RecentLabelEnter(Sender: TObject);
    procedure RecentLabelLeave(Sender: TObject);
    procedure TabActivated(Sender: TObject);
    procedure TabCloseRequest(Sender: TObject; AIndex: Integer);
    procedure BtnPrevClick(Sender: TObject);
    procedure BtnNextClick(Sender: TObject);
    procedure PageBoxKeyDown(Sender: TObject; var Key: Word;
      Shift: TShiftState);
    procedure PageBoxKeyPress(Sender: TObject; var Key: Char);
    procedure PageBoxExit(Sender: TObject);
    procedure StripPageClick(Sender: TObject; APage: Integer);
    procedure ThumbsToggleClick(Sender: TObject);
    procedure ZoomOutClick(Sender: TObject);
    procedure ZoomInClick(Sender: TObject);
    procedure FitWidthClick(Sender: TObject);
    procedure ZoomPillClick(Sender: TObject);
    procedure ZoomMenuItemClick(Sender: TObject);
    procedure ViewZoomChanged(Sender: TObject);
    procedure ViewPageChanged(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure InitializeViewer;
    procedure ShutdownViewer;
    procedure OpenPDFFile(const AFileName: string);
  end;

  TRADEPDFViewerEditorHost = class
  public
    { Toggles a PDF panel on the right half of the active editor window. }
    class procedure ShowViewer;
  end;

implementation

const
  PanelName = 'RADEPdfDockPanel';

  { Colours sampled from the design (TColor is BGR). }
  clBarBack = TColor($00151515);   { #151515 tab strip, thumbs, status }
  clToolBack = TColor($00191A1A);  { #1A1A19 toolbar / active tab }
  clViewBack = TColor($000B0B0B);  { #0B0B0B page area }
  clDivider = TColor($00303031);   { #313130 }
  clDividerSoft = TColor($002C2C2C);
  clAccent = TColor($00D6782A);    { #2A78D6 }
  clAccentText = TColor($00EEA56A);
  clTextAct = TColor($00E8E8E8);
  clTextDim = TColor($00A8A8A8);
  clTextHot = TColor($00D0D0D0);
  clIcon = TColor($00C8C8C8);
  clIconHot = TColor($00FFFFFF);
  clIconOff = TColor($00606060);
  clHover = TColor($002B2B2B);
  clPress = TColor($00383838);
  clTabHot = TColor($001B1B1B);
  clPillBack = TColor($001F1F1F);
  clPillLine = TColor($00474747);  { #474747 }

{ ---- helpers ------------------------------------------------------------ }

function Scl(AValue: Integer): Integer;
begin
  Result := MulDiv(AValue, Screen.PixelsPerInch, 96);
end;

procedure DrawGlyph(C: TCanvas; AKind: TRADEIcon; U, OX, OY: Double;
  AColor: TColor);

  function Pt(X, Y: Double): TPoint;
  begin
    Result := Point(Round(OX + X * U), Round(OY + Y * U));
  end;

  procedure Ln(X1, Y1, X2, Y2: Double);
  begin
    C.MoveTo(Pt(X1, Y1).X, Pt(X1, Y1).Y);
    C.LineTo(Pt(X2, Y2).X, Pt(X2, Y2).Y);
  end;

begin
  C.Pen.Style := psSolid;
  C.Pen.Color := AColor;
  C.Pen.Width := Max(1, Round(1.7 * U));
  C.Brush.Style := bsClear;
  { Everything is drawn on a 28x28 grid. }
  case AKind of
    icPrev: C.Polyline([Pt(16, 8), Pt(10, 14), Pt(16, 20)]);
    icNext: C.Polyline([Pt(12, 8), Pt(18, 14), Pt(12, 20)]);
    icZoomOut: Ln(8, 14, 20, 14);
    icZoomIn, icPlus:
      begin
        Ln(8, 14, 20, 14);
        Ln(14, 8, 14, 20);
      end;
    icClose:
      begin
        Ln(9, 9, 19, 19);
        Ln(19, 9, 9, 19);
      end;
    icThumbs:
      begin
        C.RoundRect(Pt(6, 8).X, Pt(6, 8).Y, Pt(22, 20).X, Pt(22, 20).Y,
          Round(3 * U), Round(3 * U));
        Ln(12, 8, 12, 20);
      end;
    icFitWidth:
      begin
        Ln(6, 8, 6, 20);
        Ln(22, 8, 22, 20);
        Ln(9, 14, 19, 14);
        C.Polyline([Pt(12, 11), Pt(9, 14), Pt(12, 17)]);
        C.Polyline([Pt(16, 11), Pt(19, 14), Pt(16, 17)]);
      end;
  end;
end;

{ Renders the icon at 4x into a temp bitmap and halftone-shrinks it onto the
  target, which gives smooth edges without GDI+. AHotBack = clNone: no
  hover plate. }
procedure PaintIcon(ADest: TCanvas; const R: TRect; AKind: TRADEIcon;
  ABack, AFore, AHotBack: TColor);
const
  SS = 4;
var
  B: TBitmap;
  W, H: Integer;
  U: Double;
begin
  W := R.Right - R.Left;
  H := R.Bottom - R.Top;
  if (W <= 0) or (H <= 0) then
    Exit;
  B := TBitmap.Create;
  try
    B.PixelFormat := pf24bit;
    B.SetSize(W * SS, H * SS);
    B.Canvas.Brush.Style := bsSolid;
    B.Canvas.Brush.Color := ABack;
    B.Canvas.FillRect(Rect(0, 0, B.Width, B.Height));
    if AHotBack <> clNone then
    begin
      B.Canvas.Brush.Color := AHotBack;
      B.Canvas.Pen.Style := psClear;
      B.Canvas.RoundRect(0, 0, B.Width, B.Height, Scl(6) * SS, Scl(6) * SS);
    end;
    U := Min(W, H) * SS / 28;
    DrawGlyph(B.Canvas, AKind, U, (B.Width - 28 * U) / 2,
      (B.Height - 28 * U) / 2, AFore);
    SetStretchBltMode(ADest.Handle, HALFTONE);
    SetBrushOrgEx(ADest.Handle, 0, 0, nil);
    StretchBlt(ADest.Handle, R.Left, R.Top, W, H, B.Canvas.Handle, 0, 0,
      B.Width, B.Height, SRCCOPY);
  finally
    B.Free;
  end;
end;

{ ---- TRADEIconButton ---------------------------------------------------- }

constructor TRADEIconButton.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FBack := clToolBack;
  Width := Scl(28);
  Height := Scl(28);
  ShowHint := True;
end;

procedure TRADEIconButton.SetKind(AValue: TRADEIcon);
begin
  if FKind <> AValue then
  begin
    FKind := AValue;
    Invalidate;
  end;
end;

procedure TRADEIconButton.SetActive(AValue: Boolean);
begin
  if FActive <> AValue then
  begin
    FActive := AValue;
    Invalidate;
  end;
end;

procedure TRADEIconButton.CMMouseEnter(var Msg: TMessage);
begin
  inherited;
  FHot := True;
  Invalidate;
end;

procedure TRADEIconButton.CMMouseLeave(var Msg: TMessage);
begin
  inherited;
  FHot := False;
  FDown := False;
  Invalidate;
end;

procedure TRADEIconButton.CMEnabledChanged(var Msg: TMessage);
begin
  inherited;
  Invalidate;
end;

procedure TRADEIconButton.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  inherited;
  if Button = mbLeft then
  begin
    FDown := True;
    Invalidate;
  end;
end;

procedure TRADEIconButton.MouseUp(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  inherited;
  FDown := False;
  Invalidate;
end;

procedure TRADEIconButton.Paint;
var
  Fore, Plate: TColor;
begin
  Plate := clNone;
  if not Enabled then
    Fore := clIconOff
  else if FActive then
    Fore := clAccent
  else
    Fore := clIcon;
  if Enabled then
  begin
    if FDown then
      Plate := clPress
    else if FHot then
    begin
      Plate := clHover;
      if not FActive then
        Fore := clIconHot;
    end;
  end;
  PaintIcon(Canvas, ClientRect, FKind, FBack, Fore, Plate);
end;

{ ---- TRADECenterEdit / TRADEPill ---------------------------------------- }

procedure TRADECenterEdit.CreateParams(var Params: TCreateParams);
begin
  inherited;
  Params.Style := Params.Style or ES_CENTER;
end;

constructor TRADEPill.Create(AOwner: TComponent; AEditable: Boolean);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  StyleElements := [];
  Width := Scl(44);
  Height := Scl(26);
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  Font.Color := clTextAct;
  if AEditable then
  begin
    FEdit := TRADECenterEdit.Create(Self);
    FEdit.Parent := Self;
    FEdit.BorderStyle := bsNone;
    FEdit.AutoSize := False;
    FEdit.StyleElements := [];
    FEdit.ParentFont := False;
    FEdit.Font.Name := 'Segoe UI';
    FEdit.Font.Size := 9;
    FEdit.Font.Color := clTextAct;
    FEdit.ParentColor := False;
    FEdit.Color := clPillBack;
    FEdit.OnEnter := EditFocusEnter;
    FEdit.OnExit := EditFocusExit;
  end
  else
    Cursor := crHandPoint;
end;

function TRADEPill.GetPillText: string;
begin
  if FEdit <> nil then
    Result := FEdit.Text
  else
    Result := FText;
end;

procedure TRADEPill.SetPillText(const AValue: string);
begin
  if FEdit <> nil then
    FEdit.Text := AValue
  else if FText <> AValue then
  begin
    FText := AValue;
    Invalidate;
  end;
end;

procedure TRADEPill.UpdateEditBounds;
var
  H: Integer;
begin
  if FEdit = nil then
    Exit;
  H := Max(1, Round(Abs(FEdit.Font.Height) * 1.35));
  FEdit.SetBounds(Scl(4), (Height - H) div 2, Max(1, Width - Scl(8)), H);
end;

procedure TRADEPill.Resize;
begin
  inherited;
  UpdateEditBounds;
end;

procedure TRADEPill.EditFocusEnter(Sender: TObject);
begin
  FFocused := True;
  Invalidate;
end;

procedure TRADEPill.EditFocusExit(Sender: TObject);
begin
  FFocused := False;
  Invalidate;
  if Assigned(FOnEditExit) then
    FOnEditExit(Self);
end;

procedure TRADEPill.CMMouseEnter(var Msg: TMessage);
begin
  inherited;
  FHot := True;
  Invalidate;
end;

procedure TRADEPill.CMMouseLeave(var Msg: TMessage);
begin
  inherited;
  FHot := False;
  Invalidate;
end;

procedure TRADEPill.Paint;
var
  R: TRect;
begin
  Canvas.Brush.Style := bsSolid;
  if Parent is TPanel then
    Canvas.Brush.Color := TPanel(Parent).Color
  else
    Canvas.Brush.Color := clToolBack;
  Canvas.FillRect(ClientRect);
  if FHot or FFocused then
    Canvas.Pen.Color := clAccent
  else
    Canvas.Pen.Color := clPillLine;
  Canvas.Pen.Width := 1;
  Canvas.Pen.Style := psSolid;
  Canvas.Brush.Color := clPillBack;
  Canvas.RoundRect(0, 0, Width, Height, Scl(10), Scl(10));
  if FEdit = nil then
  begin
    Canvas.Brush.Style := bsClear;
    Canvas.Font.Assign(Font);
    R := ClientRect;
    DrawText(Canvas.Handle, PChar(FText), Length(FText), R,
      DT_SINGLELINE or DT_CENTER or DT_VCENTER or DT_NOPREFIX);
  end;
end;

{ ---- TRADETabBar -------------------------------------------------------- }

constructor TRADETabBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  DoubleBuffered := True;
  StyleElements := [];
  FTabs := TList<TRADETabItem>.Create;
  FActive := -1;
  FHotTab := -1;
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  Height := Scl(38);
  ShowHint := True;
end;

destructor TRADETabBar.Destroy;
begin
  FTabs.Free;
  inherited;
end;

function TRADETabBar.GetCount: Integer;
begin
  Result := FTabs.Count;
end;

procedure TRADETabBar.SetActiveIndex(AValue: Integer);
begin
  if AValue >= FTabs.Count then
    AValue := FTabs.Count - 1;
  if FActive <> AValue then
  begin
    FActive := AValue;
    Invalidate;
  end;
end;

function TRADETabBar.AddTab(const ACaption, AHint: string;
  AData: TObject): Integer;
var
  Item: TRADETabItem;
begin
  Item.Caption := ACaption;
  Item.Hint := AHint;
  Item.Data := AData;
  Result := FTabs.Add(Item);
  Invalidate;
end;

procedure TRADETabBar.RemoveTab(AIndex: Integer);
begin
  if (AIndex < 0) or (AIndex >= FTabs.Count) then
    Exit;
  FTabs.Delete(AIndex);
  if FActive > AIndex then
    Dec(FActive)
  else if FActive = AIndex then
    FActive := Min(AIndex, FTabs.Count - 1);
  FHotTab := -1;
  FHotClose := False;
  Invalidate;
end;

function TRADETabBar.TabData(AIndex: Integer): TObject;
begin
  if (AIndex >= 0) and (AIndex < FTabs.Count) then
    Result := FTabs[AIndex].Data
  else
    Result := nil;
end;

function TRADETabBar.TabHint(AIndex: Integer): string;
begin
  if (AIndex >= 0) and (AIndex < FTabs.Count) then
    Result := FTabs[AIndex].Hint
  else
    Result := '';
end;

procedure TRADETabBar.CalcWidths(out AWidths: TArray<Integer>);
var
  I, Total, Avail: Integer;
begin
  SetLength(AWidths, FTabs.Count);
  Canvas.Font.Assign(Font);
  Total := 0;
  for I := 0 to High(AWidths) do
  begin
    AWidths[I] := EnsureRange(Canvas.TextWidth(FTabs[I].Caption) + Scl(56),
      Scl(110), Scl(240));
    Inc(Total, AWidths[I]);
  end;
  Avail := ClientWidth - Scl(40); { room for the "+" }
  if (Total > Avail) and (Total > 0) then
    for I := 0 to High(AWidths) do
      AWidths[I] := Max(Scl(64), MulDiv(AWidths[I], Max(Avail, 1), Total));
end;

function TRADETabBar.CloseRectOf(const ATab: TRect): TRect;
var
  S: Integer;
begin
  S := Scl(18);
  Result.Right := ATab.Right - Scl(12);
  Result.Left := Result.Right - S;
  Result.Top := (ATab.Bottom - ATab.Top - S) div 2;
  Result.Bottom := Result.Top + S;
end;

function TRADETabBar.PlusRectAt(ALeft: Integer): TRect;
var
  S: Integer;
begin
  S := Scl(28);
  Result.Left := ALeft + Scl(6);
  Result.Right := Result.Left + S;
  Result.Top := (Height - S) div 2;
  Result.Bottom := Result.Top + S;
end;

function TRADETabBar.HitTest(X, Y: Integer; out AClose,
  APlus: Boolean): Integer;
var
  W: TArray<Integer>;
  I, L: Integer;
  R: TRect;
begin
  Result := -1;
  AClose := False;
  APlus := False;
  CalcWidths(W);
  L := 0;
  for I := 0 to High(W) do
  begin
    R := Rect(L, 0, L + W[I], Height);
    if PtInRect(R, Point(X, Y)) then
    begin
      AClose := PtInRect(CloseRectOf(R), Point(X, Y));
      Exit(I);
    end;
    Inc(L, W[I]);
  end;
  APlus := PtInRect(PlusRectAt(L), Point(X, Y));
end;

procedure TRADETabBar.UpdateHot(X, Y: Integer);
var
  I: Integer;
  C, P: Boolean;
begin
  I := HitTest(X, Y, C, P);
  if (I <> FHotTab) or (C <> FHotClose) or (P <> FHotPlus) then
  begin
    FHotTab := I;
    FHotClose := C;
    FHotPlus := P;
    if I >= 0 then
      Hint := FTabs[I].Hint
    else
      Hint := '';
    Invalidate;
  end;
end;

procedure TRADETabBar.CMMouseLeave(var Msg: TMessage);
begin
  inherited;
  FHotTab := -1;
  FHotClose := False;
  FHotPlus := False;
  Invalidate;
end;

procedure TRADETabBar.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  inherited;
  UpdateHot(X, Y);
end;

procedure TRADETabBar.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  I: Integer;
  C, P: Boolean;
begin
  inherited;
  I := HitTest(X, Y, C, P);
  if P then
  begin
    FPlusDown := True;
    Exit;
  end;
  if I < 0 then
    Exit;
  if (Button = mbMiddle) or ((Button = mbLeft) and C) then
  begin
    if Assigned(FOnCloseTab) then
      FOnCloseTab(Self, I);
    Exit; { the tab list changed; touch nothing else }
  end;
  if (Button = mbLeft) and (I <> FActive) then
  begin
    FActive := I;
    Invalidate;
    if Assigned(FOnActivate) then
      FOnActivate(Self);
  end;
end;

procedure TRADETabBar.MouseUp(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  C, P: Boolean;
begin
  inherited;
  if not FPlusDown then
    Exit;
  FPlusDown := False;
  HitTest(X, Y, C, P);
  if not P then
    Exit;
  case Button of
    mbLeft:
      if Assigned(FOnAddClick) then
        FOnAddClick(Self);
    mbRight:
      if Assigned(FOnAddMenu) then
        FOnAddMenu(Self);
  end;
end;

procedure TRADETabBar.Paint;
var
  W: TArray<Integer>;
  I, X: Integer;
  R, CR, TR: TRect;
  IsAct, IsHot: Boolean;
  Back, CloseFore, CloseHot: TColor;
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := clBarBack;
  Canvas.FillRect(ClientRect);
  Canvas.Pen.Style := psSolid;
  Canvas.Pen.Width := 1;
  Canvas.Pen.Color := clDivider;
  Canvas.MoveTo(0, Height - 1);
  Canvas.LineTo(Width, Height - 1);
  Canvas.Font.Assign(Font);
  CalcWidths(W);
  X := 0;
  for I := 0 to High(W) do
  begin
    R := Rect(X, 0, X + W[I], Height);
    IsAct := I = FActive;
    IsHot := I = FHotTab;
    Back := clBarBack;
    Canvas.Brush.Style := bsSolid;
    if IsAct then
    begin
      Back := clToolBack;
      Canvas.Brush.Color := Back;
      Canvas.FillRect(R);
      Canvas.Brush.Color := clAccent;
      Canvas.FillRect(Rect(R.Left, 0, R.Right - 1, Scl(2)));
    end
    else if IsHot then
    begin
      Back := clTabHot;
      Canvas.Brush.Color := Back;
      Canvas.FillRect(Rect(R.Left, 0, R.Right, Height - 1));
    end;
    Canvas.Pen.Color := clDivider;
    Canvas.MoveTo(R.Right - 1, 0);
    Canvas.LineTo(R.Right - 1, Height);

    CR := CloseRectOf(R);
    TR := Rect(R.Left + Scl(16), 0, CR.Left - Scl(6), Height);
    Canvas.Brush.Style := bsClear;
    if IsAct then
      Canvas.Font.Color := clTextAct
    else if IsHot then
      Canvas.Font.Color := clTextHot
    else
      Canvas.Font.Color := clTextDim;
    DrawText(Canvas.Handle, PChar(FTabs[I].Caption),
      Length(FTabs[I].Caption), TR,
      DT_SINGLELINE or DT_VCENTER or DT_END_ELLIPSIS or DT_NOPREFIX);

    CloseHot := clNone;
    if IsAct or IsHot then
      CloseFore := clIcon
    else
      CloseFore := clIconOff;
    if IsHot and FHotClose then
    begin
      CloseHot := clHover;
      CloseFore := clIconHot;
    end;
    PaintIcon(Canvas, CR, icClose, Back, CloseFore, CloseHot);
    Inc(X, W[I]);
  end;
  CR := PlusRectAt(X);
  if FHotPlus then
    PaintIcon(Canvas, CR, icPlus, clBarBack, clIconHot, clHover)
  else
    PaintIcon(Canvas, CR, icPlus, clBarBack, clIcon, clNone);
end;

{ ---- TRADEThumbStrip ---------------------------------------------------- }

constructor TRADEThumbStrip.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  DoubleBuffered := True;
  StyleElements := [];
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  FSelected := -1;
  FCache := TObjectDictionary<Integer, TBitmap>.Create([doOwnsValues]);
  Width := Scl(108);
end;

destructor TRADEThumbStrip.Destroy;
begin
  FCache.Free;
  inherited;
end;

procedure TRADEThumbStrip.CreateParams(var Params: TCreateParams);
begin
  inherited;
  Params.Style := Params.Style or WS_VSCROLL;
end;

procedure TRADEThumbStrip.CreateWnd;
begin
  inherited;
  SetWindowTheme(Handle, 'DarkMode_Explorer', nil); { dark scrollbar }
end;

procedure TRADEThumbStrip.WMEraseBkgnd(var Msg: TMessage);
begin
  Msg.Result := 1;
end;

function TRADEThumbStrip.BoxW: Integer;
begin
  Result := Scl(72);
end;

function TRADEThumbStrip.BoxH: Integer;
begin
  Result := Scl(100);
end;

function TRADEThumbStrip.CellHeight(I: Integer): Integer;
begin
  Result := Scl(10) + FThumbH[I] + Scl(4) + FLabelH + Scl(8);
end;

function TRADEThumbStrip.GetThumb(I: Integer): TBitmap;
begin
  if FCache.TryGetValue(I, Result) then
    Exit;
  if FCache.Count > 200 then
    FCache.Clear;
  Result := TBitmap.Create;
  try
    FView.RenderThumbnail(I, BoxW, BoxH, Result);
  except
    FreeAndNil(Result); { never let a render error escape into paint }
    Exit;
  end;
  FCache.Add(I, Result);
end;

procedure TRADEThumbStrip.SetView(AView: TRADEPdfView);
begin
  if AView = FView then
    Exit;
  FView := AView;
  FCache.Clear;
  FPos := 0;
  FSelected := -1;
  Relayout;
end;

procedure TRADEThumbStrip.Relayout;
var
  I, Y, N: Integer;
  S: TSizeF;
  K: Double;
begin
  Canvas.Font.Assign(Font);
  FLabelH := Canvas.TextHeight('0');
  FTops := nil;
  FThumbW := nil;
  FThumbH := nil;
  FTotalH := 0;
  if FView <> nil then
  begin
    N := FView.PageCount;
    SetLength(FTops, N);
    SetLength(FThumbW, N);
    SetLength(FThumbH, N);
    Y := 0;
    for I := 0 to N - 1 do
    begin
      S := FView.PageSizePts(I);
      K := Min(BoxW / S.cx, BoxH / S.cy);
      FThumbW[I] := Max(8, Round(S.cx * K));
      FThumbH[I] := Max(8, Round(S.cy * K));
      FTops[I] := Y;
      Inc(Y, CellHeight(I));
    end;
    FTotalH := Y;
  end;
  SetPos(FPos);
  Invalidate;
end;

procedure TRADEThumbStrip.UpdateScrollBar;
var
  SI: TScrollInfo;
begin
  if not HandleAllocated then
    Exit;
  SI.cbSize := SizeOf(SI);
  SI.fMask := SIF_RANGE or SIF_PAGE or SIF_POS;
  SI.nMin := 0;
  SI.nMax := Max(FTotalH - 1, 0);
  SI.nPage := ClientHeight;
  SI.nPos := FPos;
  SetScrollInfo(Handle, SB_VERT, SI, True);
end;

procedure TRADEThumbStrip.SetPos(AValue: Integer);
begin
  FPos := Max(0, Min(AValue, FTotalH - ClientHeight));
  UpdateScrollBar;
  Invalidate;
end;

procedure TRADEThumbStrip.Resize;
begin
  inherited;
  SetPos(FPos);
end;

procedure TRADEThumbStrip.EnsureVisible(AIndex: Integer);
var
  Top, Bottom: Integer;
begin
  if (AIndex < 0) or (AIndex >= Length(FTops)) then
    Exit;
  Top := FTops[AIndex];
  Bottom := Top + CellHeight(AIndex);
  if Top < FPos then
    SetPos(Top)
  else if Bottom > FPos + ClientHeight then
    SetPos(Bottom - ClientHeight);
end;

procedure TRADEThumbStrip.SetSelected(APage: Integer);
begin
  if APage - 1 = FSelected then
    Exit;
  FSelected := APage - 1;
  EnsureVisible(FSelected);
  Invalidate;
end;

procedure TRADEThumbStrip.WMVScroll(var Msg: TWMVScroll);
var
  SI: TScrollInfo;
begin
  SI.cbSize := SizeOf(SI);
  SI.fMask := SIF_ALL;
  GetScrollInfo(Handle, SB_VERT, SI);
  case Msg.ScrollCode of
    SB_LINEUP: SetPos(FPos - 40);
    SB_LINEDOWN: SetPos(FPos + 40);
    SB_PAGEUP: SetPos(FPos - ClientHeight + 40);
    SB_PAGEDOWN: SetPos(FPos + ClientHeight - 40);
    SB_THUMBTRACK, SB_THUMBPOSITION: SetPos(SI.nTrackPos);
    SB_TOP: SetPos(0);
    SB_BOTTOM: SetPos(FTotalH);
  end;
end;

function TRADEThumbStrip.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint): Boolean;
begin
  SetPos(FPos - WheelDelta div 2);
  Result := True;
end;

procedure TRADEThumbStrip.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  I: Integer;
begin
  inherited;
  if Button <> mbLeft then
    Exit;
  for I := 0 to High(FTops) do
    if (Y + FPos >= FTops[I]) and (Y + FPos < FTops[I] + CellHeight(I)) then
    begin
      if Assigned(FOnPageClick) then
        FOnPageClick(Self, I + 1);
      Exit;
    end;
end;

procedure TRADEThumbStrip.Paint;
var
  I, Y, X, W, H, K: Integer;
  Bmp: TBitmap;
  R: TRect;
  Num: string;
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := clBarBack;
  Canvas.FillRect(ClientRect);
  if FView = nil then
    Exit;
  Canvas.Font.Assign(Font);
  for I := 0 to High(FTops) do
  begin
    Y := FTops[I] - FPos;
    if Y + CellHeight(I) < 0 then
      Continue;
    if Y > ClientHeight then
      Break;
    Y := Y + Scl(10);
    W := FThumbW[I];
    H := FThumbH[I];
    X := (ClientWidth - W) div 2;
    Bmp := GetThumb(I);
    if Bmp <> nil then
    begin
      W := Bmp.Width;
      H := Bmp.Height;
      X := (ClientWidth - W) div 2;
      Canvas.Draw(X, Y, Bmp);
    end
    else
    begin
      Canvas.Brush.Color := clWhite;
      Canvas.FillRect(Rect(X, Y, X + W, Y + H));
    end;
    if I = FSelected then
    begin
      Canvas.Brush.Color := clAccent;
      for K := 1 to Max(2, Scl(2)) do
        Canvas.FrameRect(Rect(X - K, Y - K, X + W + K, Y + H + K));
    end
    else
    begin
      Canvas.Brush.Color := clDividerSoft;
      Canvas.FrameRect(Rect(X - 1, Y - 1, X + W + 1, Y + H + 1));
    end;
    Canvas.Brush.Style := bsClear;
    if I = FSelected then
      Canvas.Font.Color := clAccentText
    else
      Canvas.Font.Color := clTextDim;
    Num := IntToStr(I + 1);
    R := Rect(0, Y + H + Scl(4), ClientWidth, Y + H + Scl(4) + FLabelH);
    DrawText(Canvas.Handle, PChar(Num), Length(Num), R,
      DT_SINGLELINE or DT_CENTER or DT_NOPREFIX);
    Canvas.Brush.Style := bsSolid;
  end;
end;

{ ---- TRADEPDFViewerEditorHost ------------------------------------------- }

class procedure TRADEPDFViewerEditorHost.ShowViewer;
var
  Svc: INTAEditorServices;
  Form: TCustomForm;
  FocusedControl: TWinControl;
  EditorHost: TWinControl;
  Panel: TPanel;
  Splitter: TSplitter;
  Frame: TRADEPDFViewerFrame;
begin
  if not Supports(BorlandIDEServices, INTAEditorServices, Svc) then
    Exit;
  if (Svc.TopEditWindow = nil) or (Svc.TopEditWindow.Form = nil) then
  begin
    MessageDlg('Open a source file first.', mtInformation, [mbOK], 0);
    Exit;
  end;
  Form := Svc.TopEditWindow.Form;

  { Already created for this editor window: just toggle it. }
  Panel := Form.FindComponent(PanelName) as TPanel;
  if Panel <> nil then
  begin
    Panel.Visible := not Panel.Visible;
    Splitter := Form.FindComponent(PanelName + 'Splitter') as TSplitter;
    if Splitter <> nil then
      Splitter.Visible := Panel.Visible;
    Exit;
  end;

  { The IDE may not update Form.ActiveControl for its embedded editor HWND. }
  FocusedControl := FindControl(GetFocus);
  if FocusedControl = nil then
    FocusedControl := Form.ActiveControl;
  if FocusedControl = nil then
  begin
    MessageDlg('Focus a source editor before opening the PDF viewer.',
      mtInformation, [mbOK], 0);
    Exit;
  end;
  EditorHost := FocusedControl.Parent;
  if EditorHost = nil then
  begin
    MessageDlg('Could not locate the source editor area.', mtInformation,
      [mbOK], 0);
    Exit;
  end;

  { Order matters: panel first, splitter second. Both alRight, so the
    splitter ends up on the left edge of the panel, between code and PDF. }
  Panel := TPanel.Create(Form);
  Panel.Name := PanelName;
  Panel.Caption := '';
  Panel.BevelOuter := bvNone;
  Panel.ParentBackground := False;
  Panel.Color := clBarBack;
  Panel.Parent := EditorHost;
  Panel.Align := alRight;
  Panel.Width := EditorHost.ClientWidth * 2 div 5;
  if Panel.Width > EditorHost.ClientWidth - 280 then
    Panel.Width := Max(220, EditorHost.ClientWidth - 280);
  if Panel.Width < 240 then
    Panel.Width := Min(240, EditorHost.ClientWidth div 2);

  Splitter := TSplitter.Create(Form);
  Splitter.Name := PanelName + 'Splitter';
  Splitter.Width := 6;
  Splitter.MinSize := 400;
  Splitter.AutoSnap := False;
  Splitter.ResizeStyle := rsUpdate;
  Splitter.Parent := EditorHost;
  Splitter.Align := alRight;
  Splitter.Left := Panel.Left - Splitter.Width;

  Frame := TRADEPDFViewerFrame.Create(Form);
  Frame.Parent := Panel;
  Frame.Align := alClient;
  Frame.InitializeViewer;
end;

{ ---- TRADEPDFViewerFrame ------------------------------------------------ }

constructor TRADEPDFViewerFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  BevelOuter := bvNone;
  Caption := '';
  ShowCaption := False;
  ParentBackground := False;
  StyleElements := [];
  Color := clBarBack;
end;

destructor TRADEPDFViewerFrame.Destroy;
begin
  FreeAndNil(FRecentLabels);
  FreeAndNil(FRecentFiles);
  inherited Destroy;
end;

procedure TRADEPDFViewerFrame.ShutdownViewer;
begin
  { Nothing to tear down: views are owned by this frame. }
end;

function TRADEPDFViewerFrame.MakePanel(AParent: TWinControl; AAlign: TAlign;
  AColor: TColor): TPanel;
begin
  Result := TPanel.Create(Self);
  Result.Parent := AParent;
  Result.BevelOuter := bvNone;
  Result.ShowCaption := False;
  Result.ParentBackground := False;
  Result.StyleElements := [];
  Result.Color := AColor;
  Result.Align := AAlign;
end;

{ 1 px separator. Left/Top are set high first so it lands after siblings. }
function TRADEPDFViewerFrame.MakeLine(AParent: TWinControl;
  AAlign: TAlign): TPanel;
begin
  Result := TPanel.Create(Self);
  Result.Parent := AParent;
  Result.BevelOuter := bvNone;
  Result.ShowCaption := False;
  Result.ParentBackground := False;
  Result.StyleElements := [];
  Result.Color := clDivider;
  if AAlign in [alLeft, alRight] then
    Result.Width := 1
  else
    Result.Height := 1;
  Result.Left := 10000;
  Result.Top := 10000;
  Result.Align := AAlign;
end;

function TRADEPDFViewerFrame.MakeButton(AKind: TRADEIcon; const AHint: string;
  AOnClick: TNotifyEvent): TRADEIconButton;
begin
  Result := TRADEIconButton.Create(Self);
  Result.Parent := PanelToolbar;
  Result.Kind := AKind;
  Result.Hint := AHint;
  Result.OnClick := AOnClick;
end;

function TRADEPDFViewerFrame.MakeLabel(AParent: TWinControl; ASize: Integer;
  AColor: TColor): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := AParent;
  Result.StyleElements := [];
  Result.Font.Name := 'Segoe UI';
  Result.Font.Size := ASize;
  Result.Font.Color := AColor;
end;

function TRADEPDFViewerFrame.GetRecentListPath: string;
begin
  Result := TPath.Combine(TPath.Combine(TPath.GetHomePath, 'RadeEssentials'),
    'recent-pdfs.txt');
end;

procedure TRADEPDFViewerFrame.LoadRecentList;
var
  I: Integer;
begin
  FRecentFiles.Clear;
  if TFile.Exists(GetRecentListPath) then
    try
      FRecentFiles.LoadFromFile(GetRecentListPath, TEncoding.UTF8);
    except
      FRecentFiles.Clear;
    end;
  for I := FRecentFiles.Count - 1 downto 0 do
    if not TFile.Exists(FRecentFiles[I]) then
      FRecentFiles.Delete(I);
  RefreshRecentLinks;
end;

procedure TRADEPDFViewerFrame.AddToRecentList(const AFileName: string);
var
  LPath: string;
  LIndex: Integer;
begin
  LPath := TPath.GetFullPath(AFileName);
  LIndex := FRecentFiles.IndexOf(LPath);
  if LIndex >= 0 then
    FRecentFiles.Delete(LIndex);
  FRecentFiles.Insert(0, LPath);
  while FRecentFiles.Count > 15 do
    FRecentFiles.Delete(FRecentFiles.Count - 1);
  ForceDirectories(ExtractFileDir(GetRecentListPath));
  try
    FRecentFiles.SaveToFile(GetRecentListPath, TEncoding.UTF8);
  except
    { not worth interrupting the user for }
  end;
  RefreshRecentLinks;
end;

{ The welcome screen lists up to 5 recent files as links. }
procedure TRADEPDFViewerFrame.RefreshRecentLinks;
var
  I: Integer;
  L: TLabel;
begin
  if FRecentLabels = nil then
    Exit;
  FRecentLabels.Clear;
  for I := 0 to Min(4, FRecentFiles.Count - 1) do
  begin
    L := MakeLabel(PanelWelcome, 9, clAccentText);
    L.AutoSize := False;
    L.Alignment := taCenter;
    L.Layout := tlCenter;
    L.Height := Scl(22);
    L.Caption := ExtractFileName(FRecentFiles[I]);
    L.Hint := FRecentFiles[I];
    L.ShowHint := True;
    L.Cursor := crHandPoint;
    L.OnClick := RecentLabelClick;
    L.OnMouseEnter := RecentLabelEnter;
    L.OnMouseLeave := RecentLabelLeave;
    FRecentLabels.Add(L);
  end;
  ArrangeWelcome;
end;

procedure TRADEPDFViewerFrame.RecentLabelClick(Sender: TObject);
begin
  OpenPDFFile((Sender as TLabel).Hint);
end;

procedure TRADEPDFViewerFrame.RecentLabelEnter(Sender: TObject);
begin
  (Sender as TLabel).Font.Style := [fsUnderline];
end;

procedure TRADEPDFViewerFrame.RecentLabelLeave(Sender: TObject);
begin
  (Sender as TLabel).Font.Style := [];
end;

procedure TRADEPDFViewerFrame.ShowRecentMenu(Sender: TObject);
var
  I: Integer;
  Item: TMenuItem;
  P: TPoint;
begin
  FRecentMenu.Items.Clear;
  if FRecentFiles.Count = 0 then
  begin
    Item := TMenuItem.Create(FRecentMenu);
    Item.Caption := 'No recent files';
    Item.Enabled := False;
    FRecentMenu.Items.Add(Item);
  end
  else
    for I := 0 to FRecentFiles.Count - 1 do
    begin
      Item := TMenuItem.Create(FRecentMenu);
      Item.Caption := StringReplace(ExtractFileName(FRecentFiles[I]), '&',
        '&&', [rfReplaceAll]);
      Item.Hint := FRecentFiles[I];
      Item.Tag := I;
      Item.OnClick := RecentMenuClick;
      FRecentMenu.Items.Add(Item);
    end;
  P := Mouse.CursorPos;
  FRecentMenu.Popup(P.X, P.Y);
end;

procedure TRADEPDFViewerFrame.RecentMenuClick(Sender: TObject);
var
  Idx: Integer;
begin
  Idx := (Sender as TMenuItem).Tag;
  if (Idx >= 0) and (Idx < FRecentFiles.Count) then
    OpenPDFFile(FRecentFiles[Idx]);
end;

procedure TRADEPDFViewerFrame.BtnOpenPDFClick(Sender: TObject);
var
  LDialog: TOpenDialog;
  LFile: string;
begin
  LDialog := TOpenDialog.Create(Self);
  try
    LDialog.Title := 'Open PDF documents';
    LDialog.Filter := 'PDF documents (*.pdf)|*.pdf';
    LDialog.Options := [ofFileMustExist, ofPathMustExist, ofAllowMultiSelect];
    if LDialog.Execute then
      for LFile in LDialog.Files do
        OpenPDFFile(LFile);
  finally
    LDialog.Free;
  end;
end;

function TRADEPDFViewerFrame.FindTab(const APath: string): Integer;
var
  I: Integer;
begin
  for I := 0 to TabBar.Count - 1 do
    if SameText(TabBar.TabHint(I), APath) then
      Exit(I);
  Result := -1;
end;

function TRADEPDFViewerFrame.GetActiveView: TRADEPdfView;
begin
  Result := nil;
  if (TabBar <> nil) and (TabBar.ActiveIndex >= 0) then
    Result := TabBar.TabData(TabBar.ActiveIndex) as TRADEPdfView;
end;

procedure TRADEPDFViewerFrame.OpenPDFFile(const AFileName: string);
var
  I: Integer;
  LPath: string;
  LView: TRADEPdfView;
begin
  if not TFile.Exists(AFileName) then
  begin
    SetStatus('That PDF file can no longer be found.');
    Exit;
  end;
  LPath := TPath.GetFullPath(AFileName);
  I := FindTab(LPath);
  if I >= 0 then
  begin
    TabBar.ActiveIndex := I;
    SwitchToActive;
    AddToRecentList(LPath);
    Exit;
  end;

  LView := TRADEPdfView.Create(Self);
  try
    LView.Parent := PanelPages;
    LView.Align := alClient;
    LView.LoadFromFile(LPath);
  except
    on E: Exception do
    begin
      LView.Free;
      UpdateUI;
      SetStatus('Could not open PDF: ' + E.Message);
      Exit;
    end;
  end;
  LView.OnZoomChange := ViewZoomChanged;
  LView.OnPageChange := ViewPageChanged;
  TabBar.ActiveIndex := TabBar.AddTab(ExtractFileName(LPath), LPath, LView);
  SwitchToActive;
  AddToRecentList(LPath);
end;

{ Shows only the active tab's view and refreshes everything that depends on it. }
procedure TRADEPDFViewerFrame.SwitchToActive;
var
  I: Integer;
  V: TRADEPdfView;
begin
  for I := 0 to TabBar.Count - 1 do
    (TabBar.TabData(I) as TRADEPdfView).Visible := I = TabBar.ActiveIndex;
  V := GetActiveView;
  Strip.SetView(V);
  UpdateUI;
  if (V <> nil) and V.CanFocus then
    V.SetFocus;
end;

procedure TRADEPDFViewerFrame.TabActivated(Sender: TObject);
begin
  SwitchToActive;
end;

procedure TRADEPDFViewerFrame.TabCloseRequest(Sender: TObject;
  AIndex: Integer);
var
  V: TObject;
begin
  V := TabBar.TabData(AIndex);
  TabBar.RemoveTab(AIndex);
  SwitchToActive; { strip lets go of the old view before it is freed }
  V.Free;
end;

procedure TRADEPDFViewerFrame.SetStatus(const AText: string);
begin
  if LblStatus <> nil then
    LblStatus.Caption := AText;
end;

procedure TRADEPDFViewerFrame.UpdateUI;
var
  V: TRADEPdfView;
  Pg, Cnt: Integer;
begin
  V := GetActiveView;
  PanelWelcome.Visible := V = nil;
  if V <> nil then
  begin
    Pg := V.CurrentPage;
    Cnt := V.PageCount;
  end
  else
  begin
    Pg := 0;
    Cnt := 0;
  end;
  if not PageBox.Edit.Focused then
    if V <> nil then
      PageBox.Text := IntToStr(Pg)
    else
      PageBox.Text := '';
  PageBox.Edit.Enabled := V <> nil;
  LblTotal.Caption := '/ ' + IntToStr(Cnt);
  BtnPrev.Enabled := (V <> nil) and (Pg > 1);
  BtnNext.Enabled := (V <> nil) and (Pg < Cnt);
  BtnZoomOut.Enabled := V <> nil;
  BtnZoomIn.Enabled := V <> nil;
  BtnFit.Enabled := V <> nil;
  BtnFit.Active := (V <> nil) and V.FitWidthActive;
  if V <> nil then
  begin
    ZoomPill.Text := Format('%d%%', [Round(V.Zoom * 100)]);
    SetStatus(Format('Page %d of %d | %d%%', [Pg, Cnt, Round(V.Zoom * 100)]));
  end
  else
  begin
    ZoomPill.Text := '--%';
    SetStatus('Open a PDF to get started.');
  end;
  Strip.SetSelected(Pg);
end;

procedure TRADEPDFViewerFrame.ViewZoomChanged(Sender: TObject);
begin
  if Sender = GetActiveView then
    UpdateUI;
end;

procedure TRADEPDFViewerFrame.ViewPageChanged(Sender: TObject);
begin
  if Sender = GetActiveView then
    UpdateUI;
end;

procedure TRADEPDFViewerFrame.BtnPrevClick(Sender: TObject);
var
  V: TRADEPdfView;
begin
  V := GetActiveView;
  if V <> nil then
    V.GoToPage(V.CurrentPage - 1);
end;

procedure TRADEPDFViewerFrame.BtnNextClick(Sender: TObject);
var
  V: TRADEPdfView;
begin
  V := GetActiveView;
  if V <> nil then
    V.GoToPage(V.CurrentPage + 1);
end;

procedure TRADEPDFViewerFrame.PageBoxKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
var
  V: TRADEPdfView;
  LPage: Integer;
begin
  if (Key <> VK_RETURN) and (Key <> VK_ESCAPE) then
    Exit;
  V := GetActiveView;
  if (Key = VK_RETURN) and (V <> nil) and
     TryStrToInt(PageBox.Edit.Text, LPage) then
    V.GoToPage(LPage);
  Key := 0;
  if (V <> nil) and V.CanFocus then
    V.SetFocus; { leaving the box restores the real page number }
end;

procedure TRADEPDFViewerFrame.PageBoxKeyPress(Sender: TObject; var Key: Char);
begin
  if CharInSet(Key, [#13, #27]) then
    Key := #0 { swallow, avoids the beep }
  else if not CharInSet(Key, ['0'..'9', #8]) then
    Key := #0;
end;

procedure TRADEPDFViewerFrame.PageBoxExit(Sender: TObject);
begin
  UpdateUI;
end;

procedure TRADEPDFViewerFrame.StripPageClick(Sender: TObject; APage: Integer);
var
  V: TRADEPdfView;
begin
  V := GetActiveView;
  if V <> nil then
  begin
    V.GoToPage(APage);
    if V.CanFocus then
      V.SetFocus;
  end;
end;

procedure TRADEPDFViewerFrame.ThumbsToggleClick(Sender: TObject);
begin
  Strip.Visible := not Strip.Visible;
  PanelThumbLine.Visible := Strip.Visible;
  BtnThumbs.Active := Strip.Visible;
end;

procedure TRADEPDFViewerFrame.ZoomOutClick(Sender: TObject);
var
  V: TRADEPdfView;
begin
  V := GetActiveView;
  if V <> nil then
    V.ZoomStep(-1);
end;

procedure TRADEPDFViewerFrame.ZoomInClick(Sender: TObject);
var
  V: TRADEPdfView;
begin
  V := GetActiveView;
  if V <> nil then
    V.ZoomStep(1);
end;

procedure TRADEPDFViewerFrame.FitWidthClick(Sender: TObject);
var
  V: TRADEPdfView;
begin
  V := GetActiveView;
  if V <> nil then
    V.FitWidth;
end;

procedure TRADEPDFViewerFrame.ZoomPillClick(Sender: TObject);
var
  P: TPoint;
begin
  if GetActiveView = nil then
    Exit;
  P := ZoomPill.ClientToScreen(Point(0, ZoomPill.Height));
  FZoomMenu.Popup(P.X, P.Y);
end;

procedure TRADEPDFViewerFrame.ZoomMenuItemClick(Sender: TObject);
var
  V: TRADEPdfView;
  Pct: Integer;
begin
  V := GetActiveView;
  if V = nil then
    Exit;
  Pct := (Sender as TMenuItem).Tag;
  if Pct = 0 then
    V.FitWidth
  else
    V.Zoom := Pct / 100;
end;

procedure TRADEPDFViewerFrame.ToolbarResize(Sender: TObject);
begin
  ArrangeToolbar;
end;

procedure TRADEPDFViewerFrame.WelcomeResize(Sender: TObject);
begin
  ArrangeWelcome;
end;

procedure TRADEPDFViewerFrame.ArrangeToolbar;
var
  X, Y, BS, PH, PillW, AreaH: Integer;
begin
  if (PanelToolbar = nil) or (BtnFit = nil) or (LblTotal = nil) then
    Exit;
  AreaH := PanelToolbar.ClientHeight - 1; { minus the bottom line }
  BS := Scl(28);
  PH := Scl(26);
  Y := (AreaH - BS) div 2;

  X := Scl(8);
  BtnThumbs.SetBounds(X, Y, BS, BS);
  Inc(X, BS + Scl(2));
  BtnPrev.SetBounds(X, Y, BS, BS);
  Inc(X, BS + Scl(2));
  BtnNext.SetBounds(X, Y, BS, BS);
  Inc(X, BS + Scl(10));
  PageBox.SetBounds(X, (AreaH - PH) div 2, Scl(44), PH);
  Inc(X, Scl(44) + Scl(8));
  LblTotal.Left := X;
  LblTotal.Top := (AreaH - LblTotal.Height) div 2;

  PillW := Scl(60);
  X := PanelToolbar.ClientWidth - Scl(8) - BS;
  BtnFit.SetBounds(X, Y, BS, BS);
  Dec(X, BS + Scl(2));
  BtnZoomIn.SetBounds(X, Y, BS, BS);
  Dec(X, PillW + Scl(4));
  ZoomPill.SetBounds(X, (AreaH - PH) div 2, PillW, PH);
  Dec(X, BS + Scl(4));
  BtnZoomOut.SetBounds(X, Y, BS, BS);
end;

procedure TRADEPDFViewerFrame.ArrangeWelcome;
var
  Total, Y, I, W: Integer;
begin
  if (PanelWelcome = nil) or (LblWelcome = nil) or (BtnWelcomeOpen = nil) or
     (FRecentLabels = nil) then
    Exit;
  W := PanelWelcome.ClientWidth;
  Total := Scl(32) + Scl(26) + Scl(16) + Scl(32);
  if FRecentLabels.Count > 0 then
    Inc(Total, Scl(24) + FRecentLabels.Count * Scl(22));
  Y := Max(Scl(16), (PanelWelcome.ClientHeight - Total) div 2);
  LblWelcome.SetBounds(Scl(12), Y, Max(1, W - Scl(24)), Scl(32));
  Inc(Y, Scl(32));
  LblWelcomeSub.SetBounds(Scl(12), Y, Max(1, W - Scl(24)), Scl(26));
  Inc(Y, Scl(26) + Scl(16));
  BtnWelcomeOpen.SetBounds((W - Scl(130)) div 2, Y, Scl(130), Scl(32));
  Inc(Y, Scl(32) + Scl(24));
  for I := 0 to FRecentLabels.Count - 1 do
  begin
    FRecentLabels[I].SetBounds(Scl(12), Y, Max(1, W - Scl(24)), Scl(22));
    Inc(Y, Scl(22));
  end;
end;

procedure TRADEPDFViewerFrame.InitializeViewer;
const
  ZoomPresets: array[0..8] of Integer = (25, 50, 75, 100, 125, 150, 200, 300,
    400);
var
  I: Integer;
  Item: TMenuItem;
begin
  FRecentFiles := TStringList.Create;
  FRecentLabels := TObjectList<TLabel>.Create(True);
  FRecentMenu := TPopupMenu.Create(Self);
  FZoomMenu := TPopupMenu.Create(Self);
  for I := Low(ZoomPresets) to High(ZoomPresets) do
  begin
    Item := TMenuItem.Create(FZoomMenu);
    Item.Caption := IntToStr(ZoomPresets[I]) + '%';
    Item.Tag := ZoomPresets[I];
    Item.OnClick := ZoomMenuItemClick;
    FZoomMenu.Items.Add(Item);
  end;
  Item := TMenuItem.Create(FZoomMenu);
  Item.Caption := 'Fit width';
  Item.Tag := 0;
  Item.OnClick := ZoomMenuItemClick;
  FZoomMenu.Items.Add(Item);

  { ---- status bar (bottom) ---- }
  PanelStatus := MakePanel(Self, alBottom, clBarBack);
  PanelStatus.Height := Scl(28);
  MakeLine(PanelStatus, alTop);
  LblStatus := MakeLabel(PanelStatus, 9, clTextDim);
  LblStatus.AutoSize := False;
  LblStatus.Layout := tlCenter;
  LblStatus.AlignWithMargins := True;
  LblStatus.Margins.Left := Scl(14);
  LblStatus.Align := alClient;

  { ---- tab strip (top) ---- }
  TabBar := TRADETabBar.Create(Self);
  TabBar.Parent := Self;
  TabBar.Top := 0;
  TabBar.Align := alTop;
  TabBar.OnActivate := TabActivated;
  TabBar.OnCloseTab := TabCloseRequest;
  TabBar.OnAddClick := BtnOpenPDFClick;
  TabBar.OnAddMenu := ShowRecentMenu;

  { ---- toolbar ---- }
  PanelToolbar := MakePanel(Self, alNone, clToolBack);
  PanelToolbar.Height := Scl(42);
  PanelToolbar.Top := 10000;
  PanelToolbar.Align := alTop;
  PanelToolbar.OnResize := ToolbarResize;
  MakeLine(PanelToolbar, alBottom);

  BtnThumbs := MakeButton(icThumbs, 'Show / hide thumbnails',
    ThumbsToggleClick);
  BtnThumbs.Active := True;
  BtnPrev := MakeButton(icPrev, 'Previous page', BtnPrevClick);
  BtnNext := MakeButton(icNext, 'Next page', BtnNextClick);

  PageBox := TRADEPill.Create(Self, True);
  PageBox.Parent := PanelToolbar;
  PageBox.Hint := 'Page number; press Enter to go';
  PageBox.ShowHint := True;
  PageBox.Edit.OnKeyDown := PageBoxKeyDown;
  PageBox.Edit.OnKeyPress := PageBoxKeyPress;
  PageBox.OnEditExit := PageBoxExit;

  LblTotal := MakeLabel(PanelToolbar, 9, clTextHot);
  LblTotal.Caption := '/ 0';

  BtnZoomOut := MakeButton(icZoomOut, 'Zoom out', ZoomOutClick);
  ZoomPill := TRADEPill.Create(Self, False);
  ZoomPill.Parent := PanelToolbar;
  ZoomPill.Hint := 'Zoom presets';
  ZoomPill.ShowHint := True;
  ZoomPill.Text := '--%';
  ZoomPill.OnClick := ZoomPillClick;
  BtnZoomIn := MakeButton(icZoomIn, 'Zoom in', ZoomInClick);
  BtnFit := MakeButton(icFitWidth, 'Fit page width', FitWidthClick);

  { ---- content: thumbnails | PDF ---- }
  PanelContent := MakePanel(Self, alClient, clViewBack);

  Strip := TRADEThumbStrip.Create(Self);
  Strip.Parent := PanelContent;
  Strip.Left := 0;
  Strip.Align := alLeft;
  Strip.OnPageClick := StripPageClick;

  PanelThumbLine := MakeLine(PanelContent, alLeft);
  PanelThumbLine.Color := clDividerSoft;

  PanelPages := MakePanel(PanelContent, alClient, clViewBack);

  { ---- welcome screen (shown while no PDF is open) ---- }
  PanelWelcome := MakePanel(PanelPages, alClient, clViewBack);
  PanelWelcome.OnResize := WelcomeResize;
  LblWelcome := MakeLabel(PanelWelcome, 15, clWhite);
  LblWelcome.Font.Style := [fsBold];
  LblWelcome.AutoSize := False;
  LblWelcome.Alignment := taCenter;
  LblWelcome.Layout := tlCenter;
  LblWelcome.Caption := 'No document open';
  LblWelcomeSub := MakeLabel(PanelWelcome, 10, clTextDim);
  LblWelcomeSub.AutoSize := False;
  LblWelcomeSub.Alignment := taCenter;
  LblWelcomeSub.Layout := tlCenter;
  LblWelcomeSub.Caption := 'Choose a document to begin';
  BtnWelcomeOpen := TRADEPill.Create(Self, False);
  BtnWelcomeOpen.Parent := PanelWelcome;
  BtnWelcomeOpen.Text := 'Open PDF';
  BtnWelcomeOpen.OnClick := BtnOpenPDFClick;

  ArrangeToolbar;
  LoadRecentList;
  ArrangeWelcome;
  UpdateUI;
end;

end.
