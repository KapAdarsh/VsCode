CREATE OR REPLACE PROCEDURE EDW.SP_SEND_AUDIT_ALERT_AD()
RETURNS STRING
LANGUAGE JAVASCRIPT
EXECUTE AS CALLER
AS
$$

var sql = `
WITH LATEST_RUNS AS (
    SELECT
        a.TABLE_NAME,
        a.STATUS,
        a.NEW_COLUMNS_DETECTED,
        a.ERROR_MESSAGE,
        a.CREATED_TS,
        a.COLUMNS_MAPPED
    FROM METADATA.DWF_SILVER_AUDIT_LOG a join METADATA.dwf_silver_table_config b ON a.table_metadata_id = b.id and b.IS_ACTIVE = 'TRUE'
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY a.TABLE_NAME
        ORDER BY a.CREATED_TS DESC
    ) = 1
)
SELECT
    TABLE_NAME,
    STATUS,
    NEW_COLUMNS_DETECTED,
    ERROR_MESSAGE,
    COLUMNS_MAPPED
FROM LATEST_RUNS`;

var stmt = snowflake.createStatement({sqlText: sql});
var rs = stmt.execute();

var failedTables = '';
var newColumnsDetected = '';

while (rs.next())
{
    var tableName = rs.getColumnValue(1);
    var status    = rs.getColumnValue(2);
    var newCols   = rs.getColumnValue(3);
    var errorMsg  = rs.getColumnValue(4);
    var columnMap = rs.getColumnValue(5);

    if (newCols && newCols.toString().includes('NEW IN SRC'))
        {
            newCols = newCols.toString()
            .split(' | ')
            .filter(item => item.includes('NEW IN SRC'))
            .map(item => item.split(' | ')[0])
            .join(', ');
        }

    if (status && status.toUpperCase() === 'FAILED')
    {
        failedTables +=
            tableName + ' : ' +
            (errorMsg || 'No Error Message') + ' ' +(newCols) +'\n';
    }
    else if (
        status &&
        status.toUpperCase() !== 'FAILED' &&
        newCols &&
        newCols.toString().trim() !== '' &&
        columnMap &&
        columnMap.toString().trim() !== ''
    )
    {
        newColumnsDetected +=
            tableName + ' : ' +
            columnMap + ' : ' +
            newCols + '\n';
    }
}
/* Threshold Logic */
var driftTables = [];
var minimumThresholdTables = [];

var sqlText = `
    SELECT
        a.TABLE_NAME,
        a.WATERMARK_COL,
        a.WATERMARK_FROM,
        a.ROWS_INSERTED,
        c.ALLOWED_DRIFT_PERC,
        c.MIN_THRESHOLD_COUNT,
        c.BUSINESS_EMAIL_RECEIPIENTS,
        c.OPS_EMAIL_RECEIPIENTS,
        b.TGT_DATABASE,
        b.TGT_SCHEMA
    FROM METADATA.DWF_SILVER_AUDIT_LOG a
    JOIN METADATA.DWF_SILVER_TABLE_CONFIG b
        ON a.TABLE_METADATA_ID = b.ID
    JOIN METADATA.LOAD_FREQUENCY_CONFIG c
        ON c.TABLE_NAME = a.TABLE_NAME
    WHERE b.IS_ACTIVE = TRUE
      AND a.STATUS = 'SUCCESS'
      AND c.RULE_ENABLE_FLAG = TRUE
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY a.TABLE_NAME
        ORDER BY a.CREATED_TS DESC
    ) = 1
`;

var rs = snowflake.createStatement({
    sqlText: sqlText
}).execute();

