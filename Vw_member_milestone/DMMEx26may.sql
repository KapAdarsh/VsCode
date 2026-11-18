create or replace dynamic table EDW.EDW.DT_MEMBER_MILESTONE(
	MEMBER_SID COMMENT 'SID of the Elite member number.',
	ACTIVITY_CODE_SID COMMENT 'Surrogate key that uniquely identifies each record in the Activity Code dimension.',
	POINT_TYPE_SID COMMENT 'Surrogate key that uniquely identifies each record in the Point Type dimension.',
	SQC_MILESTONE_SID COMMENT 'Surrogate key that uniquely identifies each record in the Member Milestone dimension.',
	ACTIVITY_NUMBER COMMENT 'Activity number that triggered the change of threshold for the Elite member.',
	ACTIVITY_CODE_DESCRIPTION COMMENT 'Description of the activity that triggered the new milestone.',
	THRESHOLD_TYPE COMMENT 'Type of threshold crossed by the member.',
	SQC_MILESTONE_CODE COMMENT 'Level of SQC threshold valid for the Elite member between ThresholdStartDate and ThresholdEndDate.',
	MILESTONE_START_TIMESTAMP COMMENT 'Timestamp of the activity that made the member reach the current SQC milestone',
	MILESTONE_END_TIMESTAMP COMMENT 'Timestamp of the activity that made the member reach the next SQC milestone or when the milestone expired.',
	MILESTONE_YEAR COMMENT 'Year when the member reached the SQC milestone/threshold.',
	YEAR_LATEST_FLAG COMMENT 'Indicates the latest milestone reached by each member, for each calendar year.',
	MILESTONE_LATEST_FLAG COMMENT 'Indicates the most recent achievement date for each milestone code. Useful when multiple records exist for the same milestone due to cancellation and re‑completion by a member.',
	TOTAL_THRESHOLD_VALUE COMMENT 'Value indicating the accumulated number of thresholds credited to the member’s account',
	MEMBER_HASHKEY COMMENT 'Hash key of the Elite member number.'
) target_lag = '1 day' refresh_mode = AUTO initialize = ON_CREATE warehouse = USAGE_ALL1_WH
 COMMENT='Tracks the Status Qualifying Currency (SQC) milestones reached by Aeroplan members.'
 cluster by (THRESHOLD_TYPE,SQC_MILESTONE_CODE) as WITH 
