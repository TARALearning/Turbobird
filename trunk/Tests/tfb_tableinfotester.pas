unit TFB_TableInfoTester;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, TestFramework, uFBTestcase, uEvsDBSchema, uTBTypes;

type

  { TFBTableInfo }

  TFBTableInfo = class(TEvsFBMetaTester)
  public
    procedure SetUp; override;
    procedure TearDown; override;
    procedure SetupCopy(var aExisting, aCopy :IEvsTableInfo);
    procedure LoadDetails(const aTable:IEvsTableInfo);
  published
    procedure Retrieval;
    procedure DetailsRetrieval;
    procedure TableTriggersRetrieval;
    procedure IndexRetrieval;
    procedure PrimaryKeyRetrieval;

    procedure ForeignKeyRetrieval;

    procedure CheckRetrieval;
    procedure Copy;
    procedure ListCopy;
  end;

implementation

uses Dialogs, uTBCommon;

function TableByName(const aDB:IEvsDatabaseInfo; const aTableName:string):IEvsTableInfo;
var
  vCntr :Integer;
begin
  Result:=Nil;
  for vCntr := 0 to aDB.TableCount do
    if CompareText(aTableName,aDB.Table[vCntr].TableName) = 0 then Exit(aDB.Table[vCntr]);
end;

procedure TFBTableInfo.SetUp;
begin
  DoConnect;
  FDB.Connection.MetaData.GetTables(FDB);
end;

procedure TFBTableInfo.TearDown;
begin
  FDB.ClearTables;
end;

procedure TFBTableInfo.SetupCopy(var aExisting, aCopy :IEvsTableInfo);
begin
  aExisting := FDB.Table[Random(FDB.TableCount)];
  if aCopy = Nil then aCopy := TEvsDBInfoFactory.NewTable(Nil);
  aCopy.CopyFrom(aExisting);
end;

procedure TFBTableInfo.LoadDetails(const aTable :IEvsTableInfo);
begin
  FDB.Connection.MetaData.GetTableInfo(aTable);
end;

procedure TFBTableInfo.Retrieval;
begin
  CheckEquals(10,         FDB.TableCount, 'Unexpected number of tables found');
  CheckEquals('COUNTRY',  FDB.Table[0].TableName);
  CheckEquals('CUSTOMER', FDB.Table[1].TableName);
  CheckEquals('SALES',    FDB.Table[9].TableName);
end;

procedure TFBTableInfo.Copy;
var
  vTbl     :IEvsTableInfo = nil;
  vDBTable :IEvsTableInfo = nil;
begin
  SetupCopy(vDBTable, vTbl);
  CheckEquals(vDBTable.TableName,   vTbl.TableName,   'Tablename copy failed');
  CheckEquals(vDBTable.Description, vTbl.Description, 'Description copy failed');
  CheckEquals(vDBTable.CharSet,     vTbl.CharSet,     'CharSet copy failed');
  CheckEquals(vDBTable.Collation,   vTbl.Collation,   'Collation copy failed');
  CheckEquals(vDBTable.SystemTable, vTbl.SystemTable, 'SystemTable copy failed');
  Check(vTbl.EqualsTo(vDBTable), 'Internal check failed');
end;

procedure TFBTableInfo.DetailsRetrieval;
var
  vCntr :Integer;
  vTbl : IEvsTableInfo;
begin
  CheckEquals(10, FDB.TableCount, 'Unexpected table count');
  for vCntr := 0 to FDB.TableCount -1 do
    FDB.Connection.MetaData.GetTableInfo(FDB.Table[vCntr]);
  vCntr := 0;
  repeat
    CheckNotEquals(0, FDB.Table[vCntr].FieldCount, '0 fields on table ' + FDB.Table[vCntr].TableName+' at '+IntToStr(vCntr));
    Inc(vCntr);
  until vCntr >= FDB.TableCount;
  CheckEquals(12, FDB.Table[1].FieldCount,   'Unexpected Count of fields for table '   + FDB.Table[1].TableName);
  CheckEquals(02, FDB.Table[0].FieldCount,   'Unexpected Count of fields for table '   + FDB.Table[0].TableName);
  CheckEquals(13, FDB.Table[9].FieldCount,   'Unexpected Count of fields for table '   + FDB.Table[9].TableName);
  CheckEquals(03, FDB.Table[1].IndexCount,   'Unexpected Count of Indices for table '  + FDB.Table[1].TableName);
  CheckEquals(01, FDB.Table[1].TriggerCount, 'Unexpected Count of triggers for table ' + FDB.Table[1].TableName);
  CheckEquals(04, FDB.Table[9].IndexCount,   'Unexpected Count of indices for table '  + FDB.Table[9].TableName);
  CheckEquals(01, FDB.Table[9].TriggerCount, 'Unexpected Count of triggers for table ' + FDB.Table[9].TableName);
  vTbl := TableByName(FDB,'department');
  if vTbl = nil then Fail('Table department was not retrieved.');
  CheckEquals(7,vTbl.FieldCount,  'Invalid field count for Table '    + vTbl.TableName);
  CheckEquals(0,vTbl.TriggerCount,'Invalid trigger count  for Table ' + vTbl.TableName);
  CheckEquals(2,vTbl.IndexCount,  'Invalid index count for Table '    + vTbl.TableName);
