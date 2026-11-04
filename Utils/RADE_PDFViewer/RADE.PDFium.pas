unit RADE.PDFium;

{ Browser-free PDF rendering via PDFium. pdfium.dll is embedded inside the
  BPL as a resource (RADE.PDFium32.res / RADE.PDFium64.res) and unpacked
  on first use. Bitness MUST match the IDE: x86 for RAD Studio 12. }

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes,
  System.Types, System.Math, System.IOUtils, System.Generics.Collections,
  Winapi.UxTheme, Vcl.Graphics, Vcl.Controls, Vcl.Clipbrd;

type
  ERADEPdf = class(Exception);

  TRADEPdfCharBox = record
    Left, Top, Right, Bottom: Double;
  end;

  TRADEPdfDoc = class
  private
    FData: TBytes;
    FDoc: Pointer;
    FSizes: TArray<TSizeF>;
    FTextLoaded: TArray<Boolean>;
    FTextChars: TArray<TArray<Cardinal>>;
    FTextBoxes: TArray<TArray<TRADEPdfCharBox>>;
    procedure EnsureTextPage(AIndex: Integer);
    function GetPageCount: Integer;
  public
    constructor Create(const AFileName: string);
    destructor Destroy; override;
    function PageSize(AIndex: Integer): TSizeF; { in PDF points (1/72 in) }
    procedure RenderPage(AIndex, AWidth, AHeight: Integer; ABmp: TBitmap);
    function TextCharCount(AIndex: Integer): Integer;
    function TextChar(AIndex, ACharIndex: Integer): Cardinal;
    function TextCharBox(AIndex, ACharIndex: Integer): TRADEPdfCharBox;
    property PageCount: Integer read GetPageCount;
  end;

  TRADEPdfView = class(TCustomControl)
  private
    FDoc: TRADEPdfDoc;
    FZoom: Double; { 1.0 = 100% at 96 dpi }
    FTops: TArray<Integer>;
    FTotalH: Integer;
    FPos: Integer;
    FFitWidth: Boolean;
    FCache: TObjectDictionary<Integer, TBitmap>;
    FSelectionPage, FSelectionStart, FSelectionEnd: Integer;
    FSelecting: Boolean;
    FOnZoomChange: TNotifyEvent;
    FOnPageChange: TNotifyEvent;
    FCurrentPage: Integer;
    function Scale: Double;
    function PW(I: Integer): Integer;
    function PH(I: Integer): Integer;
    procedure Relayout;
    procedure UpdateScrollBar;
    procedure SetPos(AValue: Integer);
    procedure SetZoom(AValue: Double);
    function GetCurrentPage: Integer;
    function GetPageCount: Integer;
    procedure ApplyZoom(AValue: Double; AFit: Boolean);
    procedure NotifyPageChange;
    procedure WMVScroll(var Msg: TWMVScroll); message WM_VSCROLL;
    procedure WMEraseBkgnd(var Msg: TMessage); message WM_ERASEBKGND;
    function CharAt(X, Y: Integer; out APage, AChar: Integer): Boolean;
    procedure CopySelection;
  protected
    procedure CreateParams(var Params: TCreateParams); override;
    procedure CreateWnd; override;
    procedure Paint; override;
    procedure Resize; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure LoadFromFile(const AFileName: string);
    procedure FitWidth;
    procedure ZoomStep(ADirection: Integer);
    procedure GoToPage(APageNumber: Integer);
    procedure RenderThumbnail(APageIndex, AMaxWidth, AMaxHeight: Integer;
      ABmp: TBitmap);
    function PageSizePts(AIndex: Integer): TSizeF;
    property FitWidthActive: Boolean read FFitWidth;
    property PageCount: Integer read GetPageCount;
    property CurrentPage: Integer read GetCurrentPage;
    property OnZoomChange: TNotifyEvent read FOnZoomChange write FOnZoomChange;
    property OnPageChange: TNotifyEvent read FOnPageChange write FOnPageChange;
    property Zoom: Double read FZoom write SetZoom;
  end;

