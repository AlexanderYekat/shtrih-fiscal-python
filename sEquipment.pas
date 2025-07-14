unit sEquipment;
                                      
interface

uses
  Windows, Forms, ComObj, IniFiles, Classes, SysUtils, CPort, libmerc, System.JSON,
  System.Net.HttpClient, System.NetEncoding;

type

  TApiResponse = record
    //Code: Integer;
    Code: String;
    Error: string;
    Description: string;
    ReqId: string;
    //ReqTimestamp: Int64;
    ReqTimestamp: string;
  end;

  Trs232ScanBar = class(TComponent)
    public
      sc1Prefix: string;
      sc1Suffix: string;
      sc1Data: string;
      cpCom1: TComPort;
      cfcCom1: TComFlowControl;
      InitOk: Bool;
      constructor Create(AOwner: TComponent); override;
      destructor Destroy; override;
  end;

  TServicePrint = class(TComponent)
    public
      ovObject: OLEVariant;
      LineLength: Byte;
      WideLineLen: Byte;
      InitOk: Bool;
      constructor Create(AOwner: TComponent); override;
      destructor Destroy; override;
      function Setup(SvrIP:string; SvrPort, Port, Baud: Word; Beep: Bool): Bool;
      function CheckFRResult(sOption: string): Bool;
      function FeedPaper(iLines: Byte): Bool;
      function PrintString(sLine: string): Bool;
      function PrintWideString(sLine: string): Bool;
  end;

  TVariantPrint = class(TComponent)
    private
      FCashierName:string; //фамилия кассира
    public
      ovObject: OLEVariant;
      ocObject: TocMercury;
      FsModel: string;
      LineLength: Byte;
      WideLineLen: Byte;
      Tax1: Byte;
      InitOk: Bool;
      iLastNDoc: Integer;
      Change: Currency;
      ifSetup: TIniFile;
      IV: Integer;   // Mercury ONLY
      bIsFisc: Bool; // Mercury ONLY
      iLastDepartment: Integer;
//      slDepart2Tax: TStrings;
//      baTaxType: array of byte;
      //DocIsActive: Bool;
      constructor Create(AOwner: TComponent; sModel: string); virtual;
      destructor Destroy; override;
      function Setup(ifMain: TIniFile): Bool;
      function CheckFRResult(sOption: string): Bool;
      function CheckFRStateBegin: Bool;
      function CheckFRAdvancedMode(wTimeOut: Word; sCheckSection: string): Bool;
      procedure CancelDoc;
      function DrawImage: Bool;
      function OpenDrawer: Bool;
      function Cut: Bool;
      function FeedPaper(iLines: Byte): Bool;
      function Continue: Bool;
      function OpenSession(sSysOpNm: string): Bool;
      function MSPrintTitle(sLine: string; bSubType: Byte): Bool;
      function MMSKPrintTitle(sLine: string; SubType: Byte): Bool;
      property CashierName:string read FCashierName write FCashierName;
      function PrintString(sLine: string): Bool;
      function PrintWideString(sLine: string): Bool;
      function IsFFD12():boolean;
      function PrintQRCode(text:string):bool;
      function ParsMarka(marka:string; var gtin:string; var serial:string; var tail:string):boolean;
      function CheckMarkRR(addressService:string; MarkingCodeDurty:string):TApiResponse;
      function CheckMarkOnServer(returnCheck:boolean; matrix, gtin, serial, tail:string):integer;
      function Sale(returnCheck:boolean; sLine: string; cQty: Currency; cPrice: Currency; iDepartment, iTaxIx: Integer;
                    datamatrix, gtin, serial, tail:string; excise:boolean; sno:integer; Validation_result:integer;
                    VersFFD12:boolean; rrRes:TApiResponse): Bool;
      function SaleCredit(sLine: string; cQty: Currency; cPrice: Currency): Bool;
      function ReturnSale(sLine: string; cQty: Currency; cPrice: Currency; iDepartment,
                          iTaxIx: Integer; datamatrix, gtin, serial, tail:string; excise:boolean; sno:integer): Bool;
      function CloseCheck(sLine: string; cSum: Currency; cExact: Currency; TPayment, Tax: Integer): Bool;
