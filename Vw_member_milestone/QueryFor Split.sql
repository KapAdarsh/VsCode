
WITH cts AS (
    SELECT
        dmb.memberhashkey,
        b.pointtypecode,
        a.creditinggmttimestamp,
        a.pointvalue AS original_pointvalue,
        IFF(a.pointvalue < 0, -1, 1) AS unitpointvalue,
        SUM(IFF(a.pointvalue < 0, -1, 1)) OVER (
            PARTITION BY dmb.memberhashkey, b.pointtypecode
            ORDER BY a.creditinggmttimestamp
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS TotalThresholdValue

    FROM edw_ha.fact_point_transaction a
    JOIN edw_ha.dim_pointtype b 
        ON a.pointtypesid = b.pointtypesid
    JOIN edw_ha.dim_member dmb
        ON a.membersid = dmb.membersid

    /* EXPLOSION: generate rows = ABS(pointvalue) */
    CROSS JOIN LATERAL FLATTEN(
        INPUT => ARRAY_GENERATE_RANGE(
                     1,
                     ABS(COALESCE(a.pointvalue, 0)) + 1
                 )
    ) f

    WHERE dmb.memberhashkey = '000fb6ccc69dbb5b732ecfd7c83bc184483a6f20ff1982c25afe37e190cbfbf9'
      AND b.pointtypecode IN ('SLBTHRLVL','THRLVL')
)

SELECT *
FROM cts
ORDER BY memberhashkey, pointtypecode, creditinggmttimestamp, TOTALTHRESHOLDVALUE;

'000fb6ccc69dbb5b732ecfd7c83bc184483a6f20ff1982c25afe37e190cbfbf9'  -- positive
'd32c0bdb2d6693e9f400676c5f3a61d7b0954516a9cbf539481af017b026fdd7'  -- negetive
'aa9a59a872c68c152ace981bc0c6e5ed4cfd0249043765813f9271e7e02e7118' -- autacc




'56a82173e5c11578ada2124a80a3b05cb959c65be2a25ee835ad1583e9c05aaa',
'80bef939ce530fbca12c982e2bf27cb229e9f9ca4657fede9a82ad99fd620227',
'c19031710b59f057025345cae20cc0c83cab7fcdb1c58698a56d1c1a1e9fef51'


'51d77c7389ad2d52c75c351b14ba44629ee3558d10495f0a99e50a3f04f2a27a',
'16a1d5b094d97abbc1826eef810d9be23bbffc415d78cba8ed4a54231095f135',
'645867fddef6b23693f77453e7d0c421a473a40c674b4c245b07cc1490a57750',
'5881436b606e5a18530f5c36a7acf270f89d3543a7fe105ed7054fd2bd22b2ca'