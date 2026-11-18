create or replace dynamic table DT_MEMBER_CONSOLIDATED_BENEFIT_USAGE(
	ACTIVITY_GMT_DATE_SID COMMENT 'Date and time when the member used the benefit, can be joined with Dim_Date',
	MEMBER_SID COMMENT 'Surrogate key for Aeroplan member number, can be linked with Dim_Member',
	POINT_TYPE_SID COMMENT 'Surrogate key for PointTypeCode, can be linked with Dim_PointType',
	PNR_SID COMMENT 'Surrogate key for the PNR, can be linked with Dim_PNR',
	ACTIVITY_GMT_DATE_TIME COMMENT 'Date and time when the member used the benefit, when the benefit is debited from the member''s account',
	MEMBER_NUMBER COMMENT 'Aeroplan member number',
	POINT_TYPE_CODE COMMENT 'Code used to identify the type of benefit used by the member',
	POINT_TYPE_NAME COMMENT 'Name of the benefit used by the member',
	BENEFIT_VALUE COMMENT 'Number of benefits used by the member, debited from his account',
	ACTIVITY_NUMBER COMMENT 'Unique number used to identify the benefit usage transaction',
	TRANSACTION_TYPE COMMENT 'Code used to identify if the benefit is debited from the member''s account (i.e. used or burnt) or credited to the member''s account (i.e. usage refunded or cancelled).',
	PNR_UNIQUE_CODE COMMENT 'Code used to identify the flight reservation number done by a member who used a benefit associated with a flight (like Status Pass, Priority Reward or eUpgrades)',
	MEMBER_HASHKEY COMMENT 'Hashkey of Aeroplan member number'
) target_lag = '1 day' refresh_mode = AUTO initialize = ON_CREATE warehouse = USAGE_ALL1_WH
 COMMENT='Tracks the Elite benefits used by Aeroplan members. The table consolidates information from different data sources to provide a unified version of the truth for end users who want to know what member, used which Elite benefit, on what date and other complementary information.'
 cluster by (PNR_UNIQUE_CODE, POINT_TYPE_CODE) as 
