CREATE OR REPLACE PROCEDURE METADATA.SP_ARCHIVE_SILVER_TABLES(
    P_ARCHIVE_STAGE VARCHAR
)
RETURNS VARCHAR
LANGUAGE JAVASCRIPT
EXECUTE AS OWNER
AS
$$

var processedCount = 0;


/* Get all eligible audit records */
var sql_query = `
    SELECT
        a.LOG_ID,
        c.TGT_DATABASE,
        c.TGT_SCHEMA,
        c.TABLE_NAME,
        a.WATERMARK_COL,
        a.WATERMARK_FROM,
        a.WATERMARK_TO
    FROM METADATA.DWF_SILVER_TABLE_CONFIG c
    JOIN METADATA.DWF_SILVER_AUDIT_LOG a
        ON c.ID = a.TABLE_METADATA_ID
    WHERE c.IS_ARCHIVE = TRUE
      AND c.IS_ACTIVE = TRUE
      AND a.STATUS = 'SUCCESS'
      AND a.IS_ARCHIVED = FALSE
      AND a.WATERMARK_FROM IS NOT NULL
      AND a.WATERMARK_TO IS NOT NULL
    ORDER BY
        c.TABLE_NAME,
        a.WATERMARK_FROM
`;


var stmt = snowflake.createStatement({
    sqlText: sql_query
});

var rs = stmt.execute();


/* Loop through every audit record */
while (rs.next()) {

    var logId =
        rs.getColumnValue("LOG_ID");

    var tgtDatabase =
        rs.getColumnValue("TGT_DATABASE");

    var tgtSchema =
        rs.getColumnValue("TGT_SCHEMA");

    var tableName =
        rs.getColumnValue("TABLE_NAME");

    var watermarkCol =
        rs.getColumnValue("WATERMARK_COL");

    var watermarkFrom =
        rs.getColumnValue("WATERMARK_FROM");

    var watermarkTo =
        rs.getColumnValue("WATERMARK_TO");


    /* Create current date as YYYY-MM-DD */
    var dateStmt = snowflake.createStatement({
        sqlText: `SELECT TO_CHAR(CURRENT_DATE(), 'YYYY-MM-DD')`
    });

    var dateRs = dateStmt.execute();
    dateRs.next();

    var archiveDate =
        dateRs.getColumnValue(1);


    /* Source table */
    var sourceTable =
        '"' + tgtDatabase + '"."' +
        tgtSchema + '"."' +
        tableName + '"';


    /* Required folder:
       daily/<table_name>/<yyyy-mm-dd>/
    */
    var archivePath =
        P_ARCHIVE_STAGE +
        '/daily/' +
        tableName +
        '/' +
        archiveDate +
        '/';


    /* Archive records within this audit watermark range */
    var copySql = `

        COPY INTO ${archivePath}

        FROM
        (
            SELECT *
            FROM ${sourceTable}
            WHERE IDENTIFIER(?) >= TO_TIMESTAMP_NTZ(?)
              AND IDENTIFIER(?) <= TO_TIMESTAMP_NTZ(?)
        )

        FILE_FORMAT = (
            TYPE = PARQUET
            COMPRESSION = SNAPPY
        )

        HEADER = TRUE
        OVERWRITE = FALSE
    `;


    var copyStmt = snowflake.createStatement({
        sqlText: copySql,
        binds: [
            watermarkCol,
            String(watermarkFrom),
            watermarkCol,
            String(watermarkTo)
        ]
    });


    /* Archive data */
    copyStmt.execute();


    /* Update audit only after archive is successful */
    var updateSql = `

        UPDATE METADATA.DWF_SILVER_AUDIT_LOG

        SET
            IS_ARCHIVED = TRUE,
            ARCHIVED_AT = CURRENT_DATE()

        WHERE LOG_ID = ?
    `;


    var updateStmt = snowflake.createStatement({
        sqlText: updateSql,
        binds: [logId]
    });

    updateStmt.execute();


    processedCount++;
}


return 'ARCHIVE COMPLETED. '
       + processedCount
       + ' AUDIT RECORD(S) ARCHIVED.';

$$;