end;

procedure TFBTableInfo.TableTriggersRetrieval;
var
  vTbl :IEvsTableInfo;
begin
  FDB.ClearTables;
  FDB.Connection.MetaData.GetTables(FDB);
  vTbl := TableByName(FDB, 'Customer');
  FDB.Connection.MetaData.GetTriggers(vTbl);
  CheckEquals(01, vTbl.TriggerCount, 'Unexpected Count of triggers for table ' + vTbl.TableName);
  CheckEqualText('Set_Cust_No', vTbl.Trigger[0].Name, 'Unexpected Name of trigger at 0' + vTbl.TableName);
end;

procedure TFBTableInfo.ListCopy;
function IndexOf(aTableName:string):integer;
var
  vCntr :Integer;
begin
  Result := -1;
  for vCntr := 0 to FDB.TableCount -1 do
    if WideCompareText(aTableName,FDB.Table[vCntr].TableName)=0 then Exit(vCntr);
end;
function IndexOf(aTable:IEvsTableInfo):Integer;
var
  vCntr :Integer;
begin
  Result := -1;
  for vCntr := 0 to FDB.TableCount -1 do
    if aTable = FDB.Table[vCntr] then Exit(vCntr);
end;

var
  vDBTable, vTbl : IEvsTableInfo;
  vCntr :Integer;
begin
  FDB.ClearTables;
  FDB.Connection.MetaData.GetTables(FDB);
  CheckNotEquals(0,FDB.TableCount,'Invalid table count');
  //for vCntr := 0 to FDB.TableCount -1 do ;
  //  FDB.Connection.MetaData.GetTableInfo(FDB.Table[vCntr]);
  vCntr := 0;
  repeat //for some reason the for loop above does not execute for all the tables.
         //I had to change to this repeat until loop to avoid failing the field count test
    FDB.Connection.MetaData.GetTableInfo(FDB.Table[vCntr]);
    Inc(vCntr);
  until vCntr >= FDB.TableCount;
  //for vCntr := 0 to FDB.TableCount -1 do ; //this does not work as expected for some reason.
  //  CheckNotEquals(0, FDB.Table[vCntr].FieldCount,'Invalid field count for table '+FDB.Table[vCntr].TableName+'at '+inttostr(vCntr));
  vCntr := 0;
  repeat
    CheckNotEquals(0, FDB.Table[vCntr].FieldCount, '0 fields on table ' + FDB.Table[vCntr].TableName+' at '+IntToStr(vCntr));
    Inc(vCntr);
  until vCntr >= FDB.TableCount;

  vDBTable := nil;
  vTbl     := nil;
  SetupCopy(vDBTable, vTbl);
  CheckNotEquals(0, vDBTable.FieldCount, 'Invalid Field count for table ' + vDBTable.TableName); //this fails with the for loops above.
  CheckEquals(vDBTable.FieldCount, vTbl.FieldCount,  'field count differs');
  Check(vDBTable.Field[0].EqualsTo(vTbl.Field[0]),   'first field does not much');
  Check(vDBTable.Field[vDBTable.FieldCount-1].EqualsTo(vTbl.Field[vTbl.FieldCount-1]),'first field does not much');
  CheckEquals(vDBTable.TriggerCount, vTbl.TriggerCount, 'Invalid trigger number');
  CheckEquals(vDBTable.IndexCount,   vTbl.IndexCount,   'Invalid index number');
  Fail('No Constraint test written');
end;

procedure TFBTableInfo.ForeignKeyRetrieval;
var
  vCntr :Integer;
begin
  for vCntr := 0 to FDB.TableCount -1 do begin
    FDB.Connection.MetaData.GetForeignKeys(FDB.Table[vCntr]);
  end;
  Check(TableByName(FDB, 'Customer').ForeignKeyCount >0);
  Fail('No test writen');
end;

procedure TFBTableInfo.PrimaryKeyRetrieval;
var
  vHasPrimary : Boolean = False;
  vCntr :Integer;
begin
  LoadDetails(FDB.Table[0]);
  for vCntr := 0 to FDB.Table[0].IndexCount -1 do
    vHasPrimary := vHasPrimary or FDB.Table[0].Index[vCntr].Primary;
  CheckTrue(vHasPrimary, FDB.Table[0].TableName + ': No primary index found');
end;

procedure TFBTableInfo.CheckRetrieval;
begin
  Fail('No test written');

end;

procedure TFBTableInfo.IndexRetrieval;
begin
  LoadDetails(FDB.Table[0]);
  CheckEquals(1, FDB.Table[0].IndexCount, FDB.Table[0].TableName +': Incorect index count');
  LoadDetails(FDB.Table[1]);
  CheckEquals(3, FDB.Table[1].IndexCount, FDB.Table[1].TableName +': Incorect index count');
  LoadDetails(FDB.Table[2]);
  CheckEquals(2, FDB.Table[2].IndexCount, FDB.Table[2].TableName +': Incorect index count');
end;

initialization
  RegisterTest(cSchema, TFBTableInfo.Suite);

end.

