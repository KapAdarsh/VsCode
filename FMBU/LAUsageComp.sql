select * from (with FPT AS ( 

    SELECT  DM.MEMBERNUMBER ,
            DM.MEMBERHASHKEY,
            CREDITINGGMTDATESID ,
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

select distinct FLA.ACTIVITYDATESID , 
                FLA.PRIMARYMEMBERSID , 
                FPT.pointtypesid , 
                FLA.PNRSID,  
                FLA.mem_num, 
                FPT.Pointtypecode , 
                FPT.pointtypename, 
                1 as benefit_value, 
                concat('IEG',FLA.ENTRYREFERENCEID) as activity_number, 
                'Debited' as transaction_type, 
                PNRUNIQUECODE AS PNR_UNIQUE_CODE, 
                PRIMARYMEMBERHASHKEY as MEMBER_HASHKEY 
from FLA  
join FPT on FLA.primarymemberhashkey = FPT.MEMBERhashkey  
join DIM_PNR DP on DP.PNRSID = FLA.PNRSID 
JOIN DIM_POINTTYPE DPT ON FLA.MLLP_TYPE=DPT.pointtypecode AND (FLA.ENTRYDATETIME  BETWEEN DPT.SCDSTARTDATETIME AND DPT.SCDENDDATETIME) 
where FLA.yearOfLA = LEFT(CREDITINGGMTDATESID::VARCHAR, 4) or  FLA.yearOfLA -1 =(LEFT(CREDITINGGMTDATESID::VARCHAR, 4)::VARCHAR)) 

minus 

select * from (with FPT AS ( 
    SELECT  YEAR(FPT.CREDITINGGMTTIMESTAMP) AS CREDITING_YEAR,   
            DM.MEMBERHASHKEY,
            pointtypecode , 
            SUM(FPT.POINTVALUE) AS TOTAL_POINTVALUE, 
            FPT.pointtypesid , 
            pointtypename 
    FROM FACT_POINT_TRANSACTION FPT 
    JOIN DIM_POINTTYPE DPT ON DPT.POINTTYPESID=FPT.POINTTYPESID 
    JOIN DIM_MEMBER DM ON DM.MEMBERSID=FPT.MEMBERSID 
    JOIN DIM_ACTIVITYCODE DAC ON DAC.ACTIVITYCODESID=FPT.ACTIVITYCODESID 
    WHERE   ACTIVITYCODE IN ('BS','TC','AC') AND POINTTYPECODE like '%MLLP%'  
    GROUP BY  
    CREDITING_YEAR, 
    DAC.ACTIVITYCODE, 
    DPT.POINTTYPECODE, 
    DM.MEMBERHASHKEY, 
    FPT.pointtypesid, 
    pointtypename 
    having SUM(FPT.POINTVALUE) > 0 ), 

FLA AS ( 

    SELECT  REGEXP_SUBSTR(LOUNGEAGENTNOTE, 'ADT([0-9]{9})', 1, 1, 'e', 1) as mem_num, 
            year(entrydatetime) as yearOfLA , 
            REGEXP_SUBSTR(LOUNGEAGENTNOTE, '(MLLPWW|MLLPTB|MLLP)',1, 1, 'i') AS MLLP_TYPE,* 
    FROM FACT_MEMBER_LOUNGE_ACCESS  
    where LOUNGEAGENTNOTE LIKE '%%MLLP%%') 
select distinct FLA.ACTIVITYDATESID , 
                FLA.PRIMARYMEMBERSID , 
                FPT.pointtypesid , 
                FLA.PNRSID,  
                FLA.mem_num, 
                FPT.Pointtypecode , 
                FPT.pointtypename, 
                1 as benefit_value, 
                concat('IEG',FLA.ENTRYREFERENCEID) as activity_number, 
                'Debited' as transaction_type, 
                PNRUNIQUECODE AS PNR_UNIQUE_CODE, 
                PRIMARYMEMBERHASHKEY as MEMBER_HASHKEY 
from FLA  
join FPT on FLA.primarymemberhashkey = FPT.MEMBERhashkey  
join DIM_PNR DP on DP.PNRSID = FLA.PNRSID 
JOIN DIM_POINTTYPE DPT ON FLA.MLLP_TYPE=DPT.pointtypecode AND (FLA.ENTRYDATETIME  BETWEEN DPT.SCDSTARTDATETIME AND DPT.SCDENDDATETIME) 
where FLA.yearOfLA = LEFT(FPT.CREDITING_YEAR::VARCHAR, 4) or  FLA.yearOfLA -1 =(LEFT(FPT.CREDITING_YEAR::VARCHAR, 4)::VARCHAR)); 



with FPT AS ( 
    SELECT  YEAR(FPT.CREDITINGGMTTIMESTAMP) AS CREDITING_YEAR,   
            DM.MEMBERNUMBER,
            pointtypecode , 
            SUM(FPT.POINTVALUE) AS TOTAL_POINTVALUE, 
            FPT.pointtypesid , 
            pointtypename 
    FROM FACT_POINT_TRANSACTION FPT 
    JOIN DIM_POINTTYPE DPT ON DPT.POINTTYPESID=FPT.POINTTYPESID 
    JOIN DIM_MEMBER DM ON DM.MEMBERSID=FPT.MEMBERSID 
    JOIN DIM_ACTIVITYCODE DAC ON DAC.ACTIVITYCODESID=FPT.ACTIVITYCODESID 
    WHERE   ACTIVITYCODE IN ('BS','TC','AC') AND POINTTYPECODE like '%MLLP%'  
    GROUP BY  
    CREDITING_YEAR, 
    DAC.ACTIVITYCODE, 
    DPT.POINTTYPECODE, 
    DM.MEMBERNUMBER, 
    FPT.pointtypesid, 
    pointtypename 
    having SUM(FPT.POINTVALUE) > 0 ), 

FLA AS ( 

    SELECT  REGEXP_SUBSTR(LOUNGEAGENTNOTE, 'ADT([0-9]{9})', 1, 1, 'e', 1) as mem_num, 
            year(entrydatetime) as yearOfLA , 
            REGEXP_SUBSTR(LOUNGEAGENTNOTE, '(MLLPWW|MLLPTB|MLLP)',1, 1, 'i') AS MLLP_TYPE,* 
    FROM FACT_MEMBER_LOUNGE_ACCESS  
    where LOUNGEAGENTNOTE LIKE '%%MLLP%%') 
select distinct FLA.ACTIVITYDATESID AS ACTIVITYGMTDATESID , 
                FLA.MAINPASSENGERMEMBERSID , 
                FPT.pointtypesid , 
                FLA.PNRSID,  
                FLA.mem_num, 
                FPT.Pointtypecode , 
                FPT.pointtypename, 
                1 as benefit_value, 
                concat('IEG',FLA.ENTRYREFERENCEID) as activity_number, 
                'Debited' as transaction_type, 
                PNRUNIQUECODE AS PNR_UNIQUE_CODE, 
                PRIMARYMEMBERHASHKEY as MEMBER_HASHKEY 
from FLA  
join FPT on FLA.MEM_NUM = FPT.MEMBERNUMBER  
join DIM_PNR DP on DP.PNRSID = FLA.PNRSID 
JOIN DIM_POINTTYPE DPT ON FLA.MLLP_TYPE=DPT.pointtypecode AND (FLA.ENTRYDATETIME  BETWEEN DPT.SCDSTARTDATETIME AND DPT.SCDENDDATETIME) 
where FLA.yearOfLA = LEFT(FPT.CREDITING_YEAR::VARCHAR, 4) or  FLA.yearOfLA -1 =(LEFT(FPT.CREDITING_YEAR::VARCHAR, 4)::VARCHAR)




select REGEXP_SUBSTR(LOUNGEAGENTNOTE, 'ADT([0-9]{9})', 1, 1, 'e', 1) as mem_num , DM.membernumber 
from FACT_MEMBER_LOUNGE_ACCESS LA join DIM_MEMBER DM on LA.MEMBER_HASHKEY = DM.MEMBERHASHKEY
 where REGEXP_SUBSTR(LOUNGEAGENTNOTE, 'ADT([0-9]{9})', 1, 1, 'e', 1) <>  DM.membernumber ;

 