WITH ELITE_COUPON_KEYS AS (
    SELECT DISTINCT 
        FPC.MERCHANTID, 
        FPC.PROMOCOUPONHASHKEY
    FROM EDW_HA.DIM_PROMOCOUPONGROUP DPC  
    JOIN EDW_HA.FACT_PROMOCOUPON FPC   
        ON DPC.PROMOCOUPONGROUPHASHKEY = FPC.PROMOCOUPONGROUPHASHKEY
        AND DPC.MERCHANTID = FPC.MERCHANTID
    WHERE DPC.MERCHANTID IN ('RO', 'CXL')
        AND DPC.ELITEFLAG = 1
        AND DPC.CURRENTFLAG = 1 
        AND DPC.DELETEDFLAG = 0
), 
BENEFIT_NON_AIR AS (
    SELECT DISTINCT
        COALESCE(CU.BookingLastModifiedGMTDateSID, CU.BookingGMTDateSID) AS Activity_GMT_Date_SID,  --
        CU.BookingMemberSID AS Member_SID,
        COALESCE(D_PT.POINTTYPESID, -1) AS Point_Type_SID,
        -3 AS PNR_SID, 
		COALESCE(CU.BookingLastModifiedGMTDateTime, CU.BookingGMTDateTime) AS Activity_GMT_Date_Time, --
        DM.MEMBERNUMBER AS Member_Number,
        D_PT.POINTTYPECODE AS Point_Type_Code, 
        D_PT.POINTTYPENAME AS Point_Type_Name,
        CAST(1 AS NUMBER(38,2)) AS Benefit_Value,  
        CAST(CONCAT(CU.MerchantID, '-', CU.ORDERID) AS VARCHAR(30)) AS Activity_Number,
        CAST('Debited' AS VARCHAR(30)) AS Transaction_Type,
        'Not Applicable' AS PNR_Unique_Code,
        DM.MEMBERHASHKEY AS Member_HashKey
    FROM EDW_HA.FACT_BOOKINGNONAIR CU
    INNER JOIN ELITE_COUPON_KEYS EC
        ON CU.PROMOCOUPONHASHKEY = EC.PROMOCOUPONHASHKEY 
        AND CU.MERCHANTID = EC.MERCHANTID
    INNER JOIN EDW_HA.DIM_POINTTYPE D_PT 
        ON D_PT.POINTTYPECODE = (CASE WHEN CU.MerchantID = 'CXL' THEN 'NAT' WHEN CU.MerchantID = 'RO' THEN 'NAR' ELSE NULL END)
        AND (COALESCE(CU.BookingLastModifiedGMTDateTime, CU.BookingGMTDateTime) BETWEEN D_PT.SCDSTARTDATETIME AND D_PT.SCDENDDATETIME) 
    JOIN EDW_HA.DIM_MEMBER DM
        ON DM.MEMBERSID = CU.BookingMemberSID
    WHERE CU.MERCHANTID IN ('RO','CXL')
        AND CU.BOOKINGGMTDATESID > 20253112
        AND CU.PROMOCOUPONHASHKEY IS NOT NULL 
        AND CU.TRANSACTIONTYPE = 'BOOKING'
    QUALIFY ( ROW_NUMBER() OVER (PARTITION BY Member_Number, Activity_GMT_Date_Time, Point_Type_Code, Activity_Number, Transaction_Type, EC.PROMOCOUPONHASHKEY ORDER BY Activity_GMT_Date_Time DESC) = 1 
)),
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
        fpt.CANCELLEDACTIVITYNUMBER
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
CTE_FPT AS (SELECT * FROM CTE_FPT_INITIAL cpt_i WHERE cpt_i.activitycode <> 'ACC' OR (cpt_i.activitycode = 'ACC' AND EXISTS (SELECT 1 FROM CTE_RD RD WHERE rd.activitynumber = cpt_i.cancelledactivitynumber))),
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
        AND (main_t.CREDITINGGMTTIMESTAMP BETWEEN dpnr.SCDSTARTDATETIME AND dpnr.SCDENDDATETIME)   
    WHERE 
        (main_t.ACTIVITYCODE != 'RD' AND main_t.POINTTYPECODE NOT IN ('PRWWJ','PRNAPY','PRWWPY','STPA', 'PRCUY25', 'PRWWF')) 
        OR (
            frc.ACTIVITYNUMBER IS NOT NULL
            AND main_t.ACTIVITYCODE = 'RD'
            AND main_t.POINTTYPECODE IN ('PRWWJ','PRNAPY','PRWWPY','STPA', 'PRCUY25', 'PRWWF')
            AND main_t.CREDITINGGMTTIMESTAMP BETWEEN dpnr.SCDSTARTDATETIME AND dpnr.SCDENDDATETIME    
            AND dpnr.PNRBOOKINGUTCDATETIME <= main_t.CREDITINGGMTTIMESTAMP 
        )
    QUALIFY ROW_NUMBER() OVER (PARTITION BY Member_Number, Activity_GMT_Date_Time, PNR_UNIQUE_CODE, Point_Type_Code, Activity_Number, Transaction_Type ORDER BY Activity_GMT_Date_Time DESC, dpnr.PNRBOOKINGUTCDATETIME DESC) = 1      
),
EUPG_BENEFIT_USAGE AS (
    SELECT DISTINCT
        DD.DATESID AS Activity_GMT_Date_SID,
		COALESCE(DM.MEMBERSID, -1) AS Member_SID,
        DPT.POINTTYPESID AS Point_Type_SID,
		COALESCE(DP.PNRSID, -1) AS PNR_SID,
        VW.EFFECTIVE_DATE_TIME AS Activity_GMT_Date_Time,
        VW.PAYMENT_MEMBER_NUMBER AS Member_Number,
        'EUPG' AS Point_Type_Code,
        DPT.POINTTYPENAME AS Point_Type_Name,
        VW.EUPGRADE_CREDIT_AMOUNT AS Benefit_Value,
        VW.FOP_ID AS Activity_Number,
        IFF(VW.EUPGRADE_CREDIT_AMOUNT > 0, 'Debited', 'Credited') AS Transaction_Type,
        VW.PNR_UNIQUE_CODE AS PNR_Unique_Code,
        VW.PAYMENT_MEMBER_HASHKEY AS Member_Hashkey
     FROM EDW.DT_EUPGRADE_TRANSACTIONS VW
    JOIN EDW_HA.DIM_POINTTYPE DPT
        ON  DPT.POINTTYPECODE = 'EUPG' 
        AND (VW.EFFECTIVE_DATE_TIME BETWEEN DPT.SCDSTARTDATETIME AND DPT.SCDENDDATETIME)
    LEFT JOIN EDW_HA.DIM_MEMBER DM
        ON VW.PAYMENT_MEMBER_HASHKEY = DM.MEMBERHASHKEY 
        AND (VW.EFFECTIVE_DATE_TIME BETWEEN DM.SCDSTARTDATETIME AND DM.SCDENDDATETIME)
    LEFT JOIN EDW_HA.DIM_PNR DP
        ON VW.PNR_UNIQUE_CODE = DP.PNRUNIQUECODE 
        AND (VW.EFFECTIVE_DATE_TIME BETWEEN DP.SCDSTARTDATETIME AND DP.SCDENDDATETIME)
    LEFT JOIN EDW_HA.DIM_DATE DD 
        ON DATE(VW.EFFECTIVE_DATE_TIME) = DD.FULLDATE
    WHERE VW.EMD_FLAG = '1'  
        AND EUPGRADE_CREDIT_AMOUNT <> 0
    QUALIFY ROW_NUMBER() OVER (PARTITION BY VW.EMD_NUMBER ORDER BY VW.EFFECTIVE_DATE_TIME) = 1
),
 Parsed_FLA AS (
        SELECT
            FLA.ACTIVITYDATESID,
            FLA.ENTRYDATETIME,
            FLA.ENTRYREFERENCEID,
            FLA.LOUNGEAGENTNOTE,
            FLA.PNRSID,
            REGEXP_SUBSTR(FLA.LOUNGEAGENTNOTE,'(ADT|AIN)([0-9]{9})',1,1,'ei',2) AS MEMBER_NUMBER,
            UPPER(REGEXP_SUBSTR(FLA.LOUNGEAGENTNOTE,'(MLLPWW|MLLPTB)',1,1,'i')) AS POINT_TYPE_CODE
        FROM EDW_HA.FACT_MEMBER_LOUNGE_ACCESS FLA
        WHERE REGEXP_SUBSTR(FLA.LOUNGEAGENTNOTE,'(ADT|AIN)([0-9]{9})',1,1,'ei',2) IS NOT NULL
        AND UPPER(REGEXP_SUBSTR(FLA.LOUNGEAGENTNOTE,'(MLLPWW|MLLPTB)',1,1,'i')) IN ('MLLPWW', 'MLLPTB')
),
LOUNGE_BENEFIT_USAGE as (SELECT DISTINCT
        PFLA.ACTIVITYDATESID AS Activity_GMT_Date_SID,
        COALESCE(DM.MEMBERSID, -1) AS Member_SID,
        COALESCE(DPT.POINTTYPESID, -1) AS Point_Type_SID,
        COALESCE(DP.PNRSID, -1) AS PNR_SID,
        PFLA.ENTRYDATETIME AS Activity_GMT_Date_Time,
        PFLA.MEMBER_NUMBER AS Member_Number,
        PFLA.POINT_TYPE_CODE AS Point_Type_Code,
        DPT.POINTTYPENAME AS Point_Type_Name,
        CAST(1 AS NUMBER(38,2)) AS Benefit_Value,
        CONCAT('IEG-', PFLA.ENTRYREFERENCEID) AS Activity_Number,
        'Debited' AS Transaction_Type,
        COALESCE(DP.PNRUNIQUECODE, 'Unknown') AS PNR_Unique_Code,
        COALESCE(DM.MEMBERHASHKEY, 'Unknown') AS Member_Hashkey
    FROM Parsed_FLA PFLA
    LEFT JOIN EDW_HA.DIM_MEMBER DM
        ON PFLA.MEMBER_NUMBER = DM.MEMBERNUMBER
       AND PFLA.ENTRYDATETIME BETWEEN DM.SCDSTARTDATETIME
                                   AND DM.SCDENDDATETIME
    JOIN EDW_HA.DIM_POINTTYPE DPT
        ON PFLA.POINT_TYPE_CODE = UPPER(DPT.POINTTYPECODE)
       AND PFLA.ENTRYDATETIME BETWEEN DPT.SCDSTARTDATETIME
                                   AND DPT.SCDENDDATETIME
    LEFT JOIN EDW_HA.DIM_PNR DP
        ON PFLA.PNRSID = DP.PNRSID
)
SELECT * FROM BENEFIT_NON_AIR 
UNION ALL
SELECT * FROM IFLY_BENEFIT_USAGE
UNION ALL
SELECT * FROM EUPG_BENEFIT_USAGE
UNION ALL
SELECT * FROM LOUNGE_BENEFIT_USAGE;



