unit Scriptdb;

{ Non-GUI unit that allows you to script a database's object DDL statements }
{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, utbcommon, uTBTypes, dialogs, MDOQuery, sqldb;


// Scripts all roles; changes List to contain the CREATE ROLE SQL statements
// Will deal with existing RDB$ADMIN role (FB 2.5+ has this present by default;
// earlier db versions do not)
function ScriptAllRoles(dbIndex: Integer; var List: TStringList): Boolean;
// Scripts all UDF functions in a database
function ScriptAllFunctions(dbIndex: Integer; var List: TStringList): Boolean;
// Scripts all domains in a database
function ScriptAllDomains(dbIndex: Integer; var List: TStringList): Boolean;
// Scripts all exceptions defined in a database
function ScriptAllExceptions(dbIndex: Integer; var List: TStringList): Boolean;
// Scripts all sequences (old name: generators) in a database
function ScriptAllGenerators(dbIndex: Integer; var List: TStringList): Boolean;
// Scripts a single table as CREATE TABLE DDL
procedure ScriptTableAsCreate(dbIndex: Integer; ATableName: string; ScriptList: TStringList);
// Scripts all tables calling ScriptTableAsCreate for each table
function ScriptAllTables(dbIndex: Integer; var List: TStringList): Boolean;
// Scripts all stored procedures
function ScriptAllProcedureTemplates(dbIndex: Integer; var List: TStringList): Boolean;
// Scripts all views in a database
function ScriptAllViews(dbIndex: Integer; var List: TStringList): Boolean;
function ScriptAllTriggers(dbIndex: Integer; var List: TStringList): Boolean;
// Scripts all non-primary key indexes for a database
function ScriptAllSecIndices(dbIndex: Integer; var List: TStringList): Boolean;

// Scripts check constraints for all tables
function ScriptAllCheckConstraints(dbIndex: Integer; var List: TStringList): Boolean;
// Scripts all foreign key constraints for tables in a database
{
There are 5 kind of constraints:
    NOT NULL
    PRIMARY KEY
    UNIQUE
    FOREIGN KEY
    CHECK
This function only covers foreign keys; the other constraints are covered elsewhere
}
function ScriptAllConstraints(dbIndex: Integer; var List: TStringList): Boolean;
function ScriptObjectPermission(dbIndex: Integer; ObjName, UserName: string; var ObjType: Integer;
   List: TStrings; NewUser: string = ''): Boolean;
function ScriptAllPermissions(dbIndex: Integer; var List: TStringList): Boolean;

function ScriptUserAllPermissions(dbIndex: Integer; UserName: string; var List: TStringList;
   NewUser: string = ''): Boolean;

procedure RemoveParamClosing(var AParams: string);



implementation

uses SysTables, Main;

// Indicates if a constraint name is system-generated.
function IsConstraintSystemGenerated(ConstraintName: string): boolean;
begin
  { Unfortunately there does not seem to be a way to search the system tables
  and make sure the constraint name is system-generated - we have to guess based
  on the name}
  result:=(pos('INTEG_',uppercase(Trim(ConstraintName)))=1);
end;

(********************  Script Roles  ***********************)

function ScriptAllRoles(dbIndex: Integer; var List: TStringList): Boolean;
const
  AdminRole= 'RDB$ADMIN';
var
  Count       :Integer;
  HasRDBAdmin :Boolean;
  vCntr       :Integer;
begin
  HasRDBAdmin:= false;
  {$IFDEF EVS_New}
  dmSysTables.GetDBObjectNames(fmMain.RegisteredDatabases[dbIndex], otRoles, List);
  {$ELSE}
  List.CommaText := dmSysTables.GetDBObjectNames(fmMain.RegisteredDatabases[dbIndex], otRoles, Count);
  {$ENDIF}
  //List.CommaText := dmSysTables.GetDBObjectNames(fmMain.RegisteredDatabases[dbIndex], otRoles, Count);
  { Wwrap creates role RDB$Admin statement - in FB 2.5+ this role is present
  by default, in lower dbs it isn't. No way to find out in advance when writing
  a script. No support in FB yet for CREATE OR UPDATE ROLE so best
  to do it in execute block with error handling }
  vCntr:= 0;

  while vCntr<List.Count do begin
    if uppercase(List[vCntr]) = AdminRole then begin
      // Delete now; recreate at beginning with line endings
      HasRDBAdmin := True;
      List.Delete(vCntr);
    end else begin
      // Normal role
      List[vCntr] := 'Create Role ' + List[vCntr] + ';';
      Inc(vCntr);
    end;
  end;

  if HasRDBAdmin then begin
    // Insert special role at beginning for easy editing
    List.Insert(0, '-- use set term for isql, FlameRobin etc. Execute block supported since FB 2.0');
    List.Insert(1, 'set term !! ;'); //temporarily change terminator
    List.Insert(2, 'Execute block As ');
    List.Insert(3, 'Begin ');
    List.Insert(4, '  Execute statement ''Create Role ' + AdminRole + ';''; ');
    List.Insert(5, '  When any do ');
    List.Insert(6, '  begin ');
    List.Insert(7, '    -- ignore errors creating role (e.g. if it already exists) ');
    List.Insert(8, '  end ');
    List.Insert(9, 'End!! '); //closes block using changed terminator
    List.Insert(10, 'set term ; !!');
  end;
  Result:= List.Count > 0;
end;

(****************  Script Functions (UDFs)  *******************)

procedure RemoveParamClosing(var AParams: string);
var
  i: Integer;
  R: Integer;
begin
  R:= Pos('returns', LowerCase(AParams));
  if R > 0 then
  begin
    for i:= R downto 0 do
    begin
      if AParams[i] = ')' then
      begin
        Delete(AParams, i, 1);
        Break;
      end;
    end;
  end;
end;

function ScriptAllFunctions(dbIndex: Integer; var List: TStringList): Boolean;
var
  Count: Integer;
  i: Integer;
  FunctionsList: TStringList;
  ModuleName, EntryPoint, Params: string;
begin
  FunctionsList:= TStringList.Create;
  FunctionsList.CommaText:= dmSysTables.GetDBObjectNames(fmMain.RegisteredDatabases[dbIndex], uTBTypes.otUDFs, Count);
  // Get functions in dependency order:
  dmSysTables.SortDependencies(FunctionsList);
  List.Clear;
  for i:= 0 to FunctionsList.Count - 1 do
  begin
    List.Add('Declare External Function ' + FunctionsList[i]);
    if fmMain.GetUDFInfo(dbIndex, FunctionsList[i], ModuleName, EntryPoint, Params) then
    begin
      RemoveParamClosing(Params);
      List.Add(Params);
      List.Add('ENTRY_POINT ' + QuotedStr(EntryPoint));
      List.Add('MODULE_NAME ' + QuotedStr(ModuleName) + ';');
      List.Add('');
    end;
  end;
  Result:= FunctionsList.Count > 0;
  FunctionsList.Free;
end;


(********************  Script Exceptions   ***********************)

function ScriptAllExceptions(dbIndex: Integer; var List: TStringList): Boolean;
var
  Count: Integer;
  CreateStatement: string;
  Description,Message: string; {not actually used here}
  i: Integer;
begin
  List.CommaText:= dmSysTables.GetDBObjectNames(fmMain.RegisteredDatabases[dbIndex], otExceptions, Count);
  for i:= 0 to List.Count - 1 do
  begin
    dmSysTables.GetExceptionInfo(dbIndex, List[i],
      Message, Description, CreateStatement, false);
    List[i]:= CreateStatement;
  end;
  Result:= List.Count > 0;
end;

(********************  Script Generators/Sequences   ***********************)

function ScriptAllGenerators(dbIndex: Integer; var List: TStringList): Boolean;
var
  Count: Integer;
  i: Integer;
begin
  List.CommaText:= dmSysTables.GetDBObjectNames(fmMain.RegisteredDatabases[dbIndex], otGenerators, Count);
  for i:= 0 to List.Count - 1 do
    List[i]:= 'Create Generator ' + List[i] + ' ;';
  Result:= List.Count > 0;
end;


(********************  Script Domains  ***********************)

function ScriptAllDomains(dbIndex: Integer; var List: TStringList): Boolean;
var
  Count: Integer;
  i: Integer;
  CharacterSet: string;
  Collation: string;
  DomainType: string;
  DomainSize: Integer;
  CheckConstraint: string;
  DefaultValue: string;
begin
  List.CommaText:= dmSysTables.GetDBObjectNames(fmMain.RegisteredDatabases[dbIndex], otDomains, Count);
  // Get domains in dependency order (if dependencies can exist between domains)
  dmSysTables.SortDependencies(List);
  for i:= 0 to List.Count - 1 do
  begin
    dmSysTables.GetDomainInfo(dbIndex, List[i], DomainType, DomainSize, DefaultValue, CheckConstraint, CharacterSet, Collation);

    List[i]:= 'Create Domain ' + List[i] + ' as ' + DomainType;
    if (Pos('CHAR', DomainType) > 0) or (DomainType = 'CSTRING') then
      List[i]:= List[i] + '(' + IntToStr(DomainSize) + ')';
    List[i]:= List[i] + ' ' + DefaultValue;
    // Check constraint, if any:
    if CheckConstraint <> '' then
      List[i]:= List[i] + ' ' + CheckConstraint;

    { Character set is apparently not supported for domains, at least in FB2.5
    if CharacterSet <> '' then
      List[i]:= List[i] + ' CHARACTER SET ' + CharacterSet;
    }
    // Collation for text types, if any:
    if Collation <> '' then
      List[i]:= List[i] + ' COLLATE ' +  Collation;
    // Close off create clause:
    List[i]:= List[i] + ' ;';
  end;
  Result:= List.Count > 0;
end;


(********************  Script Tables   ***********************)

procedure ScriptTableAsCreate(dbIndex: Integer; ATableName: string; ScriptList: TStringList);
var
  i: Integer;
  PKeyIndexName  :string;
  PKFieldsList   :TStringList;
  FieldLine      :string;
  Skipped        :Boolean;
  BlobSubType    :string;
  ConstraintName :string;
  CalculatedList :TStringList; // for calculated fields
  DefaultValue   :string;
  //vFields        :TSQLQuery;
  vFields        :TMDOQuery;
begin
  vFields  := GetQuery(fmMain.RegisteredDatabases[dbIndex].Conn, cTmplFields, [aTableName]);
  //fmMain.GetFields(dbIndex, ATableName, nil);
  ScriptList.Clear;
  ScriptList.Add('create table ' + ATableName + ' (');
  CalculatedList:= TStringList.Create;
  try
    // Fields
    //with vFields do
    while not vFields.EOF do begin
      Skipped := False;
      if (vFields.FieldByName('computed_source').AsString = '') then
      begin
        // Field Name
        FieldLine:= Trim(vFields.FieldByName('Field_Name').AsString) + ' ';

        if (vFields.FieldByName(cFldSource).IsNull) or
          (Trim(vFields.FieldByName(cFldSource).AsString)='') or
          (IsFieldDomainSystemGenerated(Trim(vFields.FieldByname(cFldSource).AsString))) then
        begin
          // Field type is not based on a domain but a standard SQL type
          // Field type
          FieldLine := FieldLine + GetFBTypeName(vFields.FieldByName(cfldType).AsInteger,
          vFields.FieldByName(cFldSubType).AsInteger,
          vFields.FieldByName(cFldLength).AsInteger,
          vFields.FieldByName(cFldPrecision).AsInteger,
          vFields.FieldByName(cFldScale).AsInteger);

          if (vFields.FieldByName(cfldType).AsInteger) in [CharType, CStringType, VarCharType] then
            FieldLine:= FieldLine + '(' + vFields.FieldByName(cFldCharLength).AsString + ') ';

          if (vFields.FieldByName(cfldType).AsInteger = BlobType) then begin
            BlobSubType:= fmMain.GetBlobSubTypeName(vFields.FieldByName(cFldSubType).AsInteger);
            if BlobSubType<>'' then
              FieldLine:= FieldLine + ' ' + BlobSubType;
          end;

          // Rudimentary support for array datatypes (only covers 0 dimension types):
          {todo: (low priority) expand to proper array type detection though arrays are
           virtually unused}
          if not(vFields.FieldByName(cArrUpBound).IsNull) then
            FieldLine := FieldLine + ' [' + vFields.FieldByName(cArrUpBound).AsString + '] ';
        end else begin
          // Field is based on a domain
          FieldLine := FieldLine + ' ' + trim(vFields.FieldByName(cFldSource).AsString);
        end;
        // Default value
        DefaultValue := Trim(vFields.FieldByName(cFldDefSource).AsString);
        if DefaultValue <> '' then
        begin
          if pos('default', LowerCase(DefaultValue)) <> 1 then
            DefaultValue := ' default ' + QuotedStr(DefaultValue);
          FieldLine := FieldLine + ' ' + DefaultValue;
        end;

        // Null/Not null
        if vFields.FieldByName(cFldNullFlag).AsString = '1' then
           FieldLine := FieldLine + ' not null ';
      end else begin
        Skipped:= True;
      end;

      // Computed Fields
      if vFields.FieldByName(cFldComputedSrc).AsString <> '' then
        CalculatedList.Add('ALTER TABLE ' + ATableName + ' ADD ' +
          Trim(vFields.FieldByName(cFldName).AsString) + ' COMPUTED BY ' + vFields.FieldByName(cFldComputedSrc).AsString + ';');

      vFields.Next;

      if not Skipped then
      begin
        if not vFields.EOF then
          FieldLine:= FieldLine + ',';
        ScriptList.Add(FieldLine);
      end;
    end;

    if Pos(',', ScriptList[ScriptList.Count - 1]) > 0 then
      ScriptList[ScriptList.Count - 1]:= Copy(ScriptList[ScriptList.Count - 1], 1,
        Length(ScriptList[ScriptList.Count - 1]) - 1);

    vFields.Close;

    // Primary Keys
    PKFieldsList:= TStringList.Create;
    try
      PKeyIndexName:= fmMain.GetPrimaryKeyIndexName(dbIndex, ATableName, ConstraintName);
      if PKeyIndexName <> '' then begin
        fmMain.GetConstraintFields(ATableName, PKeyIndexName, PKFieldsList);
        // Follow isql -x (not FlameRobin) by omitting system-generated
        // constraint names and let the system generate its own names
        if IsConstraintSystemGenerated(ConstraintName) then
          FieldLine:= ' primary key ('
        else // User-specified, so explicilty mention constraint name
          FieldLine:= 'constraint ' + ConstraintName + ' primary key (';
        for i:= 0 to PKFieldsList.Count - 1 do
          FieldLine:= FieldLine + PKFieldsList[i] + ', ';
        if PKFieldsList.Count > 0 then
        begin
          Delete(FieldLine, Length(FieldLine) - 1, 2);
          FieldLine:= FieldLine + ')';
          ScriptList.Add(', ' + FieldLine);
        end;
      end;
    finally
      PKFieldsList.Free;
    end;
    ScriptList.Add(');');
    ScriptList.Add(CalculatedList.Text);
  finally
    CalculatedList.Free;
    ReleaseQuery(vFields)
  end;
end;

(***************  Script All Tables  ********************)

function ScriptAllTables(dbIndex: Integer; var List: TStringList): Boolean;
var
  Count: Integer;
  i: Integer;
  TablesList: TStringList;
  TableScript: TStringList;
begin
  TablesList:= TStringList.Create;
  TableScript:= TStringList.Create;
  try
    TablesList.CommaText:= dmSysTables.GetDBObjectNames(fmMain.RegisteredDatabases[dbIndex], otTables, Count);
    List.Clear;
    for i:= 0 to TablesList.Count - 1 do
    begin
      ScriptTableAsCreate(dbIndex, TablesList[i], TableScript);
      List.Add('');
      List.AddStrings(TableScript);
    end;
    Result:= TablesList.Count > 0;
  finally
    TablesList.Free;
    TableScript.Free;
  end;
end;

(********************  Script Procedure Template  ***********************)

function ScriptAllProcedureTemplates(dbIndex: Integer; var List: TStringList): Boolean;
var
  Count: Integer;
  i: Integer;
  ProceduresList: TStringList;
  ProcedureScript: TStringList;
  SPOwner: string;
begin
  ProceduresList:= TStringList.Create;
  ProcedureScript:= TStringList.Create;
  try
    ProceduresList.CommaText:= dmSysTables.GetDBObjectNames(fmMain.RegisteredDatabases[dbIndex], otStoredProcedures, Count);
    // Get procedures in dependency order:
    dmSysTables.SortDependencies(ProceduresList);
    List.Clear;
    for i:= 0 to ProceduresList.Count - 1 do
    begin
      // Insert procedure body...
      ProcedureScript.Text:= fmMain.GetStoredProcBody(dbIndex, ProceduresList[i], SPOwner);
      // Then put CREATE part above it...
      ProcedureScript.Insert(0, 'SET TERM ^ ;');
      ProcedureScript.Insert(1, 'CREATE Procedure ' + ProceduresList[i]);
      // ... and closing SET TERM part below it.
      ProcedureScript.Add('^');
      ProcedureScript.Add('SET TERM ; ^');
      ProcedureScript.Add('');
      List.AddStrings(ProcedureScript);
    end;
    Result:= ProceduresList.Count > 0;
  finally
    ProceduresList.Free;
    ProcedureScript.Free;
  end;
end;

(********************  Script Views   ***********************)

function ScriptAllViews(dbIndex: Integer; var List: TStringList): Boolean;
var
  Count: Integer;
  i: Integer;
  ViewsList: TStringList;
  ViewsBodyList: TStringList;
  Columns, ViewBody: string;
begin
  ViewsList:= TStringList.Create;
  ViewsBodyList:= TStringList.Create;
  try
    ViewsList.CommaText:= dmSysTables.GetDBObjectNames(fmMain.RegisteredDatabases[dbIndex], otViews, Count);
    // Get procedures in dependency order:
    dmSysTables.SortDependencies(ViewsList);
    List.Clear;
    for i:= 0 to ViewsList.Count - 1 do
    begin
      fmMain.GetViewInfo(dbIndex, ViewsList[i], Columns, ViewBody);
      ViewsBodyList.Text:= Trim(ViewBody);
      List.Add('CREATE VIEW "' + ViewsList[i] + '" (' + Columns + ')');
      List.Add('AS');
      List.AddStrings(ViewsBodyList);
      List.Add(' ;');
    end;
    Result:= ViewsList.Count > 0;
  finally
    ViewsList.Free;
    ViewsBodyList.Free;
  end;
end;


(********************  Script Triggers   ***********************)

function ScriptAllTriggers(dbIndex: Integer; var List: TStringList): Boolean;
var
  Count: Integer;
  i: Integer;
  TriggersList: TStringList;
  TriggerScript: TStringList;
begin
  TriggersList:= TStringList.Create;
  TriggerScript:= TStringList.Create;
  try
    TriggersList.CommaText:= dmSysTables.GetDBObjectNames(fmMain.RegisteredDatabases[dbIndex], otTriggers, Count);
    List.Clear;
    for i:= 0 to TriggersList.Count - 1 do
    begin
      TriggerScript.Clear;
      dmSysTables.ScriptTrigger(dbIndex, TriggersList[i], TriggerScript, True);
      List.AddStrings(TriggerScript);
      List.Add('');
    end;
    Result:= TriggersList.Count > 0;
  finally
    TriggerScript.Free;
    TriggersList.Free;
  end;
end;

(********************  Script Secondary indices  ***********************)

function ScriptAllSecIndices(dbIndex: Integer; var List: TStringList): Boolean;
var
  Count: Integer;
  i: Integer;
  TablesList: TStringList;
  PKName: string;
  FieldsList: TStringList;
  Line: string;
  ConstraintName: string;

begin
  TablesList:= TStringList.Create;
  FieldsList:= TStringList.Create;
  try
    TablesList.CommaText:= dmSysTables.GetDBObjectNames(fmMain.RegisteredDatabases[dbIndex], otTables, Count);
    List.Clear;
    for i:= 0 to TablesList.Count - 1 do
    begin
      PKName:= fmMain.GetPrimaryKeyIndexName(dbIndex, TablesList[i], ConstraintName);

      if fmMain.GetIndices(TablesList[i], dmSysTables.MDOQuery) then
      with dmSysTables.MDOQuery do
      while not EOF do begin
        if PKName <> Trim(FieldByName('RDB$Index_name').AsString) then begin
          Line:= 'create ';
          if FieldByName('RDB$Unique_Flag').AsString = '1' then
            Line:= Line + 'Unique ';
          if FieldByName('RDB$Index_Type').AsString = '1' then
            Line:= Line + 'Descending ';

          Line:= Line + 'index ' + Trim(FieldByName('RDB$Index_name').AsString) + ' on ' + TablesList[i];

          fmMain.GetIndexFields(TablesList[i], Trim(FieldByName('RDB$Index_Name').AsString), fmMain.qryMain, FieldsList);
          Line:= Line + ' (' + FieldsList.CommaText + ') ;';
          List.Add(Line);
        end;
        Next;
      end;
    end;
    dmSysTables.MDOQuery.Close;
    Result:= List.Count > 0;
  finally
    TablesList.Free;
    FieldsList.Free;
  end;
end;


(********************  Script Check Constraints   ***********************)

function ScriptAllCheckConstraints(dbIndex: Integer; var List: TStringList
  ): Boolean;
begin
  dmSysTables.ScriptCheckConstraints(dbIndex,List);
end;

(********************  Script Constraints   ***********************)

function ScriptAllConstraints(dbIndex: Integer; var List: TStringList): Boolean;
var
  Count: integer;
  ConstraintArray: TConstraintCounts;
  ConstraintName: string;
  CompositeClauseFK: string;
  CompositeClauseRef: string;
  CompositeConstraint: string;
  CompositeCount: integer;
  CompositeCounter: integer;
  TableCounter: integer;
  TablesList: TStringList;

  procedure WriteResult(
    const TableName, ConstraintName, CurrentFieldName,
    OtherFieldName, OtherTableName, DeleteRule, UpdateRule: string;
    var List: TStringList);
  const
    { isql -x outputs DDL like this here:
    ALTER TABLE DEPARTMENT ADD FOREIGN KEY (MNGR_NO) REFERENCES EMPLOYEE (EMP_NO);
    i.e. does not mention constraint name.
    This avoids name conflicts with autogenerated constraint names (which
    FlameRobin also suffers from)
    We're going to try follow this and find out what is a system-generated
    constraint name and what is user-generated so we don't lose information
    }
    Template= 'alter table %s' +
      ' add constraint %s' +
      ' foreign key (%s)'+
      ' references %s' +
      ' (%s)';
    TemplateNoName= 'alter table %s' +
      ' add foreign key (%s)'+
      ' references %s' +
      ' (%s)';
  var
    Line: string;
  begin
    if IsConstraintSystemGenerated(ConstraintName) then
    begin
      // If system-generated, don't specify constraint name
      Line:= format(TemplateNoName,[TableName,CurrentFieldName,
        OtherTableName, OtherFieldName]);
    end
    else
    begin
      // Do spell out constraint name
      Line:= format(Template,[TableName,ConstraintName,CurrentFieldName,
        OtherTableName, OtherFieldName]);
    end;
    if UpdateRule <> 'RESTRICT' then
      Line:= Line + ' on update ' + UpdateRule;
    if DeleteRule <> 'RESTRICT' then
      Line:= Line + ' on delete ' + DeleteRule;
    List.Add(Line + ';');
  end;

begin
  TablesList := TStringList.Create;
  try
    TablesList.CommaText:= dmSysTables.GetDBObjectNames(fmMain.RegisteredDatabases[dbIndex], otTables, Count);
    // Get tables in dependency order - probably won't matter much in this case:
    dmSysTables.SortDependencies(TablesList);
    List.Clear;
    for TableCounter:= 0 to TablesList.Count - 1 do
    with dmSysTables do
    begin
      GetTableConstraints(TablesList[TableCounter], MDOQuery);
      FillCompositeFKConstraints(TablesList[TableCounter],ConstraintArray);
      CompositeConstraint:= '';
      while not mdoQuery.EOF do
      begin
        ConstraintName:= MDOQuery.FieldByName('ConstName').AsString;
        CompositeCount:= GetCompositeFKConstraint(ConstraintName, ConstraintArray);
        if CompositeCount>0 then
        begin
          // Multiple columns form a composite foreign key index.
          if ConstraintName<>CompositeConstraint then
          begin
            // A new constraint just started
            CompositeConstraint:= ConstraintName;
            CompositeCounter:= 1;
            CompositeClauseFK:= MDOQuery.FieldByName('CurrentFieldName').AsString+', ';
            CompositeClauseRef:= MDOQuery.FieldByName('OtherFieldName').AsString+', ';
          end
          else
          begin
            inc(CompositeCounter);
            if CompositeCounter=CompositeCount then
            begin
              // Last record for this constraint, so write out
              CompositeClauseFK:= CompositeClauseFK + MDOQuery.FieldByName('CurrentFieldName').AsString;
              CompositeClauseRef:= CompositeClauseRef + MDOQuery.FieldByName('OtherFieldName').AsString;
              WriteResult(TablesList[TableCounter],
                ConstraintName,
                CompositeClauseFK,
                CompositeClauseRef,
                Trim(MDOQuery.FieldByName('OtherTableName').AsString),
                Trim(MDOQuery.FieldByName('DeleteRule').AsString),
                Trim(MDOQuery.FieldByName('UpdateRule').AsString),
                List);
            end
            else
            begin
              // In middle of clause, so keep adding
              CompositeClauseFK:= CompositeClauseFK + MDOQuery.FieldByName('CurrentFieldName').AsString + ', ';
              CompositeClauseRef:= CompositeClauseRef + MDOQuery.FieldByName('OtherFieldName').AsString + ', ';
            end;
          end;
        end else begin
          // Normal, non-composite foreign key which we can write out based on one record in the query
          // We're using fieldbyname here instead of fields[x] because of maintainability and probably
          // low performance impact.
          // If performance is an issue, define field variables outside the loop and reference them instead
          WriteResult(TablesList[TableCounter],
            ConstraintName,
            Trim(MDOQuery.FieldByName('CurrentFieldName').AsString),
            Trim(MDOQuery.FieldByName('OtherFieldName').AsString),
            Trim(MDOQuery.FieldByName('OtherTableName').AsString),
            Trim(MDOQuery.FieldByName('DeleteRule').AsString),
            Trim(MDOQuery.FieldByName('UpdateRule').AsString),
            List);
        end;
        MDOQuery.Next;
      end;
      MDOQuery.Close;
    end;
    Result:= List.Count > 0;
  finally
    TablesList.Free;
  end;
end;


function ScriptObjectPermission(dbIndex: Integer; ObjName, UserName: string; var ObjType: Integer;
   List: TStrings; NewUser: string = ''): Boolean;
var
  Permissions: string;
  Line: string;
  PermissionList: TStringList;
  OrigObjName: string;
begin
  try
    if NewUser = '' then
      NewUser:= UserName;
    OrigObjName:= ObjName;
    ObjName:= Copy(ObjName, 4, Length(ObjName) - 3);
    Permissions:= dmSysTables.GetObjectUserPermission(dbIndex, ObjName, UserName, ObjType);
    PermissionList:= TstringList.Create;
    try
      if Permissions <> '' then
      begin
        if Pos('<T>', OrigObjName) = 1 then // Table/View
        begin
          PermissionList.Clear;
          if Pos('S', Permissions) > 0 then
            PermissionList.Add('Select');

          if Pos('U', Permissions) > 0 then
            PermissionList.Add('Update');

          if Pos('I', Permissions) > 0 then
            PermissionList.Add('Insert');

          if Pos('D', Permissions) > 0 then
            PermissionList.Add('Delete');

          if Pos('R', Permissions) > 0 then
            PermissionList.Add('References');
          Line:= 'Grant ' + PermissionList.CommaText + ' on ' + ObjName + ' to ' + NewUser;
          if Pos('G', Permissions) > 0 then
            Line:= Line + ' with Grant option';
        end
        else
        if Pos('<P>', OrigObjName) = 1 then // Procedure
        begin
          Line:= 'Grant Execute on procedure ' + ObjName + ' to ' + NewUser;
          if Pos('G', Permissions) > 0 then
            Line:= Line + ' with Grant option';
        end
        else
        if Pos('<R>', OrigObjName) = 1 then // Role
        begin
          Line:= 'Grant ' + ObjName + ' to ' + NewUser;
          if Pos('G', Permissions) > 0 then
            Line:= Line + ' with Grant option';
        end;
        List.Add(Line + ' ;');
      end;
    finally
      PermissionList.Free;
    end;
    Result:= True;
  except
    on E: Exception do
      Result:= False;
  end;
end;

(********************  Script All Usesr and Rules permissions ***********************)

function ScriptAllPermissions(dbIndex: Integer; var List: TStringList): Boolean;
var
  i, j: Integer;
  UsersList: TStringList;
  ObjectsList: TStringList;
  PermissionList: TStringList;
  UserName: string;
  ObjType: Integer;
begin
  UsersList:= TStringList.Create;
  ObjectsList:= TStringList.Create;
  PermissionList:= TStringList.Create;
  try
    UsersList.CommaText:= dmSysTables.GetDBUsers(dbIndex);
    List.Clear;
    for i:= 0 to UsersList.Count - 1 do
      if Pos('<R>', UsersList[i]) = 1 then
        List.Add('/* Role ' + Copy(UsersList[i], 4, Length(UsersList[i]) - 3) + ' */')
      else
        List.Add('/* User ' + UsersList[i] + ' */');

    for i:= 0 to UsersList.Count - 1 do
    begin
      ObjectsList.CommaText:= dmSysTables.GetDBObjectsForPermissions(dbIndex);
      if Pos('<R>', UsersList[i]) = 1 then
        UserName:= Copy(UsersList[i], 4, Length(UsersList[i]) - 3)
      else
        UserName:= UsersList[i];

      List.Add('');
      List.Add('/* Permissions for: ' + UserName + ' */');

      for j:= 0 to ObjectsList.Count - 1 do
      begin
        Result:= ScriptObjectPermission(dbIndex,  ObjectsList[j], UserName, ObjType, List);
      end;
    end;
    Result:= UsersList.Count > 0;
  finally
    UsersList.Free;
    ObjectsList.Free;
    PermissionList.Free;
  end;
end;

(********************  Script One User or Rule permissions ***********************)

function ScriptUserAllPermissions(dbIndex: Integer; UserName: string; var List: TStringList;
   NewUser: string = ''): Boolean;
var
  j: Integer;
  UsersList: TStringList;
  ObjectsList: TStringList;
  ObjType: Integer;
begin
  if NewUser = '' then
    NewUser:= UserName;
  UsersList:= TStringList.Create;
  ObjectsList:= TStringList.Create;
  try
    UsersList.CommaText:= dmSysTables.GetDBUsers(dbIndex);
    List.Clear;

    ObjectsList.CommaText:= dmSysTables.GetDBObjectsForPermissions(dbIndex);

    List.Add('');
    List.Add('/* Permissions for: ' + UserName + ' */');

    for j:= 0 to ObjectsList.Count - 1 do
      Result:= ScriptObjectPermission(dbIndex,  ObjectsList[j], UserName, ObjType, List, NewUser);

    Result:= UsersList.Count > 0;
  finally
    UsersList.Free;
    ObjectsList.Free;
  end;
end;

end.

