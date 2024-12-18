 *********************** Link Server T-SQL ************************

set identity_insert [vsr_SecurityParse].[dbo].[unified_import_queue] on

insert into [vsr_SecurityParse].[dbo].[unified_import_queue] ([ID]
      ,[NameSpace]
      ,[SourceFilePath]
      ,[SourceFileTimeStamp]
      ,[CloudFilePath]
      ,[SourceFileSize]
      ,[IsEmptyFile]
      ,[CreatedDate]
      ,[Status]
      ,[Type]
      ,[StageData]
      ,[SectionCount]
      ,[rowguid]
      ,[Filename])
SELECT  [ID]
      ,[NameSpace]
      ,[SourceFilePath]
      ,[SourceFileTimeStamp]
      ,[CloudFilePath]
      ,[SourceFileSize]
      ,[IsEmptyFile]
      ,[CreatedDate]
      ,[Status]
      ,[Type]
      ,[StageData]
      ,[SectionCount]
      ,[rowguid]
      ,[Filename]
    FROM OPENQUERY(DATA7, 'SELECT [ID]
      ,[NameSpace]
      ,[SourceFilePath]
      ,[SourceFileTimeStamp]
      ,[CloudFilePath]
      ,[SourceFileSize]
      ,[IsEmptyFile]
      ,[CreatedDate]
      ,[Status]
      ,[Type]
      ,[StageData]
      ,[SectionCount]
      ,[rowguid]
      ,[Filename] FROM vsr_SecurityParse.dbo.unified_import_queue where cast(Createddate as date) >= ''2024-10-24''') 
set identity_insert [vsr_SecurityParse].[dbo].[unified_import_queue] off


******************* Flat data set into Normalized Tables **********************


CREATE TABLE #InsertedMainTableIds (
    Id INT,
    Name NVARCHAR(255),
    OtherColumn NVARCHAR(255)
);

INSERT INTO MainTable (Name, OtherColumn)
OUTPUT INSERTED.Id, INSERTED.Name, INSERTED.OtherColumn INTO #InsertedMainTableIds
SELECT DISTINCT Name, OtherColumn
FROM #FlatData;

-- Step 2: Insert data into ForeignKeyTable using the captured identity values
INSERT INTO ForeignKeyTable (MainTableId, SomeDetail)
SELECT imt.Id AS MainTableId, fd.SomeDetail
FROM #FlatData fd
JOIN #InsertedMainTableIds imt
    ON fd.Name = imt.Name AND fd.OtherColumn = imt.OtherColumn;

-- Clean up the temporary table
DROP TABLE #InsertedMainTableIds;
