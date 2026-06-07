program DDrawCompatDelphiXExample;

uses
  Forms,
  MainForm in 'MainForm.pas' {MainForm};

begin
  Application.Initialize;
  Application.Title := 'DDrawCompat DelphiX Example';
  Application.CreateForm(TMainForm, ExampleMainForm);
  Application.Run;
end.