//      function CloseCheck(sLine: string; cSum: Currency; cExact: Currency; bSaleCredit: Bool): Bool;
      function CashIncome(sLine: string; cSum: Currency): Bool;
      function CashOutcome(sLine: string; cSum: Currency): Bool;
      function Report(bClearing:Bool): Bool;
      function DReport(bClearing:Bool): Bool;
      function GetDocIsActive: Bool; // MMSKVCL ONLY, all another is always true
      function DepartReport(): Bool;
      function FNSendCustomerTel(sLine: string): Bool;
      function FNSendCustomerEml(sLine: string): Bool;
      function FNSendCustomerINN(sLine: string): Bool;
      function FNSendCashFam(sLine: string): Bool;
      function FNSendCustomerNm(sLine: string): Bool;
      function WaitForPrinting(): Bool;
  end;

implementation

uses sMF, sDM, hUsrAuth, sSF;


{*******************************************************************************}
{                               PRINT EQUIPMENT                                 }
{*******************************************************************************}

constructor TVariantPrint.Create(AOwner: TComponent; sModel: string);
begin
  inherited Create(AOwner);

  InitOk := False;
  FsModel := sModel;

  if sModel = 'Shtrih' then begin
     try
       ovObject := CreateOleObject('AddIn.DrvFR');
     finally
       InitOk := True;
     end;
  end;
end;

function TVariantPrint.CheckFRResult(sOption: string): Bool;
var sResMsg, sResMsg2: string;
    //receiptType:integer;
begin

  CheckFRResult := False;

  if Assigned(ocObject) then begin
     if (ocObject.ResultCode <> 0) then begin
        sResMsg := IntToStr(ocObject.ResultCode) + sOption + ocObject.ResultCodeDescription;
        sResMsg2 := '';
        WriteLogFile(sResMsg + ' :: ' + sResMsg2);
        sfMF.AddSingleResultEvent(57, 41, sResMsg, sResMsg2);
     end else
        CheckFRResult := True;
     Exit;
  end;

  if (ovObject.ResultCode <> 0) then begin

     sResMsg := IntToStr(ovObject.ResultCode) + sOption;

     if (FsModel = 'Shtrih') then begin
       sResMsg := sResMsg + ovObject.ResultCodeDescription;
       sResMsg2 := ovObject.ECRModeDescription + ' :: ' + ovObject.ECRAdvancedModeDescription;
     end;

  end else
     CheckFRResult := True;
end;

function TVariantPrint.Setup(ifMain: TIniFile): Bool;
  const sOption: string = ':: FRSetup ::';
  var i: Integer;
      ComIsIP:boolean;
      baudRate, resBoudRate:integer;
begin
  Setup := False;
  ifSetup := ifMain;
  bIsFisc := False;
  ComIsIP:=false;

  if (FsModel = 'Shtrih') then begin
     LineLength := 36;
     WideLineLen := 18;
     try
       ovObject.ComNumber := ifMain.ReadInteger('FRCash', 'Port', 1);
       ovObject.BaudRate  := ifMain.ReadInteger('FRCash', 'Baud', 5);
       ovObject.Password  := ifMain.ReadInteger('FRCash', 'Password', 30);
       ovObject.Connect;
       ovObject.Beep;
     finally
       sleep(100);
       if CheckFRResult(sOption) then
          Setup := True;
     end;

  end;

end;

function TVariantPrint.CheckFRStateBegin: Bool;
const sOption: string = ':: CheckFRState ::';
var sUserQuestion: string;
begin

  Result := False;

  if (FsModel = 'Shtrih') then begin

     while Result = False do begin

       try
         ovObject.GetECRStatus;
       finally
         CheckFRResult(sOption);
       end;

       if ovObject.ECRMode = 8 then begin
          sUserQuestion := 'Печать нового документа невозможна.'#$D#$A +
                           'Состояние ФР:' + ovObject.ECRModeDescription +
                           '/' + ovObject.ECRAdvancedModeDescription + #$D#$A +
                           'Вероятно, для продолжения необходимо отменить'#$D#$A +
                           'предыдущий незавершенный документ.';
          if Application.MessageBox(PChar(sUserQuestion), 'Предупреждение ФР', $30 + MB_OKCANCEL) = idOk then begin
             try
               ovObject.CancelCheck;
             finally
               CheckFRResult(':: CancelCheck inside CheckResult ::');
               Result := True;
             end;
          end else begin
             Break;
          end;
       end else begin
         Result := True;
       end; // if

     end; // while

  end; // FsModel Shtrih

end; // proc

function TVariantPrint.CheckFRAdvancedMode(wTimeOut: Word; sCheckSection: string): Bool;
var
  sUserQuestion: string;
  receiptType:integer;
