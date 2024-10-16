When working with large tables (such as your 40-column table with 400 million records), filtering and inserting a subset of records into a new table efficiently requires careful planning. Here are some best practices for filtering and moving approximately one-third of the records into a new table:

### 1. **Use `SELECT INTO` for Initial Data Load**:
If the new table doesn’t exist yet, the `SELECT INTO` statement is one of the most efficient ways to create and populate a table in a single operation.

- **Example**:
    ```sql
    SELECT *
    INTO [dbo].[new_filtered_table]
    FROM [dbo].[original_table]
    WHERE <filter_conditions>;
    ```
- **Advantages**:
  - **Fast**: SQL Server can create the table and insert the data in one pass without the overhead of logging or index maintenance (unless you are in `FULL` recovery mode).
  - **Efficient for Large Data Loads**: This method is faster than creating the table first and then doing an `INSERT` because it bypasses the usual insert overhead.

### 2. **Batch Insert with `INSERT INTO`**:
If the new table already exists, or you need more control over the insert process, consider batching the `INSERT` to avoid long transaction times and excessive locking.

- **Example**:
    ```sql
    SET NOCOUNT ON;
    DECLARE @BatchSize INT = 100000;  -- Choose a batch size (100k rows, for example)

    WHILE (1 = 1)
    BEGIN
        INSERT INTO [dbo].[new_filtered_table]
        SELECT TOP (@BatchSize) *
        FROM [dbo].[original_table]
        WHERE <filter_conditions>
        AND NOT EXISTS (
            SELECT 1 FROM [dbo].[new_filtered_table] t
            WHERE t.<key_column> = original_table.<key_column>
        );
        
        IF @@ROWCOUNT = 0 BREAK;  -- Exit loop when no more rows to insert
    END;
    ```
- **Advantages**:
  - **Transaction Control**: Each batch operates as a separate transaction, reducing locking and log space consumption.
  - **Avoid Long-Running Transactions**: Large inserts in one go can cause transaction log growth and long locks. Batch inserts avoid this problem.
  - **Minimal Resource Impact**: By breaking down the insert into smaller batches, you reduce the load on the system, which can allow other processes to continue working efficiently.

### 3. **Use Filtered Indexes (If Appropriate)**:
If you can anticipate the filtering condition in advance and it is a commonly used filter, consider creating **filtered indexes** or **regular indexes** on the columns involved in the `WHERE` clause.

- **Example**:
    ```sql
    CREATE INDEX idx_filtered_column ON [dbo].[original_table] (filter_column)
    WHERE <filter_condition>;
    ```
    This will help speed up the filtering process significantly, especially when the `WHERE` clause involves selective filtering on one or more columns.

- **Advantages**:
  - **Faster Query Execution**: SQL Server will be able to use the index to locate the relevant rows faster.
  - **Improved Query Plan**: Indexed queries can avoid full table scans and reduce the processing time.

### 4. **Use Partitioning**:
If you plan to perform such large operations regularly, you can consider **table partitioning**. Table partitioning allows SQL Server to divide the table logically into smaller parts (partitions) based on a column, such as date or ID.

- **Example**:
    If your table is partitioned by date and you need to filter on recent dates, the query can scan only the relevant partitions rather than the entire table.
  
    ```sql
    SELECT *
    INTO [dbo].[new_filtered_table]
    FROM [dbo].[original_partitioned_table]
    WHERE partition_column = <specific_partition_value>;
    ```

- **Advantages**:
  - **Improved Performance**: SQL Server can work on smaller portions of the table (partitions) rather than the entire dataset.
  - **Partition Switching**: If needed, you can also **switch partitions** to move large blocks of data between tables without moving rows, which is much faster.

### 5. **Enable Minimal Logging (Bulk Inserts)**:
If your database is in the **Simple** or **Bulk-Logged** recovery model, you can enable **minimal logging** to reduce the overhead on the transaction log during large insert operations.

