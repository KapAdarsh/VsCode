CREATE OR REPLACE TABLE EDW.FACT_COBRANDCARDACCOUNTBANKOFFERS (
    CARDACCOUNTSID NUMBER(38,0) NOT NULL COMMENT 'Code used to identify the co-brand card account.',
    MEMBERSID NUMBER(38,0) NOT NULL COMMENT "Code used to track the Aeroplan member information, the SID changes when the member information are updated (eg. Change in member's status, phone number or address).",
    FROMPRODUCTCODESID NUMBER(38,0) NOT NULL COMMENT 'Surrogate key referencing the original/current product code the member holds before a potential product conversion offer',
    TOPRODUCTCODESID NUMBER(38,0) NOT NULL COMMENT 'Surrogate key referencing the target product code being offered to the member for a product conversion or upgrade',
    GENERATEDFILEDATESID NUMBER(38,0) NOT NULL COMMENT 'Date surrogate key indicating when the offer file was generated for outbound processing',
    CASLEXPIREDATESID NUMBER(38,0) NOT NULL COMMENT 'Date surrogate key for CASL (Canadian Anti-Spam Legislation) consent expiration date for marketing communications',
    TDCASLINDICATOR VARCHAR(2) NOT NULL COMMENT 'TD Bank CASL compliance indicator flag showing member consent status for TD marketing communications (N means it did not pass TD CASL and Y it passed TD CASL or TD did not have email address)',
    PARTNEROFFER VARCHAR(20) COMMENT 'Identifier or code representing the specific partner offer or promotion being extended to the cardholder',   
    CREATEDBATCHLOGID NUMBER(38,0) NOT NULL COMMENT 'ID number of the bach that created the record',
    UPDATEDBATCHLOGID NUMBER(38,0) COMMENT 'ID number of the bach that updated the record',
    UPDATETYPE VARCHAR(100) NOT NULL COMMENT 'Type of update of the table',
    FACTHASH VARCHAR(64) NOT NULL COMMENT 'Hash value representing the fact record.'
) COMMENT = 'This table stores weekly eligibility data received from TD to support Aeroplan cobranded card upsell campaigns. Each record represents a TD card account / Aeroplan member combination that is eligible for an upgrade offer, along with the current and target product codes, CASL indicator, and offer metadata.'
;


COMMENT ON TABLE DIM_CANADA_PROVINCIAL_SALES_TAX IS 'Stores Canadian provincial sales tax rates by province and tax type (GST/HST/QST/PST), including total sales tax and input tax credit (ITC) rates. ';
COMMENT ON COLUMN DIM_CANADA_PROVINCIAL_SALES_TAX.Canada_Provincial_Sales_Tax_SID IS 'SID for the dimension, technical field, auto incremental';
COMMENT ON COLUMN DIM_CANADA_PROVINCIAL_SALES_TAX.Province_Code IS 'Province code';
COMMENT ON COLUMN DIM_CANADA_PROVINCIAL_SALES_TAX.Province_Name IS 'Province name';
COMMENT ON COLUMN DIM_CANADA_PROVINCIAL_SALES_TAX.Tax_Type_Code IS 'Tax type code';
COMMENT ON COLUMN DIM_CANADA_PROVINCIAL_SALES_TAX.GST_Rate IS 'GST rate';
COMMENT ON COLUMN DIM_CANADA_PROVINCIAL_SALES_TAX.HST_Rate IS 'HST rate';
COMMENT ON COLUMN DIM_CANADA_PROVINCIAL_SALES_TAX.QST_Rate IS 'QST rate';
COMMENT ON COLUMN DIM_CANADA_PROVINCIAL_SALES_TAX.PST_Rate IS 'PST rate';
COMMENT ON COLUMN DIM_CANADA_PROVINCIAL_SALES_TAX.Total_Sales_Tax_Rate IS 'Total Sales Tax rate';
COMMENT ON COLUMN DIM_CANADA_PROVINCIAL_SALES_TAX.Total_ITC_Rate IS 'Total ITC rate';
COMMENT ON COLUMN DIM_CANADA_PROVINCIAL_SALES_TAX.Effective_Start_DTE IS 'Effective start date';
COMMENT ON COLUMN DIM_CANADA_PROVINCIAL_SALES_TAX.Effective_End_DTE IS 'Effective end date';
COMMENT ON COLUMN DIM_CANADA_PROVINCIAL_SALES_TAX.LOAD_DATE IS 'Load date';
COMMENT ON COLUMN DIM_CANADA_PROVINCIAL_SALES_TAX.Canada_Provincial_Sales_Tax_HashKey IS 'Hashkey for the business key';
COMMENT ON COLUMN DIM_CANADA_PROVINCIAL_SALES_TAX.CurrentFlag IS 'Flag indicating whether the record is currently active.Possible values: 1 = Active (current) 0 = Inactive (non-current)';
COMMENT ON COLUMN DIM_CANADA_PROVINCIAL_SALES_TAX.DeletedFlag IS 'Flag indicating whether the record has been logically deleted (soft delete). Possible values: 1 = Deleted 0 = Not deleted';
COMMENT ON COLUMN DIM_CANADA_PROVINCIAL_SALES_TAX.SCDStartDateTime IS 'Exact UTC timestamp when this record became effective.';
COMMENT ON COLUMN DIM_CANADA_PROVINCIAL_SALES_TAX.SCDEndDateTime IS 'Exact UTC timestamp when this record was superseded by another record.';
COMMENT ON COLUMN DIM_CANADA_PROVINCIAL_SALES_TAX.LateArrivingFlag IS 'Flag indicating whether the record was created outside the standard dimension load process. Possible values: 1 = Late arriving (e.g., created by a fact load, not a dimension load) 0 = Normal';
COMMENT ON COLUMN DIM_CANADA_PROVINCIAL_SALES_TAX.Type1Hash IS "if it a type 1 specify all columns TypeHash : HASH(CONCAT(All Columns excluding SID's & Control Columns) else null";
COMMENT ON COLUMN DIM_CANADA_PROVINCIAL_SALES_TAX.Type2Hash IS "if it a type 2 specify all columns TypeHash : HASH(CONCAT(All Columns excluding SID's & Control Columns) else null";
COMMENT ON COLUMN DIM_CANADA_PROVINCIAL_SALES_TAX.CreatedBatchLogID IS 'ID number of the batch that created the record';
COMMENT ON COLUMN DIM_CANADA_PROVINCIAL_SALES_TAX.UpdatedBatchLogID IS 'ID number of the batch that updated the record';
COMMENT ON COLUMN DIM_CANADA_PROVINCIAL_SALES_TAX.UpdateType IS 'Type of update of the table';