(SELECT 
        DD.DATESID AS Activity_GMT_Date_SID,
		COALESCE(DM.MEMBERSID, -1) AS Member_SID,
        DPT.POINTTYPESID AS Point_Type_SID,
		COALESCE(DP.PNRSID, -1) AS PNR_SID,
        VW.EFFECTIVE_DATE_TIME AS Activity_GMT_Date_Time,
        VW.PAYMENT_MEMBER_NUMBER AS Member_Number,
        'EUPG' AS Point_Type_Code,
        DPT.POINTTYPENAME AS Point_Type_Name,
        VW.EUPGRADE_CREDIT_AMOUNT AS Benefit_Value,
        VW.FOP_ID AS Activity_Number,
        IFF(VW.EUPGRADE_CREDIT_AMOUNT > 0, 'Debited', 'Credited') AS Transaction_Type,
        VW.PNR_UNIQUE_CODE AS PNR_Unique_Code,
        VW.PAYMENT_MEMBER_HASHKEY AS Member_Hashkey,
        --VW.EMD_NUMBER,
        rd.segment_origin,
        rd.segment_destination,
        CASE WHEN dest.CountryCode IS NULL OR arv.CountryCode IS NULL
             THEN NULL
             WHEN dest.CountryCode = 'CA' AND arv.CountryCode = 'CA'
             THEN 'Domestic'
             WHEN (dest.CountryCode = 'CA' AND arv.CountryCode = 'US') OR (dest.CountryCode = 'US' AND arv.CountryCode = 'CA') 
             THEN 'Transborder'
             WHEN dest.CountryCode NOT IN ('CA', 'US')
             THEN 'International'
             ELSE NULL
        END AS Flight_Market

        
     FROM EDW.DT_EUPGRADE_TRANSACTIONS VW
    JOIN EDW_HA.DIM_POINTTYPE DPT
        ON  DPT.POINTTYPECODE = 'EUPG' 
        AND (VW.EFFECTIVE_DATE_TIME BETWEEN DPT.SCDSTARTDATETIME AND DPT.SCDENDDATETIME)
    LEFT JOIN EDW_HA.DIM_MEMBER DM
        ON VW.PAYMENT_MEMBER_HASHKEY = DM.MEMBERHASHKEY 
        AND (VW.EFFECTIVE_DATE_TIME BETWEEN DM.SCDSTARTDATETIME AND DM.SCDENDDATETIME)
    LEFT JOIN EDW_HA.DIM_PNR DP
        ON VW.PNR_UNIQUE_CODE = DP.PNRUNIQUECODE 
        AND (VW.EFFECTIVE_DATE_TIME BETWEEN DP.SCDSTARTDATETIME AND DP.SCDENDDATETIME)
    LEFT JOIN EDW_HA.DIM_DATE DD 
        ON DATE(VW.EFFECTIVE_DATE_TIME) = DD.FULLDATE
    left join edw.dt_eupgrade_request_details rd 
        on vw.FOP_ID = rd.latest_fop_id and rd.segment_origin is not null
    left join dim_airport arv on rd.segment_origin = arv.airportcodeiata and 
        vw.EFFECTIVE_DATE_TIME between arv.scdstartdatetime and arv.scdenddatetime       
    left join dim_airport dest on rd.segment_destination = dest.airportcodeiata 
        and vw.EFFECTIVE_DATE_TIME between dest.scdstartdatetime and dest.scdenddatetime
    WHERE VW.EMD_FLAG = '1'  
        AND EUPGRADE_CREDIT_AMOUNT <> 0
    QUALIFY ROW_NUMBER() OVER (PARTITION BY VW.EMD_NUMBER ORDER BY VW.EFFECTIVE_DATE_TIME) = 1)