CTE_TRANS AS(
SELECT DISTINCT
memberhashkey,
fp.membersid,
activitynumber,
fp.activitycodesid,
pointtypecode AS ThresholdType,
pointvalue,
fp.pointtypesid,
IFF(pointvalue < 0, -1, 1) AS unitpointvalue,
activityestdatesid, 
creditinggmttimestamp AS MilestoneStartTimestamp, 
activitycode,
activitycodedescription,
YEAR(creditinggmttimestamp) AS MilestoneYear,
f.index
FROM EDW_HA.FACT_POINT_TRANSACTION fp
JOIN EDW_HA.DIM_POINTTYPE dp
ON fp.pointtypesid = dp.pointtypesid
AND dp.pointtypecode IN ('THRLVL' ,'SLBTHRLVL','AUTACC','ACCTHR')
JOIN EDW_HA.DIM_MEMBER dmb
ON fp.membersid = dmb.membersid
JOIN EDW_HA.DIM_ACTIVITYCODE da
ON fp.activitycodesid = da.activitycodesid AND da.programcode='ACRP'
CROSS JOIN LATERAL FLATTEN(
        INPUT => ARRAY_GENERATE_RANGE(
                     1,
                     ABS(COALESCE(pointvalue, 0)) + 1
                 )
    ) f 
),
CTE_SUM AS (
SELECT ct.*,
SUM(unitpointvalue) OVER (PARTITION BY memberhashkey, ThresholdType ORDER BY MilestoneStartTimestamp, index 
ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS TotalThresholdValue
FROM CTE_TRANS ct
),
CTE_DATE AS (
  SELECT ct_s.*,
   COALESCE(
  LEAD(MilestoneStartTimestamp) OVER (PARTITION BY memberhashkey,ThresholdType ORDER BY MilestoneStartTimestamp, index
  ), '9999-12-31 23:59:59.996') AS next_date
  FROM CTE_SUM ct_s
)
,
CTE_SLBTHRLVL AS (SELECT selectable_threshold_level_value, selectable_threshold_level_value - 1 AS ACCTHR_THRESHOLD,
milestone_code,milestone_sid,scdstartdatetime,scdenddatetime
FROM edw_ha.dim_member_milestone
QUALIFY ROW_NUMBER() OVER (PARTITION BY selectable_threshold_level_value, scdstartdatetime ORDER BY sqc_amount_required ASC)=1
),
elite_member_min_date AS (SELECT memberhashkey, MilestoneYear, MIN(MilestoneStartTimestamp) AS elite_start_date,
MAX(DATE_TRUNC('YEAR', DATEADD(YEAR, 2, MilestoneStartTimestamp::TIMESTAMP))) AS end_date
FROM CTE_DATE 
WHERE ThresholdType = 'AUTACC'
GROUP BY memberhashkey, MilestoneYear),
elite_member AS (SELECT memberhashkey, MilestoneYear, elite_start_date,
 COALESCE(
           LEAST( LEAD(elite_start_date) OVER (PARTITION BY memberhashkey ORDER BY MilestoneYear), end_date),
            end_date)
         AS valid_til_date,
1 AS elite_flag FROM elite_member_min_date
)
SELECT DISTINCT
ctn.MemberSID AS MEMBER_SID,
ctn.activitycodesid AS ACTIVITY_CODE_SID,
ctn.pointtypesid AS POINT_TYPE_SID,
COALESCE(CASE WHEN ctn.ThresholdType = 'THRLVL' THEN dm.milestone_sid
WHEN ctn.ThresholdType = 'SLBTHRLVL' THEN cts.milestone_sid
WHEN ctn.ThresholdType = 'ACCTHR' AND EM.elite_flag = 1 THEN cts.milestone_sid 
WHEN ctn.ThresholdType = 'ACCTHR' THEN cts2.milestone_sid
WHEN ctn.ThresholdType = 'AUTACC' THEN -3
END, -1) AS SQC_MILESTONE_SID,
ctn.ActivityNumber AS ACTIVITY_NUMBER,
ctn.activitycodedescription AS ACTIVITY_CODE_DESCRIPTION,
ctn.ThresholdType AS THRESHOLD_TYPE,
CAST(COALESCE(
CASE WHEN ctn.ThresholdType = 'THRLVL' THEN dm.milestone_code
WHEN ctn.ThresholdType = 'SLBTHRLVL' THEN cts.milestone_code
WHEN ctn.ThresholdType = 'AUTACC' THEN '10K'
WHEN ctn.ThresholdType = 'ACCTHR' AND EM.elite_flag = 1 THEN cts.milestone_code 
WHEN ctn.ThresholdType = 'ACCTHR' THEN cts2.milestone_code
END, 'Unknown') AS VARCHAR(14)) AS SQC_MILESTONE_CODE,
ctn.MilestoneStartTimestamp AS MILESTONE_START_TIMESTAMP,
ctn.next_date AS MILESTONE_END_TIMESTAMP,
ctn.milestoneyear AS MILESTONE_YEAR,
IFF(ROW_NUMBER() OVER ( PARTITION BY ctn.MemberHashkey, ctn.MilestoneYear, ctn.ThresholdType
           ORDER BY ctn.next_date DESC, index DESC) = 1,1,0) AS YEAR_LATEST_FLAG,
IFF(ROW_NUMBER() OVER ( PARTITION BY ctn.MemberHashkey, SQC_MILESTONE_CODE, ctn.ThresholdType
           ORDER BY ctn.MilestoneStartTimestamp DESC) = 1,1,0) 
            AS MILESTONE_LATEST_FLAG,         
ctn.TotalThresholdValue AS TOTAL_THRESHOLD_VALUE,
ctn.MemberHashkey AS MEMBER_HASHKEY
FROM CTE_DATE AS ctn
LEFT JOIN EDW_HA.dim_member_milestone dm
ON ctn.ThresholdType = 'THRLVL' AND ctn.TotalThresholdValue = dm.threshold_level_value
AND MilestoneStartTimestamp >= dm.scdstartdatetime AND MilestoneStartTimestamp <=  dm.scdenddatetime
LEFT JOIN CTE_SLBTHRLVL cts
ON ctn.ThresholdType in ('SLBTHRLVL','ACCTHR') AND ctn.TotalThresholdValue = cts.selectable_threshold_level_value
AND MilestoneStartTimestamp >= cts.scdstartdatetime AND MilestoneStartTimestamp <=  cts.scdenddatetime
LEFT JOIN CTE_SLBTHRLVL cts2
ON ctn.ThresholdType = 'ACCTHR' AND ctn.TotalThresholdValue  = cts2.ACCTHR_THRESHOLD
AND MilestoneStartTimestamp >= cts2.scdstartdatetime AND MilestoneStartTimestamp <=  cts2.scdenddatetime
LEFT JOIN elite_member EM
ON ctn.MemberHashkey=EM.MemberHashkey AND ctn.MilestoneStartTimestamp >= EM.elite_start_date AND ctn.MilestoneStartTimestamp < valid_til_date
WHERE ctn.activitycode <> 'EP' AND totalthresholdvalue <> 0 
ORDER BY MEMBER_HASHKEY, MILESTONE_START_TIMESTAMP, THRESHOLD_TYPE,TOTAL_THRESHOLD_VALUE;




