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
    ) f where da.activitycode <> 'EP' 
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
CTE_SLBTHRLVL AS (SELECT selectable_threshold_level_value, selectable_threshold_level_value - 1 as ACCTHR_THRESHOLD,
milestone_code,scdstartdatetime,scdenddatetime
FROM edw_ha.dim_member_milestone
QUALIFY ROW_NUMBER() OVER (PARTITION BY selectable_threshold_level_value ORDER BY sqc_amount_required ASC)=1
),
elite_member as (select memberhashkey , IFF(ThresholdType = 'AUTACC',1,0) as elite_flag from CTE_DATE 
where IFF(ThresholdType = 'AUTACC',1,0) = 1)

SELECT distinct
ctn.MemberSID,
ctn.ActivityNumber,
ctn.activitycodedescription,
ctn.ThresholdType,
CAST(
CASE WHEN ctn.ThresholdType = 'THRLVL' THEN dm.milestone_code
WHEN ctn.ThresholdType = 'SLBTHRLVL' THEN cts.milestone_code
WHEN ctn.ThresholdType = 'AUTACC' THEN '10K'
WHEN ctn.ThresholdType = 'ACCTHR' AND EM.elite_flag = '1' then cts.milestone_code 
WHEN ctn.ThresholdType = 'ACCTHR'  then cts2.milestone_code
END AS VARCHAR(14)) AS SQCMilestoneCode,
ctn.MilestoneStartTimestamp,
COALESCE(ctn.next_date, '9999-12-31 23:59:59.996') AS MilestoneEndTimestamp,
ctn.milestoneyear,
ctn.TotalThresholdValue,
ctn.MemberHashkey,
ctn.unitpointvalue,
iFF(MilestoneEndTimestamp = TIMESTAMP '9999-12-31 23:59:59.996',1,0) AS current_flag,
IFF(ROW_NUMBER() OVER ( PARTITION BY ctn.MemberHashkey, SQCMilestoneCode, ctn.ThresholdType
            ORDER BY ctn.MilestoneStartTimestamp DESC) = 1,1,0) AS latest_flag





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
ON ctn.MemberHashkey=EM.MemberHashkey 

WHERE  ctn.memberhashkey = 'd32c0bdb2d6693e9f400676c5f3a61d7b0954516a9cbf539481af017b026fdd7'
ORDER BY MemberHashkey, MilestoneStartTimestamp, activitynumber, thresholdtype,totalthresholdvalue;

 ;