- **Step 1: Set the Recovery Model**:
    ```sql
    ALTER DATABASE YourDatabaseName SET RECOVERY BULK_LOGGED;
    ```

- **Step 2: Insert with Minimal Logging**:
    Use the `TABLOCK` hint to enable minimal logging for the bulk insert:
    ```sql
    INSERT INTO [dbo].[new_filtered_table] WITH (TABLOCK)
    SELECT *
    FROM [dbo].[original_table]
    WHERE <filter_conditions>;
    ```

- **Advantages**:
  - **Reduced Logging Overhead**: Minimal logging reduces the amount of information written to the transaction log, speeding up the insert process.
  - **Faster Insert**: Bulk operations with minimal logging can be significantly faster than fully logged transactions.

### 6. **Ensure Adequate Resources**:
- **Memory & CPU**: Ensure your SQL Server instance has enough memory and CPU resources to handle the large insert operation.
- **TempDB**: If your query requires significant sorting or temp table usage, make sure the `TempDB` has enough space and is optimized (e.g., multiple data files).

### 7. **Use a Staging Table**:
If the filtering and insert process involves heavy transformations or complex filtering logic, consider using a **staging table**. This table can be a temporary table or a real table designed to temporarily hold the data.

- **Example**:
    ```sql
    SELECT *
    INTO #staging_table
    FROM [dbo].[original_table]
    WHERE <filter_conditions>;
    
    INSERT INTO [dbo].[new_filtered_table]
    SELECT * FROM #staging_table;
    ```

- **Advantages**:
  - **Simplifies Workflow**: Using a staging table can break down complex operations into smaller, more manageable steps.
  - **Easier Debugging**: You can inspect the staging table before the final insert to ensure the filtering was done correctly.

### Summary of Best Practices:
1. **Use `SELECT INTO`** if the table doesn’t exist yet for fast bulk inserts.
2. **Batch inserts** using `INSERT INTO` with smaller chunks to reduce locking and transaction log pressure.
3. **Create filtered indexes** to optimize query performance on large tables.
4. **Partition the table** if the filtering is based on a predictable column (e.g., date) to reduce the query scan size.
5. **Enable minimal logging** with `TABLOCK` to improve insert performance under the Simple/Bulk-Logged recovery model.
6. **Ensure proper system resources** such as CPU, memory, and `TempDB` are configured to handle large data operations efficiently.

---

Table partitioning in SQL Server allows you to divide a large table into smaller, more manageable "partitions" based on a partitioning column, typically a column with natural ranges like a date, ID, or another value. Partitioning helps improve query performance and manageability by allowing SQL Server to work on smaller parts of the table rather than the entire dataset.

Here’s how you can partition a table in SQL Server, along with a step-by-step guide:

### Step-by-Step Guide to Table Partitioning

1. **Choose a Partitioning Column**:
   The partitioning column is a column that naturally divides the data into ranges. Common choices are:
   - **Date** (e.g., `PriceDate`, `TransactionDate`): Partition by year, month, or day.
   - **ID** (e.g., `OrderID`, `CustomerID`): Partition by ranges of IDs.

   **Example**: Let’s assume we are partitioning the table by the `PriceDate` column, where each partition stores data for one year.

2. **Create a Partition Function**:
   A **partition function** defines how SQL Server splits the data into different partitions by specifying the boundaries.

   - **Example**: Partition data by year (e.g., 2020, 2021, 2022).

   ```sql
   CREATE PARTITION FUNCTION PF_PriceDate (DATE)
   AS RANGE RIGHT FOR VALUES ('2020-12-31', '2021-12-31', '2022-12-31');
   ```

   - **Explanation**:
     - `RANGE RIGHT`: This means that the boundary value belongs to the partition on the right.
     - `FOR VALUES`: Specifies the boundary values for each partition.
     - Rows with `PriceDate` ≤ `2020-12-31` will go into one partition, rows with `PriceDate` ≤ `2021-12-31` into the next, and so on.