while (rs.next()) {

    var tableName = rs.getColumnValue(1);
    var watermarkCol = rs.getColumnValue(2);
    var watermarkFrom = rs.getColumnValue(3);
    var rowsInserted = Number(rs.getColumnValue(4));
    var allowedDrift = Number(rs.getColumnValue(5));
    var minimumThreshold = Number(rs.getColumnValue(6));
    var businessRecipients = rs.getColumnValue(7);
    var opsRecipients = rs.getColumnValue(8);
    var targetDatabase = rs.getColumnValue(9);
    var targetSchema = rs.getColumnValue(10);

    var countSql =
        `SELECT COUNT(*)
         FROM IDENTIFIER(?)
         WHERE IDENTIFIER(?) < ?`;

    var tablePath =
        targetDatabase + "." +
        targetSchema + "." +
        tableName;

    var countRs = snowflake.createStatement({
        sqlText: countSql,
        binds: [
            tablePath,
            watermarkCol,
            watermarkFrom
        ]
    }).execute();

    countRs.next();

    var beforeWatermarkCount =
        Number(countRs.getColumnValue(1));

    var actualDrift = 0;

    if (beforeWatermarkCount > 0) {
        actualDrift = Number(
            (
                rowsInserted /
                beforeWatermarkCount *
                100
            ).toFixed(2)
        );
    }

    if (actualDrift > allowedDrift) {

        driftTables.push(
            tableName +
            " | Previous RowCount: " + beforeWatermarkCount +
            " | Current RowCount: " + Number(beforeWatermarkCount + rowsInserted) +
            " | Allowed Drift: " + allowedDrift + "%" +
            " | Actual Drift: " + actualDrift + "%" 
            
        );
    }

    /*if (rowsInserted < minimumThreshold) {

        minimumThresholdTables.push(
            tableName +
            " | Minimum Threshold: " + minimumThreshold +
            " | Rows Inserted: " + rowsInserted +
            
        );
    }*/
}

var validationMessage = "";

if (driftTables.length > 0) {

    validationMessage +=
        "Tables exceeding allowed drift percentage:\n\n" +
        driftTables.join("\n");
}

/*if (minimumThresholdTables.length > 0) {

    if (validationMessage !== "") {
        validationMessage += "\n\n";
    }

    validationMessage +=
        "Tables below minimum threshold count:\n\n" +
        minimumThresholdTables.join("\n");
}*/

/* for 2 cosecutive loads */

var sqlText = `
WITH today_loads AS (
    SELECT
        TABLE_NAME,
        STATUS,
        CREATED_TS,
        LAG(STATUS) OVER (
            PARTITION BY TABLE_NAME
            ORDER BY CREATED_TS
        ) AS PREV_STATUS
    FROM METADATA.DWF_SILVER_AUDIT_LOG
    WHERE CAST(CREATED_TS AS DATE) = CURRENT_DATE()
)
SELECT DISTINCT TABLE_NAME
FROM today_loads
WHERE STATUS = 'SKIPPED'
  AND PREV_STATUS = 'SKIPPED'
`;

var stmt = snowflake.createStatement({sqlText: sqlText});
var rs = stmt.execute();

var skippedTables = [];

while (rs.next()) {
    skippedTables.push(rs.getColumnValue(1));
}

var currentDateRs = snowflake.createStatement({
    sqlText: "SELECT CURRENT_DATE()"
}).execute();

currentDateRs.next();
var currentDate = currentDateRs.getColumnValue(1);

var skippedMsg = null;

if (skippedTables.length > 0) {
    skippedMsg =
        'The following tables had 2 consecutive SKIPPED loads on ' +
        currentDate +
        ':\n\n' +
        skippedTables.join(', ');
}



/* Creating Email Body */
if (failedTables.trim() !== '' || newColumnsDetected.trim() !== '' || validationMessage.trim() !==  '')
{
    var emailBody =
        'Hello Team,\n\n' +
        'The latest audit execution has identified the following items requiring attention.\n\n';

    if (failedTables.trim() !== '')
    {
        emailBody +=
            'FAILED TABLES\n' +
            '------------------------------------------------\n' +
            failedTables +
            '\n';
    }

    if (newColumnsDetected.trim() !== '')
    {
        emailBody +=
            'SUCCESSFUL / SKIPPED tables\n' +
            '------------------------------------------------\n' +
            newColumnsDetected +
            '\n';
    }

    if (validationMessage.trim() !== '')
    {
        emailBody+=
            '\n' +
            validationMessage +
            '\n'
    }

    if (skippedMsg.trim() !== '')
    {
        emailBody+=
        '\n'+
        skippedMsg +
        '\n'
    }

    emailBody +=
        'Please review and take appropriate action.\n\n' +
        'Regards,\n' +
        'DWF Audit Framework';

    return emailBody;
}

return  'No Failures or New Columns Detected';

$$;


call edw.SP_SEND_AUDIT_ALERT_AD ();