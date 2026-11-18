var v_supportedTemplate = [''LF_LFIO_FH'', ''*''];
    var v_dynSQL;
    var v_factSIDColumns;
    var v_factColumns;
    var v_factControlColumns;
    var v_transformFactColumns;
    var v_transformFachHashColumns;
    var v_transformFullSourceTableName;
    var v_EDWFullTargetTableName;
    var v_fullSIDColumns;
    var v_BKJoins;
    var errMessage = '''';
    
    // Declare and set variables: Parameters
    var v_sourceFullTableName = P_SOURCEFULLTABLENAME.toUpperCase();
    var v_sourceFullTableNameList = v_sourceFullTableName.split(''.'');
    var v_sourceSchemaName = v_sourceFullTableNameList[0];
    var v_sourceTableName = v_sourceFullTableNameList[1];
    var v_targetFullTableName = P_TARGETFULLTABLENAME.toUpperCase();
    var v_targetFullTableNameList = v_targetFullTableName.split(''.'');
    var v_targetSchemaName = v_targetFullTableNameList[0];
    var v_targetTableName = v_targetFullTableNameList[1];
    var v_templateCode = P_TEMPLATECODE.toUpperCase();
    
    // Schema & table validation check. Calls helper function validateFullTableName()
    // Source schema check
    if (validateFullTableName(v_sourceSchemaName, v_sourceTableName, 0) == 0) {
        throw ''Source schema does not exist in database.'';
    }
    // Source table check
    if (validateFullTableName(v_sourceSchemaName, v_sourceTableName, 1) == 0) {
        throw ''Source table does not exist in schema.'';
    }
    // Target schema check
    if (validateFullTableName(v_targetSchemaName, v_targetTableName, 0) == 0) {
       throw ''Target schema does not exist in database.'';
    }
    // Target table check
    if (validateFullTableName(v_targetSchemaName, v_targetTableName, 1) == 0) {
        throw ''Target table does not exist in schema.'';
    }
    
    // ADF pipeline will pass templatecode as "*", then we must use the target table
    // to retrieve the template code associated with the table from FACTSETTING.
    if (v_templateCode == "*") {
        var getTempCodeSql = `SELECT TEMPLATECODE FROM DYN.FACTSETTING WHERE SCHEMANAME = ? AND TABLENAME = ?;`;
        try {
            var getTempCodeVal = snowflake.execute({sqlText: getTempCodeSql, binds: [v_targetSchemaName, v_targetTableName]});
            getTempCodeVal.next();
            v_templateCode = getTempCodeVal.getColumnValue(1);        
        } catch(err) {
            errMessage =  "Failed: Code: " + err.code + "\\n  State: " + err.state;
            errMessage += "\\n  Message: " + err.message;
            errMessage += "\\nStack Trace:\\n" + err.stackTraceTxt;  
            throw ''Encountered error in getTempCodeVal. \\n'' + errMessage;
        }
    }
    
    // Condition to check if the templatecode is supported
    if (v_supportedTemplate.includes(v_templateCode) == false) {
        throw ''Template code '' + v_templateCode + '' is not supported from DYN.SPEXECFACTTEMP.'';
    }
    
    // Fetching the template
    var getTemplateSql = `SELECT TEMPLATESTRING FROM DYN.TEMPLATE WHERE TEMPLATECODE = ?`;
    try {
        var getTemplateVal = snowflake.execute({sqlText: getTemplateSql, binds:[v_templateCode]});
        getTemplateVal.next();
        v_dynSQL = getTemplateVal.getColumnValue(1);    
    } catch(err) {
        errMessage =  "Failed: Code: " + err.code + "\\n  State: " + err.state;
        errMessage += "\\n  Message: " + err.message;
        errMessage += "\\nStack Trace:\\n" + err.stackTraceTxt;  
        throw ''Encountered error in getTemplateVal. \\n'' + errMessage;
    }

    // Call helper function, get table metadata
    var metadata = getMetadata();

    // LF_LFIO_FH := Load fact, insert only; Fact Hash
    if (v_templateCode == ''LF_LFIO_FH''){        
        // Checking to see if factHash needs to be created or not
        if ((v_transformFachHashColumns != null) && (v_transformFachHashColumns != '''')){
            v_EDWFullTargetTableName = v_targetFullTableName;
            v_transformFullSourceTableName = v_sourceFullTableName + ''_TEMP'';
            var createFactHashSQL = "CALL DYN.SPGETFACTHASH(''"+v_sourceFullTableName+"'', ''"+v_transformFullSourceTableName+"'', ''"+v_transformFachHashColumns+"'');";
            
            try {
                // Creates temp transform table with FactHash column
                snowflake.execute({sqlText:createFactHashSQL});
            } catch(err) {
                errMessage =  "Failed: Code: " + err.code + "\\n  State: " + err.state;
                errMessage += "\\n  Message: " + err.message;
                errMessage += "\\nStack Trace:\\n" + err.stackTraceTxt;  
                throw ''Encountered error in createFactHashSQL execution. \\n'' + errMessage;
            }   
        } else {
            v_transformFullSourceTableName = v_sourceFullTableName;
            v_EDWFullTargetTableName = v_targetFullTableName;
        }
        
        v_dynSQL = v_dynSQL.replace(new RegExp("{EDWFACTFULLTABLENAME}",''gi''),v_EDWFullTargetTableName)
                            .replace(new RegExp("{TRANSFORMFACTFULLTABLENAME}",''gi''),v_transformFullSourceTableName)
                            .replace(new RegExp("{FACTSIDCOLUMNS}",''gi''),columnFormatting(metadata["v_factSIDColumns"], ''{Column}'', ''\\n,'',1))
                            .replace(new RegExp("{FACTCOLUMNS}",''gi''),columnFormatting(metadata["v_factColumns"], ''{Column}'', ''\\n,'',1))
                            .replace(new RegExp("{FACTCONTROLCOLUMNS}", ''gi''),columnFormatting(metadata["v_factControlColumns"], ''{Column}'', ''\\n,'',1))
                            .replace(new RegExp("{FACTSIDCOLUMNSTFT}",''gi''),metadata["v_fullSIDColumns"])
                            .replace(new RegExp("{FACTCOLUMNSTFT}",''gi''),columnFormatting(metadata["v_transformFactColumns"], ''TFT.{Column}'', ''\\n,'',1))
                            .replace(new RegExp("{BATCHLOGID}",''gi''),P_BATCHLOGID)
                            .replace(new RegExp("{BKJOINS}",''gi''),metadata["v_BKJoins"].replace(new RegExp("{Alias}", ''gi''), ''TFT''));

    }

    // Returns assigned variables and SQL script for debugging purposes
    if (P_DEBUG == 1 && P_EXECUTE == 0) {
        var debugPrint = ''Debugging ------------- \\n'';
        debugPrint += ''v_sourceFullTableName: '' + v_sourceFullTableName + ''\\n'';
        debugPrint += ''v_targetFullTableName: '' + v_targetFullTableName + ''\\n'';
        debugPrint += ''v_templateCode: '' + v_templateCode + ''\\n'';
        debugPrint += ''v_factSIDColumns: '' + v_factSIDColumns + ''\\n'';
        debugPrint += ''v_factColumns: '' + v_factColumns + ''\\n'';
        debugPrint += ''v_transformFactColumns: '' + v_transformFactColumns + ''\\n'';
        debugPrint += ''v_fullSIDColumns: '' + v_fullSIDColumns + ''\\n'';
        debugPrint += ''v_BKJoins: '' + v_BKJoins + ''\\n'';
        debugPrint += ''\\n\\n\\n Load Template  ------------- \\n'';
        debugPrint += v_dynSQL;
        return debugPrint;
    }
    
    // Executes the SQL script
    if (P_DEBUG == 0 && P_EXECUTE == 1) {
        try {
            snowflake.execute({sqlText: ''BEGIN;''});
            executeDynSQL(v_dynSQL);
            if (v_transformFullSourceTableName.slice(-5) == ''_TEMP'') {
                var dropTableSql = ''DROP TABLE '' + v_transformFullSourceTableName ;
                snowflake.execute({sqlText:dropTableSql});
            }
            snowflake.execute({sqlText: ''COMMIT;''});
        } catch(err) {
            snowflake.execute({sqlText: ''ROLLBACK;''});
            errMessage =  "Failed: Code: " + err.code + "\\n  State: " + err.state;
            errMessage += "\\n  Message: " + err.message;
            errMessage += "\\nStack Trace:\\n" + err.stackTraceTxt;  
            throw ''Encountered error in dynSQL execution. \\n'' + errMessage;
        }
        return v_targetTableName +'' loaded successfully.'';
    }

    // Helper function to execute query
    function executeDynSQL(p_dynSQL) {
        queryList = p_dynSQL.split('';'');
        for(var i = 0; i < queryList.length; i++) { 
            var sqlStmt = snowflake.createStatement({sqlText: queryList[i]});
            sqlStmt.execute();
        }
    }

    // Helper function to get meta data for tables
    function getMetadata() {
        // Getting columns for target & source table
        var getColsSql = "SELECT SIDFACTCOLUMNS\\
                                 , FACTCOLUMNS\\
                                 , CONTROLCOLUMNS\\
                                 , TRANSFORMFACTCOLUMNS\\
                                 , TRANSFORMFACTHASHCOLUMNS\\
                          FROM DYN.FACTSETTING FS\\
                          WHERE FS.SCHEMANAME = ?\\
                            AND FS.TABLENAME = ?;";
        try {
            var getColsRS = snowflake.execute({sqlText: getColsSql, binds:[v_targetSchemaName, v_targetTableName]});
            getColsRS.next();
            
            // These columns are comming from target table
            v_factSIDColumns = getColsRS.getColumnValue(1);
            v_factColumns = getColsRS.getColumnValue(2);
            v_factControlColumns = getColsRS.getColumnValue(3)
            v_transformFactColumns = getColsRS.getColumnValue(4);
            v_transformFachHashColumns = getColsRS.getColumnValue(5);
        
        } catch(err) {
            errMessage =  "Failed: Code: " + err.code + "\\n  State: " + err.state;
            errMessage += "\\n  Message: " + err.message;
            errMessage += "\\nStack Trace:\\n" + err.stackTraceTxt;  
            throw ''Encountered error in getColsRS execution. \\n'' + errMessage;
        }
        
        // Getting BK joins and SID columns
        var v_joinFactDim = joinFactDim(v_targetFullTableName);
        var v_fullSIDColumns = v_joinFactDim["FullSIDColumns"];
        var v_BKJoins = v_joinFactDim["BK Joins"];
        var metadata = {"v_factSIDColumns":v_factSIDColumns, "v_factColumns":v_factColumns, "v_factControlColumns":v_factControlColumns, "v_transformFactColumns":v_transformFactColumns, "v_transformFachHashColumns":v_transformFachHashColumns, "v_fullSIDColumns":v_fullSIDColumns, "v_BKJoins":v_BKJoins};
        return metadata;
    }

    // Helper function to get BK joins and SID columns
    function joinFactDim(tablename) {
        var v_min;
        var v_max;
        var v_fullTableName = tablename;
        var v_fullTableNameList = v_fullTableName.split(''.'');
        var v_schemaName = v_fullTableNameList[0];
        var v_tableName = v_fullTableNameList[1];
        var v_fullSIDColumns = '''';
        var v_dimSettingID;
        var v_factMappingColumn;
        var v_factColumnName;
        var v_columnTransformation;
        var v_defaultSIDValue;
        var v_transactionColumn;
        var v_dateOrCurrentFlag;
        var v_dimFullTableName;
        var v_dimSK;
        var v_dimBKColumns;
        var v_dimStartDateColumn;
        var v_dimEndDateColumn;
        var v_BKJoins = '''';
        var errMessage = '''';
        
        // Get min and max SID order numbers
        var getMinMaxSQL = `SELECT MAX(SIDORDER), MIN(SIDORDER)
                            FROM DYN.FACTSETTING FS
                            INNER JOIN DYN.FACTDIMLOOKUPSETTING FD
                                ON FS.FACTSETTINGID = FD.FACTSETTINGID
                            WHERE FS.TABLENAME = ?
                                AND FS.SCHEMANAME = ?;`;
        try {
            var getMinMaxRS = snowflake.execute({sqlText: getMinMaxSQL, binds:[v_tableName, v_schemaName]});
            getMinMaxRS.next();
            v_max = getMinMaxRS.getColumnValue(1);
            v_min = getMinMaxRS.getColumnValue(2);    
        } catch(err) {
            errMessage =  "Failed: Code: " + err.code + "\\n  State: " + err.state;
            errMessage += "\\n  Message: " + err.message;
            errMessage += "\\nStack Trace:\\n" + err.stackTraceTxt;  
            throw ''Encountered error in getMinMaxRS. \\n'' + errMessage;
        }

        // Looping to get concat BK Joins, sid columns
        while (v_min <= v_max) {
            var v_columnStatement = '''';
            var v_BKJoinsTemp = '''';
            var v_BKJoinsTemplate = '''';
            
            // GET variable
            var getColumnsSQL = `SELECT FD.DIMSETTINGID
                                        , FD.BKCOLUMNSFACTMAPPING
                                        , FD.BKDIMMAPPING
                                        , FD.FACTCOLUMNNAME
                                        , FD.COLUMNTRANSFORMATION
                                        , FD.DEFAULTVALUESID
                                        , FD.TRANSACTIONDATETIMECOLUMN
                                        , FD.DATEORCURRENTFLAG
                                        , CONCAT(DS.TABLESCHEMA, ''.'', DS.TABLENAME)
                                        , DS.SKCOLUMN
                                 FROM DYN.FACTSETTING  FS
                                 INNER JOIN DYN.FACTDIMLOOKUPSETTING FD
                                    ON FS.FACTSETTINGID = FD.FACTSETTINGID
                                 LEFT OUTER JOIN DYN.DIMSETTING DS
                                    ON FD.DIMSETTINGID = DS.DIMSETTINGID
                                 WHERE FS.TABLENAME = ?
                                    AND FS.SCHEMANAME = ?
                                    AND SIDORDER = ?;`;
            try {
                var getColumnsRS = snowflake.execute({sqlText: getColumnsSQL, binds:[v_tableName, v_schemaName, v_min]});
                getColumnsRS.next();
                
                v_dimSettingID = getColumnsRS.getColumnValue(1);
                v_factMappingColumn = getColumnsRS.getColumnValue(2);
                v_dimBKColumns = getColumnsRS.getColumnValue(3);
                v_factColumnName = getColumnsRS.getColumnValue(4);
                v_columnTransformation = getColumnsRS.getColumnValue(5);
                v_defaultSIDValue = getColumnsRS.getColumnValue(6);
                v_transactionColumn = getColumnsRS.getColumnValue(7);
                v_dateOrCurrentFlag = getColumnsRS.getColumnValue(8);
                v_dimFullTableName = getColumnsRS.getColumnValue(9);
                v_dimSK = getColumnsRS.getColumnValue(10);
                
            } catch(err) {
                errMessage =  "Failed: Code: " + err.code + "\\n  State: " + err.state;
                errMessage += "\\n  Message: " + err.message;
                errMessage += "\\nStack Trace:\\n" + err.stackTraceTxt;  
                throw ''Encountered error in getColumnsRS at SIDORDER = '' + v_min + ''\\n'' + errMessage;
            }

            // GET v_ColumnCaseStatement
            if(v_dimSettingID > 0){
                v_columnStatement = ",COALESCE(DT" + v_min + "." + v_dimSK + ", " + v_defaultSIDValue + ") AS "+ v_factColumnName + "\\n"; 
            } else {
                v_columnTransformation = v_columnTransformation.replace(new RegExp("{Alias}",''gi''),''TFT'')
                                                                .replace(new RegExp("{DefaultValueSID}",''gi''),v_defaultSIDValue);
                v_columnStatement = "," + v_columnTransformation + " AS "+ v_factColumnName + "\\n";  
            }
            

            // SET v_FullColumns        
            v_fullSIDColumns += v_columnStatement;
            
            // Get BK joins except Date and Time dimension
            if(v_dimSettingID > 0) {
                var v_factMapList = v_factMappingColumn.split('','');
                var v_dimBKList = v_dimBKColumns.split('','');
                
                // Checking if we have correct BK joins
                if (v_factMapList.length != v_dimBKList.length) {
                    throw ''Incorrect business key joins between fact and dimension.'';
                }
                
                for(i = 0; i<v_factMapList.length; i++) {
                    if(i > 0) {
                        v_BKJoinsTemp += "  AND UPPER(DT"+v_min+"."+ v_dimBKList[i].trim() +") = UPPER({Alias}."+ v_factMapList[i].trim() + ") \\n";
                    } else {
                        v_BKJoinsTemp += " ON UPPER(DT"+v_min+"."+ v_dimBKList[i].trim() +") = UPPER({Alias}."+ v_factMapList[i].trim() + ") \\n";
                    }
                    
                }
                
                if(v_dateOrCurrentFlag == 0){
                    v_BKJoinsTemplate = "LEFT OUTER JOIN " + v_dimFullTableName + " DT"+v_min+ "" + v_BKJoinsTemp +
                                        "   AND DT"+v_min+".CURRENTFLAG = 1 \\n";
                } else if(v_dateOrCurrentFlag == 2) {
                    v_BKJoinsTemplate = "LEFT OUTER JOIN " + v_dimFullTableName + " DT"+v_min+ "" + v_BKJoinsTemp +
                                        "   AND ({Alias}."+v_transactionColumn+ " BETWEEN DT"+v_min+".SCDSTARTDATETIME AND DT"+v_min+".SCDENDDATETIME) \\n" +
                                        "   AND DT"+v_min+".CURRENTFLAG = 1 \\n";
                } else {
                    v_BKJoinsTemplate = "LEFT OUTER JOIN " + v_dimFullTableName + " DT"+v_min+ "" + v_BKJoinsTemp +
                                        "   AND ({Alias}."+v_transactionColumn+ " BETWEEN DT"+v_min+".SCDSTARTDATETIME AND DT"+v_min+".SCDENDDATETIME) \\n";
                }
                                                 
                v_BKJoins += v_BKJoinsTemplate;
            }
            v_min++;
        }   
        return {"FullSIDColumns": v_fullSIDColumns.slice(1), "BK Joins": v_BKJoins};
    }
    
    // Helper function for validating Schema and Table.
    function validateFullTableName(schemaName, tableName, schemaOrTableFlag) {
        if (schemaOrTableFlag == 0) {
            var checkValidNameSql = "SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = ?;";
            var checkValidNameStmt = snowflake.createStatement({sqlText: checkValidNameSql, binds:[schemaName]});
        } else {
            var checkValidNameSql = "SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ?;";
            var checkValidNameStmt = snowflake.createStatement({sqlText: checkValidNameSql, binds:[schemaName, tableName]});
        }
        
        var rs = checkValidNameStmt.execute();
        return checkValidNameStmt.getRowCount();
    }
    
    // Helper function for column formatting
    function columnFormatting(columns, format, separator, skipFirstSeparator) {
        var columnList;
        if (columns == null) {
            columnList = [''''];
        } else {
            columnList = columns.split('','');
        }
        
        var v_results = '''';
        for (i=0; i < columnList.length; i++) {
            if (columnList[i].trim() == '''') {
            } else {
                var col = columnList[i].trim();
                v_results = v_results + separator + format.replace(new RegExp("{Column}",''g''), col);
            }
        }
        
        if (skipFirstSeparator == 1) {
            v_results = v_results.slice(separator.length);
        }
  
    return v_results;
    }
    