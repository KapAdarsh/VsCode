CREATE OR REPLACE PROCEDURE METADATA.SP_ARCHIVE_TABLES()
RETURNS VARCHAR
LANGUAGE JAVASCRIPT
EXECUTE AS OWNER
AS
$$

var STAGE_NAME = "EDW_AWF.AZURE_ADLS_BRONZE_LME_AWF_DEV_STAGE";

var successCount = 0;
var skippedCount = 0;
var failedCount  = 0;

var failedTables = [];

try {

    // Get previous  date
    var dateSql = `
        SELECT TO_VARCHAR(
            DATEADD(DAY, -1, CURRENT_DATE()),
            'YYYY-MM-DD'
        )
    `;

    var dateRs = snowflake.createStatement({
        sqlText: dateSql
    }).execute();

    dateRs.next();
    var archiveDate = dateRs.getColumnValue(1);


    // Get all tables enabled for archive
    var configSql = `
        SELECT
            SRC_DATABASE,
            SRC_SCHEMA,
            TABLE_NAME
        FROM METADATA.DWF_SILVER_TABLE_CONFIG
        WHERE IS_ARCHIVE = TRUE
        ORDER BY SRC_DATABASE, SRC_SCHEMA, TABLE_NAME
    `;

    var configRs = snowflake.createStatement({
        sqlText: configSql
    }).execute();


    while (configRs.next()) {

        var srcDatabase = configRs.getColumnValue("SRC_DATABASE");
        var srcSchema   = configRs.getColumnValue("SRC_SCHEMA");
        var tableName   = configRs.getColumnValue("TABLE_NAME");

        try {

            // Validate configuration
            if (
                srcDatabase === null ||
                srcSchema === null ||
                tableName === null
            ) {
                throw new Error(
                    "Database, schema or table name is null"
                );
            }


            var fullTableName =
                srcDatabase + "." +
                srcSchema + "." +
                tableName;


            // -------------------------------------------------------------
            // Check historical folder
            // -------------------------------------------------------------

            var historicalPath =
                "@" + STAGE_NAME +
                "/historical/" +
                tableName + "/";

            var historicalRs = snowflake.createStatement({
                sqlText: "LIST " + historicalPath
            }).execute();

            var historicalExists = historicalRs.next();


            // -------------------------------------------------------------
            // Historical does not exist
            // Archive complete table
            // -------------------------------------------------------------

            if (!historicalExists) {

                var fullArchiveSql =
                    "COPY INTO " + historicalPath + " " +
                    "FROM (" +
                        "SELECT * FROM " + fullTableName +
                    ") " +
                    "FILE_FORMAT = (" +
                        "TYPE = PARQUET " +
                        "COMPRESSION = SNAPPY" +
                    ") " +
                    "HEADER = TRUE " +
                    "OVERWRITE = TRUE";

                snowflake.createStatement({
                    sqlText: fullArchiveSql
                }).execute();

                successCount++;
            }


            // -------------------------------------------------------------
            // Historical exists
            // Archive yesterday data
            // -------------------------------------------------------------

            else {

                var dailyPath =
                    "@" + STAGE_NAME +
                    "/daily/" +
                    tableName + "/" +
                    archiveDate + "/";


                // Check whether daily file already exists
                var dailyListRs = snowflake.createStatement({
                    sqlText: "LIST " + dailyPath
                }).execute();


                if (dailyListRs.next()) {

                    skippedCount++;
                    continue;
                }


                // Check whether yesterday has records
                var recordCheckSql =
                    "SELECT 1 " +
                    "FROM " + fullTableName + " " +
                    "WHERE DL_LOAD_TIMESTAMP >= " +
                        "DATEADD(DAY, -1, CURRENT_DATE()) " +
                    "AND DL_LOAD_TIMESTAMP < CURRENT_DATE() " +
                    "LIMIT 1";

                var recordCheckRs = snowflake.createStatement({
                    sqlText: recordCheckSql
                }).execute();


                // No records available
                if (!recordCheckRs.next()) {

                    skippedCount++;
                    continue;
                }


                // ---------------------------------------------------------
                // Archive yesterday records
                // ---------------------------------------------------------

                var dailyArchiveSql =
                    "COPY INTO " + dailyPath + " " +
                    "FROM (" +
                        "SELECT * FROM " + fullTableName + " " +
                        "WHERE DL_LOAD_TIMESTAMP >= " +
                            "DATEADD(DAY, -1, CURRENT_DATE()) " +
                        "AND DL_LOAD_TIMESTAMP < CURRENT_DATE()" +
                    ") " +
                    "FILE_FORMAT = (" +
                        "TYPE = PARQUET " +
                        "COMPRESSION = SNAPPY" +
                    ") " +
                    "HEADER = TRUE " +
                    "OVERWRITE = TRUE";

                snowflake.createStatement({
                    sqlText: dailyArchiveSql
                }).execute();

                successCount++;
            }

        }
        catch (tableError) {

            failedCount++;

            failedTables.push(
                tableName + ": " + tableError.message
            );
        }
    }


    // -------------------------------------------------------------
    // Simple final output
    // -------------------------------------------------------------

    var result =
        "Archive process completed. " +
        "Success: " + successCount +
        ", Skipped: " + skippedCount +
        ", Failed: " + failedCount;

    if (failedCount > 0) {

        result +=
            ". Failed tables: " +
            failedTables.join(" | ");
    }

    return result;

}
catch (procedureError) {

    return "Archive procedure failed: " +
           procedureError.message;
}

$$;