3. **Create a Partition Scheme**:
   A **partition scheme** maps the partitions defined by the partition function to one or more filegroups. Filegroups are logical storage units in SQL Server that manage where the data is physically stored.

   - **Example**: Store all partitions in the `PRIMARY` filegroup, but you can split them across multiple filegroups for better performance.

   ```sql
   CREATE PARTITION SCHEME PS_PriceDate
   AS PARTITION PF_PriceDate TO (PRIMARY, PRIMARY, PRIMARY, PRIMARY);
   ```

   - **Explanation**:
     - `AS PARTITION`: Ties the partition scheme to the partition function.
     - `TO (PRIMARY, PRIMARY, PRIMARY, PRIMARY)`: Maps each partition to the same filegroup. If you have multiple filegroups, you can map each partition to different filegroups.

4. **Create the Partitioned Table**:
   Now, create the partitioned table using the partition scheme. This step involves defining the table just like any regular table but specifying the partitioning column and partition scheme.

   - **Example**:

   ```sql
   CREATE TABLE dbo.edi_prices
   (
       PriceID INT IDENTITY(1,1) PRIMARY KEY,
       PriceDate DATE,
       Price DECIMAL(18,4),
       ProductID INT,
       [Hash] BINARY(16),
       -- other columns
   )
   ON PS_PriceDate(PriceDate);
   ```

   - **Explanation**:
     - The `ON PS_PriceDate(PriceDate)` clause specifies that the `PriceDate` column will be used to determine how the data is partitioned across the filegroups as defined by the partition scheme.

5. **Inserting Data into the Partitioned Table**:
   When you insert data into the partitioned table, SQL Server automatically assigns rows to the appropriate partition based on the `PriceDate` column.

   - **Example**:

   ```sql
   INSERT INTO dbo.edi_prices (PriceDate, Price, ProductID, [Hash])
   VALUES ('2022-05-15', 123.45, 101, 0xABCD);
   ```

   In this example, the record will automatically be stored in the correct partition based on the `PriceDate`.

6. **Querying a Partitioned Table**:
   SQL Server will automatically use the correct partition when querying the table based on the partitioning column. This is known as **partition elimination**, which means SQL Server only scans the relevant partition(s) instead of the whole table.

   - **Example**:

   ```sql
   SELECT * FROM dbo.edi_prices
   WHERE PriceDate BETWEEN '2022-01-01' AND '2022-12-31';
   ```

   SQL Server will only access the partition(s) that contain the data for the year 2022.

7. **Managing Partitions**:
   You can add, merge, split, or remove partitions as needed. For example, if you need to add a new partition for 2023, you would do the following:

   ```sql
   ALTER PARTITION FUNCTION PF_PriceDate()
   SPLIT RANGE ('2023-12-31');
   ```

   This will create a new partition for the year 2023.

8. **Indexing a Partitioned Table**:
   You can create indexes on a partitioned table just like you would for a regular table. You can specify whether the index should be partitioned or not.

   - **Example** (creating a partitioned index):
   
   ```sql
   CREATE INDEX IX_PriceDate
   ON dbo.edi_prices (PriceDate)
   ON PS_PriceDate(PriceDate);
   ```

   This index will be partitioned according to the partition scheme.

9. **Benefits of Table Partitioning**:
   - **Improved Query Performance**: Queries that filter on the partitioning column (e.g., `PriceDate`) will only scan the relevant partitions, reducing the number of rows scanned and improving performance.
   - **Easier Data Management**: You can quickly move, archive, or delete entire partitions, which is much faster than operating on individual rows.
   - **Parallelism**: SQL Server can process queries on different partitions in parallel, improving performance for large-scale queries.
   - **Better Resource Utilization**: Partitioning allows for better use of resources like memory and disk I/O, as SQL Server can focus on smaller subsets of data.

### Example Summary:
Here’s a full example of partitioning a table by `PriceDate`:

