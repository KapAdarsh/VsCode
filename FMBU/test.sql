with CTE_FPT_INITIAL AS (
SELECT DISTINCT 
        fpt.ACTIVITYNUMBER,
        fpt.TRANSACTIONTYPECODE,   
        fpt.POINTVALUE,            
        dac.ACTIVITYCODE,
        dpt.POINTTYPECODE,
        dpt.POINTTYPENAME,
        fpt.CREDITINGGMTTIMESTAMP,
        fpt.MEMBERSID,
        fpt.CREDITINGGMTDATESID,
        fpt.POINTTYPESID,
        fpt.CANCELLEDACTIVITYNUMBER,
        fpt.TRANSACTIONNUMBER
    FROM EDW_HA.FACT_POINT_TRANSACTION fpt
    JOIN EDW_HA.DIM_ACTIVITYCODE dac
        ON fpt.ACTIVITYCODESID = dac.ACTIVITYCODESID
    JOIN EDW_HA.DIM_POINTTYPE dpt
        ON fpt.POINTTYPESID = dpt.POINTTYPESID
    WHERE CREDITINGGMTTIMESTAMP IS NOT NULL
        AND (
            (ACTIVITYCODE IN ('RD', 'ACC') AND POINTTYPECODE IN ('PRWWJ','PRNAPY','PRWWPY','STPA', 'PRCUY25', 'PRWWF'))
            OR (ACTIVITYCODE = 'NT' AND dpt.GROUPNAME IN ('Benefits'))
            OR (TRANSACTIONTYPECODE IN ('D') AND POINTTYPECODE IN ('BS25K','BS35K','BS50K','BS75K','BS100K'))
        )
),
CTE_RD AS (SELECT activitynumber FROM CTE_FPT_INITIAL WHERE activitycode = 'RD'),
CTE_FPT AS (SELECT * FROM CTE_FPT_INITIAL cpt_i WHERE cpt_i.activitycode <> 'ACC' 
OR (cpt_i.activitycode = 'ACC' AND cpt_i.pointtypecode NOT IN ('PRWWJ','PRNAPY','PRWWPY','STPA', 'PRCUY25', 'PRWWF'))  
OR (cpt_i.activitycode = 'ACC' AND EXISTS (SELECT 1 FROM CTE_RD RD WHERE rd.activitynumber = cpt_i.cancelledactivitynumber)))

    SELECT DISTINCT
        main_t.CREDITINGGMTDATESID AS Activity_GMT_Date_SID,
        main_t.MEMBERSID AS Member_SID,
		main_t.POINTTYPESID AS Point_Type_SID,
		COALESCE(dpnr.PNRSID, -1) AS PNR_SID, 
		main_t.CREDITINGGMTTIMESTAMP AS Activity_GMT_Date_Time,
        dm.MEMBERNUMBER AS Member_Number,
        main_t.POINTTYPECODE AS Point_Type_Code,
        main_t.POINTTYPENAME AS Point_Type_Name,
         -main_t.POINTVALUE AS Benefit_Value,
        main_t.ACTIVITYNUMBER AS Activity_Number,
        CASE
            WHEN main_t.TRANSACTIONTYPECODE = 'C' THEN 'Credited'
            WHEN main_t.TRANSACTIONTYPECODE = 'D' THEN 'Debited'
            ELSE 'Unknown'
        END AS Transaction_Type,
        COALESCE(dpnr.PNRUNIQUECODE, 'Unknown') AS PNR_UNIQUE_CODE,
        dm.MEMBERHASHKEY AS Member_Hashkey,
        main_t.ACTIVITYCODE
    FROM CTE_FPT main_t
    JOIN EDW_HA.DIM_MEMBER dm
        ON dm.MEMBERSID = main_t.MEMBERSID
    LEFT JOIN EDW_HA.FACT_REDEMPTIONCERTIFICATE frc
        ON main_t.ACTIVITYNUMBER = frc.ACTIVITYNUMBER
        AND main_t.ACTIVITYCODE = 'RD'
        AND main_t.POINTTYPECODE IN ('PRWWJ','PRNAPY','PRWWPY','STPA', 'PRCUY25', 'PRWWF')
    LEFT JOIN EDW_HA.DIM_PNR dpnr  ---
        ON frc.MERCHANTREFERENCEID = dpnr.PNRCODE
        AND main_t.ACTIVITYCODE = 'RD'
        AND main_t.POINTTYPECODE IN ('PRWWJ','PRNAPY','PRWWPY','STPA', 'PRCUY25', 'PRWWF')
        AND (main_t.CREDITINGGMTTIMESTAMP BETWEEN dpnr.SCDSTARTDATETIME AND dpnr.SCDENDDATETIME)   
        AND dpnr.PNRBOOKINGUTCDATETIME <= main_t.CREDITINGGMTTIMESTAMP 
    WHERE 
        (main_t.ACTIVITYCODE != 'RD' AND main_t.POINTTYPECODE NOT IN ('PRWWJ','PRNAPY','PRWWPY','STPA', 'PRCUY25', 'PRWWF')) 
        OR (
            main_t.ACTIVITYNUMBER IS NOT NULL
            AND main_t.ACTIVITYCODE = 'RD'
            AND main_t.POINTTYPECODE IN ('PRWWJ','PRNAPY','PRWWPY','STPA', 'PRCUY25', 'PRWWF')
            -- AND main_t.CREDITINGGMTTIMESTAMP BETWEEN dpnr.SCDSTARTDATETIME AND dpnr.SCDENDDATETIME    
            -- AND dpnr.PNRBOOKINGUTCDATETIME <= main_t.CREDITINGGMTTIMESTAMP 
        )
        OR ( 
            main_t.ACTIVITYCODE = 'ACC'
            AND main_t.POINTTYPECODE IN ('PRWWJ','PRNAPY','PRWWPY','STPA', 'PRCUY25', 'PRWWF')
        ) 
    QUALIFY ROW_NUMBER() OVER (PARTITION BY Member_Number, Activity_GMT_Date_Time, PNR_UNIQUE_CODE, Point_Type_Code, Activity_Number, Transaction_Type, transactionnumber ORDER BY Activity_GMT_Date_Time DESC, dpnr.PNRBOOKINGUTCDATETIME DESC) = 1 ; 



    CTE_FPT_INITIAL AS (
    SELECT DISTINCT 
        fpt.ACTIVITYNUMBER,
        fpt.TRANSACTIONTYPECODE,   
        fpt.POINTVALUE,            
        dac.ACTIVITYCODE,
        dpt.POINTTYPECODE,
        dpt.POINTTYPENAME,
        fpt.CREDITINGGMTTIMESTAMP,
        fpt.MEMBERSID,
        fpt.CREDITINGGMTDATESID,
        fpt.POINTTYPESID,
        fpt.CANCELLEDACTIVITYNUMBER,
        fpt.TRANSACTIONNUMBER
    FROM EDW_HA.FACT_POINT_TRANSACTION fpt
    JOIN EDW_HA.DIM_ACTIVITYCODE dac
        ON fpt.ACTIVITYCODESID = dac.ACTIVITYCODESID
    JOIN EDW_HA.DIM_POINTTYPE dpt
        ON fpt.POINTTYPESID = dpt.POINTTYPESID
    WHERE CREDITINGGMTTIMESTAMP IS NOT NULL
        AND (
            (ACTIVITYCODE IN ('RD', 'ACC') AND POINTTYPECODE IN ('PRWWJ','PRNAPY','PRWWPY','STPA', 'PRCUY25', 'PRWWF'))
            OR (ACTIVITYCODE = 'NT' AND dpt.GROUPNAME IN ('Benefits'))
            OR (TRANSACTIONTYPECODE IN ('D') AND POINTTYPECODE IN ('BS25K','BS35K','BS50K','BS75K','BS100K'))
        )
),
CTE_RD AS (SELECT activitynumber FROM CTE_FPT_INITIAL WHERE activitycode = 'RD'),
CTE_FPT AS (SELECT * FROM CTE_FPT_INITIAL cpt_i WHERE cpt_i.activitycode <> 'ACC' 
OR (cpt_i.activitycode = 'ACC' AND cpt_i.pointtypecode NOT IN ('PRWWJ','PRNAPY','PRWWPY','STPA', 'PRCUY25', 'PRWWF'))  
OR (cpt_i.activitycode = 'ACC' AND EXISTS (SELECT 1 FROM CTE_RD RD WHERE rd.activitynumber = cpt_i.cancelledactivitynumber))),
IFLY_BENEFIT_USAGE AS (
    SELECT DISTINCT
        main_t.CREDITINGGMTDATESID AS Activity_GMT_Date_SID,
        main_t.MEMBERSID AS Member_SID,
		main_t.POINTTYPESID AS Point_Type_SID,
		COALESCE(dpnr.PNRSID, -1) AS PNR_SID, 
		main_t.CREDITINGGMTTIMESTAMP AS Activity_GMT_Date_Time,
        dm.MEMBERNUMBER AS Member_Number,
        main_t.POINTTYPECODE AS Point_Type_Code,
        main_t.POINTTYPENAME AS Point_Type_Name,
         -main_t.POINTVALUE AS Benefit_Value,
        main_t.ACTIVITYNUMBER AS Activity_Number,
        CASE
            WHEN main_t.TRANSACTIONTYPECODE = 'C' THEN 'Credited'
            WHEN main_t.TRANSACTIONTYPECODE = 'D' THEN 'Debited'
            ELSE 'Unknown'
        END AS Transaction_Type,
        COALESCE(dpnr.PNRUNIQUECODE, 'Unknown') AS PNR_UNIQUE_CODE,
        dm.MEMBERHASHKEY AS Member_Hashkey
    FROM CTE_FPT main_t
    JOIN EDW_HA.DIM_MEMBER dm
        ON dm.MEMBERSID = main_t.MEMBERSID
    LEFT JOIN EDW_HA.FACT_REDEMPTIONCERTIFICATE frc
        ON main_t.ACTIVITYNUMBER = frc.ACTIVITYNUMBER
        AND main_t.ACTIVITYCODE = 'RD'
        AND main_t.POINTTYPECODE IN ('PRWWJ','PRNAPY','PRWWPY','STPA', 'PRCUY25', 'PRWWF')
    LEFT JOIN EDW_HA.DIM_PNR dpnr  ---
        ON frc.MERCHANTREFERENCEID = dpnr.PNRCODE
        AND main_t.ACTIVITYCODE = 'RD'
        AND main_t.POINTTYPECODE IN ('PRWWJ','PRNAPY','PRWWPY','STPA', 'PRCUY25', 'PRWWF')
        AND main_t.CREDITINGGMTTIMESTAMP BETWEEN dpnr.SCDSTARTDATETIME AND dpnr.SCDENDDATETIME
        AND dpnr.PNRBOOKINGUTCDATETIME <= main_t.CREDITINGGMTTIMESTAMP
    WHERE 
        (main_t.ACTIVITYCODE != 'RD' AND main_t.POINTTYPECODE NOT IN ('PRWWJ','PRNAPY','PRWWPY','STPA', 'PRCUY25', 'PRWWF')) 
        OR (
            frc.ACTIVITYNUMBER IS NOT NULL
            AND main_t.ACTIVITYCODE = 'RD'
            AND main_t.POINTTYPECODE IN ('PRWWJ','PRNAPY','PRWWPY','STPA', 'PRCUY25', 'PRWWF')
        )
        OR ( 
            main_t.ACTIVITYCODE = 'ACC'
            AND main_t.POINTTYPECODE IN ('PRWWJ','PRNAPY','PRWWPY','STPA', 'PRCUY25', 'PRWWF')
        )
    QUALIFY ROW_NUMBER() OVER (PARTITION BY Member_Number, Activity_GMT_Date_Time, PNR_UNIQUE_CODE, Point_Type_Code, Activity_Number, Transaction_Type, transactionnumber ORDER BY Activity_GMT_Date_Time DESC, dpnr.PNRBOOKINGUTCDATETIME DESC) = 1 )



