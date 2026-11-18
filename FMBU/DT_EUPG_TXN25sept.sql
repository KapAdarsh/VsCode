create or replace temporary table DT as(
WITH CTE_IRU AS (
  select 
  FOP.PNR_HASHKEY,
  FOP.FOP_ID ,
  FOP.PNR_ID AS PNR_Unique_Code,
  Cast(SUBSTRING(FOP_FREE_TEXT, 7, 9) as Varchar(30)) as Payment_Member_Number,
  VER_EFF_DTE_TME as Effective_Date_Time,
  COALESCE(LEAD(FOP.VER_EFF_DTE_TME) OVER (PARTITION BY FOP.FOP_ID ORDER BY FOP.FOP_VER),'9999-12-31 00:00:00.000') AS VER_EXP_DTE_TME,
  Cast(SUBSTRING(FOP_FREE_TEXT,CHARINDEX('-ECR', FOP_FREE_TEXT) + 4,
  CHARINDEX('*', FOP_FREE_TEXT) - CHARINDEX('-ECR', FOP_FREE_TEXT) - 4) AS INT)AS eUpgrade_Credit_Amount,
  IS_DELETED As FOP_Deleted_Flag
  From BDV.PIT_PNR_FOP FOP where FOP_CDE in ('IRU','na') and  FOP_FREE_TEXT LIKE 'EUPGAC%'
  AND FOP.FOP_ID IS NOT NULL
  AND FOP.PNR_ID IS NOT NULL
  AND FOP.VER_EFF_DTE_TME IS NOT NULL 
   ),
   --get distinct Pnrs
  DISTINCT_PNR AS (
SELECT DISTINCT PNR_HASHKEY FROM CTE_IRU
),
CTE_IRU_IsDeleted AS (
SELECT 
  ISD.PNR_HASHKEY,
  ISD.FOP_ID
  FROM BDV.PIT_PNR_FOP ISD
  INNER JOIN DISTINCT_PNR DP
  ON DP.PNR_HASHKEY=ISD.PNR_HASHKEY
  WHERE FOP_CDE IN ('IRU','na')
  AND FOP_FREE_TEXT LIKE 'EUPGAC%'
  AND IS_DELETED='Y'
  ),
CTE_CC AS(
  select 
   FOP.PNR_HASHKEY,
   FOP.FOP_ID ,
   FOP.PNR_ID ,
   Cast(LEFT(REGEXP_SUBSTR(FOP_FREE_TEXT, '[A-Z]{3}\\d+\\.\\d{2}'), 3) as VARCHAR(30)) AS Cash_Add_On_Currency_Code,
   Cast(REGEXP_SUBSTR(REGEXP_SUBSTR(FOP_FREE_TEXT, '[A-Z]{3}\\d+\\.\\d{2}'), '\\d+\\.\\d{2}')as NUMBER(25,6)) AS Cash_Add_On_Amount,
   VER_EFF_DTE_TME  AS VER_EFF_DTE_TME,
   MIN(VER_EFF_DTE_TME) OVER (PARTITION BY FOP_ID) AS MIN_VER_EFF_DTE_TME
   From BDV.PIT_PNR_FOP FOP 
   INNER JOIN DISTINCT_PNR DP
  ON DP.PNR_HASHKEY=FOP.PNR_HASHKEY
   where FOP_CDE='CC' 
   AND REGEXP_SUBSTR(FOP_FREE_TEXT, '[A-Z]{3}\\d+\\.\\d{2}') IS NOT NULL
   AND REGEXP_SUBSTR(REGEXP_SUBSTR(FOP_FREE_TEXT, '[A-Z]{3}\\d+\\.\\d{2}'), '\\d+\\.\\d{2}') IS NOT NULL
    ),
CTE_CC_FX AS (
SELECT
    C.PNR_HASHKEY,
    C.FOP_ID,
    C.PNR_ID,
    C.VER_EFF_DTE_TME,
    C.Cash_Add_On_Currency_Code,
    C.Cash_Add_On_Amount,
    CASE 
        WHEN C.Cash_Add_On_Currency_Code = 'CAD' THEN C.Cash_Add_On_Amount
        ELSE (C.Cash_Add_On_Amount * FX.EXCHG_RTE)
    END AS CASH_ADD_ON_CAD_AMOUNT,

FROM CTE_CC C
LEFT JOIN EDW.DIM_CRCY_EXCHG_RTE FX
    ON C.Cash_Add_On_Currency_Code = FX.SRCE_CRCY
   AND FX.TRGT_CRCY = 'CAD'
   AND CAST(C.MIN_VER_EFF_DTE_TME as date) BETWEEN 
   cast(FX.EFFECTIVE_START_DATE_TIME as date) AND cast(FX.EFFECTIVE_END_DATE_TIME as date)

LEFT JOIN EDW.DIM_CRCY_EXCHG_RTE_TYP TYP
    ON FX.CRCY_EXCHG_RTE_TYP_SID = TYP.CRCY_EXCHG_RTE_TYP_SID
   AND TYP.CRCY_EXCHG_RTE_TYP_CDE = 'M'

 QUALIFY ROW_NUMBER() OVER (
        PARTITION BY C.FOP_ID, C.VER_EFF_DTE_TME
        ORDER BY 
        CASE
            WHEN Cash_Add_On_Currency_Code <> 'CAD' AND TYP.CRCY_EXCHG_RTE_TYP_CDE = 'M' THEN 1
            WHEN Cash_Add_On_Currency_Code <> 'CAD' THEN 2
            ELSE 1
        END, 
        FX.EFFECTIVE_START_DATE_TIME DESC
    ) = 1
),
CTE_QUOT as(
    SELECT 
	t.PNR_HASHKEY,
    f.value:id::STRING AS FOP_ID,
    t.QUOTATION_CPN_PRICINGS_PRODUCT:id::STRING AS SERV_ID
    FROM BDV.PIT_PNR_QUOTATION t
	INNER JOIN DISTINCT_PNR DP
  ON DP.PNR_HASHKEY=t.PNR_HASHKEY
    CROSS JOIN LATERAL FLATTEN(INPUT => t.QUOTATION_FARE_ELEMENTS:collection) f
    WHERE t.QUOTATION_FARE_ELEMENTS IS NOT NULL
   ),
CTE_TKT_REF as(
    select  
	tr.PNR_HASHKEY,
    TKT_CPN_PRODUCT_ID as SERV_ID,
    TKT_NUM AS EMD_ID,
    TKT_REF_TYP_ID,
    IS_DELETED
    from BDV.PIT_PNR_TKT_REF tr 
	INNER JOIN DISTINCT_PNR DP
  ON DP.PNR_HASHKEY=tr.PNR_HASHKEY
	where TKT_DOC_TYP='EMD_ASSOCIATED' AND TKT_REF_TYP_ID IN ('FA', 'FHE')
),
CTE_SEG as (
    select
    seg.PNR_ID,
    seg.VER_EFF_DTE_TME,
    seg.SEG_ORIG,
    seg.SEG_DEST,
    f.value:id::STRING AS PRODUCT_ID
    from BDV.PIT_PNR_SEG seg 
    CROSS JOIN LATERAL FLATTEN(INPUT => seg.SEG_PRODUCTS:collection) f

),
CTE_EUPG_FINAL as (
Select distinct
    CTE_IRU.FOP_ID AS FOP_ID,
    CTE_IRU.PNR_Unique_Code AS PNR_Unique_Code,
    CTE_IRU.Payment_Member_Number AS Payment_Member_Number,
    CTE_IRU.Effective_Date_Time AS Effective_Date_Time,
    CTE_IRU.eUpgrade_Credit_Amount AS Eupgrade_Credit_Amount,
    CTE_CC_FX.Cash_Add_On_Amount AS Cash_Add_On_Amount,
    CTE_CC_FX.Cash_Add_On_Currency_Code AS Cash_Add_On_Currency_Code,
    CTE_IRU.FOP_Deleted_Flag  AS FOP_Deleted_Flag,
    CAST(CASE WHEN CTE_IRU_IsDeleted.FOP_ID IS NOT NULL THEN NULL ELSE CTE_TKT_REF.EMD_ID END AS VARCHAR(14)) as EMD_Number,
    CAST(CASE  WHEN CTE_TKT_REF.EMD_ID IS NOT NULL AND CTE_IRU_IsDeleted.FOP_ID IS NULL  THEN 1 ELSE 0 END AS VARCHAR(5)) AS EMD_Flag,
    CAST(
            CASE WHEN DENSE_RANK() OVER (PARTITION BY CTE_IRU.FOP_ID ORDER BY CTE_IRU.Effective_Date_Time DESC) = 1 
            THEN 1 ELSE 0 END AS VARCHAR(5)
        ) AS Latest_Flag,
    CAST(CTE_CC_FX.CASH_ADD_ON_CAD_AMOUNT AS NUMBER(25,6)) AS CASH_ADD_ON_CAD_AMOUNT,
        CAST(SHA2(CTE_IRU.Payment_Member_Number,256) AS VARCHAR(64)) AS Payment_Member_Hashkey
    from CTE_IRU 
    LEFT JOIN CTE_IRU_IsDeleted ON CTE_IRU.FOP_ID=CTE_IRU_IsDeleted.FOP_ID and CTE_IRU.PNR_HASHKEY=CTE_IRU_IsDeleted.PNR_HASHKEY
    LEFT JOIN CTE_CC_FX on CTE_IRU.FOP_ID=CTE_CC_FX.FOP_ID  and cast(CTE_IRU.Effective_Date_Time as date)=cast(CTE_CC_FX.VER_EFF_DTE_TME as date) and CTE_IRU.PNR_HASHKEY=CTE_CC_FX.PNR_HASHKEY
    LEFT JOIN CTE_QUOT on CTE_IRU.FOP_ID=CTE_QUOT.FOP_ID   and CTE_IRU.PNR_HASHKEY=CTE_QUOT.PNR_HASHKEY
    LEFT JOIN CTE_TKT_REF on CTE_QUOT.SERV_ID=CTE_TKT_REF.SERV_ID   and CTE_IRU.PNR_HASHKEY=CTE_TKT_REF.PNR_HASHKEY
     )
    SELECT 
    FOP_ID,
    PNR_Unique_Code,
    Payment_Member_Number,
    Effective_Date_Time,
    Eupgrade_Credit_Amount,
    Cash_Add_On_Amount,
    Cash_Add_On_Currency_Code,
    FOP_Deleted_Flag,
    EMD_Number,
    EMD_Flag,
    Latest_Flag,
    CASH_ADD_ON_CAD_AMOUNT,
    Payment_Member_Hashkey
FROM CTE_EUPG_FINAL)
    --order by PNR_Unique_Code,Payment_Member_Number,FOP_ID,Effective_Date_Time,EMD_Flag
;

select * from DT where  PNR_UNIQUE_CODE = '222226-2022-01-24' order by effective_date_time ;

select * from BDV.PIT_PNR_SEG where PNR_ID = '222226-2022-01-24';