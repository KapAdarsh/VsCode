CREATE OR REPLACE PROCEDURE METADATA.SP_ARCHIVE_TABLES()
RETURNS VARIANT
LANGUAGE JAVASCRIPT
EXECUTE AS OWNER
AS
$$
/*
===============================================================================
Purpose
-------------------------------------------------------------------------------
1. Read archive-enabled tables from METADATA.DWF_SILVER_TABLE_CONFIG.
2. Check whether historical/<TABLE_NAME>/ contains files.
3. If historical files do not exist:
      Export all records to historical/<TABLE_NAME>/.
4. If historical files exist:
      Export previous-day records to:
      daily/<TABLE_NAME>/<YYYY-MM-DD>/
5. Capture success, skipped, and failed table details.
6. One table failure does not stop the remaining tables.
===============================================================================
*/

// -----------------------------------------------------------------------------
// Configuration
// -----------------------------------------------------------------------------

var STAGE_NAME =
    "EDW_DEV.LND.AZURE_OD_WTP_OBS_TEST_1_UAT_STG";



// -----------------------------------------------------------------------------
// Helper function: safely quote Snowflake object identifiers
// -----------------------------------------------------------------------------




// -----------------------------------------------------------------------------
// Output variables
// -----------------------------------------------------------------------------

var processedTables = [];
var failedTables    = [];

var fullArchiveCount  = 0;
var dailyArchiveCount = 0;
var skippedCount      = 0;
var failedCount       = 0;


// -----------------------------------------------------------------------------
// Main procedure
// -----------------------------------------------------------------------------

