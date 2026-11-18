CREATE OR REPLACE PROCEDURE EDW.SP_SEND_AUDIT_ALERT_AD(RUN_TYPE STRING,  MAIL_INTEGRATION  VARCHAR)
RETURNS STRING
LANGUAGE JAVASCRIPT
EXECUTE AS CALLER
AS
$$

var mailIntegration = MAIL_INTEGRATION
/* Normalize procedure parameter */
var runType = RUN_TYPE
    ? RUN_TYPE.toString().trim().toUpperCase()
    : '';

if (runType !== 'FOUR_HOURLY' && runType !== 'DAILY') {
    return 'Invalid RUN_TYPE: ' + runType +
           '. Accepted values are FOUR_HOURLY or DAILY.';
}

var currentDate = new Date().toISOString().split('T')[0];



var emailRecipients = '';

var sqlCmd = `
    SELECT DISTINCT
           OPS_EMAIL_RECEIPIENTS,
           BUSINESS_EMAIL_RECEIPIENTS
    FROM METADATA.LOAD_FREQUENCY_CONFIG
    WHERE PROJECT_NAME = 'AWF'
`;

var stmt = snowflake.createStatement({ sqlText: sqlCmd });
var rs = stmt.execute();

var emailSet = new Set();

while (rs.next()) {
    var opsEmail = rs.getColumnValue(1);
    var businessEmail = rs.getColumnValue(2);

    if (opsEmail) {
        opsEmail.split(',').forEach(email => emailSet.add(email.trim()));
    }

    if (businessEmail) {
        businessEmail.split(',').forEach(email => emailSet.add(email.trim()));
    }
}

var emailRecipients = Array.from(emailSet).join(',');




/* Initialize all message variables outside the conditions */
var failedTables = '';
var newColumnsDetected = '';
var validationMessage = '';
var skippedMsg = '';


/* =========================================================
   FOUR-HOURLY LOGIC
   Your existing code up to approximately line 199 goes here
   ========================================================= */

