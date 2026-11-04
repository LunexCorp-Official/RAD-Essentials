unit DiscordRPC;

interface

uses
  System.SysUtils,
  System.JSON,
  Winapi.Windows;

type
  /// <summary>
  ///   Structure defining the rich presence data to display on Discord.
  /// </summary>
  TDiscordRichPresence = record
    /// <summary>
    ///   The user's current state, displayed as the large text on the profile.
    /// </summary>
    State: string;
    /// <summary>
    ///   What the user is doing, displayed as the smaller text below the state.
    /// </summary>
    Details: string;
    /// <summary>
    ///   Unix timestamp (seconds) for the start of the activity.
    /// </summary>
    StartTimestamp: Int64;
    /// <summary>
    ///   Unix timestamp (seconds) for the end of the activity.
    /// </summary>
    EndTimestamp: Int64;
    /// <summary>
    ///   Key for the large image asset (from your Discord application's Rich Presence assets).
    /// </summary>
    LargeImageKey: string;
    /// <summary>
    ///   Hover text for the large image.
    /// </summary>
    LargeImageText: string;
    /// <summary>
    ///   Key for the small image asset.
    /// </summary>
    SmallImageKey: string;
    /// <summary>
    ///   Hover text for the small image.
    /// </summary>
    SmallImageText: string;
    /// <summary>
    ///   Unique identifier for the current activity. Used to update an existing activity.
    /// </summary>
    ActivityId: string;
    /// <summary>
    ///   The user's current party size, displayed as "1/5".
    /// </summary>
    PartySize: Integer;
    /// <summary>
    ///   The maximum party size.
    /// </summary>
    PartyMax: Integer;
    /// <summary>
    ///   The secret key for joining the party.
    /// </summary>
    JoinSecret: string;
    /// <summary>
    ///   The secret key for spectating the party.
    /// </summary>
    SpectateSecret: string;
    /// <summary>
    ///   The secret key for an instanced match.
    /// </summary>
    MatchSecret: string;
    /// <summary>
    ///   The instance status of the activity.
    /// </summary>
    Instance: Boolean;
  end;

  /// <summary>
  ///   Handles communication with Discord's Rich Presence via the official RPC DLL.
  /// </summary>
  TDiscordRPC = class
  private
    FClientId: string;
    FPipeHandle: THandle;
    FReady: Boolean;
    FNonce: Integer;
    FRefCount: Integer;
    function GetPipePath: string;
    function ConnectToPipe: Boolean;
    function SendPayload(const APayload: TJSONObject; AOpcode: Integer): Boolean;
    function ReceivePayload: TJSONObject;
    function GetNextNonce: string;
  public
    /// <summary>
    ///   Creates a new Discord RPC instance.
    /// </summary>
    /// <param name="AClientId">
    ///   The Client ID of your application from the Discord Developer Portal.
    /// </param>
    constructor Create(const AClientId: string);
    destructor Destroy; override;

    /// <summary>
    ///   Initializes the connection to Discord and sets up the RPC handshake.
    /// </summary>
    procedure Initialize;

    /// <summary>
    ///   Shuts down the RPC connection and clears the presence.
    /// </summary>
    procedure Shutdown;

    /// <summary>
    ///   Updates the user's rich presence on Discord.
    /// </summary>
    /// <param name="APresence">
    ///   A <see cref="TDiscordRichPresence" /> record with the data to display.
    /// </param>
    procedure UpdatePresence(const APresence: TDiscordRichPresence);

    /// <summary>
    ///   Clears the current rich presence from Discord.
    /// </summary>
    procedure ClearPresence;
    procedure AddRef;
    procedure Release;

    /// <summary>
    ///   Checks if the RPC connection is ready.
    /// </summary>
    property IsReady: Boolean read FReady;
  end;

implementation

const
  DISCORD_RPC_PIPE_NAME = '\\.\pipe\discord-ipc-';
  DISCORD_RPC_VERSION = 1;

{ TDiscordRPC }

constructor TDiscordRPC.Create(const AClientId: string);
begin
  inherited Create;
  FClientId := AClientId;
  FPipeHandle := INVALID_HANDLE_VALUE;
  FReady := False;
  FNonce := 0;
  FRefCount := 1;
end;

destructor TDiscordRPC.Destroy;
begin
  FReady := False;
  if FPipeHandle <> INVALID_HANDLE_VALUE then
  begin
    CloseHandle(FPipeHandle);
    FPipeHandle := INVALID_HANDLE_VALUE;
  end;
  inherited;
end;

function TDiscordRPC.GetPipePath: string;
var
  I: Integer;
  PipePath: string;
  Handle: THandle;
begin
  Result := '';
  for I := 0 to 9 do begin
    PipePath := DISCORD_RPC_PIPE_NAME + I.ToString;
    Handle :=
        CreateFile(
            PChar(PipePath),
            GENERIC_READ or GENERIC_WRITE,
            FILE_SHARE_READ or FILE_SHARE_WRITE,
            nil,
            OPEN_EXISTING,
            0,
            0
        );

    if Handle <> INVALID_HANDLE_VALUE then begin
      FPipeHandle := Handle;
      Result := PipePath;
      Exit;
    end;
  end;
