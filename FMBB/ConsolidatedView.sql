use database edw;
with max_snapshot as /* get the latest data from FMBB */
            (select 
              max(memberbenefitbalancesnapshotdate) as max_snapshotdate 
            from EDW.FACT_MEMBER_BENEFIT_BALANCE),
     Ifly_pointtypes as /* Filtering out necessary point types from dim_pointtypes */
            (select
                pointtypesid ,
                groupname,
                pointtypecode,
                pointtypename
            from edw.dim_pointtype 
                where   GroupName IN ('Benefits','eUpgrades') 
                and PointTypeCode NOT IN ('CDSC','CFC','CMLP','GFTCARD','GIFT','SP50','MIWIFI','WIFIACTIV','MWIFIVIP','WIFI12','WIFI6')
            ),
     agg as /* for calculation of eupgrades , NAR ,NAT and IEG usage, will use VW_MEMBER_CONSOLIDATED_BENEFIT_USAGE */
            (SELECT
                mem.membernumber,
                pt.pointtypecode,
                SUM(vw.benefit_value) AS cnt
            FROM ae_analytics.VW_MEMBER_CONSOLIDATED_BENEFIT_USAGE vw 
            join edw.dim_member mem on vw.member_sid = mem.membersid
            join edw.dim_pointtype pt on vw.pointtypesid = pt.pointtypesid
            GROUP BY mem.membernumber, pt.pointtypecode )       
    SELECT
        mem.membernumber,
        FMBB.MEMBERBENEFITBALANCESNAPSHOTDATE,
        FMBB.POINTTYPECODE,
        pt.POINTTYPENAME,
        FMBB.TOTALACCRUALALLOTMENT as TOTALACCRUED,
        FMBB.TOTALEXPIRYALLOTMENT as TOTALEXPIRED,
        Case 
            when FMBB.pointtypecode in ('EUPG','PEUPG','MLLPTB','MLLPWW','NAR','NAT') 
            then (FMBB.totalaccrualallotment - FMBB.TOTALEXPIRYALLOTMENT - agg.cnt) 
            else (FMBB.totalaccrualallotment - FMBB.TOTALEXPIRYALLOTMENT - FMBB.TOTALREDEMPTIONALLOTMENT) 
        end  AS balance,/* For eupgrades , NAR ,NAT and IEG usage , will use VW_MEMBER_CONSOLIDATED_BENEFIT_USAGE else FMBB */
        Case 
            when FMBB.pointtypecode in ('EUPG','PEUPG','MLLPTB','MLLPWW','NAR','NAT')
            then agg.cnt 
            else FMBB.TOTALREDEMPTIONALLOTMENT 
        end AS TOTALUSED
       
    FROM edw.fact_member_benefit_balance FMBB 
    join edw.dim_member mem on FMBB.MEMBERSID = mem.membersid
    join  Ifly_pointtypes pt on FMBB.pointtypesid = pt.pointtypesid
    join max_snapshot on max_snapshot.max_snapshotdate = FMBB.MEMBERBENEFITBALANCESNAPSHOTDATE
    join agg on agg.membernumber = mem.membernumber and agg.pointtypecode = FMBB.pointtypecode;