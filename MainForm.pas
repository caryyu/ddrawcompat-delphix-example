unit MainForm;

interface

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms, StdCtrls,
  ExtCtrls, DirectX, DXDraws;

type
  TMainForm = class(TForm)
  private
    FDXDraw: TDXDraw;
    FEdit: TEdit;
    FButton: TButton;
    FStressCheck: TCheckBox;
    FPrimaryClipperCheck: TCheckBox;
    FMemo: TMemo;
    FInfoLabel: TLabel;
    FFrame: Integer;
    FPrimaryClipperApplied: Integer;
    procedure AddWindowStyles(AHandle: HWND; AStyles: Longint);
    procedure EnsureDirectDrawInitialized;
    procedure ApplyPrimaryClipperSetting;
    procedure ApplicationIdle(Sender: TObject; var Done: Boolean);
    procedure DrawFrame;
    procedure DrawFrameToSurfaceViaLock;
    procedure PresentToPrimary;
    procedure StressChildWindows;
    procedure WMEraseBkgnd(var Message: TWMEraseBkgnd); message WM_ERASEBKGND;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

var
  ExampleMainForm: TMainForm;

implementation

constructor TMainForm.Create(AOwner: TComponent);
begin
  inherited CreateNew(AOwner);

  Caption := 'DDrawCompat DelphiX child-window clipping repro';
  Position := poScreenCenter;
  ClientWidth := 720;
  ClientHeight := 520;
  Color := clBtnFace;
  Font.Name := 'Tahoma';
  Font.Size := 9;
  DoubleBuffered := False;
  HandleNeeded;
  AddWindowStyles(Handle, WS_CLIPSIBLINGS);

  FDXDraw := TDXDraw.Create(Self);
  FDXDraw.Parent := Self;
  FDXDraw.AutoInitialize := False;
  FDXDraw.AutoSize := False;
  FDXDraw.SurfaceWidth := 640;
  FDXDraw.SurfaceHeight := 360;
  FDXDraw.Options := [doDirectX7Mode, doSystemMemory, doStretch];
  FDXDraw.SetBounds(24, 24, 640, 360);
  FDXDraw.Color := clBlack;
  FDXDraw.HandleNeeded;
  AddWindowStyles(FDXDraw.Handle, WS_CLIPSIBLINGS);

  FEdit := TEdit.Create(Self);
  FEdit.Parent := Self;
  FEdit.SetBounds(104, 84, 300, 24);
  FEdit.Text := 'Sibling TEdit over DirectDraw primary blits';
  FEdit.TabOrder := 0;
  FEdit.BringToFront;

  FButton := TButton.Create(Self);
  FButton.Parent := Self;
  FButton.SetBounds(440, 82, 150, 28);
  FButton.Caption := 'Sibling Button';
  FButton.TabOrder := 1;
  FButton.BringToFront;

  FStressCheck := TCheckBox.Create(Self);
  FStressCheck.Parent := Self;
  FStressCheck.SetBounds(440, 130, 190, 24);
  FStressCheck.Caption := 'Stress child HWND redraw';
  FStressCheck.Checked := True;
  FStressCheck.TabOrder := 2;
  FStressCheck.BringToFront;

  FPrimaryClipperCheck := TCheckBox.Create(Self);
  FPrimaryClipperCheck.Parent := Self;
  FPrimaryClipperCheck.SetBounds(440, 156, 220, 24);
  FPrimaryClipperCheck.Caption := 'Use primary HWND clipper';
  FPrimaryClipperCheck.Checked := False;
  FPrimaryClipperCheck.TabOrder := 3;
  FPrimaryClipperCheck.BringToFront;

  FMemo := TMemo.Create(Self);
  FMemo.Parent := Self;
  FMemo.SetBounds(104, 132, 300, 76);
  FMemo.Lines.Text := 'Sibling TMemo'#13#10'If this flickers or disappears, child HWND clipping is not preserved.';
  FMemo.TabOrder := 4;
  FMemo.BringToFront;

  FInfoLabel := TLabel.Create(Self);
  FInfoLabel.Parent := Self;
  FInfoLabel.SetBounds(24, 400, 660, 100);
  FInfoLabel.AutoSize := False;
  FInfoLabel.WordWrap := True;
  FInfoLabel.Caption :=
    'Rendering via Surface.Lock/Unlock + Primary.Draw in OnIdle (no frame cap). ' +
    'Present target intentionally uses FORM ClientToScreen + ClientRect (wider overdraw test). ' +
    'Parent keeps WS_CLIPSIBLINGS only (no WS_CLIPCHILDREN). ' +
    'Stress mode does not force child repaint; this helps reproduce persistent text overdraw. ' +
    'Toggle "Use primary HWND clipper" at runtime for A/B test.';

  FFrame := 0;
  FPrimaryClipperApplied := -1;

  Application.OnIdle := ApplicationIdle;
end;

destructor TMainForm.Destroy;
begin
  Application.OnIdle := nil;
  if Assigned(FDXDraw) then
    FDXDraw.Finalize;
  inherited Destroy;
end;

procedure TMainForm.AddWindowStyles(AHandle: HWND; AStyles: Longint);
var
  Style: Longint;
