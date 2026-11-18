create or replace view VW_MEMBER_MILESTONE(
	MEMBERSID COMMENT 'SID of the Elite member number.',
	ACTIVITYNUMBER COMMENT 'Activity number that triggered the change of threshold for the Elite member.',
	ACTIVITYCODEDESCRIPTION COMMENT 'Description of the activity that triggered the new milestone.',
	THRESHOLDTYPE COMMENT 'Type of threshold crossed by the member.',
	SQCMILESTONECODE COMMENT 'Level of SQC threshold valid for the Elite member between ThresholdStartDate and ThresholdEndDate.',
	MILESTONESTARTTIMESTAMP COMMENT 'Timestamp of the activity that made the member reach the current SQC milestone',
	MILESTONEENDTIMESTAMP COMMENT 'Timestamp of the activity that made the member reach the next SQC milestone or when the milestone expired.',
	MILESTONEYEAR COMMENT 'Year when the member reached the SQC milestone/threshold.',
	TOTALTHRESHOLDVALUE COMMENT 'Value indicating the accumulated number of thresholds credited to the member’s account',
	MEMBERHASHKEY COMMENT 'Hash key of the Elite member number.'
) as  
WITH 
CTE_TRANS AS(
SELECT DISTINCT
memberhashkey,
fp.membersid,
activitynumber,
pointtypecode AS ThresholdType,
pointvalue,
activityestdatesid, 
creditinggmttimestamp AS MilestoneStartTimestamp, 
activitycode,
activitycodedescription,
CAST(SUBSTR(activityestdatesid,0,4) AS VARCHAR(4)) AS MilestoneYear,
FROM EDW_HA.FACT_POINT_TRANSACTION fp
JOIN EDW_HA.DIM_POINTTYPE dp
ON fp.pointtypesid = dp.pointtypesid
AND dp.pointtypecode IN ('THRLVL', 'SLBTHRLVL')
JOIN EDW_HA.DIM_MEMBER dmb
ON fp.membersid = dmb.membersid
JOIN EDW_HA.DIM_ACTIVITYCODE da
ON fp.activitycodesid = da.activitycodesid
),
CTE_SUM AS (
SELECT ct.*,
SUM(pointvalue) OVER (PARTITION BY memberhashkey, ThresholdType ORDER BY MilestoneStartTimestamp 
ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) as TotalThresholdValue
FROM CTE_TRANS ct
),
CTE_DATE AS (
  SELECT DISTINCT memberhashkey,membersid,MilestoneStartTimestamp,ActivityNumber,ThresholdType,
  LEAD(MilestoneStartTimestamp) OVER (PARTITION BY memberhashkey,ThresholdType ORDER BY MilestoneStartTimestamp) AS next_date
  FROM CTE_TRANS
),
CTE_SLBTHRLVL AS (SELECT selectable_threshold_level_value, 
milestone_code,scdstartdatetime,scdenddatetime
FROM edw_ha.dim_member_milestone
QUALIFY ROW_NUMBER() OVER (PARTITION BY selectable_threshold_level_value ORDER BY sqc_amount_required ASC)=1
)
SELECT DISTINCT
ctn.MemberSID,
ctn.ActivityNumber,
ctn.activitycodedescription,
ctn.ThresholdType,
CAST(
CASE WHEN ctn.ThresholdType = 'THRLVL' THEN dm.milestone_code
WHEN ctn.ThresholdType = 'SLBTHRLVL' THEN cts.milestone_code
END AS VARCHAR(14)) AS SQCMilestoneCode,
ctn.MilestoneStartTimestamp,
COALESCE(ctd.next_date, '9999-12-31 23:59:59.996') AS MilestoneEndTimestamp,
ctn.milestoneyear,
ctn.TotalThresholdValue,
ctn.MemberHashkey

FROM CTE_SUM AS ctn

LEFT JOIN EDW_HA.dim_member_milestone dm
ON ctn.ThresholdType = 'THRLVL' AND ctn.TotalThresholdValue = dm.threshold_level_value
AND MilestoneStartTimestamp >= dm.scdstartdatetime AND MilestoneStartTimestamp <=  dm.scdenddatetime

LEFT JOIN CTE_SLBTHRLVL cts
ON ctn.ThresholdType = 'SLBTHRLVL' AND ctn.TotalThresholdValue = cts.selectable_threshold_level_value
AND MilestoneStartTimestamp >= cts.scdstartdatetime AND MilestoneStartTimestamp <=  cts.scdenddatetime

LEFT JOIN CTE_DATE ctd
ON ctn.MemberHashkey=ctd.MemberHashkey AND ctn.membersid=ctd.membersid AND ctn.ActivityNumber=ctd.ActivityNumber AND ctn.ThresholdType=ctd.ThresholdType

WHERE ctn.activitycode <> 'EP'
ORDER BY MemberHashkey, MilestoneStartTimestamp;