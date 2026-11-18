WITH fmbb_max_snapshot AS 
            (SELECT DISTINCT
		membersid,
        memberhashkey,
        pointtypesid,
		memberbenefitbalancesnapshotdate,
		pointtypecode,
		totalaccrualallotment,
        totalredemptionallotment,   
		totalexpiryallotment
        FROM EDW_HA.fact_member_benefit_balance 
		WHERE memberbenefitbalancesnapshotdate = (SELECT MAX(memberbenefitbalancesnapshotdate) FROM EDW_HA.fact_member_benefit_balance)),
     Ifly_pointtypes AS 
            (SELECT DISTINCT pointtypesid,
            groupname,
            pointtypecode,
            pointtypename 
            FROM EDW_HA.dim_pointtype 
            WHERE PointTypeCode IN  ('STPA','PRCUY25','PRNAPY','PRWWPY','PRWWJ','PRWWF', 'N25K','SPLTN25K','N35K','TN35K','SPLTN35K','N50K','TN50K','TNL50K', 'SPLTN50K','TNL75K','SPLTN75K','SPLTN100','BS25K','BS35K','BS50K', 'BS75K','BS100K','PYNAR','PYNAT','NAR','NAT')),
     agg AS 
            (SELECT vw.member_number,
            vw.point_type_code,
            SUM(vw.benefit_value) AS cnt 
            FROM EDW.DT_MEMBER_CONSOLIDATED_BENEFIT_USAGE vw 
            GROUP BY vw.member_number, vw.point_type_code)      
        SELECT DISTINCT 
        mem.membernumber AS MEMBER_NUMBER,
        fmbb.memberhashkey AS MEMBER_HASHKEY,
	   fmbb.memberbenefitbalancesnapshotdate AS MEMBER_BENEFIT_BALANCE_SNAPSHOT_DATE,
	   fmbb.pointtypecode AS POINT_TYPE_CODE,
	   pt.pointtypename AS POINT_TYPE_NAME,
        CASE
            WHEN FMBB.pointtypecode IN ('PYNAR','PYNAT','NAR','NAT')
            THEN (FMBB.totalaccrualallotment - FMBB.TOTALEXPIRYALLOTMENT - COALESCE(agg.cnt, 0))
            ELSE (FMBB.totalaccrualallotment - FMBB.TOTALEXPIRYALLOTMENT - FMBB.TOTALREDEMPTIONALLOTMENT)
        END  AS BENEFIT_BALANCE,
		fmbb.totalaccrualallotment AS TOTAL_ACCRUED,
        CASE
            WHEN FMBB.pointtypecode IN ('PYNAR','PYNAT','NAR','NAT')
            THEN COALESCE(agg.cnt, 0)
            ELSE FMBB.TOTALREDEMPTIONALLOTMENT
        END AS TOTAL_USED,
	fmbb.totalexpiryallotment AS TOTAL_EXPIRED
    FROM fmbb_max_snapshot FMBB
    JOIN EDW_HA.dim_member mem ON FMBB.MEMBERSID = mem.membersid
    JOIN  Ifly_pointtypes pt ON FMBB.pointtypesid = pt.pointtypesid
    LEFT JOIN agg ON agg.member_number = mem.membernumber AND agg.point_type_code = FMBB.pointtypecode;