begin
  Result := False;

  if (FsModel = 'Shtrih') then begin

     while Result = False do begin

       CheckFRResult('::' + sCheckSection + '::');

       sleep(wTimeOut);

       Application.ProcessMessages;

       ovObject.GetECRStatus;

       case ovObject.ECRMode of
         3: begin
              sUserQuestion := 'Печать документа невозможна.'#$D#$A +
                               'Состояние ФР:' + ovObject.ECRModeDescription + #$D#$A +
                               'Для продолжения работы необходимо закрыть смену.';
              Application.MessageBox(PChar(sUserQuestion), 'Ошибка ФР', $10);
              Break;
            end;
         5, 6, 7, 9, 10:
            begin
              sUserQuestion := 'Печать документа невозможна.'#$D#$A +
                               'Состояние ФР:' + ovObject.ECRModeDescription + #$D#$A +
                               'Вероятно, необходим вызов технического специалиста.';
              Application.MessageBox(PChar(sUserQuestion), 'Ошибка ФР', $10);
              Break;
            end;
       end;

       case ovObject.ECRAdvancedMode of
         0: Result := True;
       1,2: begin
             sUserQuestion := 'Печать документа приостановлена.'#$D#$A +
                              'Состояние ФР:' + ovObject.ECRAdvancedModeDescription + #$D#$A +
                              'Для продолжения необходимо устранить'#$D#$A +
                              'неисправность, затем нажать "продолжить"';
             if Application.MessageBox(PChar(sUserQuestion), 'Предупреждение ФР', $30 + MB_RETRYCANCEL) = idRetry then begin
                try
                  ovObject.ContinuePrint;
                finally
                  CheckFRResult(':: ContPrint inside CheckAdvMode ::');
   //               Result := True;
                end;
             end else begin
                Break;
             end;
            end; // if
         3: try
              ovObject.ContinuePrint;
            finally
              CheckFRResult(':: ContPrint inside CheckAdvMode ::');
              Result := True;
            end;
       end; // case

     end; // while

  end; // FsModel Shtrih

end; // proc


procedure TVariantPrint.CancelDoc;
const sOption: string = ':: CancelDoc ::';
var bCashErr: Bool;
begin

  if (FsModel = 'Shtrih') then begin
     try
       ovObject.CancelCheck;
     finally
     end;
     if not CheckFRAdvancedMode(100, sOption) then
        Exit;
  end;

end;

function TVariantPrint.DrawImage: Bool;
begin
  DrawImage := False;

  if (FsModel = 'Shtrih') then begin
     try
       ovObject.FirstLineNumber := 1;
       ovObject.LastLineNumber := 64;
       ovObject.Draw;
     finally
       DrawImage := True;
     end;
  end;

end;

function TVariantPrint.OpenDrawer: Bool;
begin
  OpenDrawer := False;

  if (FsModel = 'Shtrih') then begin
     try
       ovObject.OpenDrawer;
     finally
       OpenDrawer := True;
     end;
  end;
end;

function TVariantPrint.Continue: Bool;
begin
  Continue := False;

  if (FsModel = 'Shtrih') then begin
     try
       ovObject.ContinuePrint;
     finally
       sfMF.AddSingleResultEvent(54, 56, 'Печать продолжена после ошибки.', '');
     end;

     if not CheckFRAdvancedMode(100, 'ContPrint') then                         // проверка обрыв бумаги
       Exit;
  end;

  Continue := True;
end;

function TVariantPrint.OpenSession(sSysOpNm: string): Bool;
const sOption: string = ':: Open Session ::';
begin
  WriteLogFile('OpenSession+');
  OpenSession := False;
  if (FsModel = 'Shtrih') then begin
     try
       ovObject.TableNumber := 2;
       ovObject.FieldNumber := 2;
       ovObject.RowNumber := 30;
       ovObject.ValueOfFieldString := sSysOpNm;
       ovObject.WriteTable;
     finally
       sfMF.AddSingleResultEvent(54, 56, 'Задано имя оператора.', '');
     end;

     try
       ovObject.TableNumber := 1;
       ovObject.FieldNumber := 6;
       ovObject.RowNumber := 1;
       ovObject.ValueOfFieldInteger := 0; //не открываем денежный ящик
       ovObject.WriteTable;
     finally
       sfMF.AddSingleResultEvent(54, 56, 'Не октрываем денежный ящик автоматически.', '');
     end;

     try
       ovObject.OpenSession;
     finally
       sfMF.AddSingleResultEvent(54, 56, 'Смена открыта.', '');
     end;

     if not CheckFRAdvancedMode(100, 'ContPrint') then                         // проверка обрыв бумаги
       Exit;
  end;
  WriteLogFile('OpenSession-');
