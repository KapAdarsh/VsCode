CREATE OR REPLACE PROCEDURE GENERATE_DEFAULT_INSERTS(
    DATABASE_NAME VARCHAR,
    SCHEMA_NAME   VARCHAR,
    TABLE_NAME    VARCHAR,
    SID_COLUMN    VARCHAR
)
RETURNS VARCHAR
LANGUAGE JAVASCRIPT
EXECUTE AS CALLER
AS
$$
/*
    Returns default SQL value based on datatype.

    SID column:
        -1, -2 or -3

    Numeric columns:
        -1, -2 or -3

    Character columns:
        Unknown, Not Applicable or Error

    Date/Timestamp columns:
        9999-01-01

    Boolean columns:
        FALSE

    Unsupported datatypes:
        NULL
*/
function getDefaultValue(columnName, dataType, specialValue) {

    const col = columnName.toUpperCase();
    const type = dataType.toUpperCase();

    const fixedValues = {
        'CURRENTFLAG'      : '1',
        'DELETEFLAG'       : '0',
        'TYPE1HASH'        : '-1',
        'TYPE2HASH'        : '-1',
        'SCDSTARTDATE'     : "'1999-01-01 00:00:00'",
        'SCDENDDATE'       : "'9999-12-31 23:59:59'",
        'UPDATEBATCHLOGID' : '-1',
        'CREATEBATCHLOGID' : '-1',
        'UPDATETYPE'       : "'Insert'"
    };

    // Standard metadata columns
    if (fixedValues[col]) {
        return fixedValues[col];
    }

    // Only SID columns get -1/-2/-3
    if (col.endsWith('_SID')) {
        return specialValue.toString();
    }

    // Character columns
    if (
        type.includes('VARCHAR') ||
        type.includes('CHAR') ||
        type.includes('TEXT') ||
        type.includes('STRING')
    ) {
        return specialValue === -1
            ? "'Unknown'"
            : specialValue === -2
            ? "'Not Applicable'"
            : "'Error'";
    }

    // All other numeric columns always -1
    if (
        type.includes('NUMBER') ||
        type.includes('INT') ||
        type.includes('DECIMAL') ||
        type.includes('NUMERIC') ||
        type.includes('FLOAT') ||
        type.includes('DOUBLE')
    ) {
        return '-1';
    }

    // Dates
    if (type.includes('TIMESTAMP')) {
        return "'9999-12-31 23:59:59'";
    }

    if (type === 'DATE') {
        return "'9999-12-31'";
    }

    if (type === 'BOOLEAN') {
        return 'FALSE';
    }

    return 'NULL';
}