end;

function TDiscordRPC.ConnectToPipe: Boolean;
begin
  Result := GetPipePath <> '';
end;

function TDiscordRPC.GetNextNonce: string;
begin
  Inc(FNonce);
  Result := FNonce.ToString;
end;

function TDiscordRPC.SendPayload(const APayload: TJSONObject; AOpcode: Integer): Boolean;
var
  Data: TBytes;
  Header: array[0..7] of Byte;
  BytesWritten: DWORD;
  BytesToWrite: DWORD;
  PayloadStr: string;
  PayloadLength: Integer;
  TotalWritten: Integer;
begin
  Result := False;
  if FPipeHandle = INVALID_HANDLE_VALUE then
    Exit;

  PayloadStr := APayload.ToJSON;
  Data := TEncoding.UTF8.GetBytes(PayloadStr);
  PayloadLength := Length(Data);

  // Discord IPC framing: opcode 0 for handshake, 1 for frames
  PInteger(@Header[0])^ := AOpcode;
  PInteger(@Header[4])^ := PayloadLength;

  TotalWritten := 0;
  while TotalWritten < 8 do begin
    BytesToWrite := 8 - TotalWritten;
    if not WriteFile(FPipeHandle, Header[TotalWritten], BytesToWrite, BytesWritten, nil) then
      Exit;
    if BytesWritten = 0 then
      Exit;
    Inc(TotalWritten, BytesWritten);
  end;

  TotalWritten := 0;
  while TotalWritten < PayloadLength do begin
    BytesToWrite := PayloadLength - TotalWritten;
    if not WriteFile(FPipeHandle, Data[TotalWritten], BytesToWrite, BytesWritten, nil) then
      Exit;
    if BytesWritten = 0 then
      Exit;
    Inc(TotalWritten, BytesWritten);
  end;

  Result := True;
end;

function TDiscordRPC.ReceivePayload: TJSONObject;
var
  Header: array[0..7] of Byte;
  BytesRead: DWORD;
  BytesToRead: DWORD;
  Data: TBytes;
  Length: Integer;
  TotalRead: Integer;
  PayloadStr: string;
begin
  Result := nil;
  if FPipeHandle = INVALID_HANDLE_VALUE then
    Exit;

  TotalRead := 0;
  while TotalRead < 8 do begin
    BytesToRead := 8 - TotalRead;
    if not ReadFile(FPipeHandle, Header[TotalRead], BytesToRead, BytesRead, nil) then
      Exit;
    if BytesRead = 0 then
      Exit;
    Inc(TotalRead, BytesRead);
  end;

  Length := PInteger(@Header[4])^;
  if Length < 0 then
    Exit;

  SetLength(Data, Length);
  TotalRead := 0;
  while TotalRead < Length do begin
    BytesToRead := Length - TotalRead;
    if not ReadFile(FPipeHandle, Data[TotalRead], BytesToRead, BytesRead, nil) then
      Exit;
    if BytesRead = 0 then
      Exit;
    Inc(TotalRead, BytesRead);
  end;

  PayloadStr := TEncoding.UTF8.GetString(Data);
  if PayloadStr <> '' then
    Result := TJSONObject.ParseJSONValue(PayloadStr) as TJSONObject;
end;

procedure TDiscordRPC.Initialize;
var
  Handshake: TJSONObject;
  Payload: TJSONObject;
begin
  if not ConnectToPipe then begin
    OutputDebugString(PChar('RADcord: could not connect to Discord IPC pipe.'));
    raise Exception.Create('Could not connect to Discord IPC pipe.');
  end;

  // Send handshake
  Handshake := TJSONObject.Create;
  try
    Handshake.AddPair('v', TJSONNumber.Create(DISCORD_RPC_VERSION));
    Handshake.AddPair('client_id', FClientId);
    OutputDebugString(PChar('RADcord: sending Discord handshake with client ID ' + FClientId));
    if not SendPayload(Handshake, 0) then begin
      OutputDebugString(PChar('RADcord: handshake send failed.'));
      raise Exception.Create('Failed to send Discord handshake.');
    end;
  finally
    Handshake.Free;
  end;

  // Wait for ready event
  Payload := ReceivePayload;
  try
    if Assigned(Payload) then begin
      if Payload.GetValue<string>('evt', '') = 'READY' then begin
        FReady := True;
        OutputDebugString(PChar('Discord RPC ready.'));
      end
      else begin
        OutputDebugString(PChar('Discord RPC handshake reply: ' + Payload.ToJSON));
        raise Exception.Create('Discord RPC did not return READY.');
      end;
    end
    else begin
      OutputDebugString(PChar('Discord RPC handshake returned no payload.'));
      raise Exception.Create('Discord RPC handshake returned no payload.');
    end;
  finally
    Payload.Free;
  end;
end;

procedure TDiscordRPC.Shutdown;
begin
  if FReady then begin
    ClearPresence;
    FReady := False;
  end;

  if FPipeHandle <> INVALID_HANDLE_VALUE then begin
    CloseHandle(FPipeHandle);
    FPipeHandle := INVALID_HANDLE_VALUE;
  end;