if (runType === 'FOUR_HOURLY') {

    var subjectLine = 'Adobe Workfront Alert | Audit Execution Summary |' + currentDate ;

    /* Latest Run Failure and New Column Logic */

    var latestRunSql = `
        WITH LATEST_RUNS AS (
            SELECT
                a.TABLE_NAME,
                a.STATUS,
                a.NEW_COLUMNS_DETECTED,
                a.ERROR_MESSAGE,
                a.CREATED_TS,
                a.COLUMNS_MAPPED
            FROM METADATA.DWF_SILVER_AUDIT_LOG a
            JOIN METADATA.DWF_SILVER_TABLE_CONFIG b
                ON a.TABLE_METADATA_ID = b.ID
            WHERE b.IS_ACTIVE = TRUE
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
        FROM LATEST_RUNS
    `;

    var latestRunStmt = snowflake.createStatement({
        sqlText: latestRunSql
    });

    var latestRunRs = latestRunStmt.execute();

    while (latestRunRs.next()) {

        var tableName = latestRunRs.getColumnValue(1);
        var status = latestRunRs.getColumnValue(2);
        var newCols = latestRunRs.getColumnValue(3);
        var errorMsg = latestRunRs.getColumnValue(4);
        var columnMap = latestRunRs.getColumnValue(5);

        if (
            newCols &&
            newCols.toString().includes('NEW IN SRC')
        ) {
            newCols = newCols
                .toString()
                .split(' | ')
                .filter(function(item) {
                    return item.includes('NEW IN SRC');
                })
                .map(function(item) {
                    return item.split(' | ')[0];
                })
                .join(', ');
        }

        if (
            status &&
            status.toString().toUpperCase() === 'FAILED'
        ) {
            failedTables +=
                tableName + ' : ' +
                (errorMsg || 'No Error Message') +
                (newCols ? ' : ' + newCols : '') +
                '\n';

        } else if (
            status &&
            status.toString().toUpperCase() !== 'FAILED' &&
            newCols &&
            newCols.toString().trim() !== '' &&
            columnMap &&
            columnMap.toString().trim() !== ''
        ) {
            newColumnsDetected +=
                tableName + ' : ' +
                columnMap + ' : ' +
                newCols + '\n';
        }
    }


    /* Threshold / Drift Logic */

    var driftTables = [];

    var thresholdSql = `
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
          AND UPPER(a.STATUS) = 'SUCCESS'
          AND c.RULE_ENABLE_FLAG = TRUE
        QUALIFY ROW_NUMBER() OVER (
            PARTITION BY a.TABLE_NAME
            ORDER BY a.CREATED_TS DESC
        ) = 1
    `;

    var thresholdStmt = snowflake.createStatement({
        sqlText: thresholdSql
    });

    var thresholdRs = thresholdStmt.execute();

    while (thresholdRs.next()) {

        var tableName = thresholdRs.getColumnValue(1);
        var watermarkCol = thresholdRs.getColumnValue(2);
        var watermarkFrom = thresholdRs.getColumnValue(3);
        var rowsInserted = Number(thresholdRs.getColumnValue(4));
        var allowedDrift = Number(thresholdRs.getColumnValue(5));
        var minimumThreshold = Number(thresholdRs.getColumnValue(6));
        var businessRecipients = thresholdRs.getColumnValue(7);
        var opsRecipients = thresholdRs.getColumnValue(8);
        var targetDatabase = thresholdRs.getColumnValue(9);
        var targetSchema = thresholdRs.getColumnValue(10);

        /*
          Skip drift calculation when required watermark
          information is unavailable.
        */
        if (
            watermarkCol === null ||
            watermarkFrom === null ||
            targetDatabase === null ||
            targetSchema === null
        ) {
            continue;
        }

        var tablePath =
            targetDatabase + '.' +
            targetSchema + '.' +
            tableName;

        var countSql = `
            SELECT COUNT(*)
            FROM IDENTIFIER(?)
            WHERE IDENTIFIER(?) < ?
        `;

        var countStmt = snowflake.createStatement({
            sqlText: countSql,
            binds: [
                tablePath,
                watermarkCol,
                watermarkFrom
            ]
        });

        var countRs = countStmt.execute();
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
                ' | Previous RowCount: ' +
                beforeWatermarkCount +
                ' | Current RowCount: ' +
                Number(beforeWatermarkCount + rowsInserted) +
                ' | Allowed Drift: ' +
                allowedDrift + '%' +
                ' | Actual Drift: ' +
                actualDrift + '%'
            );
        }
    }

    if (driftTables.length > 0) {
        validationMessage =
            'Tables exceeding allowed drift percentage:\n' +
            '------------------------------------------------\n' +
            driftTables.join('\n');
    }
}


/* =========================================================
   DAILY LOGIC
   check for failure loads for EDW
   Check for two consecutive skipped Silver loads
   ========================================================= */

