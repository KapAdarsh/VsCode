with max_snapshot as 
            (select 
              max(memberbenefitbalancesnapshotdate) as max_snapshotdate 
            from EDW.FACT_MEMBER_BENEFIT_BALANCE),
     Ifly_pointtypes as 
            (select
                pointtypesid ,
                groupname,
                pointtypecode 
            from edw.dim_pointtype 
                where   GroupName IN ('Benefits','eUpgrades') 
                and PointTypeCode NOT IN ('CDSC','CFC','CMLP','GFTCARD','GIFT','SP50','MIWIFI','WIFIACTIV','MWIFIVIP','WIFI12','WIFI6')
            ),
SELECT
        FMBB.MEMBERSID,
        FMBB.MEMBERBENEFITBALANCESNAPSHOTDATESID,
        FMBB.POINTTYPESID,
        FMBB.MEMBERBENEFITBALANCESNAPSHOTDATE,
        FMBB.POINTTYPECODE,
        pt.POINTTYPENAME,
        FMBB.TOTALACCRUALALLOTMENT as TOTALACCRUED,
        FMBB.TOTALEXPIRYALLOTMENT as TOTALEXPIRED,
        (FMBB.totalaccrualallotment - FMBB.TOTALEXPIRYALLOTMENT - FMBB.TOTALREDEMPTIONALLOTMENT) AS balance,/* If b.cnt is null (no bookings), keep original allotment */
        (COALESCE(agg.cnt, 0)) AS TOTALUSED,
        c.membernumber
    FROM edw.fact_member_benefit_balance FMBB 
    join  Ifly_pointtypes pt on FMBB.pointtypesid = pt.pointtypesid
    join max_snapshot on max_snapshot.max_snapshotdate = FMBB.MEMBERBENEFITBALANCESNAPSHOTDATE
-----------------------------

use database edw;
with max_snapshot as 
            (select 
              max(memberbenefitbalancesnapshotdate) as max_snapshotdate 
            from EDW.FACT_MEMBER_BENEFIT_BALANCE),
     Ifly_pointtypes as 
            (select
                pointtypesid ,
                groupname,
                pointtypecode,
                pointtypename
            from edw.dim_pointtype 
                where   GroupName IN ('Benefits','eUpgrades') 
                and PointTypeCode NOT IN ('CDSC','CFC','CMLP','GFTCARD','GIFT','EUPG','PEUPG','MLLPTB','MLLPWW','NAR','NAT','SP50','MIWIFI','WIFIACTIV','MWIFIVIP','WIFI12','WIFI6')
            )
SELECT
        FMBB.MEMBERSID,
        FMBB.MEMBERBENEFITBALANCESNAPSHOTDATESID,
        FMBB.POINTTYPESID,
        FMBB.MEMBERBENEFITBALANCESNAPSHOTDATE,
        FMBB.POINTTYPECODE,
        pt.POINTTYPENAME,
        FMBB.TOTALACCRUALALLOTMENT as TOTALACCRUED,
        FMBB.TOTALEXPIRYALLOTMENT as TOTALEXPIRED,
        (FMBB.totalaccrualallotment - FMBB.TOTALEXPIRYALLOTMENT - FMBB.TOTALREDEMPTIONALLOTMENT) AS balance,/* If b.cnt is null (no bookings), keep original allotment */
         FMBB.TOTALREDEMPTIONALLOTMENT AS TOTALUSED,
        mem.membernumber
    FROM edw.fact_member_benefit_balance FMBB 
    join edw.dim_member mem on FMBB.MEMBERSID = mem.membersid
    join  Ifly_pointtypes pt on FMBB.pointtypesid = pt.pointtypesid
    join max_snapshot on max_snapshot.max_snapshotdate = FMBB.MEMBERBENEFITBALANCESNAPSHOTDATE;
    ------------------------------------------------------------------------------------------------------

use database edw;
with max_snapshot as 
            (select 
              max(memberbenefitbalancesnapshotdate) as max_snapshotdate 
            from EDW.FACT_MEMBER_BENEFIT_BALANCE),
     Ifly_pointtypes as 
            (select
                pointtypesid ,
                groupname,
                pointtypecode,
                pointtypename
            from edw.dim_pointtype 
                where PointTypeCode  IN ('PRWWJ','PRNAPY','PRWWPY','STPA', 'PRCUY25', 'PRWWF')--Add 
            )
    SELECT
        mem.membernumber,
        FMBB.MEMBERBENEFITBALANCESNAPSHOTDATE,
        FMBB.POINTTYPECODE,
        pt.POINTTYPENAME,
        FMBB.TOTALACCRUALALLOTMENT as TOTALACCRUED,
        FMBB.TOTALEXPIRYALLOTMENT as TOTALEXPIRED,
        (FMBB.totalaccrualallotment - FMBB.TOTALEXPIRYALLOTMENT - FMBB.TOTALREDEMPTIONALLOTMENT) AS balance,/* If b.cnt is null (no bookings), keep original allotment */
         FMBB.TOTALREDEMPTIONALLOTMENT AS TOTALUSED
       
    FROM edw.fact_member_benefit_balance FMBB 
    join edw.dim_member mem on FMBB.MEMBERSID = mem.membersid
    join  Ifly_pointtypes pt on FMBB.pointtypesid = pt.pointtypesid
    join max_snapshot on max_snapshot.max_snapshotdate = FMBB.MEMBERBENEFITBALANCESNAPSHOTDATE;
    ------------------------------
    