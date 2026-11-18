WITH ELITE_COUPON_KEYS AS (
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
    COALESCE(CU.BookingLastModifiedGMTDateSID, CU.BookingGMTDateSID) AS Activity_Gmt_Date_SID,
    COALESCE(CU.BookingLastModifiedGMTDateTime, CU.BookingGMTDateTime) AS Activity_GMT_Date_Time,
    CU.BookingMemberSID  AS MEMBER_SID,
    DM.MEMBERNUMBER AS Member_Number,
    DM.MEMBERHASHKEY AS Member_HashKey,
    COALESCE(D_PT.POINTTYPESID, -1) AS Point_Type_Sid,
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
    
    
    
    -3 AS PNR_SID,
    'Not Applicable' AS PNR_Unique_Code,
FROM EDW.FACT_BOOKINGNONAIR CU
INNER JOIN ELITE_COUPON_KEYS EC
    ON CU.PROMOCOUPONHASHKEY = EC.PROMOCOUPONHASHKEY 
    AND CU.MERCHANTID = EC.MERCHANTID
INNER JOIN EDW.DIM_POINTTYPE D_PT 
    ON D_PT.POINTTYPECODE = (CASE WHEN CU.MerchantID = 'CXL' THEN 'NAT' WHEN CU.MerchantID = 'RO' THEN 'NAR' ELSE NULL END)
    AND D_PT.CURRENTFLAG = 1 
    AND D_PT.DELETEDFLAG = 0
    AND (COALESCE(CU.BookingLastModifiedGMTDateTime, CU.BookingGMTDateTime) BETWEEN D_PT.SCDSTARTDATETIME AND D_PT.SCDENDDATETIME)
  JOIN EDW.DIM_MEMBER DM
  ON dm.membersid= cu.BookingMemberSID
WHERE CU.MERCHANTID IN ('RO','CXL')
  AND CU.BOOKINGGMTDATESID > 20253112
  AND CU.PROMOCOUPONHASHKEY IS NOT NULL 
  QUALIFY(ROW_NUMBER()over(partition by Member_Number, Activity_GMT_Date_Time, Point_Type_Code, Activity_Number, Transaction_Type, EC.PROMOCOUPONHASHKEY ORDER BY Activity_GMT_Date_Time DESC))=1 
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
    main_t.CREDITINGGMTTIMESTAMP AS Activity_GMT_Date_Time,
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
    dm.MEMBERHASHKEY as Member_Hashkey,
    main_t.CREDITINGGMTDATESID AS Activity_Gmt_Date_SID ,
    main_t.MEMBERSID AS MEMBER_SID,
    main_t.POINTTYPESID as POINT_TYPE_SID,
    COALESCE(dpnr.PNRSID,-1) AS PNR_SID


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
        AND (main_t.CREDITINGGMTTIMESTAMP BETWEEN dpnr.scdstartdatetime AND dpnr.scdenddatetime)
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
   
QUALIFY(ROW_NUMBER() OVER(PARTITION BY Member_Number, Activity_GMT_Date_Time, Point_Type_Code, Activity_Number, Transaction_Type ORDER BY Activity_GMT_Date_Time DESC,PNRBOOKINGUTCDATETIME DESC))=1      
	)
SELECT * FROM BENEFIT_NON_AIR 
UNION ALL
SELECT * FROM IFLY_BENEFIT_USAGE  
;





asdasdsadmllpwwasdasdadt11243



mllptb <> MLLPTB 




select distinct 
    FLA.ACTIVITYDATESID                                                 AS Activity_GMT_Date_SID, 
    COALESCE(DM.MEMBERSID ,-1)                                          AS Member_Sid ,
    DPT.pointtypesid                                                    AS Point_Type_sid, 
    FLA.PNRSID                                                          AS PNR_SID, 
    FLA.ENTRYDATETIME                                                   AS Activity_GMT_Date_Time,
    REGEXP_SUBSTR(FLA.LOUNGEAGENTNOTE, '(ADT|AIN)([0-9]{9})', 1, 1, 'ei', 2)   AS Member_Number, 
    UPPER(REGEXP_SUBSTR(FLA.LOUNGEAGENTNOTE, '(MLLPWW|MLLPTB)',1, 1, 'i')) AS Point_Type_Code, 
    DPT.pointtypename                                                   AS Point_Type_Name, 
    1                                                                   AS Benefit_Value, 
    concat('IEG-',FLA.ENTRYREFERENCEID)                                 AS Activity_Number, 
    'Debited'                                                           AS transaction_type, 
    DP.PNRUNIQUECODE                                                    AS PNR_UNIQUE_CODE,
    DM.MEMBERHASHKEY                                                    AS Member_HashKey 
                
from edw.FACT_MEMBER_LOUNGE_ACCESS  FLA
join edw.DIM_PNR DP on DP.PNRSID = FLA.PNRSID 
JOIN edw.DIM_POINTTYPE DPT ON UPPER(REGEXP_SUBSTR(FLA.LOUNGEAGENTNOTE, '(MLLPWW|MLLPTB)',1, 1, 'i')) =DPT.pointtypecode AND (FLA.ENTRYDATETIME  BETWEEN DPT.SCDSTARTDATETIME AND DPT.SCDENDDATETIME) 
left JOIN edw.dim_member DM on REGEXP_SUBSTR(FLA.LOUNGEAGENTNOTE, '(ADT|AIN)([0-9]{9})', 1, 1, 'ei', 2) = DM.MEMBERNUMBER AND (FLA.ENTRYDATETIME  BETWEEN DM.SCDSTARTDATETIME AND DM.SCDENDDATETIME) 
where UPPER(REGEXP_SUBSTR(FLA.LOUNGEAGENTNOTE, '(MLLPWW|MLLPTB)',1, 1, 'i')) in ('MLLPTB','MLLPWW') and REGEXP_SUBSTR(FLA.LOUNGEAGENTNOTE, '(ADT|AIN)([0-9]{9})', 1, 1, 'ei', 2) is NOT NULL ;