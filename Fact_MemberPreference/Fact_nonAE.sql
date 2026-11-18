MERGE INTO EDW_NONAE_MEMBER.FACT_NONAE_MEMBER_PREFERENCE TARGET
USING ( 
-- Join Workarea table with Dimension to get the SIDs and match the Fact table structure
WITH WorkareaTable as (
   SELECT
  COALESCE(DIM_NONAE.NONAE_MEMBER_SID, -1) AS NONAE_MEMBER_SID,
  COALESCE(DIM_MEM.MEMBERPREFERENCESID, -1) AS MEMBER_PREFERENCE_SID,
  TFT.PREFERENCE_FLAG,
  TFT.EXPLICIT_CONSENT_FLAG,
  COALESCE(DIM_DATE1.DATESID, -1) AS Implicit_Subscription_Expiry_Date_SID,
  TFT.Implicit_Subscription_Expiry_Timestamp,
  COALESCE(DIM_DATE2.DATESID, -1) AS Preference_Modified_Date_SID,
  TFT.Preference_Modified_TimeStamp,
  TFT.PREFERENCECODE,
  TFT.PREFERENCETYPECODE,
  COALESCE(TFT.FACTHASH, '') AS FACTHASH,
    ROW_NUMBER() OVER (
      PARTITION BY DIM_NONAE.NONAE_MEMBER_SID,
      DIM_MEM.MEMBERPREFERENCESID,
      TFT.PREFERENCE_FLAG
      ORDER BY
        PREFERENCE_MODIFIED_TIMESTAMP DESC
    ) AS rn
  FROM
    WORKAREA.FACT_NONAE_MEMBER_PREFERENCE AS TFT
    LEFT JOIN EDW_NONAE_MEMBER.Dim_NONAE_Member AS DIM_NONAE ON (DIM_NONAE.AirCanada_UUID = TFT.AirCanada_UUID)
    AND (
      TFT.Preference_Modified_TimeStamp BETWEEN DIM_NONAE.SCDStartDateTime
      AND DIM_NONAE.SCDEndDateTime
    )
    LEFT JOIN EDW.Dim_MemberPreference AS DIM_MEM ON (DIM_MEM.PreferenceCode=TFT.PreferenceCode) 
	AND (Dim_Mem.PreferenceTypeCode = TFT.PreferenceTypeCode)
	AND (
      TFT.Preference_Modified_TimeStamp BETWEEN DIM_MEM.SCDStartDateTime
      AND DIM_MEM.SCDEndDateTime
    )
	LEFT JOIN EDW.DIM_DATE AS DIM_DATE1 ON CAST(TFT.Implicit_Subscription_Expiry_Timestamp AS DATE) = DIM_DATE1.FULLDATE
	LEFT JOIN EDW.DIM_DATE AS DIM_DATE2 ON CAST(TFT.Preference_Modified_TimeStamp AS DATE) = DIM_DATE2.FULLDATE
   )
-------ABOVE CODE UPDATED-----------------	

,WorkareaTable_Dedup AS ( 
-- Deduplicate the CTE WorkareaTable to get only the latest record per Member, PreferenceCode , Flag
Select * from WorkareaTable where rn=1
)
,combined AS (
-- Records combined from bot Fact Table and CTE tranform table
SELECT T.NonAE_Member_SID,T.Member_Preference_SID,T.Preference_Flag,T.Explicit_Consent_Flag,T.Implicit_Subscription_Expiry_Date_SID,T.Implicit_Subscription_Expiry_Timestamp,T.Preference_Modified_Date_SID,T.Preference_Modified_TimeStamp,T.FactHash,D.PREFERENCECODE,D.PREFERENCETYPECODE
FROM EDW_NONAE_MEMBER.FACT_NONAE_MEMBER_PREFERENCE T
Left JOIN EDW.DIM_MEMBERPREFERENCE D
ON T.MEMBER_PREFERENCE_SID = D.MEMBERPREFERENCESID

  UNION ALL
SELECT NonAE_Member_SID,Member_Preference_SID,Preference_Flag,Explicit_Consent_Flag,Implicit_Subscription_Expiry_Date_SID,Implicit_Subscription_Expiry_Timestamp,Preference_Modified_Date_SID,Preference_Modified_TimeStamp,FactHash,PREFERENCECODE,PREFERENCETYPECODE
FROM WorkareaTable 

)
,changes AS (
-- Detecting the records were the PREFERENCEFLAG changed compared to the last record
  SELECT
    NonAE_Member_SID,Member_Preference_SID,Preference_Flag,Explicit_Consent_Flag,Implicit_Subscription_Expiry_Date_SID,Implicit_Subscription_Expiry_Timestamp,Preference_Modified_Date_SID,Preference_Modified_TimeStamp,FactHash,PREFERENCECODE,PREFERENCETYPECODE,

    LAG(PREFERENCE_FLAG) OVER (
      PARTITION BY NonAE_Member_SID, PREFERENCECODE,PREFERENCETYPECODE
      ORDER BY PREFERENCE_MODIFIED_TIMESTAMP
    ) AS prev_Flag
  FROM combined
)
,changed_rows AS (
-- Filtering to get only the records were a change occured
  SELECT
  NonAE_Member_SID,Member_Preference_SID,Preference_Flag,Explicit_Consent_Flag,Implicit_Subscription_Expiry_Date_SID,Implicit_Subscription_Expiry_Timestamp,Preference_Modified_Date_SID,Preference_Modified_TimeStamp,FactHash,PREFERENCECODE,PREFERENCETYPECODE
  FROM changes
  WHERE PREFERENCE_FLAG != prev_Flag OR prev_Flag IS NULL
)
,finaltable as (
-- Group the records that have a change in flag to get the latest Timestamp
SELECT
    NonAE_Member_SID,
    Member_Preference_SID,
    PREFERENCECODE,
    PREFERENCETYPECODE,
    PREFERENCE_FLAG,
  MAX(PREFERENCE_MODIFIED_TIMESTAMP) AS PREFERENCE_MODIFIED_TIMESTAMP
FROM changed_rows
GROUP BY  NonAE_Member_SID,MEMBER_PREFERENCE_SID,PREFERENCECODE,PREFERENCETYPECODE, PREFERENCE_FLAG
)
-- Join the dedup tranform table and the the CTE final table to group records were no change occured 
--and records where the flag changed compared to the last one 
-- THEN MERGE with the FACT_NONAE_MEMBER_PREFERENCE
Select Distinct COALESCE(M.NonAE_Member_SID, -1) AS NonAE_Member_SID,COALESCE(CH.Preference_Modified_Date_SID,T.Preference_Modified_Date_SID) as Preference_Modified_Date_SID ,T.Member_Preference_SID,T.PREFERENCECODE,T.PREFERENCETYPECODE,COALESCE(CH.Preference_Flag,T.Preference_Flag) as Preference_Flag,COALESCE(CH.Explicit_Consent_Flag,T.Explicit_Consent_Flag) as Explicit_Consent_Flag,COALESCE(CH.Implicit_Subscription_Expiry_Date_SID,T.Implicit_Subscription_Expiry_Date_SID) as Implicit_Subscription_Expiry_Date_SID,COALESCE(CH.Implicit_Subscription_Expiry_Timestamp,T.Implicit_Subscription_Expiry_Timestamp) as Implicit_Subscription_Expiry_Timestamp,
COALESCE(CH.Preference_Modified_TimeStamp,T.Preference_Modified_TimeStamp) as Preference_Modified_TimeStamp,T.FACTHASH
from WorkareaTable_Dedup T LEFT JOIN (
Select distinct F.NONAE_MEMBER_SID,C.PREFERENCE_MODIFIED_DATE_SID,f.MEMBER_PREFERENCE_SID,f.PREFERENCECODE,f.PREFERENCETYPECODE,f.PREFERENCE_FLAG,C.Explicit_Consent_Flag,C.Implicit_Subscription_Expiry_Date_SID,C.Implicit_Subscription_Expiry_Timestamp,f.Preference_Modified_TimeStamp,C.FACTHASH
from finaltable f 
left join changed_rows C
on f.NONAE_MEMBER_SID = C.NonAE_Member_SID and DATEDIFF(second,f.PREFERENCE_MODIFIED_TIMESTAMP,C.PREFERENCE_MODIFIED_TIMESTAMP)=0 
and f.MEMBER_PREFERENCE_SID = C.MEMBER_PREFERENCE_SID and f.PREFERENCE_FLAG = C.PREFERENCE_FLAG ) CH 
on T.NONAE_MEMBER_SID = CH.NONAE_MEMBER_SID AND T.MEMBER_PREFERENCE_SID = CH.MEMBER_PREFERENCE_SID and T.PREFERENCE_FLAG = CH.PREFERENCE_FLAG
LEFT JOIN EDW_NONAE_MEMBER.Dim_NONAE_Member AS M ON (M.NONAE_MEMBER_SID = T.NONAE_MEMBER_SID)
    AND (
      COALESCE(CH.PREFERENCE_MODIFIED_TIMESTAMP,T.PREFERENCE_MODIFIED_TIMESTAMP) BETWEEN M.SCDStartDateTime
      AND M.SCDEndDateTime
    )
) AS SOURCE 
ON       TARGET.NONAE_MEMBER_SID = SOURCE.NONAE_MEMBER_SID 
       AND TARGET.MEMBER_PREFERENCE_SID = SOURCE.MEMBER_PREFERENCE_SID
       AND TARGET.PREFERENCE_FLAG = SOURCE.PREFERENCE_FLAG
