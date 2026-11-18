CREATE OR REPLACE PROCEDURE SP_ARCHIVE_TABLES()
RETURNS VARCHAR
LANGUAGE JAVASCRIPT
EXECUTE AS OWNER
AS
$$

var successTables = [];
var failedTables = [];

/*-------------------------------------------
  1. Get current date parts
-------------------------------------------*/

var dateSql = `
    SELECT
        TO_CHAR(CURRENT_DATE(), 'YYYY'),
        TO_CHAR(CURRENT_DATE(), 'MM'),
        TO_CHAR(CURRENT_DATE(), 'DD')
`;

var dateRs = snowflake.createStatement({
    sqlText: dateSql
}).execute();

dateRs.next();

var year  = dateRs.getColumnValue(1);
var month = dateRs.getColumnValue(2);
var day   = dateRs.getColumnValue(3);


/*-------------------------------------------
  2. Get tables which need archive
-------------------------------------------*/

var configSql = `
    SELECT
        SOURCE_DATABASE,
        SOURCE_SCHEMA,
        SOURCE_TABLE
    FROM YOUR_CONFIG_TABLE
    WHERE ARCHIVE_FLAG = TRUE
`;

var configRs = snowflake.createStatement({
    sqlText: configSql
}).execute();


/*-------------------------------------------
  3. Process every configured table
-------------------------------------------*/

while (configRs.next()) {

    var databaseName = configRs.getColumnValue(1);
    var schemaName   = configRs.getColumnValue(2);
    var tableName    = configRs.getColumnValue(3);

    try {

        var sourceTable =
            databaseName + "." +
            schemaName + "." +
            tableName;

        /*
          Example:
          @ADLS_STAGE/ARCHIVE/2026/10/16/ORDERS/
        */

        var archivePath =
            "@LND.AZURE_OD_WTP_OBS_TEST_1_UAT_STG/ARCHIVE/" +
            year + "/" +
            month + "/" +
            day + "/" +
            tableName + "/";


        /*------------------------------------
          4. Archive Snowflake data to ADLS
        ------------------------------------*/

        var copySql = `
            COPY INTO ${archivePath}
            FROM (
                SELECT *
                FROM ${sourceTable}
            )
            FILE_FORMAT = (
                TYPE = PARQUET
                COMPRESSION = SNAPPY
            )
            OVERWRITE = TRUE
        `;

        snowflake.createStatement({
            sqlText: copySql
        }).execute();

        successTables.push(tableName);

    }
    catch (err) {

        failedTables.push(
            tableName + " : " + err.message
        );
    }
}


/*-------------------------------------------
  5. Return final status
-------------------------------------------*/

return "Archived Tables: " +
       successTables.join(", ") +
       " | Failed Tables: " +
       failedTables.join(", ");

$$;

--