end;

function TVariantPrint.PrintQRCode(text:string):bool;
begin
 if (FsModel = 'Shtrih') then begin
  ovObject.BarcodeType:=3; //QR-код
  ovObject.BarCode:=text;
  ovObject.BarcodeStartBlockNumber:=0;
  ovObject.BarcodeParameter1:=0; //версия - авто
  ovObject.BarcodeParameter1:=4; //размер точки
  ovObject.BarcodeParameter1:=3; //Уровень коррекции ошибок, 0-3
  ovObject.LoadAndPrint2DBarcode;
  WriteLogFile('Результат печати QR-кода:' + ' :: ' + ovObject.ResultCodeDescription);
  ovObject.WaitForPrinting;
  ovObject.StringQuantity:=10; //количество строк на которое подвинуть чек
  ovObject.FeedDocument;
  ovObject.CutType:=2;
  ovObject.CutCheck;
 end;
end; //TVariantPrint.PrintQRCode


function TVariantPrint.Sale(returnCheck:boolean; sLine: string; cQty: Currency; cPrice: Currency; iDepartment, iTaxIx: Integer;
                            datamatrix, gtin, serial, tail:string; excise:boolean; sno:integer; Validation_result:integer;
                            VersFFD12:boolean; rrRes:TApiResponse): Bool;
const sOption: string = ':: Sale ::';
var
 receiptType, shiftState:integer;
 tag1162:  Variant;
 //VersFFD12:boolean;
 MarkParsed:string;
 PredmRasch, pos92, tagID:integer;
 strUUIDandTime:string;
 rrUUIDTime:Variant;
begin
  Sale := False;
  if cQty <= 0 then begin
     Sale := True;
     Exit;
  end;

  if (FsModel = 'Shtrih') then begin
     try
       if not(returnCheck) then
        ovObject.CheckType := 0 //ошибка было 1, должно быть 0 исправлено 20220813 // ffd 1.05
       else
        ovObject.CheckType := 2;
       //ovObject.OpenCheck := 1;                                                // ffd 1.05

       //ovObject.TagNumber := 1021;
       //ovObject.TagType := 7;
       //ovObject.TagValueStr := 'Кассир какой-то';
       //ovObject.FNSendTag;

       //Drv.Summ1Enabled := True; - самостоятельный расчет суммы
       ovObject.StringForPrinting := sLine;
       ovObject.Quantity   := cQty;
       ovObject.Price      := cPrice;
       ovObject.Department := iDepartment;
       iLastDepartment := iDepartment;
       ovObject.Tax1 := iTaxIx;
       ovObject.Tax2 := 0;
       ovObject.Tax3 := 0;
       ovObject.Tax4 := 0;
       ovObject.PaymentTypeSign := 4;                                          // ffd 1.05 (полный расчёт)

       PredmRasch:=1;
       ovObject.PaymentItemSign := PredmRasch;

       try
        ovObject.MeasureUnit:=0;
       except
       end;
       ovObject.FNOperation;

     finally
       if CheckFRAdvancedMode(100, sOption) then                      // проверка обрыв бумаги ?????
          Sale := True;
     end;
  end;

end; //sale

function TVariantPrint.ReturnSale(sLine: string; cQty: Currency; cPrice: Currency; iDepartment, iTaxIx: Integer;
                                  datamatrix, gtin, serial, tail:string; excise:boolean; sno:integer): Bool;
const sOption: string = ':: ReturnSale ::';
var receiptType:integer;
    tag1162:  Variant;
begin
  ReturnSale := False;
  if cQty <= 0 then begin
     ReturnSale := True;
     Exit;
  end;
  if (FsModel = 'Shtrih') then begin
     try
       ovObject.CheckType := 2;                                                // ffd 1.05
       ovObject.StringForPrinting := sLine;
       ovObject.Quantity   := cQty;
       ovObject.Price      := cPrice;
       ovObject.Department := iDepartment;
       ovObject.Tax1 := iTaxIx;
       ovObject.Tax2 := 0;
       ovObject.Tax3 := 0;
       ovObject.Tax4 := 0;
       ovObject.PaymentTypeSign := 4;                                          // ffd 1.05 (полный расчёт)
       //ovObject.PaymentItemSign := 1;                                          // ffd 1.05 (товар)
       ovObject.PaymentItemSign := 1                                          // ffd 1.05 (товар)
       ovObject.FNOperation;                                                   // ffd 1.05 (CheckType==1 => sale)
     finally
       if CheckFRAdvancedMode(100, sOption) then                      // проверка обрыв бумаги ?????
          ReturnSale := True;
     end;
  end;