/*
    Encloses object names in double quotes and escapes
    embedded double quotes.
*/
function quoteIdentifier(identifierName) {
    return '"' + identifierName.replace(/"/g, '""') + '"';
}


/*
    Generates one INSERT statement for the requested SID.
*/
function generateInsertStatement(
    databaseName,
    schemaName,
    tableName,
    columns,
    dataTypes,
    sidValue
) {
    var columnList = [];
    var valueList = [];

    for (var i = 0; i < columns.length; i++) {

        columnList.push(quoteIdentifier(columns[i]));

        valueList.push(
            getDefaultValue(
                columns[i],
                dataTypes[i],
                sidValue
            )
        );
    }

    var qualifiedTableName =
        quoteIdentifier(databaseName) + "." +
        quoteIdentifier(schemaName) + "." +
        quoteIdentifier(tableName);

    return (
        "INSERT INTO " + qualifiedTableName + "\n" +
        "(\n    " + columnList.join(",\n    ") + "\n)\n" +
        "VALUES\n" +
        "(\n    " + valueList.join(",\n    ") + "\n);"
    );
}


// Read table metadata from INFORMATION_SCHEMA
var metadataSql =
    "SELECT COLUMN_NAME, DATA_TYPE " +
    "FROM " + quoteIdentifier(DATABASE_NAME) +
    ".INFORMATION_SCHEMA.COLUMNS " +
    "WHERE TABLE_SCHEMA = ? " +
    "AND TABLE_NAME = ? " +
	"AND IS_NALLABLE = 'NO' " +
    "ORDER BY ORDINAL_POSITION";

var metadataStatement = snowflake.createStatement({
    sqlText: metadataSql,
    binds: [SCHEMA_NAME, TABLE_NAME]
});

var resultSet = metadataStatement.execute();

var columns = [];
var dataTypes = [];

while (resultSet.next()) {
    columns.push(resultSet.getColumnValue("COLUMN_NAME"));
    dataTypes.push(resultSet.getColumnValue("DATA_TYPE"));
}


// Validate that the table was found
if (columns.length === 0) {
    return (
        "No columns found for table " +
        DATABASE_NAME + "." +
        SCHEMA_NAME + "." +
        TABLE_NAME
    );
}





// Generate exactly three INSERT statements
var inserts = [];

inserts.push(
    generateInsertStatement(
        DATABASE_NAME,
        SCHEMA_NAME,
        TABLE_NAME,
        columns,
        dataTypes,
        -1
    )
);

inserts.push(
    generateInsertStatement(
        DATABASE_NAME,
        SCHEMA_NAME,
        TABLE_NAME,
        columns,
        dataTypes,
        -2
    )
);

inserts.push(
    generateInsertStatement(
        DATABASE_NAME,
        SCHEMA_NAME,
        TABLE_NAME,
        columns,
        dataTypes,
        -3
    )
);

return inserts.join("\n\n");
$$;





INSERT INTO "EDW_DEV"."EDW_AWF"."DIM_CAMPAIGN_PORTFOLIO"
(
    "PORTFOLIO_SID",
    "PORTFOLIO_ID",
    "BEGIN_EFFECTIVE_TIMESTAMP",
    "END_EFFECTIVE_TIMESTAMP",
    "CURRENTFLAG",
    "DELETEDFLAG",
    "SCDSTARTDATETIME",
    "SCDENDDATETIME",
    "LATEARRIVINGFLAG",
    "TYPE1HASH",
    "TYPE2HASH",
    "CREATEDBATCHLOGID",
    "UPDATETYPE"
)
VALUES
(
    -1,
    'Unknown',
    '9999-12-31 23:59:59',
    '9999-12-31 23:59:59',
    1,
    0,
    '1999-01-01 00:00:00',
    '9999-12-31 23:59:59',
    -1,
    -1,
    -1,
    -1,
    'Insert'
);

INSERT INTO "EDW_DEV"."EDW_AWF"."DIM_CAMPAIGN_PORTFOLIO"
(
    "PORTFOLIO_SID",
    "PORTFOLIO_ID",
    "BEGIN_EFFECTIVE_TIMESTAMP",
    "END_EFFECTIVE_TIMESTAMP",
    "CURRENTFLAG",
    "DELETEDFLAG",
    "SCDSTARTDATETIME",
    "SCDENDDATETIME",
    "LATEARRIVINGFLAG",
    "TYPE1HASH",
    "TYPE2HASH",
    "CREATEDBATCHLOGID",
    "UPDATETYPE"
)
VALUES
(
    -2,
    'Not Applicable',
    '9999-12-31 23:59:59',
    '9999-12-31 23:59:59',
    1,
    0,
    '1999-01-01 00:00:00',
    '9999-12-31 23:59:59',
    -1,
    -1,
    -1,
    -1,
    'Insert'
);

INSERT INTO "EDW_DEV"."EDW_AWF"."DIM_CAMPAIGN_PORTFOLIO"
(
    "PORTFOLIO_SID",
    "PORTFOLIO_ID",
    "BEGIN_EFFECTIVE_TIMESTAMP",
    "END_EFFECTIVE_TIMESTAMP",
    "CURRENTFLAG",
    "DELETEDFLAG",
    "SCDSTARTDATETIME",
    "SCDENDDATETIME",
    "LATEARRIVINGFLAG",
    "TYPE1HASH",
    "TYPE2HASH",
    "CREATEDBATCHLOGID",
    "UPDATETYPE"
)
VALUES
(
    -3,
    'Error',
    '9999-12-31 23:59:59',
    '9999-12-31 23:59:59',
    1,
    0,
    '1999-01-01 00:00:00',
    '9999-12-31 23:59:59',
    -1,
    -1,
    -1,
    -1,
    'Insert'
);