else if (runType === 'DAILY') {

    var subjectLine = 'Adobe Workfront Alert | Audit Execution Summary |' + currentDate ;

    /* =====================================================
       EDW MODEL TABLE FAILURE LOGIC
       ===================================================== */

    var edwFailureSql = `
        SELECT
            a.TGT_TABLE,
            split_part(a.error_message,'|',1) as ERROR_MESSAGE ,
            a.CREATED_TS
        FROM METADATA.DWF_MODEL_TABLE_AUDIT_LOG a
        JOIN METADATA.DWF_MODEL_TABLE_CONFIG b ON a.LOAD_CONFIG_ID = b.CONFIG_ID
        WHERE CAST(a.CREATED_TS AS DATE) = CURRENT_DATE()
          AND UPPER(a.STATUS) = 'FAILED'
          AND b.IS_ACTIVE = TRUE
        QUALIFY ROW_NUMBER() OVER (
            PARTITION BY a.TABLE_NAME
            ORDER BY a.CREATED_TS DESC
        ) = 1
        
    `;

    var edwFailureStmt = snowflake.createStatement({
        sqlText: edwFailureSql
    });

    var edwFailureRs = edwFailureStmt.execute();

    while (edwFailureRs.next()) {

        var edwTableName = edwFailureRs.getColumnValue(1);
        var edwErrorMsg = edwFailureRs.getColumnValue(2);

        failedTables +=
            edwTableName + ' : ' +
            (edwErrorMsg || 'No Error Message') +
            '\n';
    }

    /* =========================================================
        Check for two consecutive skipped loads
       ========================================================= */

    var skippedSql = `
        WITH TODAY_LOADS AS (
            SELECT
                a.TABLE_NAME,
                a.STATUS,
                a.CREATED_TS,
                LAG(a.STATUS) OVER (
                    PARTITION BY a.TABLE_NAME
                    ORDER BY a.CREATED_TS
                ) AS PREV_STATUS
            FROM METADATA.DWF_SILVER_AUDIT_LOG a
            JOIN METADATA.DWF_SILVER_TABLE_CONFIG b
                ON a.TABLE_METADATA_ID = b.ID
            WHERE b.IS_ACTIVE = TRUE
                AND b.HAS_SKIP_CHECK = TRUE
              AND CAST(a.CREATED_TS AS DATE) = CURRENT_DATE()
        )
        SELECT DISTINCT TABLE_NAME
        FROM TODAY_LOADS
        WHERE UPPER(STATUS) = 'SKIPPED'
          AND UPPER(PREV_STATUS) = 'SKIPPED'
        ORDER BY TABLE_NAME
    `;

    var skippedStmt = snowflake.createStatement({
        sqlText: skippedSql
    });

    var skippedRs = skippedStmt.execute();

    var skippedTables = [];

    while (skippedRs.next()) {
        skippedTables.push(
            skippedRs.getColumnValue(1)
        );
    }

    if (skippedTables.length > 0) {
        skippedMsg =
            'The following  tables had 2 consecutive ' +
            'SKIPPED loads in SILVER on the current date:\n' + currentDate
            '------------------------------------------------\n' +
            skippedTables.join('\n');
    }
}


/* =========================================================
   COMMON EMAIL-BODY CREATION
   Runs after either FOUR_HOURLY or DAILY logic
   ========================================================= */

if (
    failedTables.trim() !== '' ||
    newColumnsDetected.trim() !== '' ||
    validationMessage.trim() !== '' ||
    skippedMsg.trim() !== ''
) {
    var emailBody =
        'Hello Team,\n\n' +
        'The audit execution has identified the following ' +
        'items requiring attention.\n\n';

    if (failedTables.trim() !== '') {
        emailBody +=
            'FAILED TABLES\n' +
            '------------------------------------------------\n' +
            failedTables +
            '\n';
    }

    if (newColumnsDetected.trim() !== '') {
        emailBody +=
            'NEW COLUMNS DETECTED\n' +
            '------------------------------------------------\n' +
            newColumnsDetected +
            '\n';
    }

    if (validationMessage.trim() !== '') {
        emailBody +=
            'DRIFT VALIDATION ALERT\n' +
            '------------------------------------------------\n' +
            validationMessage +
            '\n\n';
    }

    if (skippedMsg.trim() !== '') {
        emailBody +=
            'CONSECUTIVE SKIPPED-LOAD ALERT\n' +
            '------------------------------------------------\n' +
            skippedMsg +
            '\n\n';
    }

    emailBody +=
        'To retrieve detailed information about the audit log, please check the following tables in Snowflake:\n' +
        'For Silver :\n'+
        'Table Name : METADATA.DWF_SILVER_AUDIT_LOG\n'+
        'For EDW :\n'+
        'Table Name :METADATA.DWF_MODEL_TABLE_AUDIT_LOG\n\n'+

        'Please review and take appropriate action.\n\n' +
        'Regards,\n' +
        'DWF Audit Framework';

    
}
if (emailBody && emailRecipients) {

    var sqlCmd = `
        CALL SYSTEM$SEND_EMAIL(
            ?,
            ?,
            ?,
            ?
        )
    `;

    var stmt = snowflake.createStatement({
        sqlText: sqlCmd,
        binds: [mailIntegration,emailRecipients, subjectLine, emailBody]
    });

    stmt.execute();
    return 'Email sent'
}

return 'No audit alert conditions detected for ' + runType;

$$;

call SP_SEND_AUDIT_ALERT_AD('FOUR_HOURLY','POC_GENERIC_MAIL_NOTIFICATION');