WHEN MATCHED   THEN
-- Update the existing record in case it is a match



UPDATE SET   TARGET.NonAE_Member_SID                      	=         SOURCE.NonAE_Member_SID
            ,TARGET.Member_Preference_SID              		=         SOURCE.Member_Preference_SID
            ,TARGET.Preference_Flag                    		=         SOURCE.Preference_Flag
            ,TARGET.Explicit_Consent_Flag                	=         SOURCE.Explicit_Consent_Flag 
            ,TARGET.Implicit_Subscription_Expiry_Date_SID   =         SOURCE.Implicit_Subscription_Expiry_Date_SID 
            ,TARGET.Implicit_Subscription_Expiry_Timestamp  =         SOURCE.Implicit_Subscription_Expiry_Timestamp 
            ,TARGET.Preference_Modified_Date_SID            =         SOURCE.Preference_Modified_Date_SID 
            ,TARGET.Preference_Modified_TimeStamp           =         SOURCE.Preference_Modified_TimeStamp
            ,TARGET.UPDATEBATCHLOGID                        =         -1--{BatchLogID}
            ,TARGET.UpdateType                              =        'UpdateCount'
            ,TARGET.FactHash                                =         SOURCE.FactHash
 
 
            
WHEN NOT MATCHED  THEN  
-- New Insert to EDW table in case there is no match
  INSERT (
          NonAE_Member_SID, 
          Member_Preference_SID,
          Preference_Flag ,
          Explicit_Consent_Flag,
          Implicit_Subscription_Expiry_Date_SID,
          Implicit_Subscription_Expiry_Timestamp,
          Preference_Modified_Date_SID,
          Preference_Modified_TimeStamp,
          FACTHASH,
          CREATEBATCHLOGID,
          UPDATEBATCHLOGID,
          UPDATETYPE
         )
  VALUES
         (
          NonAE_Member_SID, 
          Member_Preference_SID,
          Preference_Flag ,
          Explicit_Consent_Flag,
          Implicit_Subscription_Expiry_Date_SID,
          Implicit_Subscription_Expiry_Timestamp,
          Preference_Modified_Date_SID,
          Preference_Modified_TimeStamp,
          FACTHASH,
          -1--{BatchLogID}
          , -1
          ,'NewInsertCount'
         )            
            ; 
