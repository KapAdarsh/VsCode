select distinct 
    FLA.ACTIVITYDATESID                                                 AS Activity_GMT_Date_SID, 
    COALESCE(DM.MEMBERSID ,-1)                                          AS Member_Sid ,
    DPT.pointtypesid                                                    AS Point_Type_sid, 
    FLA.PNRSID                                                          AS PNR_SID, 
    FLA.ENTRYDATETIME                                                   AS Activity_GMT_Date_Time,
    REGEXP_SUBSTR(FLA.LOUNGEAGENTNOTE, 'ADT([0-9]{9})', 1, 1, 'e', 1)   AS Member_Number, 
    REGEXP_SUBSTR(FLA.LOUNGEAGENTNOTE, '(MLLPWW|MLLPTB|MLLP)',1, 1, 'i') AS Point_Type_Code, 
    DPT.pointtypename                                                   AS Point_Type_Name, 
    1                                                                   AS Benefit_Value, 
    concat('IEG-',FLA.ENTRYREFERENCEID)                                 AS Activity_Number, 
    'Debited'                                                           AS transaction_type, 
    DP.PNRUNIQUECODE                                                    AS PNR_UNIQUE_CODE,
    DM.MEMBERHASHKEY                                                    AS Member_HashKey
                
from edw.FACT_MEMBER_LOUNGE_ACCESS  FLA
join edw.DIM_PNR DP on DP.PNRSID = FLA.PNRSID 
JOIN edw.DIM_POINTTYPE DPT ON REGEXP_SUBSTR(FLA.LOUNGEAGENTNOTE, '(MLLPWW|MLLPTB|MLLP)',1, 1, 'i') =DPT.pointtypecode AND (FLA.ENTRYDATETIME  BETWEEN DPT.SCDSTARTDATETIME AND DPT.SCDENDDATETIME) 
left JOIN edw.dim_member DM on REGEXP_SUBSTR(FLA.LOUNGEAGENTNOTE, 'ADT([0-9]{9})', 1, 1, 'e', 1) = DM.MEMBERNUMBER AND (FLA.ENTRYDATETIME  BETWEEN DM.SCDSTARTDATETIME AND DM.SCDENDDATETIME) 
where LOUNGEAGENTNOTE LIKE '%%MLLP%%' ;


where REGEXP_SUBSTR(FLA.LOUNGEAGENTNOTE, '(MLLPWW|MLLPTB|MLLP)',1, 1, 'i') in ('MLLPWW','MLLPTB')