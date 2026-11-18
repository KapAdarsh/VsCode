create or replace dynamic table DT_MEMBER_CONSOLIDATED_BENEFIT_USAGE(
	MEMBER_NUMBER COMMENT 'Aeroplan member number',
	ACTIVITY_DATE_TIME COMMENT 'Date and time when the member used the benefit, when the benefit is debited from the member’s account',
	PNR_UNIQUE_CODE COMMENT 'Code used to identify the flight reservation number done by a member who used a benefit associated with a flight (like Status Pass, Priority Reward or eUpgrades)',
	POINT_TYPE_CODE COMMENT 'Code used to identify the type of benefit used by the member',
	POINT_TYPE_NAME COMMENT 'Name of the benefit used by the member',
	ACTIVITY_NUMBER COMMENT 'Unique number used to identify the benefit usage transaction',
	TRANSACTION_TYPE COMMENT 'Code used to identify if the benefit is debited from the member’s account (i.e. used or burnt) or credited to the member’s account (i.e. usage refunded or cancelled).',
	BENEFIT_VALUE COMMENT 'Number of benefits used by the member, debited from his account',
	MEMBER_HASHKEY COMMENT 'Hashkey of Aeroplan member number'
) target_lag = '1 day' refresh_mode = AUTO initialize = ON_CREATE warehouse = USAGE_ALL1_WH
 cluster by (PNR_UNIQUE_CODE,POINT_TYPE_CODE) as WITH ELITE_COUPON_KEYS AS (
    SELECT DISTINCT 
        FPC.MERCHANTID, 
        FPC.PROMOCOUPONHASHKEY
    FROM EDW.DIM_PROMOCOUPONGROUP DPC
    JOIN EDW.FACT_PROMOCOUPON FPC 
        ON DPC.PROMOCOUPONGROUPHASHKEY = FPC.PROMOCOUPONGROUPHASHKEY
        AND DPC.MERCHANTID = FPC.MERCHANTID
    WHERE DPC.MERCHANTID IN ('RO', 'CXL')
     AND DPC.ELITEFLAG = 1
      AND DPC.CURRENTFLAG = 1 
      AND DPC.DELETEDFLAG = 0
), 
BENEFIT_NON_AIR AS(
SELECT DISTINCT
    DM.MEMBERNUMBER AS Member_Number,
     COALESCE(CU.BookingLastModifiedGMTDateTime, CU.BookingGMTDateTime) AS Activity_Gmt_Date_Time,
    'Not Applicable' AS PNR_Unique_Code,
    COALESCE(D_PT.POINT_TYPE_SID, -1) AS Point_Type_Sid,
    CU.BookingMemberSID  AS MEMBER_SID
    D_PT.POINTTYPECODE AS Point_Type_Code, 
    D_PT.POINTTYPENAME AS Point_Type_Name,    
CAST(CONCAT(CU.MerchantID, '-', CU.ORDERID) AS VARCHAR(30)) AS Activity_Number,  
    CAST(CASE 
        WHEN CU.TransactionType = 'BOOKING' THEN 'Debited' 
        WHEN CU.TransactionType IN ('REFUND', 'CANCEL') THEN 'Credited'
        ELSE 'Unknown'
    END AS VARCHAR(30)) AS Transaction_Type,
    CAST(CASE 
        WHEN CU.TransactionType = 'BOOKING' THEN 1 
        WHEN CU.TransactionType IN ('REFUND', 'CANCEL') THEN -1 
        ELSE 0 
    END AS INT) AS Benefit_Value,
    DM.MEMBERHASHKEY AS Member_HashKey
FROM EDW.FACT_BOOKINGNONAIR CU
INNER JOIN ELITE_COUPON_KEYS EC
    ON CU.PROMOCOUPONHASHKEY = EC.PROMOCOUPONHASHKEY 
    AND CU.MERCHANTID = EC.MERCHANTID
INNER JOIN EDW.DIM_POINTTYPE D_PT 
    ON D_PT.POINTTYPECODE = (CASE WHEN CU.MerchantID = 'CXL' THEN 'NAT' WHEN CU.MerchantID = 'RO' THEN 'NAR' ELSE NULL END)
    AND D_PT.CURRENTFLAG = 1 
    AND D_PT.DELETEDFLAG = 0
    AND (CU.COALESCE(CU.BookingLastModifiedGMTDateTime, CU.BookingGMTDateTime) BETWEEN D_PT.SCDSTARTDATETIME AND D_PT.SCDENDDATETIME)
  JOIN EDW.DIM_MEMBER DM
  ON dm.membersid= cu.BookingMemberSID 
WHERE CU.MERCHANTID IN ('RO','CXL')
  AND CU.BOOKINGGMTDATESID > 20253112
  AND CU.PROMOCOUPONHASHKEY IS NOT NULL 
  QUALIFY(ROW_NUMBER()over(partition by Member_Number, Activity_Date_Time, Point_Type_Code, Activity_Number, Transaction_Type, EC.PROMOCOUPONHASHKEY ORDER BY Activity_Date_Time DESC))=1 
),
CTE_FPT AS (
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
    fpt.POINTTYPESID
    FROM EDW.Fact_Point_Transaction fpt
JOIN EDW.Dim_ActivityCode dac
    ON fpt.ACTIVITYCODESID = dac.ACTIVITYCODESID
JOIN EDW.Dim_PointType dpt
    ON fpt.POINTTYPESID = dpt.POINTTYPESID

WHERE 
CREDITINGGMTTIMESTAMP IS NOT NULL
AND (

(ACTIVITYCODE IN ('RD')
  AND POINTTYPECODE IN ('PRWWJ','PRNAPY','PRWWPY','STPA', 'PRCUY25', 'PRWWF')
  )
	OR		
(ACTIVITYCODE = 'NT'
  AND GROUPNAME IN ('Benefits')
 )
  OR
  (TRANSACTIONTYPECODE IN ('D')
    AND POINTTYPECODE IN ('BS25K','BS35K','BS50K','BS75K','BS100K')
   )
   )	
), 
IFLY_BENEFIT_USAGE AS (
    SELECT DISTINCT
    dm.MEMBERNUMBER AS Member_Number,
    main_t.CREDITINGGMTTIMESTAMP AS Activity_Gmt_Date_Time,
    main_t.MEMBERSID AS MEMBER_SID,
    main_t.POINTTYPESID as POINT_TYPE_SID,
    main_t.CREDITINGGMTDATESID AS Activity_Gmt_Date_SID ,
    COALESCE(dpnr.PNRSID,-1) AS PNR_SID,

    COALESCE(dpnr.PNRUNIQUECODE, 'Unknown') AS PNR_UNIQUE_CODE,
    main_t.POINTTYPECODE AS Point_Type_Code,
     main_t.POINTTYPENAME AS Point_Type_Name,
    main_t.ACTIVITYNUMBER AS Activity_Number,
   CASE
        WHEN main_t.TRANSACTIONTYPECODE = 'C' THEN 'Credited'
        WHEN main_t.TRANSACTIONTYPECODE = 'D' THEN 'Debited'
        ELSE 'Unknown'
    END AS Transaction_Type,
    -main_t.POINTVALUE AS Benefit_Value,
    dm.MEMBERHASHKEY as Member_Hashkey

FROM CTE_FPT  main_t
JOIN EDW.DIM_MEMBER dm
  ON dm.MEMBERSID = main_t.MEMBERSID
 LEFT JOIN EDW.Fact_RedemptionCertificate frc
        ON main_t.ACTIVITYNUMBER = frc.ACTIVITYNUMBER
        AND main_t.ACTIVITYCODE = 'RD'
      AND main_t.POINTTYPECODE IN ('PRWWJ','PRNAPY','PRWWPY','STPA', 'PRCUY25', 'PRWWF')
    LEFT JOIN EDW.Dim_PNR dpnr
        ON frc.MERCHANTREFERENCEID = dpnr.PNRCODE
        AND main_t.ACTIVITYCODE = 'RD'
        AND main_t.POINTTYPECODE IN ('PRWWJ','PRNAPY','PRWWPY','STPA', 'PRCUY25', 'PRWWF')
        (AND main_t.CREDITINGGMTTIMESTAMP BETWEEN dpnr.scdstartdatetime AND dpnr.scdenddatetime)
WHERE 
    (main_t.ACTIVITYCODE != 'RD' 
    AND main_t.POINTTYPECODE NOT IN ('PRWWJ','PRNAPY','PRWWPY','STPA', 'PRCUY25', 'PRWWF')) 
 OR 
    (frc.ACTIVITYNUMBER IS NOT NULL
    AND main_t.ACTIVITYCODE = 'RD'
    AND main_t.POINTTYPECODE IN ('PRWWJ','PRNAPY','PRWWPY','STPA', 'PRCUY25', 'PRWWF')
    AND frc.TRANSACTIONGMTDATETIME BETWEEN dpnr.scdstartdatetime AND dpnr.scdenddatetime
    AND dpnr.PNRBOOKINGUTCDATETIME <= frc.TRANSACTIONGMTDATETIME
    )
   
QUALIFY(ROW_NUMBER() OVER(PARTITION BY Member_Number, Activity_Date_Time, PNR_Unique_Code, Point_Type_Code, Activity_Number, Transaction_Type ORDER BY Activity_Date_Time DESC,PNRBOOKINGUTCDATETIME DESC))=1      
	),