end;

//function TVariantPrint.CloseCheck(sLine: string; cSum: Currency; cExact: Currency; bSaleCredit: Bool): Bool;
function TVariantPrint.CloseCheck(sLine: string; cSum: Currency; cExact: Currency; TPayment, Tax: Integer): Bool;
const sOption: string = ':: CloseCheck ::';
      saLocalParams: array[0..3] of string = ('RcHeader1','RcHeader2','RcHeader3','RcHeader4');
var sTemp: string;
    iCounter: Integer;
    tryOk: Bool;
    openDrawerB:boolean;
begin
  CloseCheck := False;

  openDrawerB:=false;
  if TPayment <= 1 then openDrawerB:=true;

  if (FsModel = 'Shtrih') then begin
     try                                                                       // Подытог
       ovObject.CheckSubTotal;
     finally
     end;

     if not CheckFRResult(':: CheckSubTotals inside CloseCheck ::') then
        Exit;

     try
       ovObject.StringForPrinting := '';
       ovObject.Summ1 := 0; ovObject.Summ2 := 0; ovObject.Summ3 := 0; ovObject.Summ4 := 0;
       ovObject.Summ5 := 0; ovObject.Summ6 := 0; ovObject.Summ7 := 0; ovObject.Summ8 := 0;
       ovObject.Summ9 := 0; ovObject.Summ10 := 0; ovObject.Summ11 := 0; ovObject.Summ12 := 0;
       ovObject.Summ13 := 0; ovObject.Summ14 := 0; ovObject.Summ15 := 0; ovObject.Summ16 := 0;
       case TPayment of
          0,1: ovObject.Summ1 := cSum;
          2: ovObject.Summ2 := cSum;
          3: ovObject.Summ3 := cSum;
          4: ovObject.Summ4 := cSum;
       end;
       ovObject.DiscountOnCheck := 0;
       ovObject.TaxValue1 := 0;
       ovObject.TaxValue2 := 0;
       ovObject.TaxValue3 := 0;
       ovObject.TaxValue4 := 0;
       ovObject.TaxValue5 := 0;
       ovObject.TaxValue6 := 0;

       ovObject.TaxType := ifSetup.ReadInteger('TaxType', IntToStr(iLastDepartment), 1);
       ovObject.FNCloseCheckEx;                                                // ffd 1.05
       if openDrawerB then
         OpenDrawer;
     finally
       if CheckFRAdvancedMode(100, sOption) then begin                         // проверка обрыв бумаги ?????
          iLastNDoc := ovObject.OpenDocumentNumber;
          CloseCheck := True;
       end;
     end;
  end;

end;

function TVariantPrint.FNSendCustomerTel(sLine: string): Bool;
const sOption: string = ':: CustomerTel ::';
begin
  FNSendCustomerTel := False;

  if (FsModel = 'Shtrih') then begin

     try
       ovObject.CustomerEmail := sLine;
       ovObject.FNSendCustomerEmail;
       ovObject.AttrNumber := 1008;
       ovObject.WriteAttribute;
     finally
     end;

     if not CheckFRResult(sOption) then
        Exit;

     FNSendCustomerTel := True;
  end;
end;

function TVariantPrint.FNSendCustomerEml(sLine: string): Bool;
const sOption: string = ':: CustomerEml ::';
begin
  FNSendCustomerEml := False;

  if (FsModel = 'Shtrih') then begin

     try
       ovObject.CustomerEmail := sLine;
       ovObject.FNSendCustomerEmail;
     finally
     end;

     if not CheckFRResult(sOption) then
        Exit;

     FNSendCustomerEml := True;
  end;
end;

function TVariantPrint.FNSendCustomerINN(sLine: string): Bool;
const sOption: string = ':: CustomerINN ::';
begin
  FNSendCustomerINN := False;

  if (FsModel = 'Shtrih') then begin

     try
       ovObject.TagNumber := 1228;
       ovObject.TagType := 7;
       ovObject.TagValueStr := sLine;
       ovObject.FNSendTag;
     finally
     end;

     if not CheckFRResult(sOption) then
        Exit;

     FNSendCustomerINN := True;
  end;
end;