begin
  if AHandle = 0 then
    Exit;

  Style := GetWindowLong(AHandle, GWL_STYLE);
  if (Style and AStyles) <> AStyles then
  begin
    SetWindowLong(AHandle, GWL_STYLE, Style or AStyles);
    SetWindowPos(AHandle, 0, 0, 0, 0, 0,
      SWP_NOMOVE or SWP_NOSIZE or SWP_NOZORDER or SWP_NOACTIVATE or SWP_FRAMECHANGED);
  end;
end;

procedure TMainForm.EnsureDirectDrawInitialized;
begin
  if FDXDraw.Initialized then
    Exit;

  FDXDraw.Initialize;
  ApplyPrimaryClipperSetting;

  SetWindowPos(FDXDraw.Handle, HWND_BOTTOM, 0, 0, 0, 0,
    SWP_NOMOVE or SWP_NOSIZE or SWP_NOACTIVATE);
  FEdit.BringToFront;
  FButton.BringToFront;
  FMemo.BringToFront;
end;

procedure TMainForm.ApplyPrimaryClipperSetting;
var
  WantedState: Integer;
begin
  if not FDXDraw.Initialized then
    Exit;

  if FPrimaryClipperCheck.Checked then
    WantedState := 1
  else
    WantedState := 0;

  if WantedState = FPrimaryClipperApplied then
    Exit;

  if WantedState <> 0 then
    FDXDraw.Primary.Clipper := FDXDraw.Clipper
  else
    FDXDraw.Primary.Clipper := nil;

  FPrimaryClipperApplied := WantedState;
end;

procedure TMainForm.ApplicationIdle(Sender: TObject; var Done: Boolean);
begin
  try
    EnsureDirectDrawInitialized;
    DrawFrame;
  except
    on E: Exception do
    begin
      Application.OnIdle := nil;
      Caption := 'DirectDraw initialization/render failed: ' + E.ClassName + ': ' + E.Message;
    end;
  end;
  Done := False;
end;

procedure TMainForm.DrawFrame;
begin
  if not FDXDraw.Initialized then
    Exit;

  Inc(FFrame);

  ApplyPrimaryClipperSetting;
  DrawFrameToSurfaceViaLock;
  PresentToPrimary;

  if FStressCheck.Checked then
    StressChildWindows;
end;

procedure TMainForm.DrawFrameToSurfaceViaLock;
var
  ddsd: TDDSurfaceDesc;
  Row, Col, I, BarX: Integer;
  Pitch: Integer;
  Bits: Pointer;
  LinePtr: PByte;
  PixelColor: Word;
  FillRect: TRect;
begin
  ddsd.dwSize := SizeOf(ddsd);
  FillRect := Rect(0, 0, FDXDraw.SurfaceWidth, FDXDraw.SurfaceHeight);
  if not FDXDraw.Surface.Lock(FillRect, ddsd) then
    Exit;

  try
    if ddsd.ddpfPixelFormat.dwRGBBitCount <> 16 then
      Exit;

    Pitch := ddsd.lPitch;
    Bits := ddsd.lpSurface;

    for Row := 0 to FDXDraw.SurfaceHeight - 1 do
    begin
      LinePtr := PByte(Integer(Bits) + Row * Pitch);
      for Col := 0 to FDXDraw.SurfaceWidth - 1 do
        PWord(Integer(LinePtr) + Col * 2)^ := Word($121C);
    end;

    for I := 0 to 11 do
    begin
      BarX := ((FFrame * 3) + I * 72) mod 760 - 100;
      if BarX + 96 > 0 then
      begin
        PixelColor := Word(((20 + I * 12) and $1F) shl 11) or
                       Word(((70 + (I mod 3) * 30) and $3F) shl 5) or
                       Word((120 + (I mod 4) * 20) and $1F);
        for Row := 38 + I * 22 to 57 + I * 22 do
        begin
          if (Row >= 0) and (Row < FDXDraw.SurfaceHeight) then
          begin
            LinePtr := PByte(Integer(Bits) + Row * Pitch);
            for Col := BarX to BarX + 95 do
            begin
              if (Col >= 0) and (Col < FDXDraw.SurfaceWidth) then
                PWord(Integer(LinePtr) + Col * 2)^ := PixelColor;
            end;
          end;
        end;
      end;
    end;
  finally
    FDXDraw.Surface.UnLock;
  end;
end;

procedure TMainForm.PresentToPrimary;
var
  DestRect: TRect;
begin
  DestRect := ClientRect;
  Windows.ClientToScreen(Handle, DestRect.TopLeft);
  Windows.ClientToScreen(Handle, DestRect.BottomRight);

  FDXDraw.Primary.Draw(DestRect.Left, DestRect.Top, FDXDraw.Surface.ClientRect,
    FDXDraw.Surface, False);
end;

procedure TMainForm.StressChildWindows;
begin
  if (FFrame mod 120) = 0 then
    FStressCheck.Caption := Format('Stress active (%d)', [FFrame]);
end;

procedure TMainForm.WMEraseBkgnd(var Message: TWMEraseBkgnd);
begin
  Message.Result := 1;
end;

end.