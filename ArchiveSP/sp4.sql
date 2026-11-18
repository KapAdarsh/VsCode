CREATE OR REPLACE PROCEDURE METADATA.SP_ARCHIVE_TABLES()
RETURNS VARCHAR
LANGUAGE JAVASCRIPT
EXECUTE AS OWNER
AS
$$

var STAGE_NAME = "EDW_AWF.AZURE_ADLS_BRONZE_LME_AWF_DEV_STAGE";

var successCount = 0;
var skippedCount = 0;


// Get previous date
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
    ORDER BY
        SRC_DATABASE,
        SRC_SCHEMA,
        TABLE_NAME
`;

var configRs = snowflake.createStatement({
    sqlText: configSql
}).execute();


while (configRs.next()) {

    var srcDatabase = configRs.getColumnValue("SRC_DATABASE");
    var srcSchema   = configRs.getColumnValue("SRC_SCHEMA");
    var tableName   = configRs.getColumnValue("TABLE_NAME");


    // Validate configuration
    if (
        srcDatabase === null ||
        srcSchema === null ||
        tableName === null
    ) {
        throw new Error(
            "Database, schema, or table name is null"
        );
    }


    var fullTableName =
        srcDatabase + "." +
        srcSchema + "." +
        tableName;


    // -------------------------------------------------------------
    // Check whether the historical archive exists
    // -------------------------------------------------------------

    var historicalPath =
        "@" + STAGE_NAME +
        "/historical/" +
        tableName + "/";

    var historicalListSql =
        "LIST " + historicalPath;

    var historicalRs = snowflake.createStatement({
        sqlText: historicalListSql
    }).execute();

    var historicalExists = historicalRs.next();


    // -------------------------------------------------------------
    // Historical archive does not exist
    // Archive the complete table
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
    // Historical archive exists
    // Archive only the previous day data
    // -------------------------------------------------------------

    else {

        var dailyPath =
            "@" + STAGE_NAME +
            "/daily/" +
            tableName + "/" +
            archiveDate + "/";


        // Check whether the daily archive already exists
        var dailyListSql =
            "LIST " + dailyPath;

        var dailyListRs = snowflake.createStatement({
            sqlText: dailyListSql
        }).execute();


        if (dailyListRs.next()) {

            skippedCount++;
            continue;
        }


        // Check whether the table has previous-day records
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


        // Skip when no records are available
        if (!recordCheckRs.next()) {

            skippedCount++;
            continue;
        }


        // ---------------------------------------------------------
        // Archive previous-day records
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


// Final output
return (
    "Archive process completed. " +
    "Success: " + successCount +
    ", Skipped: " + skippedCount
);

$$;