implementation

{ Pre-built resource files (pdfium embedded as RCDATA 'PDFIUM'). The compiler
  links .res files directly; keep them in this unit's folder. }
{$IFDEF WIN64}
  {$R 'RADE.PDFium64.res'}
{$ELSE}
  {$R 'RADE.PDFium32.res'}
{$ENDIF}

const
  Gap = 16;
  ViewBackColor = TColor($000B0B0B); { #0B0B0B }
  FPDF_ANNOT = 1;

type
  { This pdfium build exports plain cdecl functions (verified in the x86 DLL:
    its functions end in a bare RET). stdcall here would corrupt the stack. }
  TInitLib = procedure; cdecl;
  TLoadMem = function(Data: Pointer; Size: Integer; Pwd: PAnsiChar): Pointer; cdecl;
  TCloseDoc = procedure(Doc: Pointer); cdecl;
  TGetPageCount = function(Doc: Pointer): Integer; cdecl;
  TLoadPage = function(Doc: Pointer; Index: Integer): Pointer; cdecl;
  TClosePage = procedure(Page: Pointer); cdecl;
  TPageDim = function(Page: Pointer): Single; cdecl;
  TLastError = function: Cardinal; cdecl;
  TBmpCreate = function(W, H, Alpha: Integer): Pointer; cdecl;
  TBmpDestroy = procedure(Bmp: Pointer); cdecl;
  TBmpFill = procedure(Bmp: Pointer; L, T, W, H: Integer; Color: Cardinal); cdecl;
  TBmpGetBuf = function(Bmp: Pointer): Pointer; cdecl;
  TBmpGetStride = function(Bmp: Pointer): Integer; cdecl;
  TRenderBmp = procedure(Bmp, Page: Pointer; SX, SY, SW, SH, Rotate, Flags: Integer); cdecl;
  TTextLoadPage = function(Page: Pointer): Pointer; cdecl;
  TTextClosePage = procedure(TextPage: Pointer); cdecl;
  TTextCountChars = function(TextPage: Pointer): Integer; cdecl;
  TTextGetUnicode = function(TextPage: Pointer; Index: Integer): Cardinal; cdecl;
  TTextGetCharBox = function(TextPage: Pointer; Index: Integer;
    Left, Right, Bottom, Top: PDouble): Integer; cdecl;

var
  hPdfium: HMODULE = 0;
  pInit: TInitLib;
  pLoadMem: TLoadMem;
  pCloseDoc: TCloseDoc;
  pPageCount: TGetPageCount;
  pLoadPage: TLoadPage;
  pClosePage: TClosePage;
  pPageW, pPageH: TPageDim;
  pLastError: TLastError;
  pBmpCreate: TBmpCreate;
  pBmpDestroy: TBmpDestroy;
  pBmpFill: TBmpFill;
  pBmpBuf: TBmpGetBuf;
  pBmpStride: TBmpGetStride;
  pRender: TRenderBmp;
  pTextLoadPage: TTextLoadPage;
  pTextClosePage: TTextClosePage;
  pTextCountChars: TTextCountChars;
  pTextGetUnicode: TTextGetUnicode;
  pTextGetCharBox: TTextGetCharBox;

function Proc(const AName: string): Pointer;
begin
  Result := GetProcAddress(hPdfium, PChar(AName));
  if Result = nil then
    raise ERADEPdf.Create('pdfium.dll is missing export ' + AName +
      ' (wrong or too old a build?)');
end;

function FileSizeOf(const AFile: string): Int64;
var
  SR: TSearchRec;
begin
  Result := -1;
  if FindFirst(AFile, faAnyFile, SR) = 0 then
  begin
    Result := SR.Size;
    FindClose(SR);
  end;
end;

{ pdfium is embedded in the BPL as an RCDATA resource named PDFIUM.
  Windows can only load a DLL from disk, so it is unpacked once to
  %LOCALAPPDATA%\RADEssentials and reused on later IDE launches. }
function ExtractEmbeddedDll: string;
var
  Res: HRSRC;
  Glb: HGLOBAL;
  P: Pointer;
  Size: DWORD;
  Dir, Tmp: string;
  FS: TFileStream;
begin
  Res := FindResource(HInstance, 'PDFIUM', RT_RCDATA);
  if Res = 0 then
    raise ERADEPdf.Create('pdfium is not embedded in the package (resource PDFIUM missing).');
  Size := SizeofResource(HInstance, Res);
  Glb := LoadResource(HInstance, Res);
  P := LockResource(Glb);
  if (P = nil) or (Size = 0) then
    raise ERADEPdf.Create('The embedded pdfium resource is empty.');
  Dir := TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'RADEssentials');
  ForceDirectories(Dir);
  Result := TPath.Combine(Dir, Format('pdfium_%d.dll', [Size]));
  if FileSizeOf(Result) = Int64(Size) then
    Exit;
  Tmp := Result + '.' + IntToStr(GetCurrentProcessId) + '.tmp';
  FS := TFileStream.Create(Tmp, fmCreate);
  try
    FS.WriteBuffer(P^, Size);
  finally
    FS.Free;
  end;
  if not MoveFileEx(PChar(Tmp), PChar(Result), MOVEFILE_REPLACE_EXISTING) then
  begin
    DeleteFile(PChar(Tmp));
    if FileSizeOf(Result) <> Int64(Size) then
      raise ERADEPdf.Create('Could not unpack pdfium.dll to ' + Dir);
  end;
end;

procedure EnsureLoaded;
begin
  if hPdfium <> 0 then
    Exit;
  hPdfium := LoadLibrary(PChar(ExtractEmbeddedDll));
  if hPdfium = 0 then
    raise ERADEPdf.Create('Could not load the embedded pdfium (bitness must match the IDE).');
  pInit := TInitLib(Proc('FPDF_InitLibrary'));
  pLoadMem := TLoadMem(Proc('FPDF_LoadMemDocument'));
  pCloseDoc := TCloseDoc(Proc('FPDF_CloseDocument'));
  pPageCount := TGetPageCount(Proc('FPDF_GetPageCount'));
  pLoadPage := TLoadPage(Proc('FPDF_LoadPage'));
  pClosePage := TClosePage(Proc('FPDF_ClosePage'));
  pPageW := TPageDim(Proc('FPDF_GetPageWidthF'));
  pPageH := TPageDim(Proc('FPDF_GetPageHeightF'));
  pLastError := TLastError(Proc('FPDF_GetLastError'));
  pBmpCreate := TBmpCreate(Proc('FPDFBitmap_Create'));
  pBmpDestroy := TBmpDestroy(Proc('FPDFBitmap_Destroy'));
  pBmpFill := TBmpFill(Proc('FPDFBitmap_FillRect'));
  pBmpBuf := TBmpGetBuf(Proc('FPDFBitmap_GetBuffer'));
  pBmpStride := TBmpGetStride(Proc('FPDFBitmap_GetStride'));
  pRender := TRenderBmp(Proc('FPDF_RenderPageBitmap'));
  pTextLoadPage := TTextLoadPage(Proc('FPDFText_LoadPage'));
  pTextClosePage := TTextClosePage(Proc('FPDFText_ClosePage'));
  pTextCountChars := TTextCountChars(Proc('FPDFText_CountChars'));
  pTextGetUnicode := TTextGetUnicode(Proc('FPDFText_GetUnicode'));
  pTextGetCharBox := TTextGetCharBox(Proc('FPDFText_GetCharBox'));
  pInit;
end;

{ TRADEPdfDoc }

constructor TRADEPdfDoc.Create(const AFileName: string);
var
  I: Integer;
  Pg: Pointer;
begin
  inherited Create;
  EnsureLoaded;
  { Loaded from memory so the file is never locked. FData must outlive FDoc. }
  FData := TFile.ReadAllBytes(AFileName);
  if Length(FData) = 0 then
    raise ERADEPdf.Create('The file is empty.');
  FDoc := pLoadMem(@FData[0], Length(FData), nil);
  if FDoc = nil then
    raise ERADEPdf.CreateFmt(
      'PDFium could not open the file (error %d). It may be damaged or password-protected.',
      [pLastError()]);
  SetLength(FSizes, pPageCount(FDoc));
  SetLength(FTextLoaded, Length(FSizes));
  SetLength(FTextChars, Length(FSizes));
  SetLength(FTextBoxes, Length(FSizes));
  for I := 0 to High(FSizes) do
  begin
    Pg := pLoadPage(FDoc, I);
    if Pg <> nil then
    begin
      FSizes[I].cx := pPageW(Pg);
      FSizes[I].cy := pPageH(Pg);
      pClosePage(Pg);
    end
    else
    begin
      FSizes[I].cx := 612;
      FSizes[I].cy := 792;
    end;
  end;
end;

procedure TRADEPdfDoc.EnsureTextPage(AIndex: Integer);
var
  Page, TextPage: Pointer;
  I, Count: Integer;
  L, R, B, T: Double;
begin
  if FTextLoaded[AIndex] then
    Exit;
  FTextLoaded[AIndex] := True;
  Page := pLoadPage(FDoc, AIndex);
  if Page = nil then
    Exit;
  try
    TextPage := pTextLoadPage(Page);
    if TextPage = nil then
      Exit;
    try
      Count := Max(0, pTextCountChars(TextPage));
      SetLength(FTextChars[AIndex], Count);
      SetLength(FTextBoxes[AIndex], Count);
      for I := 0 to Count - 1 do
      begin
        FTextChars[AIndex][I] := pTextGetUnicode(TextPage, I);
        if pTextGetCharBox(TextPage, I, @L, @R, @B, @T) <> 0 then
        begin
          FTextBoxes[AIndex][I].Left := L;
          FTextBoxes[AIndex][I].Right := R;
          FTextBoxes[AIndex][I].Bottom := B;
          FTextBoxes[AIndex][I].Top := T;
        end;
      end;
    finally
      pTextClosePage(TextPage);
    end;
  finally
    pClosePage(Page);
  end;
end;

function TRADEPdfDoc.TextCharCount(AIndex: Integer): Integer;
begin
  EnsureTextPage(AIndex);
  Result := Length(FTextChars[AIndex]);
end;

function TRADEPdfDoc.TextChar(AIndex, ACharIndex: Integer): Cardinal;
begin
  EnsureTextPage(AIndex);
  Result := FTextChars[AIndex][ACharIndex];
end;

function TRADEPdfDoc.TextCharBox(AIndex, ACharIndex: Integer): TRADEPdfCharBox;
begin
  EnsureTextPage(AIndex);
  Result := FTextBoxes[AIndex][ACharIndex];
end;

destructor TRADEPdfDoc.Destroy;
begin
  if FDoc <> nil then
    pCloseDoc(FDoc);
  inherited;
end;

function TRADEPdfDoc.GetPageCount: Integer;
begin
  Result := Length(FSizes);
end;

function TRADEPdfDoc.PageSize(AIndex: Integer): TSizeF;
begin
  Result := FSizes[AIndex];
end;

procedure TRADEPdfDoc.RenderPage(AIndex, AWidth, AHeight: Integer; ABmp: TBitmap);
var
  Pg, PBmp, Src: Pointer;
  Stride, Y: Integer;
begin
  ABmp.PixelFormat := pf32bit;
  ABmp.SetSize(AWidth, AHeight);
  Pg := pLoadPage(FDoc, AIndex);
  if Pg = nil then
    Exit;
  try
    PBmp := pBmpCreate(AWidth, AHeight, 0); { BGRx }
    if PBmp = nil then
      Exit;
    try
      pBmpFill(PBmp, 0, 0, AWidth, AHeight, $FFFFFFFF);
      pRender(PBmp, Pg, 0, 0, AWidth, AHeight, 0, FPDF_ANNOT);
      Src := pBmpBuf(PBmp);
      Stride := pBmpStride(PBmp);
      for Y := 0 to AHeight - 1 do
        Move(Pointer(NativeUInt(Src) + NativeUInt(Y * Stride))^,
          ABmp.ScanLine[Y]^, AWidth * 4);
    finally
      pBmpDestroy(PBmp);
    end;
  finally
    pClosePage(Pg);
  end;
end;

{ TRADEPdfView }

constructor TRADEPdfView.Create(AOwner: TComponent);
begin
  inherited;
  ControlStyle := ControlStyle + [csOpaque];
  DoubleBuffered := True;
  TabStop := True;
  FZoom := 1.0;
  FSelectionPage := -1;
  FSelectionStart := -1;
  FSelectionEnd := -1;
  FCurrentPage := -1;
  FCache := TObjectDictionary<Integer, TBitmap>.Create([doOwnsValues]);
  Width := 300;
  Height := 300;
end;

destructor TRADEPdfView.Destroy;
begin
  FCache.Free;
  FDoc.Free;
  inherited;
end;

procedure TRADEPdfView.CreateParams(var Params: TCreateParams);
begin
  inherited;
  Params.Style := Params.Style or WS_VSCROLL;
end;

procedure TRADEPdfView.CreateWnd;
begin
  inherited;
  SetWindowTheme(Handle, 'DarkMode_Explorer', nil); { dark scrollbar }
end;

function TRADEPdfView.PageSizePts(AIndex: Integer): TSizeF;
begin
  if (FDoc <> nil) and (AIndex >= 0) and (AIndex < FDoc.PageCount) then
    Result := FDoc.PageSize(AIndex)
  else
    Result := TSizeF.Create(612, 792);
end;

procedure TRADEPdfView.WMEraseBkgnd(var Msg: TMessage);
begin
  Msg.Result := 1;
end;

function TRADEPdfView.Scale: Double;
begin
  Result := FZoom * 96 / 72;
end;

function TRADEPdfView.PW(I: Integer): Integer;
begin
  Result := Max(1, Round(FDoc.PageSize(I).cx * Scale));
end;

function TRADEPdfView.PH(I: Integer): Integer;
begin
  Result := Max(1, Round(FDoc.PageSize(I).cy * Scale));
end;

procedure TRADEPdfView.LoadFromFile(const AFileName: string);
var
  NewDoc: TRADEPdfDoc;
begin
  NewDoc := TRADEPdfDoc.Create(AFileName); { raises on failure, view untouched }
  FCache.Clear;
  FDoc.Free;
  FDoc := NewDoc;
  FTops := nil;
  FTotalH := 0;
  FPos := 0;
  FCurrentPage := -1;
  FitWidth;
end;

function TRADEPdfView.GetCurrentPage: Integer;
var
  I, CenterY: Integer;
begin
  Result := 0;
  if (FDoc = nil) or (FDoc.PageCount = 0) then
    Exit;
  CenterY := FPos + ClientHeight div 2;
  for I := 0 to High(FTops) do
    if (CenterY >= FTops[I]) and (CenterY < FTops[I] + PH(I)) then
      Exit(I + 1);
  Result := 1;
  for I := 0 to High(FTops) do
    if CenterY < FTops[I] then
      Exit(Max(1, I));
  Result := FDoc.PageCount;
end;

function TRADEPdfView.GetPageCount: Integer;
begin
  if FDoc = nil then
    Result := 0
  else
    Result := FDoc.PageCount;
end;

procedure TRADEPdfView.NotifyPageChange;
var
  LPage: Integer;
begin
  LPage := GetCurrentPage;
  if LPage = FCurrentPage then
    Exit;
  FCurrentPage := LPage;
  if Assigned(FOnPageChange) then
    FOnPageChange(Self);
end;

procedure TRADEPdfView.GoToPage(APageNumber: Integer);
begin
  if (FDoc = nil) or (FDoc.PageCount = 0) then
    Exit;
  APageNumber := EnsureRange(APageNumber, 1, FDoc.PageCount);
  SetPos(FTops[APageNumber - 1]);
end;

procedure TRADEPdfView.RenderThumbnail(APageIndex, AMaxWidth,
  AMaxHeight: Integer; ABmp: TBitmap);
var
  LPageSize: TSizeF;
  LScale: Double;
begin
  if (FDoc = nil) or (APageIndex < 0) or (APageIndex >= FDoc.PageCount) or
     (AMaxWidth < 1) or (AMaxHeight < 1) then
    Exit;
  LPageSize := FDoc.PageSize(APageIndex);
  LScale := Min(AMaxWidth / LPageSize.cx, AMaxHeight / LPageSize.cy);
  ABmp.PixelFormat := pf32bit;
  FDoc.RenderPage(APageIndex, Max(1, Round(LPageSize.cx * LScale)),
    Max(1, Round(LPageSize.cy * LScale)), ABmp);
end;

procedure TRADEPdfView.FitWidth;
var
  I: Integer;
  MaxW: Single;
begin
  if (FDoc = nil) or (FDoc.PageCount = 0) or (ClientWidth < 100) then
  begin
    FFitWidth := True;
    Relayout;
    Exit;
  end;
  MaxW := 1;
  for I := 0 to FDoc.PageCount - 1 do
    MaxW := Max(MaxW, FDoc.PageSize(I).cx);
  ApplyZoom((ClientWidth - 2 * Gap) / MaxW * 72 / 96, True);
end;

procedure TRADEPdfView.SetZoom(AValue: Double);
begin
  ApplyZoom(AValue, False);
end;

{ Keeps the page at the top of the viewport (and how far into it) stable
  while the zoom changes, so the page counter does not jump. }
procedure TRADEPdfView.ApplyZoom(AValue: Double; AFit: Boolean);
var
  I, AnchorPage: Integer;
  AnchorFrac: Double;
begin
  AnchorPage := -1;
  AnchorFrac := 0;
  if (FDoc <> nil) and (Length(FTops) = FDoc.PageCount) then
    for I := High(FTops) downto 0 do
      if FTops[I] <= FPos then
      begin
        AnchorPage := I;
        AnchorFrac := (FPos - FTops[I]) / PH(I);
        Break;
      end;
  FFitWidth := AFit;
  FZoom := EnsureRange(AValue, 0.25, 4.0);
  Relayout;
  if AnchorPage >= 0 then
    SetPos(FTops[AnchorPage] + Round(AnchorFrac * PH(AnchorPage)));
  if Assigned(FOnZoomChange) then
    FOnZoomChange(Self);
end;

procedure TRADEPdfView.ZoomStep(ADirection: Integer);
const
  Levels: array[0..8] of Double = (0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0, 4.0);
var
  I: Integer;
begin
  if ADirection > 0 then
  begin
    for I := Low(Levels) to High(Levels) do
      if Levels[I] > FZoom + 0.01 then
      begin
        SetZoom(Levels[I]);
        Exit;
      end;
  end
  else if ADirection < 0 then
    for I := High(Levels) downto Low(Levels) do
      if Levels[I] < FZoom - 0.01 then
      begin
        SetZoom(Levels[I]);
        Exit;
      end;
end;

procedure TRADEPdfView.Relayout;
var
  I, Y: Integer;
begin
  FCache.Clear;
  if FDoc = nil then
  begin
    FTops := nil;
    FTotalH := 0;
  end
  else
  begin
    SetLength(FTops, FDoc.PageCount);
    Y := Gap;
    for I := 0 to FDoc.PageCount - 1 do
    begin
      FTops[I] := Y;
      Inc(Y, PH(I) + Gap);
    end;
    FTotalH := Y;
  end;
  SetPos(FPos);
  Invalidate;
end;

procedure TRADEPdfView.UpdateScrollBar;
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

procedure TRADEPdfView.SetPos(AValue: Integer);
begin
  FPos := Max(0, Min(AValue, FTotalH - ClientHeight));
  UpdateScrollBar;
  NotifyPageChange;
  Invalidate;
end;

procedure TRADEPdfView.Resize;
begin
  inherited;
  if FFitWidth then
    FitWidth
  else
    SetPos(FPos);
end;

function TRADEPdfView.CharAt(X, Y: Integer; out APage, AChar: Integer): Boolean;
var
  I, J, PageTop, PageX, Count: Integer;
  PdfX, PdfY, DX, DY, Distance, BestDistance: Double;
  Box: TRADEPdfCharBox;
begin
  Result := False;
  APage := -1;
  AChar := -1;
  if FDoc = nil then
    Exit;
  for I := 0 to FDoc.PageCount - 1 do
  begin
    PageTop := FTops[I] - FPos;
    if (Y < PageTop) or (Y >= PageTop + PH(I)) then
      Continue;
    PageX := (ClientWidth - PW(I)) div 2;
    if (X < PageX - 8) or (X > PageX + PW(I) + 8) then
      Exit;
    PdfX := EnsureRange((X - PageX) / Scale, 0.0, FDoc.PageSize(I).cx);
    PdfY := EnsureRange(FDoc.PageSize(I).cy - (Y - PageTop) / Scale,
      0.0, FDoc.PageSize(I).cy);
    Count := FDoc.TextCharCount(I);
    BestDistance := MaxDouble;
    for J := 0 to Count - 1 do
    begin
      Box := FDoc.TextCharBox(I, J);
      if (Box.Right <= Box.Left) or (Box.Top <= Box.Bottom) then
        Continue;
      if PdfX < Box.Left then
        DX := Box.Left - PdfX
      else if PdfX > Box.Right then
        DX := PdfX - Box.Right
      else
        DX := 0;
      if PdfY < Box.Bottom then
        DY := Box.Bottom - PdfY
      else if PdfY > Box.Top then
        DY := PdfY - Box.Top
      else
        DY := 0;
      Distance := DX * DX + DY * DY * 2;
      if Distance < BestDistance then
      begin
        BestDistance := Distance;
        APage := I;
        AChar := J;
      end;
    end;
    Result := AChar >= 0;
    Exit;
  end;
end;

procedure TRADEPdfView.CopySelection;
var
  I, FirstChar, LastChar: Integer;
  CodePoint: Cardinal;
  Text: UnicodeString;
begin
  if (FDoc = nil) or (FSelectionPage < 0) or (FSelectionStart < 0) or
     (FSelectionEnd < 0) then
    Exit;
  FirstChar := Min(FSelectionStart, FSelectionEnd);
  LastChar := Max(FSelectionStart, FSelectionEnd);
  Text := '';
  for I := FirstChar to LastChar do
  begin
    CodePoint := FDoc.TextChar(FSelectionPage, I);
    if CodePoint <= $FFFF then
      Text := Text + WideChar(CodePoint)
    else if CodePoint <= $10FFFF then
    begin
      Dec(CodePoint, $10000);
      Text := Text + WideChar($D800 + (CodePoint shr 10)) +
        WideChar($DC00 + (CodePoint and $3FF));
    end;
  end;
  if Text <> '' then
    Clipboard.AsText := Text;
end;

procedure TRADEPdfView.KeyDown(var Key: Word; Shift: TShiftState);
begin
  inherited;
  if (Key = Ord('C')) and (ssCtrl in Shift) then
  begin
    CopySelection;
    Key := 0;
  end;
end;

procedure TRADEPdfView.WMVScroll(var Msg: TWMVScroll);
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

procedure TRADEPdfView.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  PageIndex, CharIndex: Integer;
begin
  inherited;
  if CanFocus then
    SetFocus;
  if Button <> mbLeft then
    Exit;
  if CharAt(X, Y, PageIndex, CharIndex) then
  begin
    FSelectionPage := PageIndex;
    FSelectionStart := CharIndex;
    FSelectionEnd := CharIndex;
    FSelecting := True;
    MouseCapture := True;
  end
  else
  begin
    FSelectionPage := -1;
    FSelectionStart := -1;
    FSelectionEnd := -1;
    FSelecting := False;
  end;
  Invalidate;
end;

procedure TRADEPdfView.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  PageIndex, CharIndex: Integer;
begin
  inherited;
  if FSelecting and CharAt(X, Y, PageIndex, CharIndex) and
     (PageIndex = FSelectionPage) then
  begin
    FSelectionEnd := CharIndex;
    Invalidate;
  end;
end;

procedure TRADEPdfView.MouseUp(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  inherited;
  if Button = mbLeft then
  begin
    FSelecting := False;
    MouseCapture := False;
  end;
end;

function TRADEPdfView.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint): Boolean;
begin
  if ssCtrl in Shift then
  begin
    if WheelDelta > 0 then
      ZoomStep(1)
    else
      ZoomStep(-1);
  end
  else
    SetPos(FPos - WheelDelta div 2);
  Result := True;
end;

procedure TRADEPdfView.Paint;
var
  I, Y, X, J, FirstChar, LastChar, LeftPos, RightPos, TopPos, BottomPos: Integer;
  Bmp: TBitmap;
  Box: TRADEPdfCharBox;
  Highlight: TBitmap;
  Blend: BLENDFUNCTION;
begin
  Canvas.Brush.Color := ViewBackColor;
  Canvas.FillRect(ClientRect);
  if FDoc = nil then
    Exit;
  Highlight := nil;
  if FSelectionPage >= 0 then
  begin
    Highlight := TBitmap.Create;
    Highlight.PixelFormat := pf32bit;
    Highlight.SetSize(1, 1);
    Highlight.Canvas.Pixels[0, 0] := RGB(58, 135, 235);
    Blend.BlendOp := AC_SRC_OVER;
    Blend.BlendFlags := 0;
    Blend.SourceConstantAlpha := 80;
    Blend.AlphaFormat := 0;
  end;
  try
  for I := 0 to High(FTops) do
  begin
    Y := FTops[I] - FPos;
    if Y + PH(I) < 0 then
      Continue;
    if Y > ClientHeight then
      Break;
    if not FCache.TryGetValue(I, Bmp) then
    begin
      if FCache.Count > 10 then
        FCache.Clear;
      Bmp := TBitmap.Create;
      try
        FDoc.RenderPage(I, PW(I), PH(I), Bmp);
      except
        Bmp.Free;
        Continue; { never let a render error escape into the IDE paint loop }
      end;
      FCache.Add(I, Bmp);
    end;
    X := (ClientWidth - PW(I)) div 2;
    Canvas.Draw(X, Y, Bmp);
    if I = FSelectionPage then
    begin
      FirstChar := Min(FSelectionStart, FSelectionEnd);
      LastChar := Max(FSelectionStart, FSelectionEnd);
      Canvas.Pen.Color := RGB(45, 115, 210);
      Canvas.Brush.Style := bsClear;
      for J := FirstChar to LastChar do
      begin
        if (J < 0) or (J >= FDoc.TextCharCount(I)) then
          Break;
        Box := FDoc.TextCharBox(I, J);
        LeftPos := X + Round(Box.Left * Scale);
        RightPos := X + Round(Box.Right * Scale);
        TopPos := Y + Round((FDoc.PageSize(I).cy - Box.Top) * Scale);
        BottomPos := Y + Round((FDoc.PageSize(I).cy - Box.Bottom) * Scale);
        if RightPos <= LeftPos then
          RightPos := LeftPos + 1;
        if BottomPos <= TopPos then
          BottomPos := TopPos + 1;
        AlphaBlend(Canvas.Handle, LeftPos, TopPos, RightPos - LeftPos,
          BottomPos - TopPos, Highlight.Canvas.Handle, 0, 0, 1, 1, Blend);
      end;
    end;
  end;
  finally
    Highlight.Free;
  end;
end;

initialization

finalization
  { pdfium.dll is left loaded until the IDE exits; unloading while
    the IDE may still hold paint messages is not worth the risk. }

end.