try {

    // -------------------------------------------------------------------------
    // Determine previous archive date once for the complete procedure run
    // -------------------------------------------------------------------------

    var dateSql = `
        SELECT
            TO_VARCHAR(
                DATEADD(DAY, -1, CURRENT_DATE()),
                'YYYY-MM-DD'
            ) AS ARCHIVE_DATE
    `;

    var dateRs = snowflake.createStatement({
        sqlText: dateSql
    }).execute();

    dateRs.next();

    var archiveDate = dateRs.getColumnValue("ARCHIVE_DATE");


    // -------------------------------------------------------------------------
    // Read archive-enabled tables from configuration
    // -------------------------------------------------------------------------

    var configSql = `
        SELECT
            SRC_DATABASE,
            SRC_SCHEMA,
            TABLE_NAME
        FROM METADATA.DWF_SILVER_TABLE_CONFIG
        WHERE IS_ARCHIVE = TRUE
        ORDER BY
            SRC_DATABASE,
            SRC_SCHEMA,
            TABLE_NAME
    `;

    var configRs = snowflake.createStatement({
        sqlText: configSql
    }).execute();


    // -------------------------------------------------------------------------
    // Process each configured table
    // -------------------------------------------------------------------------

    while (configRs.next()) {

        var srcDatabase = configRs.getColumnValue("SRC_DATABASE");
        var srcSchema   = configRs.getColumnValue("SRC_SCHEMA");
        var tableName   = configRs.getColumnValue("TABLE_NAME");

        var fullTableName = null;
        var archiveType   = null;
        var targetPath    = null;

        try {

            // -----------------------------------------------------------------
            // Validate configuration values
            // -----------------------------------------------------------------

            if (
                srcDatabase === null ||
                srcSchema === null ||
                tableName === null
            ) {
                throw new Error(
                    "SRC_DATABASE, SRC_SCHEMA, or TABLE_NAME is null."
                );
            }


            // -----------------------------------------------------------------
            // Build fully qualified and safely quoted source table name
            // -----------------------------------------------------------------

            var fullTableName =
                srcDatabase + "." +
                srcSchema + "." +
                tableName;


            // -----------------------------------------------------------------
            // Check whether historical folder contains any files
            // -----------------------------------------------------------------

            var historicalPath =
                "@" + STAGE_NAME +
                "/historical/" + tableName + "/";

            var listHistoricalSql =
                "LIST " + historicalPath;

            var historicalRs = snowflake.createStatement({
                sqlText: listHistoricalSql
            }).execute();

            var historicalExists = historicalRs.next();


            // -----------------------------------------------------------------
            // First archive: historical folder has no files
            // -----------------------------------------------------------------

            if (!historicalExists) {

                archiveType = "FULL_HISTORICAL";
                targetPath  = historicalPath;

                var fullArchiveSql =
                    "COPY INTO " + historicalPath + " " +
                    "FROM (" +
                        "SELECT * " +
                        "FROM " + fullTableName +
                    ") " +
                    "FILE_FORMAT = ( TYPE = PARQUET
                                    COMPRESSION = SNAPPY)
                    HEADER = TRUE
                    OVERWRITE = TRUE";

                var fullArchiveRs = snowflake.createStatement({
                    sqlText: fullArchiveSql
                }).execute();


                // Capture records unloaded from COPY INTO output
                var fullRowsUnloaded = 0;
                var fullFilesCreated = 0;

                while (fullArchiveRs.next()) {

                    var rowsValue = fullArchiveRs.getColumnValue(2);

                    if (rowsValue !== null) {
                        fullRowsUnloaded += Number(rowsValue);
                    }

                    fullFilesCreated++;
                }


                processedTables.push({
                    status: "SUCCESS",
                    archive_type: archiveType,
                    database: srcDatabase,
                    schema: srcSchema,
                    table_name: tableName,
                    archive_date: null,
                    target_path: targetPath,
                    rows_unloaded: fullRowsUnloaded,
                    files_created: fullFilesCreated,
                    message: "Complete table archived successfully."
                });

                fullArchiveCount++;
            }


            // -----------------------------------------------------------------
            // Subsequent archive: export previous-day records
            // -----------------------------------------------------------------

            else {

                archiveType = "DAILY_INCREMENTAL";

                var dailyPath =
                    "@" + STAGE_NAME +
                    "/daily/" + tableName +
                    "/" + archiveDate + "/";

                targetPath = dailyPath;


                // -------------------------------------------------------------
                // Check whether the daily folder already contains files
                // Makes the procedure restart-safe for the same date
                // -------------------------------------------------------------

                var listDailySql =
                    "LIST " + dailyPath;

                var dailyListRs = snowflake.createStatement({
                    sqlText: listDailySql
                }).execute();

                var dailyFilesExist = dailyListRs.next();


                if (dailyFilesExist) {

                    processedTables.push({
                        status: "SKIPPED",
                        archive_type: archiveType,
                        database: srcDatabase,
                        schema: srcSchema,
                        table_name: tableName,
                        archive_date: archiveDate,
                        target_path: targetPath,
                        rows_unloaded: 0,
                        files_created: 0,
                        message: "Daily archive files already exist."
                    });

                    skippedCount++;
                    continue;
                }


                // -------------------------------------------------------------
                // Check whether previous-day source records exist
                // -------------------------------------------------------------

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

                var recordsExist = recordCheckRs.next();


                if (!recordsExist) {

                    processedTables.push({
                        status: "SKIPPED",
                        archive_type: archiveType,
                        database: srcDatabase,
                        schema: srcSchema,
                        table_name: tableName,
                        archive_date: archiveDate,
                        target_path: targetPath,
                        rows_unloaded: 0,
                        files_created: 0,
                        message:
                            "No records found for the previous archive date."
                    });

                    skippedCount++;
                    continue;
                }


                // -------------------------------------------------------------
                // Export previous-day records
                // -------------------------------------------------------------

                var dailyArchiveSql =
                    "COPY INTO " + dailyPath + " " +
                    "FROM (" +
                        "SELECT * " +
                        "FROM " + fullTableName + " " +
                        "WHERE DL_LOAD_TIMESTAMP >= " +
                            "DATEADD(DAY, -1, CURRENT_DATE()) " +
                        "AND DL_LOAD_TIMESTAMP < CURRENT_DATE()" +
                    ") " +
                    "FILE_FORMAT = (TYPE = PARQUET
                                    COMPRESSION = SNAPPY)
                    HEADER = TRUE
                    OVERWRITE = TRUE";

                var dailyArchiveRs = snowflake.createStatement({
                    sqlText: dailyArchiveSql
                }).execute();


                // Capture COPY INTO output
                var dailyRowsUnloaded = 0;
                var dailyFilesCreated = 0;

                while (dailyArchiveRs.next()) {

                    var dailyRowsValue =
                        dailyArchiveRs.getColumnValue(2);

                    if (dailyRowsValue !== null) {
                        dailyRowsUnloaded += Number(dailyRowsValue);
                    }

                    dailyFilesCreated++;
                }


                processedTables.push({
                    status: "SUCCESS",
                    archive_type: archiveType,
                    database: srcDatabase,
                    schema: srcSchema,
                    table_name: tableName,
                    archive_date: archiveDate,
                    target_path: targetPath,
                    rows_unloaded: dailyRowsUnloaded,
                    files_created: dailyFilesCreated,
                    message: "Previous-day records archived successfully."
                });

                dailyArchiveCount++;
            }

        } catch (tableError) {

            // -----------------------------------------------------------------
            // Table-level exception handling
            // Procedure continues with the next table
            // -----------------------------------------------------------------

            failedCount++;

            failedTables.push({
                status: "FAILED",
                archive_type: archiveType,
                database: srcDatabase,
                schema: srcSchema,
                table_name: tableName,
                target_path: targetPath,
                error_code:
                    tableError.code === undefined
                        ? null
                        : tableError.code,
                error_state:
                    tableError.state === undefined
                        ? null
                        : tableError.state,
                error_message:
                    tableError.message === undefined
                        ? String(tableError)
                        : tableError.message,
                stack_trace:
                    tableError.stackTraceTxt === undefined
                        ? null
                        : tableError.stackTraceTxt
            });
        }
    }


    // -------------------------------------------------------------------------
    // Final procedure result
    // -------------------------------------------------------------------------

    return {
        procedure_status:
            failedCount > 0
                ? "COMPLETED_WITH_ERRORS"
                : "SUCCESS",
        archive_date: archiveDate,
        stage_name: STAGE_NAME,
        summary: {
            full_historical_archives: fullArchiveCount,
            daily_incremental_archives: dailyArchiveCount,
            skipped_tables: skippedCount,
            failed_tables: failedCount,
            total_tables_processed:
                fullArchiveCount +
                dailyArchiveCount +
                skippedCount +
                failedCount
        },
        processed_tables: processedTables,
        failed_table_details: failedTables
    };

} catch (procedureError) {

    // -------------------------------------------------------------------------
    // Procedure-level exception handling
    // Covers config query, date query, and other framework-level failures
    // -------------------------------------------------------------------------

    return {
        procedure_status: "FAILED",
        error_level: "PROCEDURE",
        error_code:
            procedureError.code === undefined
                ? null
                : procedureError.code,
        error_state:
            procedureError.state === undefined
                ? null
                : procedureError.state,
        error_message:
            procedureError.message === undefined
                ? String(procedureError)
                : procedureError.message,
        stack_trace:
            procedureError.stackTraceTxt === undefined
                ? null
                : procedureError.stackTraceTxt,
        processed_tables: processedTables,
        failed_table_details: failedTables
    };
}
$$;