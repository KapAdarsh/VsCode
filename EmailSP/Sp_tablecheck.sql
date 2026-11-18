CREATE OR REPLACE PROCEDURE SP_INSERT_SILVER_TABLE_CONFIG()
RETURNS VARCHAR
LANGUAGE JAVASCRIPT
EXECUTE AS CALLER
AS
$$


/*
  Update these values if required.
*/
var rs = snowflake.createStatement({
    sqlText: "SELECT CURRENT_DATABASE()"
}).execute();

rs.next();
var CURRENT_DB = rs.getColumnValue(1);

var SRC_DATABASE          = 'WORKFRONT';
var SRC_SCHEMA            = 'WF_LISTINGS';
var TGT_DATABASE          = CURRENT_DB;
var TGT_SCHEMA            = 'SILVER';
var TABLE_NAME            = 'ACCESSLEVELS_EVENT';

var LOAD_TYPE             = 'FULL';
var WATERMARK_COL         = 'DL_LOAD_TIMESTAMP';
var WATERMARK_TYPE        = 'TIMESTAMP';
var HAS_COLUMN_DRIFT      = 'NO';

var IS_ACTIVE             = false;
var HAS_SKIP_CHECK        = false;
var APPLY_SELECT_DISTINCT = false;

/*
  Step 1: Check whether the source table is missing
  from SILVER and the configuration table.
*/
var checkSql = `
    SELECT t1.TABLE_NAME
    FROM WORKFRONT.INFORMATION_SCHEMA.TABLES t1
    WHERE t1.TABLE_SCHEMA = 'WF_LISTINGS'
      AND t1.TABLE_NAME = 'ACCESSLEVELS_EVENT'
      AND NOT EXISTS (
          SELECT 1
          FROM INFORMATION_SCHEMA.TABLES t2
          WHERE t2.TABLE_SCHEMA = 'SILVER'
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
var newTables = []

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
            APPLY_SELECT_DISTINCT
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
            ${APPLY_SELECT_DISTINCT}
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
            HAS_COLUMN_DRIFT
        ]
    });

    insertStmt.execute();
    insertedCount++;
    
    
}

if (newTables.length > 0) {
        NewTablesMsg =
            'Following New tables found in source database which are not present in Silver \n' + 
            '------------------------------------------------\n' +
            newTables.join(', ');
    }



return NewTablesMsg ;


$$;

Call SP_INSERT_SILVER_TABLE_CONFIG ();