WITH 
CTE_TRANS AS(
SELECT 
memberhashkey,
fp.membersid,
activitynumber,
pointtypecode AS ThresholdType,
pointvalue,
IFF(pointvalue < 0, -1, 1) AS unitpointvalue,
activityestdatesid, 
creditinggmttimestamp AS MilestoneStartTimestamp, 
activitycode,
activitycodedescription,
CAST(SUBSTR(activityestdatesid,0,4) AS VARCHAR(4)) AS MilestoneYear,
FROM EDW_HA.FACT_POINT_TRANSACTION fp
JOIN EDW_HA.DIM_POINTTYPE dp
ON fp.pointtypesid = dp.pointtypesid
AND dp.pointtypecode IN ('THRLVL', 'SLBTHRLVL','AUTACC','ACCTHR')
JOIN EDW_HA.DIM_MEMBER dmb
ON fp.membersid = dmb.membersid
JOIN EDW_HA.DIM_ACTIVITYCODE da
ON fp.activitycodesid = da.activitycodesid
CROSS JOIN LATERAL FLATTEN(
        INPUT => ARRAY_GENERATE_RANGE(
                     1,
                     ABS(COALESCE(pointvalue, 0)) + 1
                 )
    ) f
),
CTE_SUM AS (
SELECT ct.*,
SUM(unitpointvalue) OVER (PARTITION BY memberhashkey, ThresholdType ORDER BY MilestoneStartTimestamp 
ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) as TotalThresholdValue
FROM CTE_TRANS ct
),
CTE_DATE AS (
  SELECT ct_d.*,
  LEAD(MilestoneStartTimestamp) OVER (PARTITION BY memberhashkey,ThresholdType ORDER BY MilestoneStartTimestamp) AS next_date
  FROM CTE_SUM ct_d
),
CTE_SLBTHRLVL AS (SELECT selectable_threshold_level_value, 
milestone_code,scdstartdatetime,scdenddatetime
FROM edw_ha.dim_member_milestone
QUALIFY ROW_NUMBER() OVER (PARTITION BY selectable_threshold_level_value ORDER BY sqc_amount_required ASC)=1
)
SELECT distinct
ctn.MemberSID,
ctn.ActivityNumber,
ctn.activitycodedescription,
ctn.ThresholdType,
CAST(
CASE WHEN ctn.ThresholdType = 'THRLVL' THEN dm.milestone_code
WHEN ctn.ThresholdType = 'SLBTHRLVL' THEN cts.milestone_code
WHEN ctn.ThresholdType = 'AUTACC' THEN '10K'
END AS VARCHAR(14)) AS SQCMilestoneCode,
ctn.MilestoneStartTimestamp,
COALESCE(ctn.next_date, '9999-12-31 23:59:59.996') AS MilestoneEndTimestamp,
ctn.milestoneyear,
ctn.TotalThresholdValue,
ctn.MemberHashkey,
ctn.unitpointvalue

FROM CTE_DATE AS ctn

LEFT JOIN EDW_HA.dim_member_milestone dm
ON ctn.ThresholdType = 'THRLVL' AND ctn.TotalThresholdValue = dm.threshold_level_value
AND MilestoneStartTimestamp >= dm.scdstartdatetime AND MilestoneStartTimestamp <=  dm.scdenddatetime

LEFT JOIN CTE_SLBTHRLVL cts
ON ctn.ThresholdType = 'SLBTHRLVL' AND ctn.TotalThresholdValue = cts.selectable_threshold_level_value
AND MilestoneStartTimestamp >= cts.scdstartdatetime AND MilestoneStartTimestamp <=  cts.scdenddatetime

--LEFT JOIN CTE_DATE ctd
--ON ctn.MemberHashkey=ctd.MemberHashkey AND ctn.membersid=ctd.membersid AND ctn.ActivityNumber=ctd.ActivityNumber AND ctn.ThresholdType=ctd.ThresholdType and ctn.milestonestarttimestamp = ctd.milestonestarttimestamp

WHERE ctn.activitycode <> 'EP' and ctn.memberhashkey = 'aa9a59a872c68c152ace981bc0c6e5ed4cfd0249043765813f9271e7e02e7118'
ORDER BY MemberHashkey, MilestoneStartTimestamp, activitynumber, thresholdtype,totalthresholdvalue;

 ;
