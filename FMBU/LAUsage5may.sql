with FPT AS ( 
    SELECT  YEAR(FPT.CREDITINGGMTTIMESTAMP) AS CREDITING_YEAR,   
            DM.MEMBERNUMBER,
            pointtypecode , 
            SUM(FPT.POINTVALUE) AS TOTAL_POINTVALUE, 
            FPT.pointtypesid , 
            pointtypename 
    FROM edw.FACT_POINT_TRANSACTION FPT 
    JOIN edw.DIM_POINTTYPE DPT ON DPT.POINTTYPESID=FPT.POINTTYPESID 
    JOIN edw.DIM_MEMBER DM ON DM.MEMBERSID=FPT.MEMBERSID 
    JOIN edw.DIM_ACTIVITYCODE DAC ON DAC.ACTIVITYCODESID=FPT.ACTIVITYCODESID 
    WHERE   ACTIVITYCODE IN ('MU','ARNC','BS','TC','AC','ACC') AND POINTTYPECODE like '%MLLP%'  -- check ACC check 'MLLP in prod' -- test the count with FTP
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
    FROM edw.FACT_MEMBER_LOUNGE_ACCESS  
    where LOUNGEAGENTNOTE LIKE '%%MLLP%%') 
select distinct FLA.ACTIVITYDATESID             AS Activity_GMT_Date_SID, 
                COALESCE(DM.MEMBERSID ,-1)      AS Member_Sid ,
                FPT.pointtypesid                AS Point_Type_sid, 
                FLA.PNRSID                      AS PNR_SID, 
                FLA.ENTRYDATETIME               AS Activity_GMT_Date_Time,
                FLA.mem_num                     AS Member_Number, 
                FPT.Pointtypecode               AS Point_Type_Code, 
                FPT.pointtypename               AS Point_Type_Name, 
                1                               AS Benefit_Value, 
                concat('IEG-',FLA.ENTRYREFERENCEID) as Activity_Number, 
                'Debited'                       as transaction_type, 
                DP.PNRUNIQUECODE                AS PNR_UNIQUE_CODE,
                DM.MEMBERHASHKEY                AS Member_HashKey
                
from FLA  
join FPT on FLA.MEM_NUM = FPT.MEMBERNUMBER  
join edw.DIM_PNR DP on DP.PNRSID = FLA.PNRSID 
JOIN edw.DIM_POINTTYPE DPT ON FLA.MLLP_TYPE=DPT.pointtypecode AND (FLA.ENTRYDATETIME  BETWEEN DPT.SCDSTARTDATETIME AND DPT.SCDENDDATETIME) 
left JOIN edw.dim_member DM on FLA.mem_num = DM.MEMBERNUMBER AND (FLA.ENTRYDATETIME  BETWEEN DM.SCDSTARTDATETIME AND DM.SCDENDDATETIME) 
where FLA.yearOfLA = LEFT(FPT.CREDITING_YEAR::VARCHAR, 4) or  FLA.yearOfLA -1 =(LEFT(FPT.CREDITING_YEAR::VARCHAR, 4)::VARCHAR);