-- Creating a temp table to check if a record that was inserted due to a difference in MemberpreferenceSID for the same Preferencecode 
-- and created a duplicate           
CREATE OR REPLACE TEMPORARY TABLE After_Merge AS
SELECT
  F.NonAE_Member_SID,
  F.Member_Preference_SID,
  D.PREFERENCECODE,
  D.PREFERENCETYPECODE,
  F.PREFERENCE_FLAG,
  F.PREFERENCE_MODIFIED_DATE_SID,
  F.PREFERENCE_MODIFIED_TIMESTAMP,
  ROW_NUMBER() OVER (
    PARTITION BY NonAE_Member_SID,
    D.PREFERENCECODE,
    D.PREFERENCETYPECODE,
    F.PREFERENCE_FLAG
    ORDER BY
      F.PREFERENCE_MODIFIED_TIMESTAMP DESC
  ) AS rn
FROM
  EDW_NONAE_MEMBER.FACT_NONAE_MEMBER_PREFERENCE AS F
  LEFT JOIN EDW.DIM_MEMBERPREFERENCE AS D ON F.MEMBER_PREFERENCE_SID = D.MEMBERPREFERENCESID;
-- Update the record that should remain with update type as UpdateCount 
UPDATE
  EDW_NONAE_MEMBER.FACT_NONAE_MEMBER_PREFERENCE AS F
SET
  UPDATETYPE = 'UpdateCount',
  UPDATEBATCHLOGID = -1--{BatchLogID}
FROM
  (
    SELECT
      DISTINCT A1.NonAE_Member_SID,
      A1.MEMBER_PREFERENCE_SID,
      A1.PREFERENCE_MODIFIED_DATE_SID,
      A1.PREFERENCE_FLAG
    FROM
      After_Merge AS A1
    WHERE
      EXISTS (
        SELECT
          1
        FROM
          After_Merge AS A2
        WHERE
          A2.NonAE_Member_SID = A1.NonAE_Member_SID
          AND A2.PREFERENCECODE = A1.PREFERENCECODE
          AND A2.PREFERENCETYPECODE = A1.PREFERENCETYPECODE
          AND A2.PREFERENCE_FLAG = A1.PREFERENCE_FLAG
          AND A2.rn > 1
      )
      AND A1.rn = 1
  ) AS A
WHERE
  F.NonAE_Member_SID = A.NonAE_Member_SID
  AND F.MEMBER_PREFERENCE_SID = A.Member_Preference_SID
  AND F.PREFERENCE_MODIFIED_DATE_SID = A.PREFERENCE_MODIFIED_DATE_SID
  AND F.PREFERENCE_FLAG = A.PREFERENCE_FLAG
  ;
-- Delete the duplicate records from The FACT_NONAE_MEMBER_PREFERENCE
DELETE FROM EDW_NONAE_MEMBER.FACT_NONAE_MEMBER_PREFERENCE AS F USING After_Merge AS A
WHERE
  F.NonAE_Member_SID = A.NonAE_Member_SID
  AND F.MEMBER_PREFERENCE_SID = A.MEMBER_PREFERENCE_SID
  AND F.PREFERENCE_MODIFIED_DATE_SID = A.PREFERENCE_MODIFIED_DATE_SID
  AND F.PREFERENCE_FLAG = A.PREFERENCE_FLAG
  AND A.rn > 1;
-- DROP The temporary table used 
  DROP TABLE IF EXISTS After_Merge;
  