function TVariantPrint.FNSendCashFam(sLine: string): Bool;
const sOption: string = ':: Cashir ::';
begin
  FNSendCashFam := False;

  if (FsModel = 'Shtrih') then begin

     try
       ovObject.TagNumber := 1021;
       ovObject.TagType := 7;
       ovObject.TagValueStr := sLine;
       ovObject.FNSendTag;
     finally
     end;

     if not CheckFRResult(sOption) then
        Exit;

     FNSendCashFam := True;
  end;
end;


function TVariantPrint.FNSendCustomerNm(sLine: string): Bool;
const sOption: string = ':: CustomerNm ::';
begin
  FNSendCustomerNm := False;

  if (FsModel = 'Shtrih') then begin

     try
       ovObject.TagNumber := 1227;
       ovObject.TagType := 7;
       ovObject.TagValueStr := sLine;
       ovObject.FNSendTag;
     finally
     end;

     if not CheckFRResult(sOption) then
        Exit;

     FNSendCustomerNm := True;
  end;
end;

function TVariantPrint.CashIncome(sLine: string; cSum: Currency): Bool;
const sOption: string = ':: CashIncome ::';
var bCloseErr: Bool;
begin
  CashIncome := False;
  WriteLogFile('CashIncome+');

  if (FsModel = 'Shtrih') then begin

     if not PrintString(sLine) then
        Exit;

     if not PrintString('Внутренняя трансляция "Сейф"-"Касса"') then
        Exit;

     try
       ovObject.Summ1 := cSum;
       ovObject.CashIncome;
     finally
     end;

     if not CheckFRResult(sOption) then
        Exit;

     iLastNDoc := ovObject.OpenDocumentNumber + 1;

     CashIncome := True;
  end;

  WriteLogFile('CashIncome+');

end;

function TVariantPrint.CashOutcome(sLine: string; cSum: Currency): Bool;
const sOption: string = ':: CashOutcome ::';
var bCloseErr: Bool;
begin
  CashOutcome := False;
  WriteLogFile('CashOutcome+');

  if (FsModel = 'Shtrih') then begin

     if not PrintString(sLine) then
        Exit;

     if not PrintString('Внутренняя трансляция "Касса"-"Сейф"') then
        Exit;

     try
       ovObject.Summ1 := cSum;
       ovObject.CashOutcome;
     finally
     end;

     if not CheckFRResult(sOption) then
        Exit;

     iLastNDoc := ovObject.OpenDocumentNumber + 1;

     CashOutcome := True;
  end;
  WriteLogFile('CashOutcome+');
end;

function TVariantPrint.Report(bClearing:Bool): Bool;
var stateSm:integer;
begin
  Report := False;
  WriteLogFile('Report+');
  if bClearing then begin

    if (FsModel = 'Shtrih') then begin
       try
         ovObject.PrintReportWithCleaning;
       finally
         Sleep(300);
       end;

       if not CheckFRResult(':: Z-REPORT ::') then
          Exit;

       Report := True;
    end;

    if (FsModel = 'MStar') then begin
       try
         ovObject.PrintReportWithCleaning;
       finally
         Sleep(300);
       end;

       if not CheckFRResult(':: Z-REPORT ::') then
          Exit;

       Report := True;
    end;
end;



function TVariantPrint.GetDocIsActive: Bool; // MMSKVCL ONLY, all another is always true
begin
  if Assigned(ocObject) then
     GetDocIsActive := ocObject.DocIsActive
  else
     GetDocIsActive := True;
end;

function TVariantPrint.DepartReport(): Bool;
begin
  DepartReport := false;
  if FsModel = 'Shtrih' then begin
    try
      ovObject.PrintDepartmentReport;
    finally
      sleep(100);
    end;
    if not CheckFRResult(':: D-REPORT ::') then
       Exit;
  end;
end;

function TVariantPrint.WaitForPrinting(): Bool;
var iC: integer;
    bRes: bool;
begin
  WriteLogFile('waitforprinting+');
  bRes := false;
  if FsModel = 'Shtrih' then begin
    for iC := 1 to 10 do begin
      try
        ovObject.GetShortECRStatus;
      finally
        WriteLogFile('t-f:EAM=' + IntToStr(ovObject.ECRAdvancedMode));
      end;
      if ovObject.ECRAdvancedMode < 1 then begin
        bRes := true;
        break;
      end;
      sleep(250);
    end;
  end;
  WaitForPrinting := bRes;
  WriteLogFile('waitforprinting-');
end;

end.



