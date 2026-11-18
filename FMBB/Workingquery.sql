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
FMBU as (SELECT DISTINCT
    CAST(CU.BookingMemberSID as INT) AS Member_SID,
     CAST(TO_CHAR(DATE(COALESCE(CU.BookingLastModifiedGMTDateTime, CU.BookingGMTDateTime)), 'YYYYMMDD')AS INT) AS Activity_Date_SID,
    CAST(-3 as int)PNR_SID,
    CAST(D_PT.POINTTYPESID AS INT)Point_Type_SID, 
    CAST(CONCAT(CU.MerchantID, '-', CU.ORDERID) AS VARCHAR(30)) AS Activity_Number,  
    CAST(CASE 
        WHEN CU.TransactionType = 'BOOKING' THEN 'D' 
        WHEN CU.TransactionType IN ('REFUND', 'CANCEL') THEN 'C' 
    END AS VARCHAR(30)) Transaction_Type_Code,
    CAST(CASE 
        WHEN CU.TransactionType = 'BOOKING' THEN 1 
        WHEN CU.TransactionType IN ('REFUND', 'CANCEL') THEN -1 
        ELSE 0 
    END AS INT)Benefit_Value,
FROM EDW.FACT_BOOKINGNONAIR CU
INNER JOIN ELITE_COUPON_KEYS EC
    ON CU.PROMOCOUPONHASHKEY = EC.PROMOCOUPONHASHKEY 
    AND CU.MERCHANTID = EC.MERCHANTID
INNER JOIN EDW.DIM_POINTTYPE D_PT 
    ON D_PT.POINTTYPECODE = (CASE WHEN CU.MerchantID = 'CXL' THEN 'NAT' WHEN CU.MerchantID = 'RO' THEN 'NAR' ELSE NULL END)
    AND D_PT.CURRENTFLAG = 1 
    AND D_PT.DELETEDFLAG = 0
WHERE CU.MERCHANTID IN ('RO','CXL')
  AND CU.BOOKINGGMTDATESID > 20253112
  AND CU.PROMOCOUPONHASHKEY IS NOT NULL 
  QUALIFY(ROW_NUMBER()over(partition by MEMBER_SID, ACTIVITY_DATE_SID, POINTTYPESID, ACTIVITY_NUMBER, TRANSACTION_TYPE_CODE, EC.PROMOCOUPONHASHKEY ORDER BY ACTIVITY_DATE_SID DESC))=1),
  max_snapshot as /* get the latest data from FMBB */
            (select 
              max(memberbenefitbalancesnapshotdate) as max_snapshotdate 
            from EDW.FACT_MEMBER_BENEFIT_BALANCE),
     Ifly_pointtypes as /* Filtering out necessary point types from dim_pointtypes */
            (select
                pointtypesid ,
                groupname,
                pointtypecode,
                pointtypename
            from edw.dim_pointtype 
                where  PointTypeCode IN ('STPA','PRCUY25','PRNAPY','PRWWPY','PRWWJ','PRWWF', 'N25K','SPLTN25K','N35K','TN35K','SPLTN35K','N50K','TN50K','TNL50K', 'SPLTN50K','TNL75K','SPLTN75K','SPLTN100','BS25K','BS35K','BS50K', 'BS75K','BS100K','PYNAR','PYNAT','NAR','NAT')
      ),
     agg as /* for calculation of eupgrades , NAR ,NAT and IEG usage, will use VW_MEMBER_CONSOLIDATED_BENEFIT_USAGE */
            (SELECT
                mem.membernumber,
                pt.pointtypecode,
                SUM(vw.benefit_value) AS cnt
            FROM FMBU vw 
            join edw.dim_member mem on vw.member_sid = mem.membersid
            join edw.dim_pointtype pt on vw.Point_Type_SID = pt.pointtypesid
            GROUP BY mem.membernumber, pt.pointtypecode )       
    SELECT
        mem.membernumber,
        FMBB.MEMBERBENEFITBALANCESNAPSHOTDATE,
        FMBB.POINTTYPECODE,
        pt.POINTTYPENAME,
        FMBB.TOTALACCRUALALLOTMENT as TOTALACCRUED,
        FMBB.TOTALEXPIRYALLOTMENT as TOTALEXPIRED,
        Case 
            when FMBB.pointtypecode in ('PYNAR','PYNAT','NAR','NAT')----'EUPG','PEUPG','MLLPTB','MLLPWW'
            then (FMBB.totalaccrualallotment - FMBB.TOTALEXPIRYALLOTMENT - COALESCE(agg.cnt, 0)) 
            else (FMBB.totalaccrualallotment - FMBB.TOTALEXPIRYALLOTMENT - FMBB.TOTALREDEMPTIONALLOTMENT) 
        end  AS balance,/* For eupgrades , NAR ,NAT and IEG usage , will use VW_MEMBER_CONSOLIDATED_BENEFIT_USAGE else FMBB */
        Case 
            when FMBB.pointtypecode in ('PYNAR','PYNAT','NAR','NAT')--'EUPG','PEUPG','MLLPTB','MLLPWW'
            then COALESCE(agg.cnt, 0) 
            else FMBB.TOTALREDEMPTIONALLOTMENT 
        end AS TOTALUSED
       
    FROM edw.fact_member_benefit_balance FMBB 
    join edw.dim_member mem on FMBB.MEMBERSID = mem.membersid
    join  Ifly_pointtypes pt on FMBB.pointtypesid = pt.pointtypesid
    join max_snapshot on max_snapshot.max_snapshotdate = FMBB.MEMBERBENEFITBALANCESNAPSHOTDATE
    left join agg on agg.membernumber = mem.membernumber and agg.pointtypecode = FMBB.pointtypecode;

    use database edw;