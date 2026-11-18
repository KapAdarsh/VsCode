with FPT AS (
    SELECT  DM.MEMBERNUMBER ,
            ACTIVITYGMTDATESID ,
            pointtypecode ,
            pointvalue,
            FPT.pointtypesid ,
            pointtypename
    FROM FACT_POINT_TRANSACTION FPT
    JOIN DIM_POINTTYPE DPT ON DPT.POINTTYPESID=FPT.POINTTYPESID
    JOIN DIM_MEMBER DM ON DM.MEMBERSID=FPT.MEMBERSID
    JOIN DIM_ACTIVITYCODE DAC ON DAC.ACTIVITYCODESID=FPT.ACTIVITYCODESID
    WHERE   ACTIVITYCODE IN ('BS','TC','AC') AND POINTTYPECODE like '%MLLP%'),
FLA AS (
    SELECT  REGEXP_SUBSTR(LOUNGEAGENTNOTE, 'ADT([0-9]{9})', 1, 1, 'e', 1) as mem_num,
            year(entrydatetime) as yearOfLA ,
            REGEXP_SUBSTR(LOUNGEAGENTNOTE, '(MLLPWW|MLLPTB|MLLP)',1, 1, 'i') AS MLLP_TYPE,*
    FROM FACT_MEMBER_LOUNGE_ACCESS 
    where LOUNGEAGENTNOTE LIKE '%%MLLP%%')
select distinct FLA.ACTIVITYGMTDATESID ,
                FLA.PRIMARYMEMBERSID
                FPT.pointtypesid ,
                FLA.PNR_SID, 
                FLA.mem_num,
                FPT.Pointtypecode ,
                FPT.pointtypename,
                1 as benefit_value,
                concat('IEG',FLA.ENTRYREFERENCEID) as activity_number,
                'Debited' as transaction_type,
                PNRUNIQUECODE AS PNR_UNIQUE_CODE,
                PRIMARY_MEMBER_HASHKEY as MEMBER_HASHKEY
from FLA 
join FPT on FLA.mem_num = FPT.MEMBERNUMBER 
join DIM_PNR DP on DP.PNRSID = FLA.PNR_SID
JOIN DIM_POINTTYPE DPT ON FLA.MLLP_TYPE=DPT.pointtypecode AND (VW.ENTRYDATETIME  BETWEEN DPT.SCDSTARTDATETIME AND DPT.SCDENDDATETIME)
where FLA.yearOfLA = LEFT(ACTIVITYGMTDATESID::VARCHAR, 4) or  FLA.yearOfLA -1 =(LEFT(ACTIVITYGMTDATESID::VARCHAR, 4)::VARCHAR);