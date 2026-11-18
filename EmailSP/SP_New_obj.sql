CREATE OR REPLACE PROCEDURE SP_DWF_SEND_EMAIL_ALERT_AD("RUN_TYPE" VARCHAR, "MAIL_INTEGRATION" VARCHAR)
RETURNS VARCHAR
LANGUAGE JAVASCRIPT
EXECUTE AS CALLER
AS 

var mailIntegration = MAIL_INTEGRATION
/* Normalize procedure parameter */
var runType = RUN_TYPE
    ? RUN_TYPE.toString().trim().toUpperCase()
    : '''';

if (runType !== ''FOUR_HOURLY'' && runType !== ''DAILY'') {
    return ''Invalid RUN_TYPE: '' + runType +
           ''. Accepted values are FOUR_HOURLY or DAILY.'';
}

var currentDate = new Date().toISOString().split(''T'')[0];



var emailRecipients = '''';

var sqlCmd = `
    SELECT DISTINCT
           OPS_EMAIL_RECEIPIENTS,
           BUSINESS_EMAIL_RECEIPIENTS
    FROM METADATA.LOAD_FREQUENCY_CONFIG
    WHERE PROJECT_NAME = ''AWF''
`;

var stmt = snowflake.createStatement({ sqlText: sqlCmd });
var rs = stmt.execute();

var emailSet = new Set();

while (rs.next()) {
    var opsEmail = rs.getColumnValue(1);
    var businessEmail = rs.getColumnValue(2);

    if (opsEmail) {
        opsEmail.split('','').forEach(email => emailSet.add(email.trim()));
    }

    if (businessEmail) {
        businessEmail.split('','').forEach(email => emailSet.add(email.trim()));
    }
}

var emailRecipients = Array.from(emailSet).join('','');