end;

procedure TDiscordRPC.AddRef;
begin
  InterlockedIncrement(FRefCount);
end;

procedure TDiscordRPC.Release;
begin
  if InterlockedDecrement(FRefCount) = 0 then
    Free;
end;

procedure TDiscordRPC.UpdatePresence(const APresence: TDiscordRichPresence);
var
  Payload: TJSONObject;
  Args: TJSONObject;
  Activity: TJSONObject;
  Timestamps: TJSONObject;
  Assets: TJSONObject;
  Party: TJSONObject;
  Secrets: TJSONObject;
  Response: TJSONObject;
  Nonce: string;
begin
  if not FReady then begin
    OutputDebugString(PChar('RADcord: UpdatePresence called but RPC not ready. Details: ' + APresence.Details));
    Exit;
  end;

  OutputDebugString(
      PChar('RADcord: UpdatePresence preparing payload. State: ' + APresence.State + ' Details: ' + APresence.Details)
  );

  Payload := TJSONObject.Create;
  Args := TJSONObject.Create;
  Activity := TJSONObject.Create;
  Timestamps := TJSONObject.Create;
  try
    Payload.AddPair('cmd', 'SET_ACTIVITY');
    Payload.AddPair('args', Args);
    Args.AddPair('pid', TJSONNumber.Create(GetCurrentProcessId));
    Args.AddPair('activity', Activity);

    Nonce := GetNextNonce;
    Payload.AddPair('nonce', Nonce);

    if APresence.State <> '' then
      Activity.AddPair('state', APresence.State);

    if APresence.Details <> '' then
      Activity.AddPair('details', APresence.Details);

    if APresence.StartTimestamp > 0 then
      Timestamps.AddPair('start', TJSONNumber.Create(APresence.StartTimestamp));
    if APresence.EndTimestamp > 0 then
      Timestamps.AddPair('end', TJSONNumber.Create(APresence.EndTimestamp));
    if Timestamps.Count > 0 then
      Activity.AddPair('timestamps', Timestamps)
    else
      Timestamps.Free;

    if (APresence.LargeImageKey <> '')
        or (APresence.LargeImageText <> '')
        or (APresence.SmallImageKey <> '')
        or (APresence.SmallImageText <> '') then
    begin
      Assets := TJSONObject.Create;
      Activity.AddPair('assets', Assets);
      if APresence.LargeImageKey <> '' then
        Assets.AddPair('large_image', APresence.LargeImageKey);
      if APresence.LargeImageText <> '' then
        Assets.AddPair('large_text', APresence.LargeImageText);
      if APresence.SmallImageKey <> '' then
        Assets.AddPair('small_image', APresence.SmallImageKey);
      if APresence.SmallImageText <> '' then
        Assets.AddPair('small_text', APresence.SmallImageText);
    end;

    if (APresence.PartySize > 0) or (APresence.PartyMax > 0) then begin
      Party := TJSONObject.Create;
      Activity.AddPair('party', Party);
      Party.AddPair('size', TJSONNumber.Create(APresence.PartySize));
      Party.AddPair('max', TJSONNumber.Create(APresence.PartyMax));
    end;

    if (APresence.JoinSecret <> '') or (APresence.SpectateSecret <> '') or (APresence.MatchSecret <> '') then begin
      Secrets := TJSONObject.Create;
      Activity.AddPair('secrets', Secrets);
      if APresence.JoinSecret <> '' then
        Secrets.AddPair('join', APresence.JoinSecret);
      if APresence.SpectateSecret <> '' then
        Secrets.AddPair('spectate', APresence.SpectateSecret);
      if APresence.MatchSecret <> '' then
        Secrets.AddPair('match', APresence.MatchSecret);
    end;

    Activity.AddPair('instance', TJSONBool.Create(APresence.Instance));

    if not SendPayload(Payload, 1) then begin
      OutputDebugString(PChar('Failed to send Discord activity update.'));
      Exit;
    end;

    Response := ReceivePayload;
    try
      if Assigned(Response) then
        OutputDebugString(PChar('Discord activity response: ' + Response.ToJSON))
      else
        OutputDebugString(PChar('Discord activity update returned no response.'));
    finally
      Response.Free;
    end;
  finally
    Payload.Free;
  end;
end;

procedure TDiscordRPC.ClearPresence;
var
  Payload: TJSONObject;
  Args: TJSONObject;
begin

  if not FReady then
    Exit;

  Payload := TJSONObject.Create;

  Args := TJSONObject.Create;
  try
    Payload.AddPair('cmd', 'SET_ACTIVITY');
    Payload.AddPair('args', Args);
    Args.AddPair('pid', TJSONNumber.Create(GetCurrentProcessId));
    Args.AddPair('activity', TJSONNull.Create);
    if not SendPayload(Payload, 1) then begin
      OutputDebugString(PChar('Failed to clear Discord activity.'));
    end;
  finally
    Payload.Free;
  end;
end;

end.