1. **Create Partition Function**:
   ```sql
   CREATE PARTITION FUNCTION PF_PriceDate (DATE)
   AS RANGE RIGHT FOR VALUES ('2020-12-31', '2021-12-31', '2022-12-31');
   ```

2. **Create Partition Scheme**:
   ```sql
   CREATE PARTITION SCHEME PS_PriceDate
   AS PARTITION PF_PriceDate TO (PRIMARY, PRIMARY, PRIMARY, PRIMARY);
   ```

3. **Create the Partitioned Table**:
   ```sql
   CREATE TABLE dbo.edi_prices
   (
       PriceID INT IDENTITY(1,1) PRIMARY KEY,
       PriceDate DATE,
       Price DECIMAL(18,4),
       ProductID INT,
       [Hash] BINARY(16)
       -- other columns
   )
   ON PS_PriceDate(PriceDate);
   ```

4. **Insert Data**:
   ```sql
   INSERT INTO dbo.edi_prices (PriceDate, Price, ProductID, [Hash])
   VALUES ('2022-05-15', 123.45, 101, 0xABCD);
   ```

5. **Query the Partitioned Table**:
   ```sql
   SELECT * FROM dbo.edi_prices
   WHERE PriceDate BETWEEN '2022-01-01' AND '2022-12-31';
   ```

### Key Considerations:
- **Partition Size**: Ensure partitions are not too small (which can increase overhead) or too large (which reduces the benefits of partition elimination).
- **Indexing**: Plan your indexing strategy carefully to ensure queries benefit from partitioning.
- **Maintenance**: Use partition management operations (e.g., splitting, merging) to keep your table structure aligned with data growth.

---

SQL Server does not have built-in, automatic partition management that automatically adds or appends new partitions as new data arrives. However, you can **automate partition management** by scheduling jobs that add new partitions when needed, typically by using SQL Server Agent jobs or other automation tools.

### Strategy for Automating Partition Management

The general idea is to periodically check if new partitions are needed (based on your data growth or a predetermined schedule), and then **split the last partition** to add a new one. You can automate this with SQL Server Agent, which will run a stored procedure or a script at regular intervals to manage partitions.

### Steps to Automate Adding New Partitions:

1. **Identify the Partitioning Strategy**: 
   - **Date-based partitions** are the most common, where you split partitions by day, month, quarter, or year.
   - You’ll need to know when new data is expected (e.g., new data is inserted for a new month), and based on that, you can trigger partition creation in advance.

2. **Create a Stored Procedure to Add New Partitions**:
   This stored procedure will check the maximum value in the partitioning column and determine if a new partition needs to be added. If the partition does not exist for future dates or ranges, it will automatically **split the current partition** and create a new one.

#### Example Stored Procedure for Date-Based Partitioning (Yearly):

```sql
CREATE PROCEDURE AddNewPartitionForNextYear
AS
BEGIN
    DECLARE @nextPartitionDate DATE;
    DECLARE @currentMaxPartitionDate DATE;

    -- Get the maximum boundary in the partition function
    SELECT @currentMaxPartitionDate = MAX(value)
    FROM sys.partition_range_values
    WHERE function_id = OBJECT_ID('PF_PriceDate');

    -- Determine the next partition boundary (next year in this case)
    SET @nextPartitionDate = DATEADD(YEAR, 1, @currentMaxPartitionDate);

    -- Check if the next partition already exists
    IF NOT EXISTS (
        SELECT 1
        FROM sys.partition_range_values
        WHERE function_id = OBJECT_ID('PF_PriceDate')
        AND value = @nextPartitionDate
    )
    BEGIN
        -- Add the new partition for the next year by splitting the last partition
        PRINT 'Adding partition for date: ' + CONVERT(VARCHAR, @nextPartitionDate);

        ALTER PARTITION FUNCTION PF_PriceDate()
        SPLIT RANGE (@nextPartitionDate);
    END
    ELSE
    BEGIN
        PRINT 'Partition for ' + CONVERT(VARCHAR, @nextPartitionDate) + ' already exists.';
    END
END;
```