EUPG_BENEFIT_USAGE as (
    SELECT DISTINCT
    VW.EFFECTIVE_DATE_TIME                          AS Activity_GMT_Date_Time,
    VW.PAYMENT_MEMBER_NUMBER                        AS Member_Number,
    VW.PAYMENT_MEMBER_HASHKEY                       AS Member_Hashkey,
    'EUPG'                                          AS Point_Type_Code,
    DPT.POINTTYPENAME                               AS Point_Type_Name,
    VW.EUPGRADE_CREDIT_AMOUNT                       AS Benefit_Value,
    VW.FOP_ID                                       AS Activity_Number,
    IFF(VW.EUPGRADE_CREDIT_AMOUNT > 0,
        'DEBITED', 'CREDITED')                      AS Transaction_Type,
    VW.PNR_UNIQUE_CODE                              AS PNR_Unique_Code,
    DPT.POINTTYPESID                                AS Point_Type_Sid,
    COALESCE(DM.MEMBERSID,-1)                       AS Member_Sid,
    COALESCE(DP.PNRSID,-1)                          AS PNR_Sid,
    DD.DATESID                                      AS Activity_GMT_Date_Time
    
FROM EDW.DT_EUPGRADE_TRANSACTIONS  VW
    JOIN EDW.DIM_POINTTYPE DPT
    ON 'EUPG' = DPT.POINTTYPECODE AND (VW.EFFECTIVE_DATE_TIME  BETWEEN DPT.SCDSTARTDATETIME AND DPT.SCDENDDATETIME)
left Join EDW.DIM_MEMBER DM
    ON VW.PAYMENT_MEMBER_HASHKEY = DM.MEMBERHASHKEY AND (VW.EFFECTIVE_DATE_TIME  BETWEEN DM.SCDSTARTDATETIME AND DM.SCDENDDATETIME)

left JOIN EDW.DIM_PNR DP
    ON VW.PNR_UNIQUE_CODE = DP.PNRUNIQUECODE AND (VW.EFFECTIVE_DATE_TIME  BETWEEN DP.SCDSTARTDATETIME AND DP.SCDENDDATETIME)

left join EDW.DIM_DATE DD 
    ON DATE(VW.EFFECTIVE_DATE_TIME) = DD.FULLDATE
    
WHERE VW.EMD_FLAG  = '1'  
  AND EUPGRADE_CREDIT_AMOUNT <> 0
QUALIFY ROW_NUMBER() OVER (PARTITION BY VW.EMD_NUMBER ORDER BY VW.EFFECTIVE_DATE_TIME ) = 1;)
SELECT * FROM BENEFIT_NON_AIR 
UNION ALL
SELECT * FROM IFLY_BENEFIT_USAGE  
;



"LEFT JOIN Dim_PNR using PNR_UNIQUE_CODE = Dim_PNR.PNRUNIQUECODE AND Activity_Date_Time Between Dim_PNR.SCDSTARTDATETIME and Dim_PNR.SCDENDDATETIME
Falls back to -1 (unknown) as PNRSID if not found."

"LEFT JOIN Dim_Member using PAYMENT_MEMBER_HASHKEY = Dim_Member.MEMBERHASHKEY AND Activity_Date_Time Between Dim_Member.SCDSTARTDATETIME and Dim_Member.SCDENDDATETIME
Falls back to -1 (unknown) as MEMBERSID if not found."

" JOIN Dim_PointType using 'EUPG' = Dim_PointType.POINTTYPECODE AND Activity_Date_Time Between Dim_PointType.SCDSTARTDATETIME and Dim_PointType.SCDENDDATETIME"
