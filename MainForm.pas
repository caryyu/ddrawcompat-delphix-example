unit MainForm;

interface

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms, StdCtrls,
  ExtCtrls, DXDraws;

type
  TMainForm = class(TForm)
  private
    FDXDraw: TDXDraw;
    FEdit: TEdit;
    FButton: TButton;
    FStressCheck: TCheckBox;
    FMemo: TMemo;
    FInfoLabel: TLabel;
    FTimer: TTimer;
    FFrame: Integer;
    procedure AddWindowStyles(AHandle: HWND; AStyles: Longint);
    procedure EnsureDirectDrawInitialized;
    procedure RenderTimer(Sender: TObject);
    procedure DrawFrame;
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
  AddWindowStyles(Handle, WS_CLIPCHILDREN or WS_CLIPSIBLINGS);

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
  FMemo := TMemo.Create(Self);
  FMemo.Parent := Self;
  FMemo.SetBounds(104, 132, 300, 76);
  FMemo.Lines.Text := 'Sibling TMemo'#13#10'If this flickers or disappears, child HWND clipping is not preserved.';
  FMemo.TabOrder := 3;
  FMemo.BringToFront;

  FInfoLabel := TLabel.Create(Self);
  FInfoLabel.Parent := Self;
  FInfoLabel.SetBounds(24, 404, 660, 72);
  FInfoLabel.AutoSize := False;
  FInfoLabel.WordWrap := True;
  FInfoLabel.Caption :=
    'This sample uses a DelphiX TDXDraw child window in windowed blit mode. ' +
    'DelphiX creates a DirectDraw primary surface, attaches an HWND clipper to the TDXDraw window, ' +
    'and this sample manually calls Primary.Draw to a screen-coordinate form client rect. Mild stress mode only brings sibling child HWNDs to front and invalidates them.';

  FTimer := TTimer.Create(Self);
  FTimer.Interval := 16;
  FTimer.OnTimer := RenderTimer;
  FTimer.Enabled := True;
end;

destructor TMainForm.Destroy;
begin
  if Assigned(FTimer) then
    FTimer.Enabled := False;
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

  SetWindowPos(FDXDraw.Handle, HWND_BOTTOM, 0, 0, 0, 0,
    SWP_NOMOVE or SWP_NOSIZE or SWP_NOACTIVATE);
  FEdit.BringToFront;
  FButton.BringToFront;
  FMemo.BringToFront;
end;

procedure TMainForm.RenderTimer(Sender: TObject);
begin
  try
    EnsureDirectDrawInitialized;
    DrawFrame;
  except
    on E: Exception do
    begin
      FTimer.Enabled := False;
      Caption := 'DirectDraw initialization/render failed: ' + E.ClassName + ': ' + E.Message;
    end;
  end;
end;

procedure TMainForm.DrawFrame;
var
  C: TCanvas;
  I: Integer;
  X: Integer;
  R: TRect;
  DestRect: TRect;
begin
  if not FDXDraw.Initialized then
    Exit;

  Inc(FFrame);
  C := FDXDraw.Surface.Canvas;
  try
    C.Brush.Color := RGB(8, 18, 28);
    C.FillRect(Rect(0, 0, FDXDraw.SurfaceWidth, FDXDraw.SurfaceHeight));

    for I := 0 to 11 do
    begin
      C.Brush.Color := RGB(20 + I * 12, 70 + (I mod 3) * 30, 120 + (I mod 4) * 20);
      X := ((FFrame * 3) + I * 72) mod 760 - 100;
      R := Rect(X, 38 + I * 22, X + 96, 58 + I * 22);
      C.FillRect(R);
    end;

    C.Brush.Style := bsClear;
    C.Font.Color := clWhite;
    C.Font.Size := 12;
    C.TextOut(28, 28, 'Manual Primary.Draw frame: ' + IntToStr(FFrame));
    C.TextOut(28, 300, 'This bypasses TDXDraw.Flip and blits to the form client rect in screen coordinates.');
    C.TextOut(28, 324, 'Mild stress mode calls BringToFront and Invalidate on sibling child HWNDs.');
    C.Brush.Style := bsSolid;
  finally
    FDXDraw.Surface.Canvas.Release;
  end;

  DestRect := ClientRect;
  Windows.ClientToScreen(Handle, DestRect.TopLeft);
  Windows.ClientToScreen(Handle, DestRect.BottomRight);
  FDXDraw.Primary.Draw(DestRect.Left, DestRect.Top, FDXDraw.Surface.ClientRect,
    FDXDraw.Surface, False);

  if FStressCheck.Checked then
    StressChildWindows;
end;

procedure TMainForm.StressChildWindows;
begin
  if (FFrame mod 180) = 0 then
    FEdit.Text := Format('Sibling TEdit mild stress frame %d', [FFrame]);

  FEdit.BringToFront;
  FButton.BringToFront;
  FStressCheck.BringToFront;
  FMemo.BringToFront;

  FEdit.Invalidate;
  FButton.Invalidate;
  FStressCheck.Invalidate;
  FMemo.Invalidate;
end;

procedure TMainForm.WMEraseBkgnd(var Message: TWMEraseBkgnd);
begin
  Message.Result := 1;
end;

end.