#### Explanation:
- **`sys.partition_range_values`**: This system view allows you to query the existing partitions and their boundary values. The procedure checks for the **latest partition** and calculates the next partition boundary (e.g., the next year).
- **`SPLIT RANGE`**: This command adds a new partition by splitting the current one at the next boundary value.

### 3. **Schedule the Stored Procedure with SQL Server Agent**:
You can use **SQL Server Agent** to schedule this stored procedure to run automatically, for example, once a week, once a month, or before new data is expected.

#### Create a SQL Server Agent Job:

1. **Open SQL Server Management Studio (SSMS)**.
2. **Expand SQL Server Agent** in Object Explorer.
3. Right-click on **Jobs** and choose **New Job**.
4. **Name the Job**: Example: `AutoPartitionManagement`.
5. **Steps**:
   - Create a new job step and select **Transact-SQL script (T-SQL)** as the type.
   - Enter the following T-SQL script to execute the stored procedure:
     ```sql
     EXEC AddNewPartitionForNextYear;
     ```
6. **Schedule**:
   - Set a schedule for the job. For example, you can set it to run monthly, or any interval that fits your data arrival pattern (daily, weekly, etc.).

7. **Monitor the Job**:
   - You can set alerts if the job fails or check the SQL Server Agent history to ensure the partitions are being created on time.

### 4. **Handling Partition Splitting and Managing Growth**:
- **Plan Ahead**: It's a good idea to create new partitions **ahead of time** to avoid having to split a partition during peak usage times. You might create partitions for the next month or year at the start of the current period.
- **Splitting Partitions**: Partition splitting moves data into a new partition, which can be resource-intensive if a large number of records need to be moved. Try to do this during **off-peak hours** or preemptively to avoid performance issues.
  
### Example Workflow:
Here’s how the automated partition management workflow could look:

1. **Schedule a Weekly Job**:
   - You schedule the `AddNewPartitionForNextYear` stored procedure to run once a week via SQL Server Agent.

2. **Job Runs Weekly**:
   - The stored procedure checks the partitioning scheme to see if a partition exists for the next year.
   - If no partition exists for the next year, it will add one by splitting the last partition.

3. **New Data Arrives**:
   - When new data is inserted into the table, SQL Server will automatically place the data into the appropriate partition (e.g., the new year).

4. **Monitor Partition Growth**:
   - Keep track of partition sizes and manage them (e.g., merging old partitions or archiving data) to maintain efficient performance.

### 5. **Archiving Old Data**:
You can automate the **archiving** of old data (e.g., moving old partitions to a separate table or archiving to another database) by using a similar technique. SQL Server allows you to **switch out partitions** quickly, which is much faster than row-by-row deletion.

- **Example**: Switch out a partition:
  
   ```sql
   ALTER TABLE dbo.edi_prices
   SWITCH PARTITION 1 TO dbo.edi_prices_archive PARTITION 1;
   ```

This quickly moves all data from the first partition of `edi_prices` to the first partition of `edi_prices_archive`, without the overhead of a `DELETE` operation.

### Summary:
- **Partitioning Automation**: While SQL Server doesn't automatically add partitions, you can automate this process using stored procedures and SQL Server Agent jobs.
- **Stored Procedure**: Write a stored procedure that checks for the need to add new partitions (based on your partitioning column) and splits the existing partition to create a new one.
- **SQL Server Agent**: Schedule the stored procedure to run periodically (weekly, monthly) to ensure new partitions are created ahead of time, avoiding runtime partition splits.
- **Archiving**: Manage old partitions using `SWITCH` to quickly move data to archive tables.

By automating partition management, you can ensure your table partitions stay optimized without manual intervention. Let me know if you need further clarification or additional examples!
