  select * from metadata.dwf_silver_audit_log where log_id between 2222 and 2230;

  update metadata.dwf_silver_audit_log set created_ts = current_timestamp() where log_id between 2222 and 2230; 

   
   
   
   
   ---for 2 consecutive skip...
   select * from metadata.dwf_silver_audit_log where log_id between 2231 and 2239;

   update metadata.dwf_silver_audit_log set created_ts = current_timestamp() where log_id between 2231 and 2239;

---for edw
   update metadata.DWF_MODEL_TABLE_AUDIT_LOG set created_ts = current_timestamp() where log_id in (562,220,217);
          select * from metadata.DWF_MODEL_TABLE_AUDIT_LOG where  log_id in (562,220,217);




----------------------------------------------------------------------------

 ALTER TABLE METADATA.DWF_SILVER_TABLE_CONFIG ADD COLUMN HAS_SKIP_CHECK BOOLEAN DEFAULT TRUE;


 CALL METADATA.SP_VALIDATE_AND_INSERT_RULE(
    'EDW_DEV',                                -- DB_NAME
    'SILVER',                                -- SCHEMA_NAME
    'PORTFOLIOS_EVENT',                                -- TABLE_NAME
    'NA',                                -- DESCRIPTION
    'TRUE',                                -- RULE_ENABLE_FLAG
    'AWF',                                -- LINE_OF_BUSINESS
    'AWF',                                -- PROJECT_NAME
    'SILVER',                                -- LAYER
    'DAILY',                                -- FREQUENCY
    'ALL',                                -- DAY_OF_WEEK
    'NA',                                -- DAY_OF_MONTH
    'NA',                                -- REFRESH_FREQUENCY_MINUTES
    'DL_LOAD_TIMESTAMP',                                -- LOAD_TIMESTAMP_COLUMN
    20,                                  -- ALLOWED_DRIFT_PERC
    0,                                  -- MIN_THRESHOLD_COUNT
    'pritesh.b.gandhi@aircanada.ca',                                -- OPS_EMAIL_RECEIPIENTS
    '',                                -- BUSINESS_EMAIL_RECEIPIENTSr
    '',                                -- CREATED_BY
    ''                                 -- UPDATED_BY
);
 CALL METADATA.SP_VALIDATE_AND_INSERT_RULE(
    'EDW_DEV',                                -- DB_NAME
    'SILVER',                                -- SCHEMA_NAME
    'PROJECTS_EVENT',                                -- TABLE_NAME
    'NA',                                -- DESCRIPTION
    'TRUE',                                -- RULE_ENABLE_FLAG
    'AWF',                                -- LINE_OF_BUSINESS
    'AWF',                                -- PROJECT_NAME
    'SILVER',                                -- LAYER
    'DAILY',                                -- FREQUENCY
    'ALL',                                -- DAY_OF_WEEK
    'NA',                                -- DAY_OF_MONTH
    'NA',                                -- REFRESH_FREQUENCY_MINUTES
    'DL_LOAD_TIMESTAMP',                                -- LOAD_TIMESTAMP_COLUMN
    20,                                  -- ALLOWED_DRIFT_PERC
    0,                                  -- MIN_THRESHOLD_COUNT
    'pritesh.b.gandhi@aircanada.ca',                                -- OPS_EMAIL_RECEIPIENTS
    '',                                -- BUSINESS_EMAIL_RECEIPIENTSr
    '',                                -- CREATED_BY
    ''                                 -- UPDATED_BY
);
 CALL METADATA.SP_VALIDATE_AND_INSERT_RULE(
    'EDW_DEV',                                -- DB_NAME
    'SILVER',                                -- SCHEMA_NAME
    'PROGRAMS_EVENT',                                -- TABLE_NAME
    'NA',                                -- DESCRIPTION
    'TRUE',                                -- RULE_ENABLE_FLAG
    'AWF',                                -- LINE_OF_BUSINESS
    'AWF',                                -- PROJECT_NAME
    'SILVER',                                -- LAYER
    'DAILY',                                -- FREQUENCY
    'ALL',                                -- DAY_OF_WEEK
    'NA',                                -- DAY_OF_MONTH
    'NA',                                -- REFRESH_FREQUENCY_MINUTES
    'DL_LOAD_TIMESTAMP',                                -- LOAD_TIMESTAMP_COLUMN
    20,                                  -- ALLOWED_DRIFT_PERC
    0,                                  -- MIN_THRESHOLD_COUNT
    'pritesh.b.gandhi@aircanada.ca',                                -- OPS_EMAIL_RECEIPIENTS
    '',                                -- BUSINESS_EMAIL_RECEIPIENTSr
    '',                                -- CREATED_BY
    ''                                 -- UPDATED_BY
);
 CALL METADATA.SP_VALIDATE_AND_INSERT_RULE(
    'EDW_DEV',                                -- DB_NAME
    'SILVER',                                -- SCHEMA_NAME
    'TASKS_EVENT',                                -- TABLE_NAME
    'NA',                                -- DESCRIPTION
    'TRUE',                                -- RULE_ENABLE_FLAG
    'AWF',                                -- LINE_OF_BUSINESS
    'AWF',                                -- PROJECT_NAME
    'SILVER',                                -- LAYER
    'DAILY',                                -- FREQUENCY
    'ALL',                                -- DAY_OF_WEEK
    'NA',                                -- DAY_OF_MONTH
    'NA',                                -- REFRESH_FREQUENCY_MINUTES
    'DL_LOAD_TIMESTAMP',                                -- LOAD_TIMESTAMP_COLUMN
    20,                                  -- ALLOWED_DRIFT_PERC
    0,                                  -- MIN_THRESHOLD_COUNT
    'pritesh.b.gandhi@aircanada.ca',                                -- OPS_EMAIL_RECEIPIENTS
    '',                                -- BUSINESS_EMAIL_RECEIPIENTSr
    '',                                -- CREATED_BY
    ''                                 -- UPDATED_BY
);
 CALL METADATA.SP_VALIDATE_AND_INSERT_RULE(
    'EDW_DEV',                                -- DB_NAME
    'SILVER',                                -- SCHEMA_NAME
    'OPTASKS_EVENT',                                -- TABLE_NAME
    'NA',                                -- DESCRIPTION
    'TRUE',                                -- RULE_ENABLE_FLAG
    'AWF',                                -- LINE_OF_BUSINESS
    'AWF',                                -- PROJECT_NAME
    'SILVER',                                -- LAYER
    'DAILY',                                -- FREQUENCY
    'ALL',                                -- DAY_OF_WEEK
    'NA',                                -- DAY_OF_MONTH
    'NA',                                -- REFRESH_FREQUENCY_MINUTES
    'DL_LOAD_TIMESTAMP',                                -- LOAD_TIMESTAMP_COLUMN
    20,                                  -- ALLOWED_DRIFT_PERC
    0,                                  -- MIN_THRESHOLD_COUNT
    'pritesh.b.gandhi@aircanada.ca',                                -- OPS_EMAIL_RECEIPIENTS
    '',                                -- BUSINESS_EMAIL_RECEIPIENTSr
    '',                                -- CREATED_BY
    ''                                 -- UPDATED_BY
);
 CALL METADATA.SP_VALIDATE_AND_INSERT_RULE(
    'EDW_DEV',                                -- DB_NAME
    'SILVER',                                -- SCHEMA_NAME
    'ROLES_EVENT',                                -- TABLE_NAME
    'NA',                                -- DESCRIPTION
    'TRUE',                                -- RULE_ENABLE_FLAG
    'AWF',                                -- LINE_OF_BUSINESS
    'AWF',                                -- PROJECT_NAME
    'SILVER',                                -- LAYER
    'DAILY',                                -- FREQUENCY
    'ALL',                                -- DAY_OF_WEEK
    'NA',                                -- DAY_OF_MONTH
    'NA',                                -- REFRESH_FREQUENCY_MINUTES
    'DL_LOAD_TIMESTAMP',                                -- LOAD_TIMESTAMP_COLUMN
    20,                                  -- ALLOWED_DRIFT_PERC
    0,                                  -- MIN_THRESHOLD_COUNT
    'pritesh.b.gandhi@aircanada.ca',                                -- OPS_EMAIL_RECEIPIENTS
    '',                                -- BUSINESS_EMAIL_RECEIPIENTSr
    '',                                -- CREATED_BY
    ''                                 -- UPDATED_BY
);
 CALL METADATA.SP_VALIDATE_AND_INSERT_RULE(
    'EDW_DEV',                                -- DB_NAME
    'SILVER',                                -- SCHEMA_NAME
    'TEAMS_EVENT',                                -- TABLE_NAME
    'NA',                                -- DESCRIPTION
    'TRUE',                                -- RULE_ENABLE_FLAG
    'AWF',                                -- LINE_OF_BUSINESS
    'AWF',                                -- PROJECT_NAME
    'SILVER',                                -- LAYER
    'DAILY',                                -- FREQUENCY
    'ALL',                                -- DAY_OF_WEEK
    'NA',                                -- DAY_OF_MONTH
    'NA',                                -- REFRESH_FREQUENCY_MINUTES
    'DL_LOAD_TIMESTAMP',                                -- LOAD_TIMESTAMP_COLUMN
    20,                                  -- ALLOWED_DRIFT_PERC
    0,                                  -- MIN_THRESHOLD_COUNT
    'pritesh.b.gandhi@aircanada.ca',                                -- OPS_EMAIL_RECEIPIENTS
    '',                                -- BUSINESS_EMAIL_RECEIPIENTSr
    '',                                -- CREATED_BY
    ''                                 -- UPDATED_BY
);
 CALL METADATA.SP_VALIDATE_AND_INSERT_RULE(
    'EDW_DEV',                                -- DB_NAME
    'SILVER',                                -- SCHEMA_NAME
    'USERS_EVENT',                                -- TABLE_NAME
    'NA',                                -- DESCRIPTION
    'TRUE',                                -- RULE_ENABLE_FLAG
    'AWF',                                -- LINE_OF_BUSINESS
    'AWF',                                -- PROJECT_NAME
    'SILVER',                                -- LAYER
    'DAILY',                                -- FREQUENCY
    'ALL',                                -- DAY_OF_WEEK
    'NA',                                -- DAY_OF_MONTH
    'NA',                                -- REFRESH_FREQUENCY_MINUTES
    'DL_LOAD_TIMESTAMP',                                -- LOAD_TIMESTAMP_COLUMN
    20,                                  -- ALLOWED_DRIFT_PERC
    0,                                  -- MIN_THRESHOLD_COUNT
    'pritesh.b.gandhi@aircanada.ca',                                -- OPS_EMAIL_RECEIPIENTS
    '',                                -- BUSINESS_EMAIL_RECEIPIENTSr
    '',                                -- CREATED_BY
    ''                                 -- UPDATED_BY
);
 CALL METADATA.SP_VALIDATE_AND_INSERT_RULE(
    'EDW_DEV',                                -- DB_NAME
    'SILVER',                                -- SCHEMA_NAME
    'PROJECTS_EVENT',                                -- TABLE_NAME
    'NA',                                -- DESCRIPTION
    'TRUE',                                -- RULE_ENABLE_FLAG
    'AWF',                                -- LINE_OF_BUSINESS
    'AWF',                                -- PROJECT_NAME
    'SILVER',                                -- LAYER
    'DAILY',                                -- FREQUENCY
    'ALL',                                -- DAY_OF_WEEK
    'NA',                                -- DAY_OF_MONTH
    'NA',                                -- REFRESH_FREQUENCY_MINUTES
    'DL_LOAD_TIMESTAMP',                                -- LOAD_TIMESTAMP_COLUMN
    20,                                  -- ALLOWED_DRIFT_PERC
    0,                                  -- MIN_THRESHOLD_COUNT
    'pritesh.b.gandhi@aircanada.ca',                                -- OPS_EMAIL_RECEIPIENTS
    '',                                -- BUSINESS_EMAIL_RECEIPIENTSr
    '',                                -- CREATED_BY
    ''                                 -- UPDATED_BY
);


 ALTER TABLE METADATA.DWF_SILVER_TABLE_CONFIG ADD COLUMN COMMENTS varchar (500);
 ALTER TABLE METADATA.DWF_SILVER_TABLE_CONFIG ADD COLUMN IS_ARCHIVE BOOLEAN default false;