/* Initialize all message variables outside the conditions */
var failedTables = '''';
var newColumnsDetected = '''';
var validationMessage = '''';
var skippedMsg = '''';
var NewTablesMsg = '''';


/* =========================================================
   FOUR-HOURLY LOGIC
   Your existing code up to approximately line 199 goes here
   ========================================================= */

if (runType === ''FOUR_HOURLY'') {

    var subjectLine = ''Adobe Workfront Alert | Audit Execution Summary |'' + currentDate ;

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
            newCols.toString().includes(''NEW IN SRC'')
        ) {
            newCols = newCols
                .toString()
                .split('' | '')
                .filter(function(item) {
                    return item.includes(''NEW IN SRC'');
                })
                .map(function(item) {
                    return item.split('' | '')[0];
                })
                .join('', '');
        }

        if (
            status &&
            status.toString().toUpperCase() === ''FAILED''
        ) {
            failedTables +=
                tableName + '' : '' +
                (errorMsg || ''No Error Message'') +
                (newCols ? '' : '' + newCols : '''') +
                ''\\n'';

        } else if (
            status &&
            status.toString().toUpperCase() !== ''FAILED'' &&
            newCols &&
            newCols.toString().trim() !== '''' &&
            columnMap &&
            columnMap.toString().trim() !== ''''
        ) {
            newColumnsDetected +=
                tableName + '' : '' +
                columnMap + '' : '' +
                newCols + ''\\n'';
        }
    }


    /* Threshold / Drift Logic */

    var driftTables = [];

    var thresholdSql = `
        with cte as (SELECT

            a.TABLE_NAME,

            a.WATERMARK_COL,

            a.WATERMARK_FROM,

            a.ROWS_INSERTED,

            c.ALLOWED_DRIFT_PERC,

            c.MIN_THRESHOLD_COUNT,

            c.BUSINESS_EMAIL_RECEIPIENTS,

            c.OPS_EMAIL_RECEIPIENTS,

            b.TGT_DATABASE,

            b.TGT_SCHEMA,

            a.status

        FROM METADATA.DWF_SILVER_AUDIT_LOG a

        JOIN METADATA.DWF_SILVER_TABLE_CONFIG b

            ON a.TABLE_METADATA_ID = b.ID

        JOIN METADATA.LOAD_FREQUENCY_CONFIG c

            ON c.TABLE_NAME = a.TABLE_NAME

        WHERE b.IS_ACTIVE = TRUE

          AND c.RULE_ENABLE_FLAG = ''TRUE''

        QUALIFY ROW_NUMBER() OVER (

            PARTITION BY a.TABLE_NAME

            ORDER BY a.CREATED_TS DESC

        ) = 1)

        select * from cte where  UPPER(STATUS) = ''SUCCESS'';
 
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
            targetDatabase + ''.'' +
            targetSchema + ''.'' +
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
                '' | Previous RowCount: '' +
                beforeWatermarkCount +
                '' | Current RowCount: '' +
                Number(beforeWatermarkCount + rowsInserted) +
                '' | Allowed Drift: '' +
                allowedDrift + ''%'' +
                '' | Actual Drift: '' +
                actualDrift + ''%''
            );
        }
    }

    if (driftTables.length > 0) {
        validationMessage =
            ''Tables exceeding allowed drift percentage:\\n'' +
            ''------------------------------------------------\\n'' +
            driftTables.join(''\\n'');
    }
}


/* =========================================================
   DAILY LOGIC
   check for failure loads for EDW
   Check for two consecutive skipped Silver loads
   ========================================================= */

else if (runType === ''DAILY'') {

    var subjectLine = ''Adobe Workfront Alert | Audit Execution Summary |'' + currentDate ;

    /* =====================================================
       EDW MODEL TABLE FAILURE LOGIC
       ===================================================== */

    var edwFailureSql = `
       with CTE as (SELECT

            a.TGT_TABLE,

            split_part(a.error_message,''|'',1) as ERROR_MESSAGE ,

            a.CREATED_TS,

            a.status

        FROM METADATA.DWF_MODEL_TABLE_AUDIT_LOG a

        JOIN METADATA.DWF_MODEL_TABLE_CONFIG b ON a.LOAD_CONFIG_ID = b.CONFIG_ID

        WHERE CAST(a.CREATED_TS AS DATE) = CURRENT_DATE()

          AND b.IS_ACTIVE = TRUE

        QUALIFY ROW_NUMBER() OVER (

            PARTITION BY a.LOAD_CONFIG_ID

            ORDER BY a.CREATED_TS DESC

        ) = 1) 

        select * from cte where UPPER(STATUS) = ''FAILED''
 
        
    `;

    var edwFailureStmt = snowflake.createStatement({
        sqlText: edwFailureSql
    });

    var edwFailureRs = edwFailureStmt.execute();

    while (edwFailureRs.next()) {

        var edwTableName = edwFailureRs.getColumnValue(1);
        var edwErrorMsg = edwFailureRs.getColumnValue(2);

        failedTables +=
            edwTableName + '' : '' +
            (edwErrorMsg || ''No Error Message'') +
            ''\\n'';
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
        WHERE UPPER(STATUS) = ''SKIPPED''
          AND UPPER(PREV_STATUS) = ''SKIPPED''
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
            ''The following tables had 2 consecutive '' +
            ''SKIPPED loads on the current date:\\n'' +
            ''------------------------------------------------\\n'' +
            skippedTables.join(''\\n'');
    }

    /* =========================================================
        Check for New Tables in Silver
       ========================================================= */

    var rs = snowflake.createStatement({
        sqlText: `SELECT CURRENT_DATABASE()`
        }).execute();

        rs.next();
        var CURRENT_DB = rs.getColumnValue(1);

        var SRC_DATABASE          = ''WORKFRONT'';
        var SRC_SCHEMA            = ''WF_LISTINGS'';
        var TGT_DATABASE          = CURRENT_DB;
        var TGT_SCHEMA            = ''SILVER'';
        

        var LOAD_TYPE             = ''FULL'';
        var WATERMARK_COL         = ''DL_LOAD_TIMESTAMP'';
        var WATERMARK_TYPE        = ''TIMESTAMP'';
        var HAS_COLUMN_DRIFT      = ''NO'';

        var IS_ACTIVE             = false;
        var HAS_SKIP_CHECK        = false;
        var APPLY_SELECT_DISTINCT = false;
        var COMMENTS              = ''NEW TABLE DETECTED IN ADOBE WORKFRONT SOURCE ON DATE '' + currentDate ; 

        /*
        Step 1: Check whether the source table is missing
        from SILVER and the configuration table.
        */
        var checkSql = `
        SELECT t1.TABLE_NAME
        FROM WORKFRONT.INFORMATION_SCHEMA.TABLES t1
        WHERE t1.TABLE_SCHEMA = ''WF_LISTINGS''
        --AND t1.TABLE_NAME in (''ACCESSLEVELS_EVENT'', ''ACCESSRULES_EVENT'')
        AND NOT EXISTS (
            SELECT 1
            FROM INFORMATION_SCHEMA.TABLES t2
            WHERE t2.TABLE_SCHEMA = ''SILVER''
            AND t2.TABLE_NAME = t1.TABLE_NAME
        )
        AND NOT EXISTS (
            SELECT 1
            FROM METADATA.DWF_SILVER_TABLE_CONFIG t3
            WHERE t3.TABLE_NAME = t1.TABLE_NAME
        )
        `;

        var checkStmt = snowflake.createStatement({
        sqlText: checkSql
        });

        var resultSet = checkStmt.execute();
        var insertedCount = 0;
        var newTables = [];

        /*
        Step 2: Insert the missing table into the config table.
        */
        while (resultSet.next()) {

        var missingTableName = resultSet.getColumnValue(1);
        newTables.push(missingTableName);

        var insertSql = `
        INSERT INTO METADATA.DWF_SILVER_TABLE_CONFIG
        (
            SRC_DATABASE,
            SRC_SCHEMA,
            TGT_DATABASE,
            TGT_SCHEMA,
            TABLE_NAME,
            IS_ACTIVE,
            LOAD_TYPE,
            WATERMARK_COL,
            WATERMARK_TYPE,
            HAS_COLUMN_DRIFT,
            CREATED_TS,
            UPDATED_TS,
            HAS_SKIP_CHECK,
            APPLY_SELECT_DISTINCT,
            COMMENTS
        )
        VALUES
        (
            ?,
            ?,
            ?,
            ?,
            ?,
            ${IS_ACTIVE},
            ?,
            ?,
            ?,
            ?,
            CURRENT_TIMESTAMP(),
            CURRENT_TIMESTAMP(),
            ${HAS_SKIP_CHECK},
            ${APPLY_SELECT_DISTINCT},
            ?
        )
        `;

        var insertStmt = snowflake.createStatement({
        sqlText: insertSql,
        binds: [
            SRC_DATABASE,
            SRC_SCHEMA,
            TGT_DATABASE,
            TGT_SCHEMA,
            missingTableName,
            LOAD_TYPE,
            WATERMARK_COL,
            WATERMARK_TYPE,
            HAS_COLUMN_DRIFT,
            COMMENTS
        ]
        });

        insertStmt.execute();
        


        }

        if (newTables.length > 0) {
        NewTablesMsg =
            ''Following New tables found in source database which are not present in Silver \\n'' + 
            newTables.join('', '');
        }


}


/* =========================================================
   COMMON EMAIL-BODY CREATION
   Runs after either FOUR_HOURLY or DAILY logic
   ========================================================= */

if (
    failedTables.trim() !== '''' ||
    newColumnsDetected.trim() !== '''' ||
    validationMessage.trim() !== '''' ||
    skippedMsg.trim() !== '''' ||
    NewTablesMsg.trim() !== ''''
) {
    var emailBody =
        ''Hello Team,\\n\\n'' +
        ''The audit execution has identified the following '' +
        ''items requiring attention.\\n\\n'';

    if (failedTables.trim() !== '''') {
        emailBody +=
            ''FAILED TABLES\\n'' +
            ''------------------------------------------------\\n'' +
            failedTables +
            ''\\n'';
    }

    if (newColumnsDetected.trim() !== '''') {
        emailBody +=
            ''NEW COLUMNS DETECTED\\n'' +
            ''------------------------------------------------\\n'' +
            newColumnsDetected +
            ''\\n'';
    }

    if (validationMessage.trim() !== '''') {
        emailBody +=
            ''DRIFT VALIDATION ALERT\\n'' +
            ''------------------------------------------------\\n'' +
            validationMessage +
            ''\\n\\n'';
    }

    if (skippedMsg.trim() !== '''') {
        emailBody +=
            ''CONSECUTIVE SKIPPED-LOAD ALERT\\n'' +
            ''------------------------------------------------\\n'' +
            skippedMsg +
            ''\\n\\n'';
    }

    if (NewTablesMsg.trim() !== '''') {
        emailBody +=
            ''New Source Tables Detected\\n'' +
            ''------------------------------------------------\\n'' +
            NewTablesMsg +
            ''\\n\\n'';
    }

    emailBody +=
        ''To retrieve detailed information about the audit log, please check the following tables in Snowflake:\\n'' +
        ''For Silver :\\n''+
        ''Table Name : METADATA.DWF_SILVER_AUDIT_LOG\\n''+
        ''For EDW :\\n''+
        ''Table Name :METADATA.DWF_MODEL_TABLE_AUDIT_LOG\\n\\n''+

        ''Please review and take appropriate action.\\n\\n'' +
        ''Regards,\\n'' +
        ''Data Analytics Team'';

    
}
if (emailBody && emailRecipients) {

    return emailBody;
}

return ''No audit alert conditions detected for '' + runType;

';




call SP_DWF_SEND_EMAIL_ALERT_AD ('DAILY' , 'SP_DWF_SEND_EMAIL_ALERT_AD');