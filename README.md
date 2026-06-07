# DDrawCompat DelphiX Child-Window Clipping Example

This is a minimal Delphi 2007 / VCL repro for DirectDraw primary-surface presentation over native child windows.

The sample intentionally mirrors a common DelphiX windowed rendering path:

- A `TDXDraw` control is created as a child window of the main VCL form.
- DelphiX runs in windowed blit mode, not exclusive fullscreen flip mode.
- DelphiX creates a DirectDraw primary surface.
- DelphiX attaches an HWND clipper to the `TDXDraw.Handle`.
- Each frame draws to the offscreen surface and manually calls `Primary.Draw` to a screen-coordinate destination rectangle based on the parent form client area.
- Native sibling child HWNDs (`TEdit`, `TButton`, and `TMemo`) overlap the `TDXDraw` child window.
- The parent form is given `WS_CLIPCHILDREN | WS_CLIPSIBLINGS`.
- The `TDXDraw` child window is given `WS_CLIPSIBLINGS`.
- Stress mode is enabled by default. After each primary draw it forces sibling child HWND z-order and repaint timing, periodically hides/shows the `TEdit`, and updates its text.

## Build

Open `DDrawCompatDelphiXExample.dproj` in Delphi 2007 and build.

The project includes a local DelphiX copy under:

```text
DelphiX
```

This copy is intentionally kept inside the example so the repro can be moved to a standalone GitHub repository.

`DelphiX\DirectX.pas` contains a small Delphi 2007 compatibility adjustment:

- `NilGUID` is declared as an initialized constant instead of using the old `absolute 0` compatibility expression.
- `PDirectDrawSurface` is fixed to `Pointer`, matching the old DelphiX workaround for compilers that reject interface types inside variant records.

## Test Matrix

Build the EXE, then test by placing one of these next to the built executable:

- no wrapper, using the system `ddraw.dll`
- DDrawCompat `DDraw.dll`
- dgVoodoo2 `DDraw.dll` plus `dgVoodoo.conf`

Expected good behavior:

- The overlapping `TEdit`, `TButton`, and `TMemo` remain visible and stable.
- DirectDraw animation continues behind them without covering or flickering through the child controls.
- With stress mode enabled, the `TEdit` is intentionally hidden for a few frames every 120 frames. Apart from that deliberate pulse, child controls should remain stable.

Problem behavior:

- The native child windows flicker.
- Child controls disappear intermittently.
- DirectDraw primary blits cover the child controls.

The `Stress child HWND redraw` checkbox can be disabled at runtime to compare the same primary-draw path without forced child-window repaint pressure.

## Relevant DelphiX Calls

The relevant DelphiX implementation is in `DXDraws.pas`:

```pascal
FDXDraw.FClipper := TDirectDrawClipper.Create(FDXDraw.FDDraw);
FDXDraw.FClipper.Handle := FDXDraw.Handle;
FDXDraw.FPrimary.Clipper := FDXDraw.FClipper;
```

and each frame:

```pascal
FDXDraw.FPrimary.Blt(Dest, FDXDraw.FSurface.ClientRect, DDBLT_WAIT, df, FDXDraw.FSurface);
```

The sample then bypasses `TDXDraw.Flip` and performs a manual primary draw similar to older DelphiX clients:

```pascal
DestRect := ClientRect;
Windows.ClientToScreen(Handle, DestRect.TopLeft);
Windows.ClientToScreen(Handle, DestRect.BottomRight);
FDXDraw.Primary.Draw(DestRect.Left, DestRect.Top, FDXDraw.Surface.ClientRect,
  FDXDraw.Surface, False);
```

This means the repro is not using a custom clip-list clipper, but it does intentionally blit to a manually calculated screen-coordinate destination rectangle.
