CREATE OR REPLACE PROCEDURE EDW_AWF.SP_ARCHIVE_TABLES_AD()
RETURNS VARCHAR
LANGUAGE JAVASCRIPT
EXECUTE AS CALLER
AS
$$

var STAGE_NAME = "EDW_AWF.AZURE_ADLS_BRONZE_LME_AWF_DEV_STAGE";

var successCount = 0;
var skippedCount = 0;


// -------------------------------------------------------------
// Get archive date for folder
// -------------------------------------------------------------

var dateSql = `
    SELECT TO_VARCHAR(CURRENT_DATE(), 'YYYY-MM-DD')
`;

var dateRs = snowflake.createStatement({
    sqlText: dateSql
}).execute();

dateRs.next();

var archiveDate = dateRs.getColumnValue(1);


// -------------------------------------------------------------
// Get tables configured for archive
// -------------------------------------------------------------

var configSql = `
    SELECT
        SRC_DATABASE,
        SRC_SCHEMA,
        TABLE_NAME,
        LAST_ARCHIVE_DATETIME
    FROM METADATA.DWF_SILVER_TABLE_CONFIG
    WHERE TABLE_NAME = 'USERS_EVENT'
    ORDER BY
        SRC_DATABASE,
        SRC_SCHEMA,
        TABLE_NAME
`;

var configRs = snowflake.createStatement({
    sqlText: configSql
}).execute();


// -------------------------------------------------------------
// Process each table
// -------------------------------------------------------------

while (configRs.next()) {

    var srcDatabase =
        configRs.getColumnValue("SRC_DATABASE");

    var srcSchema =
        configRs.getColumnValue("SRC_SCHEMA");

    var tableName =
        configRs.getColumnValue("TABLE_NAME");

    var lastArchiveDateTime =
        configRs.getColumnValue("LAST_ARCHIVE_DATETIME");


    // ---------------------------------------------------------
    // Validate configuration
    // ---------------------------------------------------------

    if (
        srcDatabase === null ||
        srcSchema === null ||
        tableName === null
    ) {
        throw new Error(
            "SRC_DATABASE, SRC_SCHEMA or TABLE_NAME is NULL"
        );
    }


    var fullTableName =
        srcDatabase + "." +
        srcSchema + "." +
        tableName;


    // ---------------------------------------------------------
    // Get current MAX(DL_LOAD_TIMESTAMP)
    // ---------------------------------------------------------

    var maxTimestampSql =
        "SELECT MAX(DL_LOAD_TIMESTAMP) " +
        "FROM " + fullTableName;

    var maxTimestampRs = snowflake.createStatement({
        sqlText: maxTimestampSql
    }).execute();

    maxTimestampRs.next();

    var currentMaxTimestamp =
        maxTimestampRs.getColumnValue(1);


    // ---------------------------------------------------------
    // Skip empty table
    // ---------------------------------------------------------

    if (currentMaxTimestamp === null) {

        skippedCount++;
        continue;
    }


    // =========================================================
    // INITIAL LOAD
    // LAST_ARCHIVE_DATETIME IS NULL
    // =========================================================

    if (lastArchiveDateTime === null) {

        var historicalPath =
            "@" + STAGE_NAME +
            "/historical/" +
            tableName + "/";


        // -----------------------------------------------------
        // Archive everything up to captured MAX timestamp
        // -----------------------------------------------------

        var historicalArchiveSql =
            "COPY INTO " + historicalPath + " " +
            "FROM (" +
                "SELECT * " +
                "FROM " + fullTableName + " " +
                "WHERE DL_LOAD_TIMESTAMP <= ?" +
            ") " +
            "FILE_FORMAT = (" +
                "TYPE = PARQUET " +
                "COMPRESSION = SNAPPY" +
            ") " +
            "HEADER = TRUE " +
            "OVERWRITE = TRUE";


        snowflake.createStatement({
            sqlText: historicalArchiveSql,
            binds: [currentMaxTimestamp]
        }).execute();


        // -----------------------------------------------------
        // Update watermark only after successful COPY INTO
        // -----------------------------------------------------

        var historicalUpdateSql = `
            UPDATE METADATA.DWF_SILVER_TABLE_CONFIG
            SET LAST_ARCHIVE_DATETIME = ?
            WHERE SRC_DATABASE = ?
              AND SRC_SCHEMA = ?
              AND TABLE_NAME = ?
        `;

        snowflake.createStatement({
            sqlText: historicalUpdateSql,
            binds: [
                currentMaxTimestamp,
                srcDatabase,
                srcSchema,
                tableName
            ]
        }).execute();


        successCount++;
    }


    // =========================================================
    // INCREMENTAL LOAD
    // LAST_ARCHIVE_DATETIME IS ALREADY AVAILABLE
    // =========================================================

    else {

        // -----------------------------------------------------
        // Check for new data after previous watermark
        // -----------------------------------------------------

        var recordCheckSql =
            "SELECT 1 " +
            "FROM " + fullTableName + " " +
            "WHERE DL_LOAD_TIMESTAMP > ? " +
            "AND DL_LOAD_TIMESTAMP <= ? " +
            "LIMIT 1";


        var recordCheckRs = snowflake.createStatement({
            sqlText: recordCheckSql,
            binds: [
                lastArchiveDateTime,
                currentMaxTimestamp
            ]
        }).execute();


        // No new records
        if (!recordCheckRs.next()) {

            skippedCount++;
            continue;
        }


        // -----------------------------------------------------
        // Daily archive path
        // -----------------------------------------------------

        var dailyPath =
            "@" + STAGE_NAME +
            "/daily/" +
            tableName + "/" +
            archiveDate + "/";


        // -----------------------------------------------------
        // Archive incremental records
        // -----------------------------------------------------

        var dailyArchiveSql =
            "COPY INTO " + dailyPath + " " +
            "FROM (" +
                "SELECT * " +
                "FROM " + fullTableName + " " +
                "WHERE DL_LOAD_TIMESTAMP > ? " +
                "AND DL_LOAD_TIMESTAMP <= ?" +
            ") " +
            "FILE_FORMAT = (" +
                "TYPE = PARQUET " +
                "COMPRESSION = SNAPPY" +
            ") " +
            "HEADER = TRUE " +
            "OVERWRITE = TRUE";


        snowflake.createStatement({
            sqlText: dailyArchiveSql,
            binds: [
                lastArchiveDateTime,
                currentMaxTimestamp
            ]
        }).execute();


        // -----------------------------------------------------
        // Update watermark after successful incremental COPY
        // -----------------------------------------------------

        var incrementalUpdateSql = `
            UPDATE METADATA.DWF_SILVER_TABLE_CONFIG
            SET LAST_ARCHIVE_DATETIME = ?
            WHERE SRC_DATABASE = ?
              AND SRC_SCHEMA = ?
              AND TABLE_NAME = ?
        `;


        snowflake.createStatement({
            sqlText: incrementalUpdateSql,
            binds: [
                currentMaxTimestamp,
                srcDatabase,
                srcSchema,
                tableName
            ]
        }).execute();


        successCount++;
    }
}


// -------------------------------------------------------------
// Final output
// -------------------------------------------------------------

return (
    "Archive process completed. " +
    "Success: " + successCount +
    ", Skipped: " + skippedCount
);

$$;