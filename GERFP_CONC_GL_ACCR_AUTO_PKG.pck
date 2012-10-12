CREATE OR REPLACE PACKAGE GERFP_CONC_GL_ACCR_AUTO_PKG
/*************************************************************************************************************************************
 *                           - Copy Right General Electric Company 2006 -
 *
 *************************************************************************************************************************************
 *************************************************************************************************************************************
 * Project      :  GEGBS Financial Implementation Project
 * Application      :  General Ledger
 * Title        :  N/A
 * Program Name     :  N/A
 * Description Purpose  :  To Load ACCURAL Concur Expenses from staging into GL interface tables
 * $Revision        :
 * Utility      :
 * Created by       :  Ramesh Soorishetty
 * Creation Date    :  12-FEB-2009
 * Called By            :  Concurrent Program
 * Parameters           :  N.A
 * Dependency       :  N/A
 * Frequency        :  On Demand
 * Related documents    :
 * Tables/views accessed:
 * Table Name                       SELECT     INSERT     UPDATE     DELETE
 * ---------------------            ------     ------     ------     ------
 * ----------------------------------------------------------------------------
 * Change History   :
 *====================================================================================================================================
 * Date         |Name               |Case#      |Remarks
 *====================================================================================================================================
 *
  *************************************************************************************************************************************
*/

IS

PROCEDURE debug_message( p_message IN  VARCHAR2 );

PROCEDURE process_gl_accr_data(  errbuff       OUT  VARCHAR2
                               , retcode       OUT  VARCHAR2
                             );

PROCEDURE display_err_congl( errbuff       OUT  VARCHAR2
                           , retcode       OUT  VARCHAR2
                           );

PROCEDURE SEND_Mail
      (
        p_action in varchar2,
        p_content in varchar2
        );                             


g_group_id          VARCHAR2(200);
g_entries           VARCHAR2(200);
tot_group_id        VARCHAR2(200);
tot_category_name   VARCHAR2(200);


END GERFP_CONC_GL_ACCR_AUTO_PKG; 
/
CREATE OR REPLACE PACKAGE BODY GERFP_CONC_GL_ACCR_AUTO_PKG
AS
/*************************************************************************************************************************************
 *                           - Copy Right General Electric Company 2006 -
 *
 *************************************************************************************************************************************
 *************************************************************************************************************************************
 * Project      :  GEGBS Financial Implementation Project
 * Application      :  General Ledger
 * Title        :  N/A
 * Program Name     :  N/A
 * Description Purpose  :  To Load ACCURAL Concur Expenses from staging into GL interface tables
 * $Revision        :
 * Utility      :
 * Created by       :  Ramesh Soorishetty
 * Creation Date    :  12-FEB-2009
 * Called By            :  Concurrent Program
 * Parameters           :  N.A
 * Dependency       :  N/A
 * Frequency        :  On Demand
 * Related documents    :
 * Tables/views accessed:
 * Table Name                       SELECT     INSERT     UPDATE     DELETE
 * ---------------------            ------     ------     ------     ------
 *  GL_CODE_COMBINATIONS              X          -          -          -
 *  GL_JE_HEADERS             X          -          -          -
 *  GL_JE_SOURCES                 X          -          -          -
 *  GL_JE_CATEGORIES              X          -          -          -
 *  GL_INTERFACE_CONTROL              -          X          -          -
 *  GL_SETS_OF_BOOKS              X          -          -          -
 *  GL_CODE_COMBINATIONS              X          -          -          -
 *  GL_INTERFACE              -          X          -          -
 *  XXRFP_CONCUR_BUS_MAP              X          -          -          -
 *  XXRFP_CONCUR_KEYAC_MAP        X          -          -          -
 *  XXRFP_CONCUR_CC_MAP           X          -          -          -
 *  GERFP_CONGL_STG               X          -          X          -
 * ----------------------------------------------------------------------------
 * Change History   :
*====================================================================================================================================
 * Date         |Name               |Case#      |Remarks
 *====================================================================================================================================
 * 11-MAY-2009  |Ramesh Soorishetty             | N.A           | Modified for Sob Id to show error records for specific sob in
 *                                                                ACCR Error Correction from
 * 11-MAY-10    Satya Chittella                                  modified the code as a aprt of project code extension
  *************************************************************************************************************************************
*/

v_conc_request        NUMBER      :=   FND_GLOBAL.CONC_REQUEST_ID;
p_flag                varchar(2);  --added by Satya Chittella for project code Extn

--Added by george on 15-Jul-2010 for automotion
g_conn utl_smtp.connection;
g_sender    VARCHAR2(100) := 'oracle_user@ge.com';
g_recipients Varchar2(300);
g_Mail_Domain Varchar2(30) default '@mail.ad.ge.com';

  /******************************************************************************/
  /*               PROCEDURE TO DISPLAY LOG MESSAGES                            */
  /******************************************************************************/

 PROCEDURE debug_message( p_message IN  VARCHAR2 )
 IS
 BEGIN
    FND_FILE.PUT_LINE( FND_FILE.LOG, p_message);
 EXCEPTION
   WHEN OTHERS THEN
      debug_message( '-> Error occured in DEBUG_MESSAGE Procedure : ' || SQLERRM );
 END debug_message;

  /******************************************************************************/
  /*   Procedure to Check Duplicate file processing with batch number           */
  /******************************************************************************/
 PROCEDURE check_dup_file_process( p_sob_id    IN   NUMBER,
                   p_batch_number  IN   VARCHAR2,
                   p_group_id IN number,
                   x_status    OUT  VARCHAR2)

 IS
    v_batch_number  VARCHAR2(50);
    v_je_cnt    NUMBER := 0;
    v_status    VARCHAR2(1);
 BEGIN

     IF (p_batch_number IS NOT NULL) THEN
      /*Checking Batch number in Oracle Base Table (GL_JE_HEADERS) */
    BEGIN
       SELECT SUM(rc) INTO V_JE_CNT
       FROM
       ( 
       SELECT COUNT(gjh.je_header_id)
         rc
         FROM gl_je_headers gjh
             ,gl_je_sources gjs
             ,gl_je_categories gjc
        WHERE gjh.external_reference like p_batch_number
          AND gjh.set_of_books_id = p_sob_id
          AND gjc.je_category_name = gjh.je_category
          AND gjs.je_source_name = gjh.je_source
          --AND UPPER(gjc.user_je_category_name) = 'CONCUR SAE'
          AND UPPER(gjs.user_je_source_name) = 'CONCUR' 
          and rownum=1
        union all
        select COUNT(1) rc  from gl_interface gi 
        where 
        --UPPER(gi.user_je_category_name) = 'CONCUR SAE' and 
        UPPER(gi.user_je_source_name) = 'CONCUR' and 
        gi.reference6= p_batch_number and gi.group_id <> p_group_id
        and rownum=1
        );

        IF (NVL(v_je_cnt,0) > 0) THEN
          x_status := 'Y';
       ELSE
          x_status := 'N';
       END IF;
    END;
     END IF;

    x_status := NVL(x_status,'N');

 EXCEPTION
   WHEN OTHERS THEN
    FND_FILE.PUT_LINE( FND_FILE.LOG,'Error occured in CHECK_DUP_FILE_PROCESS Procedure : ' || SQLERRM );
 END check_dup_file_process;


  /******************************************************************************/
  /*   PROCEDURE to Submit JOURNAL IMPORT Program                               */
  /******************************************************************************/

 PROCEDURE SUBMIT_JOURNAL_IMPORT( p_user_id IN  NUMBER
                 ,p_resp_id IN  NUMBER
                 ,p_sob_id  IN  NUMBER
                 ,p_group_id    IN  NUMBER
                 ,p_source  IN  VARCHAR2
                 ,x_status  OUT VARCHAR2
                 ,x_req_id  OUT number
                )
 IS

     v_req_id            NUMBER;
     v_appl_id           NUMBER;
     v_suspense_flag     VARCHAR2(2) := 'Y';
     v_interface_run_id  NUMBER;
     v_req_return_status BOOLEAN;
     v_summary_flag      VARCHAR2(1) := 'N';
     v_source_name       VARCHAR2(30);
     v_user_source_name  VARCHAR2(80);
     v_req_phase         VARCHAR2(30);
     v_req_status        VARCHAR2(30);
     v_req_dev_phase     VARCHAR2(30);
     v_req_dev_status    VARCHAR2(30);
     v_req_message       VARCHAR2(50);
     v_je_source         VARCHAR2(50);


 BEGIN

       SELECT DISTINCT  application_id
         INTO v_appl_id
         FROM fnd_application
        WHERE application_short_name = 'SQLGL';

     /*Deriving the Source Name*/
      BEGIN

          SELECT je_source_name
        INTO v_je_source
        FROM gl_je_sources
           WHERE user_je_source_name = p_source;

      EXCEPTION
       WHEN NO_DATA_FOUND THEN
         FND_FILE.PUT_LINE(FND_FILE.LOG, 'No Data Found Exception : JE_SOURCE_NAME does not exist for '||p_source);
       WHEN TOO_MANY_ROWS THEN
         FND_FILE.PUT_LINE(FND_FILE.LOG,'Exact Fetch Returned Too many Rows while extracting JE_SOURCE_NAME Value');
       WHEN OTHERS THEN
         FND_FILE.PUT_LINE(FND_FILE.LOG, 'SQL ERROR MESSAGE while extracting JE_SOURCE_NAME Value:' || SQLERRM);
      END;


       /* Sequence to create RUN_ID -- -- GERFP_IMPORT_RUN_ID_S.NEXTVAL */
        SELECT GL_JOURNAL_IMPORT_S.NEXTVAL
          INTO v_interface_run_id
          FROM dual;

--     debug_message('Before insert to Interface control table  ');
       /* Insert record to interface control table */
        INSERT INTO gl_interface_control(je_source_name
                        ,status
                        ,interface_run_id
                        ,group_id
                        ,set_of_books_id
                        ,packet_id
                        ,request_id
                      )
                    VALUES (v_je_source     --p_source
                       ,'S'
                       ,v_interface_run_id
                       ,p_group_id
                       ,p_sob_id
                       ,NULL
                       ,v_req_id
                      );
          COMMIT;

--     debug_message('After insert to Interface control table  ');

--   Calling FND_REQUEST for Journal Import
        v_req_id := FND_REQUEST.SUBMIT_REQUEST( application   => 'SQLGL'
                           ,program       => 'GLLEZL'
                           ,description   => NULL
                           ,start_time    => SYSDATE
                           ,sub_request   => FALSE
                           ,argument1     => to_char(v_interface_run_id)
                           ,argument2     => to_char(p_sob_id)
                           ,argument3     => 'N'    --Suspense Flag
                           ,argument4     => NULL
                           ,argument5     => NULL
                           ,argument6     => 'N'      -- Summary Flag
                           ,argument7     => 'O'    --Import DFF w/out validation
                            );

       debug_message('Import Request id :'||v_req_id);
    
    x_req_id:=v_req_id;
    
    IF v_req_id=0 THEN
      raise_application_error(-20160, FND_MESSAGE.GET);
      x_status := 'Failed';
    ELSE
       x_status := 'Done';
    END IF;

 EXCEPTION
   WHEN OTHERS THEN
    FND_FILE.PUT_LINE(FND_FILE.LOG,'JOB FAILED'||SQLERRM);
 END SUBMIT_JOURNAL_IMPORT;

  /**************************************************************/
  /*    MAIN PROCEDURE TO PROCESS DATA FROM STAGING TABLE TO INTERFACE TABLES   */
  /**************************************************************/

    PROCEDURE process_gl_accr_data( errbuff   OUT  VARCHAR2
                                  , retcode   OUT  VARCHAR2
                                  )
    IS

   /*Added by Soori on 13-FEB-2010 for Automation*/
   CURSOR cur_file_seq
   IS
   SELECT DISTINCT
          file_seq
     FROM gerfp_congl_accr_stg
    WHERE process_flag = 'U'
      AND concur_req_id = v_conc_request
      AND file_seq IS NOT NULL
      AND err_msg IS NULL;


   /*Cursor to fetch records from staging table*/
   CURSOR cur_concur_accr_data(p_conc_req_id IN VARCHAR2
                          ,p_file_seq    IN NUMBER /*Added by george on 15-JUL-2010 for Automation*/
                         )
   IS
   SELECT
       rowid, concur_req_id       ,
    concur_batch_id         ,
    detail_format_ind       ,
    concur_export_date      ,
    cc_trans_key        ,
    last_name       ,
    first_name      ,
    middle_name     ,
    ohr_emp_id      ,
    glid            ,
    department      ,
    paymt_type_seg_1    ,
    paymt_type_ap_num   ,
    custom1_segment_1   ,
    custom2_segment_1   ,
    custom3_segment_1   ,
    transaction_type    ,
    transaction_number  ,
    vendor_name     ,
    vendor_mcc_code     ,
    paymt_method        ,
    paymt_type_acc_num  ,
    paymt_acc_num       ,
    int_dom_flag        ,
    e_tran_iso_contry_code  ,
    entity_iso_country_code ,
    entity_iso_curr_code    ,
    submission_name     ,
    submit_date     ,
    transaction_date    ,
    home_amount     ,
    debit_credit_indicator  ,
    hh_description      ,
    process_flag        ,
    err_msg                 ,
    sob_id  /*Added by Soori on 11-MAY-2009*/
    ,file_seq /*Added by George on 15-JUL-2010 for Automation*/
     FROM gerfp_congl_accr_stg
    WHERE concur_req_id = p_conc_req_id
      AND file_seq = p_file_seq
      AND detail_format_ind IN ('HH','AD')
      AND process_flag = 'U'
      AND err_msg IS NULL
      ORDER BY 3 DESC;

    CURSOR notifier_list
    IS
    select DISTINCT FUTURE2 
    FROM 
    apps.xxrfp_concur_bus_map glid
    where FUTURE2 is not null
    order by FUTURE2;
    
    CURSOR CUR_FILE_STATUS(P_REQ_ID NUMBER,notifier Varchar2)
    IS
    select DISTINCT FILE_SEQ,FILE_NAME,CONCUR_BATCH_ID,CONCUR_REQ_ID,SOB_ID,GLID,FUTURE2 
    FROM 
    GERFP_CONGL_ACCR_STG stg,apps.xxrfp_concur_bus_map glid
    where glid.CONCUR_LEDGER_CODE = stg.GLID
    and CONCUR_REQ_ID=P_REQ_ID
    and glid.FUTURE2 = notifier
    order by GLID,SOB_ID,FILE_SEQ;
   
    
    CURSOR CUR_ERR_CGL(P_REQ_ID NUMBER,P_FILE_NAME VARCHAR2, P_BATCH_NAME VARCHAR2)
    IS
    SELECT *
    FROM gerfp_congl_accr_stg
    WHERE process_flag IN ('R','CR') /*CC,Key and Other Rejected*/
    AND err_msg IS NOT NULL
    And file_name=P_FILE_NAME
    and CONCUR_BATCH_ID=P_BATCH_NAME
    AND detail_format_ind = 'AD'  /*Added by Soori on 13-FEB-2010 for Automation*/
    AND concur_req_id = P_REQ_ID;

    CURSOR cur_iface_data( p_source     VARCHAR2
                         , p_group_id   NUMBER
                 )
        IS
    SELECT gi.set_of_books_id sob_id,
           sob.NAME sob_name,
           gi.reference6 Batch_name,group_id,
        COUNT(1) rec_cnt
    FROM  gl_interface gi,
          gl_sets_of_books sob
    WHERE gi.set_of_books_id=sob.set_of_books_id
    AND   user_je_source_name=p_source
    and   user_je_category_name ='Concur Accrual'
    AND   group_id=p_group_id
    AND   STATUS='NEW'
    GROUP BY gi.set_of_books_id,sob.NAME,gi.reference6,group_id;

    /*Variables Declaration*/
    v_batch_id               VARCHAR2(200);
    v_export_date            DATE;
    v_concur_export_date     DATE;
    v_err_msg                VARCHAR2(2000) := NULL;
    v_cc_err_msg             VARCHAR2(4000) := NULL;
    v_sob_id                 NUMBER;
    v_je_cnt                 NUMBER;
    v_intr_rec_cnt           NUMBER;
    v_userid                 NUMBER;
    v_resp_id                NUMBER;
    v_import_status      VARCHAR2(500);
    v_chk_status             VARCHAR2(2000);
    v_final_chk_status       VARCHAR2(2000);
    v_start_date             DATE;
    v_period_name            VARCHAR2(200);

    v_last_name              VARCHAR2(200);
    v_first_name             VARCHAR2(200);
    v_glid                   VARCHAR2(200);
    v_submission_name        VARCHAR2(200);
    v_transaction_date       DATE;
    v_entity_iso_curr_code   VARCHAR2(200);
    v_department             VARCHAR2(200);
    v_home_amount            NUMBER;
    v_debit_credit_indicator VARCHAR2(200);
    v_hh_description         VARCHAR2(4000);
    v_reference10            VARCHAR2(250);
    v_attribute10            VARCHAR2(200);
    v_tot_cr_amt             NUMBER;
    v_tot_dr_amt             NUMBER;

    v_me_code            apps.xxrfp_concur_bus_map.me_code%TYPE;
    v_le_code            apps.xxrfp_concur_bus_map.le_code%TYPE;
    v_book_type          apps.xxrfp_concur_bus_map.book_type%TYPE;
    v_sae_offset_account     apps.xxrfp_concur_bus_map.sae_offset_account%TYPE;
    v_tax_account            apps.xxrfp_concur_bus_map.tax_account%TYPE;
    v_accr_offset_account    apps.xxrfp_concur_bus_map.accrual_offset_account%TYPE;
    v_conc_suspense_account  apps.xxrfp_concur_bus_map.concur_suspense_account%TYPE;

/* Added by george for TH
--xbus.CC_SAE_OFFSET_ACCOUNT,xbus.CASH_ADV_ACCOUNT,xbus.WHT_ACCOUNT,xbus.ALLOC_CEARING_ACCOUNT
*/
    v_CC_SAE_OFFSET_ACCOUNT     apps.xxrfp_concur_bus_map.CC_SAE_OFFSET_ACCOUNT%TYPE;                      
    v_CASH_ADV_ACCOUNT          apps.xxrfp_concur_bus_map.CASH_ADV_ACCOUNT%TYPE;
    v_WHT_ACCOUNT               apps.xxrfp_concur_bus_map.WHT_ACCOUNT%TYPE;
    v_ALLOC_CEARING_ACCOUNT     apps.xxrfp_concur_bus_map.ALLOC_CEARING_ACCOUNT%TYPE;

    v_AccType varchar2(20);
    v_key_flag                varchar(2);
    
    v_na        apps.xxrfp_concur_keyac_map.natrual_account%TYPE;
    v_ime_code          apps.xxrfp_concur_keyac_map.ime_code%TYPE;
    v_ile_code          apps.xxrfp_concur_keyac_map.ile_code%TYPE;
    v_project_1         apps.xxrfp_concur_keyac_map.project%TYPE DEFAULT '0000000000';
    v_shltn_code        apps.xxrfp_shelton_cc_map.shelton_ledger%TYPE;
    v_oracle_cc     apps.xxrfp_shelton_cc_map.oracle_cc%TYPE;
    v_project           apps.xxrfp_shelton_cc_map.project%TYPE;
    v_reference         apps.xxrfp_shelton_cc_map.ref%TYPE;
    v_no_cc_flag        VARCHAR2(20);

--Added by george on 15-Jul-2010 for automotion
    V_HTML          varchar2(3000);
    v_err_cnt       number;
    v_err_buffer    varchar2(3000);
    v_req_id        number;
    v_rc    number;
    X_STATUS  varchar2(25);
    V_PHASE  varchar2(25);
    V_STATUS  varchar2(25);
    V_DEV_PHASE  varchar2(25);
    V_DEV_STATUS    varchar2(25);
    V_MESSAGE   varchar2(200);
    V_REQUEST_COMPLETE BOOLEAN;
    v_file_count number;

    /* Exception Declaration */
    end_of_program       EXCEPTION;
    e_skip_to_next_rec   EXCEPTION;
    e_end_program        EXCEPTION;
    e_acc_type           EXCEPTION;
    e_flag               EXCEPTION;
    e_flag_proj_nd       EXCEPTION;
    e_flag_proj_nd_c     EXCEPTION; 
    E_SHELTON_BUS        EXCEPTION;    
    v_default_cc VARCHAR2(100);

    BEGIN
        /*Procedure BEGIN*/
        v_userid := to_number(fnd_profile.value('USER_ID'));
        v_resp_id:= to_number(fnd_profile.value('RESP_ID'));
        
        /*For Updating the staging table for the current submission of upload*/
        BEGIN
        /*
        SELECT TO_CHAR(SYSDATE,'DDMMRRRRHH24MISS')
        INTO g_group_id
        FROM DUAL;

        debug_message('Group Id Derived - '||g_group_id);
        */

        UPDATE gerfp_congl_accr_stg
        SET concur_req_id = v_conc_request
        WHERE concur_req_id = '-1'
        AND process_flag ='U'
        AND err_msg IS NULL;
        
        debug_message('Processing staging table...');
        debug_message('Updated the Staging table with Program Request Id Derived ');
        
        EXCEPTION
        WHEN NO_DATA_FOUND THEN
        v_err_msg := v_err_msg||' /'||'No Data Exist for Updating the staging table with Current request Id';
        RAISE end_of_program;
        WHEN OTHERS THEN
        v_err_msg := v_err_msg||' /'||'Exception in Updating the staging table with Current request Id';
        RAISE end_of_program;
    END;

/*Loop for file added by george on 15-JUL-2010 for comment  */
FOR rec_file_seq IN cur_file_seq
LOOP
    /*Main Loop for each concur line*/
    --Added by george ye on 15-Jul-2010 to generate group id for a file for automotion
    select substr(to_char(systimestamp, 'yymmddhh24missff'),1,15) into g_group_id from dual;  
    g_group_id:=rec_file_seq.file_seq;
        
    debug_message('group id :'||g_group_id);
    --Added by george ye on 15-Jul-2010 to generate group id for a file for automotion
    
    --Modified by george on on 15-JUL-2010
    --FOR rec_concur_accr_data IN cur_concur_accr_data(v_conc_request)
       
    debug_message('Request :'||v_conc_request || ',File Seq:' || rec_file_seq.file_seq );
        
    FOR rec_concur_accr_data IN cur_concur_accr_data(v_conc_request,rec_file_seq.file_seq)
    LOOP
        BEGIN   /*LOOP BEGIN*/        
            v_last_name              :=  rec_concur_accr_data.last_name;
            v_first_name             :=  rec_concur_accr_data.first_name;
            v_glid                   :=  LTRIM(RTRIM(rec_concur_accr_data.glid));
            v_department             :=  rec_concur_accr_data.department;
            v_submission_name        :=  rec_concur_accr_data.submission_name;
            v_transaction_date       :=  rec_concur_accr_data.transaction_date;
            v_entity_iso_curr_code   :=  rec_concur_accr_data.entity_iso_curr_code;
            v_home_amount            :=  rec_concur_accr_data.home_amount;
            v_debit_credit_indicator :=  rec_concur_accr_data.debit_credit_indicator;
            v_hh_description         :=  rec_concur_accr_data.hh_description;

    
            /*For Header Section*/
            IF (rec_concur_accr_data.detail_format_ind = 'HH') THEN
                BEGIN
                    v_batch_id := NULL;
                    
                    --howlet
              SELECT substr(v_hh_description,
                            instr(v_hh_description,
                                  'EXPORTID:') + 9),
                     
                     to_date(substr(substr(v_hh_description,
                                           instr(v_hh_description,
                                                 'EXPORTID:') + 9),
                                    -14,
                                    8),
                             'RRRRMMDD')
                INTO v_batch_id,
                     v_export_date
                FROM dual;
            
              debug_message('Batch Number :' || v_batch_id);
              debug_message('Concur Export Date :' || v_export_date);
              

                   /* SELECT SUBSTR(v_hh_description,62,23),
                    TO_DATE(TO_CHAR(TO_DATE(SUBSTR(v_hh_description,71,8),'RRRRMMDD'),'DD-MON-RRRR'))
                    INTO v_batch_id,
                    v_export_date
                    FROM dual;
                    
                    debug_message('Batch Number :'||v_batch_id);
                    debug_message('Concur ACCR Export Date :'||v_export_date);*/
                
                EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    v_err_msg := v_err_msg||' /'||'No Export ID Data Exist for Header in the Flat File';
                    RAISE e_skip_to_next_rec;
                END;
    
                debug_message('Updating the Batch Number in the Staging table for Lines ');
              
                BEGIN
                
                    UPDATE gerfp_congl_accr_stg
                    SET concur_batch_id = v_batch_id,
                    concur_export_date = v_export_date
                    WHERE rowid=rec_concur_accr_data.rowid;
                    
                    COMMIT;
                
                EXCEPTION
                WHEN OTHERS THEN
                    v_err_msg := v_err_msg||' /'||'Exception in Updating the Batch Id in Staging Table : '||SQLERRM;
                    RAISE e_skip_to_next_rec;
                END;
    
            /*For Detail Section*/
            ELSE
                /*Deriving ME+LE+BT+SOB from Mapping form */
                BEGIN
                    v_me_code                := NULL;
                    v_le_code                := NULL;
                    v_book_type              := NULL;
                    v_sob_id                 := NULL;
                    v_sae_offset_account     := NULL;
                    v_tax_account            := NULL;
                    v_accr_offset_account    := NULL;
                    v_conc_suspense_account  := NULL;
    
                    SELECT DISTINCT
                    xbus.me_code,
                    xbus.le_code,
                    xbus.book_type,
                    xbus.sae_offset_account,
                    xbus.tax_account,
                    xbus.accrual_offset_account,
                    xbus.concur_suspense_account,
                    gsob.set_of_books_id,
                    xbus.CC_SAE_OFFSET_ACCOUNT,
                    xbus.CASH_ADV_ACCOUNT,
                    xbus.WHT_ACCOUNT,
                    xbus.ALLOC_CEARING_ACCOUNT
                    INTO v_me_code,
                    v_le_code,
                    v_book_type,
                    v_sae_offset_account,
                    v_tax_account,
                    v_accr_offset_account,
                    v_conc_suspense_account,
                    v_sob_id,
                    v_CC_SAE_OFFSET_ACCOUNT,
                    v_CASH_ADV_ACCOUNT,
                    v_WHT_ACCOUNT,
                    v_ALLOC_CEARING_ACCOUNT
                    FROM apps.xxrfp_concur_bus_map xbus,
                    apps.gl_sets_of_books gsob
                    WHERE xbus.sob_name = gsob.name
                    AND xbus.concur_ledger_code = v_glid
                    AND xbus.enabled_flag = 'Y';
                    
                    IF (v_glid LIKE '%TH%') THEN
                        V_SAE_OFFSET_ACCOUNT := NVL(V_CC_SAE_OFFSET_ACCOUNT,V_SAE_OFFSET_ACCOUNT);
                    END IF;

                EXCEPTION
                 WHEN NO_DATA_FOUND THEN
                   debug_message('-> ME+LE+BT+SOB does not exist for given GLID - '||v_glid);
                   v_err_msg := v_err_msg||' /'||'ME+LE+BT+SOB does not exist for given GLID - '||v_glid;
                   RAISE e_skip_to_next_rec;
                 WHEN TOO_MANY_ROWS THEN
                   debug_message('-> More than one ME+LE+BT+SOB exist for given GLID - '||v_glid);
                   v_err_msg := v_err_msg||' /'||'More than one ME+LE+BT+SOB exist for given GLID - '||v_glid;
                   RAISE e_skip_to_next_rec;
                 WHEN OTHERS THEN
                   debug_message('-> Exception in deriving ME+LE+BT+SOB for given GLID - '||v_glid||' ->'||SQLERRM);
                   v_err_msg := v_err_msg||' /'||'Exception in deriving ME+LE+BT+SOB for given GLID - '||v_glid||' ->'||SQLERRM;
                   RAISE e_skip_to_next_rec;
                END;
    
                /* START : Added by Soori on 11-MAY-2009*/
                -- To Update SOB Id In Staging Table, in order to show in specific error in respective SOB
                BEGIN
    
                    UPDATE gerfp_congl_accr_stg
                    SET sob_id = v_sob_id
                    WHERE rowid=rec_concur_accr_data.rowid;
                    
                    COMMIT;
    
                EXCEPTION
                WHEN OTHERS THEN
                    NULL;
                END;
                /* END : Added by Soori on 11-MAY-2009*/
                
                /* Validation on accrual offset account setup*/
                BEGIN
                    --Ignore the cc while the account is BS account
                    SELECT SUBSTR(COMPILED_VALUE_ATTRIBUTES,5,1) into v_AccType
                    FROM
                    FND_FLEX_VALUE_SETS FFVS, FND_FLEX_VALUES FFV
                    WHERE 
                    FFVS.FLEX_VALUE_SET_ID=FFV.FLEX_VALUE_SET_ID
                    AND FFVS.FLEX_VALUE_SET_NAME='RFP_KEYACCOUNT'
                    AND FFV.FLEX_VALUE=v_accr_offset_account AND FFV.ENABLED_FLAG='Y' AND FFV.SUMMARY_FLAG='N';
                
                    SELECT GERFP_CC_PROJ_EXTEND.CHK_KEY_PROJ_FLAG(v_accr_offset_account) INTO v_key_flag FROM DUAL;
                    
                    IF V_ACCTYPE NOT IN ('A','E') THEN
                        RAISE E_ACC_TYPE;
                    END IF;
                    
                    IF V_KEY_FLAG=-1 THEN
                        RAISE e_flag_proj_nd;    
                    END IF;
                
                EXCEPTION
                WHEN E_ACC_TYPE THEN    
                    debug_message('-> The accrual offset account:'||v_accr_offset_account ||'must be PL account.');
                    v_err_msg := v_err_msg||' /'||'The accrual offset account:'||v_accr_offset_account ||'must be PL account.';
                    RAISE e_skip_to_next_rec;
                
                WHEN e_flag_proj_nd THEN    
                    debug_message('-> The accrual offset account:'||v_accr_offset_account ||'can not require project.');
                    v_err_msg := v_err_msg||' /'||'The accrual offset account:'||v_accr_offset_account ||'can not require project.';
                    RAISE e_skip_to_next_rec;
                
                WHEN OTHERS THEN    
                    debug_message('-> Exception in deriving accout type of accrual offset account : '||v_na ||' ->'||SQLERRM);
                    v_err_msg := v_err_msg||' /'||'Exception in deriving accout type of accrual offset account : '||v_na ||' ->'||SQLERRM;
                    RAISE e_skip_to_next_rec;
                END;
                    
                IF INSTR(V_DEPARTMENT,'/')<>0 or length(V_DEPARTMENT)=12THEN
                /* CCL value system, no shelton dependence */
                    BEGIN
                        
                        IF INSTR(V_DEPARTMENT,'/')<>0 then
                        
                            v_oracle_cc :=substr(V_DEPARTMENT,1, instr(V_DEPARTMENT,'/')-1);
                            v_reference :=substr(V_DEPARTMENT,instr(V_DEPARTMENT,'/')+1);
                        
                            IF INSTR(V_REFERENCE,'/')<>0 THEN
                                v_project :=substr(V_REFERENCE,instr(V_REFERENCE,'/')+1);
                                V_REFERENCE :=substr(V_REFERENCE,1,instr(V_REFERENCE,'/')-1);    
                            END IF;
                        END IF;
                        
                        IF (length(V_DEPARTMENT)=12) then
                            v_oracle_cc := substr(V_DEPARTMENT,1,6);
                            v_reference := substr(V_DEPARTMENT,7,6);
                        end if;
                        
                        v_oracle_cc :=  nvl(v_oracle_cc,'0000000000');
                        v_reference :=  nvl(v_reference,'0000000000');
                        v_project :=  nvl(v_project,'0000000000');
                        
                    EXCEPTION
                    WHEN OTHERS THEN
                        debug_message('-> Exception on extracting cost center information from ' || V_DEPARTMENT);
                        v_err_msg := v_err_msg||' /'||'Exception on extracting cost center information from ' || V_DEPARTMENT;
                        RAISE e_skip_to_next_rec;
                    END;
                            
                    BEGIN    
                        SELECT FLEX_VALUE into v_oracle_cc
                        FROM
                        FND_FLEX_VALUE_SETS FFVS, FND_FLEX_VALUES FFV
                        WHERE 
                        FFVS.FLEX_VALUE_SET_ID=FFV.FLEX_VALUE_SET_ID
                        AND FFVS.FLEX_VALUE_SET_NAME='RFP_COSTCENTER'
                        AND FFV.FLEX_VALUE = v_oracle_cc
                        AND FFV.ENABLED_FLAG='Y' AND FFV.SUMMARY_FLAG='N';
                    
                    EXCEPTION
                    WHEN NO_DATA_FOUND THEN
                        /*
                        debug_message('-> The CC value:' || v_oracle_cc || ' of department:'|| v_department ||' does not exist in Cost center valueset.');
                        v_err_msg := v_err_msg||' /'||'The CC value:' || v_oracle_cc || ' from '|| v_department ||' does not exist in Cost center valueset.';
                        RAISE e_skip_to_next_rec;
                        */

                        debug_message('-> The CC value:' || v_oracle_cc || ' of department:'|| v_department ||' does not exist in Cost center valueset.');                        /*Assigning it to Suspense Account*/
                        debug_message('-> Hence JE is Accounted to Suspense Account : '||v_conc_suspense_account);
                        
                        v_accr_offset_account :=  v_conc_suspense_account;
                        v_ime_code   :=  '000000';
                        v_ile_code   :=  '000000';
                        v_oracle_cc  :=  '000000';
                        v_project    :=  '0000000000';
                        v_reference  :=  '000000';
                        
                        v_cc_err_msg := 'The CC value:' || v_oracle_cc || ' of department:'|| v_department ||' does not exist in Cost center valueset; Hence JE is Accounted to Suspense Account : '||v_conc_suspense_account;
                        v_no_cc_flag := 'Y';                    
                    
                    WHEN OTHERS THEN
                        debug_message('-> Exception in validating CC value:' || v_oracle_cc || ' for '|| v_department ||' ->'||SQLERRM);
                        v_err_msg := v_err_msg||' /'||'Exception in validating CC value:' || v_oracle_cc || ' for '|| v_department ||' ->'||SQLERRM;
                        RAISE e_skip_to_next_rec;          
                    END;        
                        
                    BEGIN    
                        SELECT FLEX_VALUE into v_project
                        FROM
                        FND_FLEX_VALUE_SETS FFVS, FND_FLEX_VALUES FFV
                        WHERE 
                        FFVS.FLEX_VALUE_SET_ID=FFV.FLEX_VALUE_SET_ID
                        AND FFVS.FLEX_VALUE_SET_NAME='RFP_PROJECT'
                        AND FFV.FLEX_VALUE = v_project
                        AND FFV.ENABLED_FLAG='Y' AND FFV.SUMMARY_FLAG='N';
                        
                    EXCEPTION
                    WHEN NO_DATA_FOUND THEN
                        /*
                        debug_message('-> The project value:' || v_project || ' of department:'|| v_department ||' does not exist in project valueset.');
                        v_err_msg := v_err_msg||' /'||'The project value:' || v_project || ' from '|| v_department ||' does not exist in project valueset.';
                        RAISE e_skip_to_next_rec;
                        */
                        
                        debug_message('-> The project value:' || v_project || ' of department:'|| v_department ||' does not exist in project valueset.');
                        /*Assigning it to Suspense Account*/
                        debug_message('-> Hence JE is Accounted to Suspense Account : '||v_conc_suspense_account);
                        
                        v_accr_offset_account :=  v_conc_suspense_account;
                        v_ime_code   :=  '000000';
                        v_ile_code   :=  '000000';
                        v_oracle_cc  :=  '000000';
                        v_project    :=  '0000000000';
                        v_reference  :=  '000000';
                        
                        v_cc_err_msg := 'The project value:' || v_project || ' from '|| v_department ||' does not exist in project valueset; Hence JE is Accounted to Suspense Account : '||v_conc_suspense_account;
                        v_no_cc_flag := 'Y';
                    WHEN OTHERS THEN
                        debug_message('-> Exception in validating project value:' || v_project || ' for '|| v_department ||' ->'||SQLERRM);
                        v_err_msg := v_err_msg||' /'||'Exception in validating project value:' || v_project || ' for '|| v_department ||' ->'||SQLERRM;
                        RAISE e_skip_to_next_rec;          
                    END;        
                        
                    BEGIN    
                        SELECT FLEX_VALUE into v_reference
                        FROM
                        FND_FLEX_VALUE_SETS FFVS, FND_FLEX_VALUES FFV
                        WHERE 
                        FFVS.FLEX_VALUE_SET_ID=FFV.FLEX_VALUE_SET_ID
                        AND FFVS.FLEX_VALUE_SET_NAME='RFP_REF'
                        AND FFV.FLEX_VALUE = v_reference
                        AND FFV.ENABLED_FLAG='Y' AND FFV.SUMMARY_FLAG='N';
                        
                    EXCEPTION
                    WHEN NO_DATA_FOUND THEN
                        /*
                        debug_message('-> The reference value:' || v_reference || ' of department:'|| v_department ||' does not exist in reference valueset.');
                        v_err_msg := v_err_msg||' /'||'The reference value:' || v_reference || ' of department: '|| v_department ||' does not exist in reference valueset.';
                        RAISE e_skip_to_next_rec;
                        */
                        
                        debug_message('-> The reference value:' || v_reference || ' of department:'|| v_department ||' does not exist in reference valueset.');                        /*Assigning it to Suspense Account*/
                        debug_message('-> Hence JE is Accounted to Suspense Account : '||v_conc_suspense_account);
                        
                        v_accr_offset_account :=  v_conc_suspense_account;
                        v_ime_code   :=  '000000';
                        v_ile_code   :=  '000000';
                        v_oracle_cc  :=  '000000';
                        v_project    :=  '0000000000';
                        v_reference  :=  '000000';
                        
                        v_cc_err_msg := 'The reference value:' || v_reference || ' of department:'|| v_department ||' does not exist in reference valueset; Hence JE is Accounted to Suspense Account : '||v_conc_suspense_account;
                        v_no_cc_flag := 'Y';
                    WHEN OTHERS THEN
                        debug_message('-> Exception in validating reference value:' || v_reference || ' of department:'|| v_department ||' ->'||SQLERRM);
                        v_err_msg := v_err_msg||' /'||'Exception in validating reference value:' || v_reference || ' of department:'|| v_department ||' ->'||SQLERRM;
                        RAISE e_skip_to_next_rec;          
                    END; 
                ELSE
                /* CCL value system converted from shelton map */                    
                    BEGIN
                    /*Derive Shelton Ledger fron Shelton BUS Mapping Form*/
                        SELECT shelton_company_code
                        INTO v_shltn_code
                        FROM xxrfp_shelton_bus_map
                        WHERE me_code = v_me_code
                        AND le_code = v_le_code
                        AND book_type = v_book_type;
                        
                        --debug_message('Shelton Ledger Code Derived : '||v_shltn_code);
                        
                        IF V_SHLTN_CODE IS NULL THEN 
                            RAISE E_SHELTON_BUS;
                        END IF;
        
                    EXCEPTION
                    WHEN E_SHELTON_BUS THEN
                        debug_message('-> Shelton Ledger Code is blank for given ME+LE+BT Combination, ME : '||v_me_code||' LE : '||v_le_code||'and Book Type : '||v_book_type);
                        v_err_msg := v_err_msg||' /'||'Shelton Ledger Code is blank for given ME+LE+BT Combination, ME : '||v_me_code||' LE : '||v_le_code||'and Book Type : '||v_book_type;
                        RAISE e_skip_to_next_rec;
                     WHEN NO_DATA_FOUND THEN
                       debug_message('-> Shelton Ledger Code does not exists for given ME+LE+BT Combination, ME : '||v_me_code||' LE : '||v_le_code||'and Book Type : '||v_book_type);
                       v_err_msg := v_err_msg||' /'||'Shelton Ledger Code does not exists for given ME+LE+BT Combination, ME : '||v_me_code||' LE : '||v_le_code||'and Book Type : '||v_book_type;
                       RAISE e_skip_to_next_rec;
                     WHEN TOO_MANY_ROWS THEN
                       debug_message('-> More than one Shelton Ledger Code exist for given ME+LE+BT Combination, ME : '||v_me_code||' LE : '||v_le_code||'and Book Type : '||v_book_type);
                       v_err_msg := v_err_msg||' /'||'More than one Shelton Ledger Code exist for given ME+LE+BT Combination, ME : '||v_me_code||' LE : '||v_le_code||'and Book Type : '||v_book_type;
                       RAISE e_skip_to_next_rec;
                     WHEN OTHERS THEN
                       debug_message('-> Exception in deriving Shelton Ledger Code for given ME+LE+BT Combination, ME : '||v_me_code||' LE : '||v_le_code||'and Book Type : '||v_book_type||' ->'||SQLERRM);
                       v_err_msg := v_err_msg||' /'||'Exception in deriving Shelton Ledger Code for given ME+LE+BT Combination, ME : '||v_me_code||' LE : '||v_le_code||'and Book Type : '||v_book_type||' ->'||SQLERRM;
                       RAISE e_skip_to_next_rec;
                    END;

                    /*Deriving CC+PROJ+REF from Shelton CC Mapping form */
                    BEGIN
                        v_no_cc_flag := 'N';
    
                        v_oracle_cc   := NULL;
                        v_project     := NULL;
                        v_reference   := NULL;
                        
                        --added by Satya Chittella for project code extn on 11-may-10
                        gerfp_cc_proj_extend.shlt_cc_proj_inbound(v_shltn_code,
                            --trim(nvl(v_department,'00000000')),
                            trim(v_department),
                            v_oracle_cc,
                            v_reference,
                            v_project,
                            p_flag
                           );
                         
                    EXCEPTION
                    WHEN NO_DATA_FOUND THEN
                        debug_message('-> CC+PROJ+REF does not exists for given Shelton Code : '||v_shltn_code||' and Shelton CC : '||v_department);
                        
                        /*Assigning it to Suspense Account*/
                        debug_message('-> Hence JE is Accounted to Suspense Account : '||v_conc_suspense_account);
                        
                        v_accr_offset_account :=  v_conc_suspense_account;
                        v_ime_code   :=  '000000';
                        v_ile_code   :=  '000000';
                        v_oracle_cc  :=  '000000';
                        v_project    :=  '0000000000';
                        v_reference  :=  '000000';
                        
                        v_cc_err_msg := 'CC+PROJ+REF does not exists for given Shelton Code : '||v_shltn_code||' and Shelton CC : '||v_department||' ; Hence JE is Accounted to Suspense Account : '||v_conc_suspense_account;
                        v_no_cc_flag := 'Y';
                    
                    WHEN TOO_MANY_ROWS THEN
                        debug_message('-> More than one CC+PROJ+REF exist for given Shelton Code : '||v_shltn_code||' and Shelton CC : '||v_department);
                        v_err_msg := v_err_msg||' /'||'More than one CC+PROJ+REF exist for given Shelton Code : '||v_shltn_code||' and Shelton CC : '||v_department;
                        RAISE e_skip_to_next_rec;
                    
                    WHEN OTHERS THEN
                        debug_message('-> Exception in deriving CC+PROJ+REF for given Shelton Code : '||v_shltn_code||' and Shelton CC : '||v_department||' ->'||SQLERRM);
                        v_err_msg := v_err_msg||' /'||'Exception in deriving CC+PROJ+REF for given Shelton Code : '||v_shltn_code||' and Shelton CC : '||v_department||' ->'||SQLERRM;
                        RAISE e_skip_to_next_rec;
                    END;
                END IF;
                
                BEGIN
                    /*
                    P_flag
                    */
                    SELECT GERFP_CC_PROJ_EXTEND.CHK_CC_PROJ_FLAG (v_oracle_cc) INTO P_FLAG FROM DUAL;
                    
                    IF P_flag='-1' and v_project<>'0000000000' THEN
                        IF v_key_flag=-1 THEN
                            RAISE e_flag;
                        End if;
                    ELSif(P_flag='-1' and v_project='0000000000') then
                        RAISE e_flag_proj_nd_c;
                    END IF; 
                    
                EXCEPTION
                WHEN e_flag THEN
                    debug_message('-> Invalid entry as Proj Req flag is Yes at Cost Center and Account Level');
                    v_err_msg := v_err_msg||' /'||'Invalid entry as Proj Req flag is Yes at Cost Center and Account Level';
                    RAISE e_skip_to_next_rec;                    
                WHEN e_flag_proj_nd_c THEN
                    debug_message('-> The non-default project is required on cost center:' || v_oracle_cc);
                    v_err_msg := v_err_msg||' /'||'The non-default project is required on cost center:' || v_oracle_cc;
                    RAISE e_skip_to_next_rec;
                WHEN OTHERS THEN
                    debug_message('-> Exception in validating project for ' || v_department ||' ->'||SQLERRM);
                    v_err_msg := v_err_msg||' /'||'Exception in validating project for ' || v_department ||' ->'||SQLERRM;
                    RAISE e_skip_to_next_rec; 
                END;
                    
                /*Details for Reversal for Next Non-Adjustment Period*/
                BEGIN
                    v_start_date :=  NULL;
                    v_period_name := NULL;
                    
                    v_concur_export_date  := v_export_date;
                    --debug_message('v_concur_export_date :'||v_concur_export_date);
    
                    SELECT start_date,period_name
                    INTO v_start_date,v_period_name
                    FROM GL_PERIODS
                    WHERE start_date = ( SELECT end_date + 1
                    FROM gl_periods
                    WHERE period_set_name = 'RFP_CALENDAR'
                    --                                             AND to_date(v_concur_export_date,'DD-MON-RRRR') BETWEEN TO_CHAR(start_date,'DD-MON-RRRR') AND TO_CHAR(end_date,'DD-MON-RRRR')
                    AND v_concur_export_date BETWEEN start_date AND end_date
                    )
                    AND period_set_name = 'RFP_CALENDAR'
                    AND adjustment_period_flag = 'N';
    
                EXCEPTION
                    WHEN NO_DATA_FOUND THEN
                    debug_message('-> Next Period is NOT Found for Reversal');
                    v_err_msg := v_err_msg||' /'||'Next Period is NOT Found for Reversal';
                    RAISE e_skip_to_next_rec;
                    WHEN TOO_MANY_ROWS THEN
                    debug_message('-> More than one Period is Found for Reversal');
                    v_err_msg := v_err_msg||' /'||'More than one Period is Found for Reversal';
                    RAISE e_skip_to_next_rec;
                    WHEN OTHERS THEN
                    debug_message('-> Exception in deriving Next Period : ->'||SQLERRM);
                    v_err_msg := v_err_msg||' /'||'Exception in deriving Next Period : ->'||SQLERRM;
                    RAISE e_skip_to_next_rec;
                END;
    
                v_reference10 := NULL;
                v_attribute10 := NULL;
                
                v_reference10         := v_first_name||'#'||v_last_name||'#'||v_glid||'#'||v_transaction_date ||'#'||rec_concur_accr_data.Ohr_Emp_Id;
                v_attribute10         := v_submission_name;
    
              --HOWLET 2-JUN-2012
          IF v_accr_offset_account = v_conc_suspense_account
             AND v_GLID = 'PHCF01' THEN
            v_oracle_cc := 'NCDZM2';
          END IF;
        
          IF (v_GLID = 'PHCF01') THEN
            v_default_cc := 'NCDZM2';
          ELSE
            v_default_cc := '000000';
          END IF;
          
                /*Check the Data and populate interface for Credit or Debit amount*/
                BEGIN
                    IF (v_debit_credit_indicator = 'DR') then
    
                        /* CREATING FOR ORIGINAL JOURNAL IN CURRRENT PERIOD*/
                        /*DR : If Net Amt Exists*/
                        FOR j IN 1..2
                        LOOP
        
                            INSERT INTO GL_INTERFACE (status,
                                accounting_date,
                                currency_code,
                                actual_flag,
                                user_je_category_name,
                                user_je_source_name,
                                segment1,
                                segment2,
                                segment3,
                                segment4,
                                segment5,
                                segment6,
                                segment7,
                                segment8,
                                segment9,
                                segment10,
                                segment11,
                                entered_dr,
                                entered_cr,
                                accounted_dr,
                                accounted_cr,
                                reference6,
                                reference10,
                                attribute10,
                                currency_conversion_date ,
                                user_currency_conversion_type,
                                currency_conversion_rate,
                                created_by,
                                date_created,
                                group_id,
                                set_of_books_id
                                )
                            VALUES('NEW',
                                   v_concur_export_date,
                                   v_entity_iso_curr_code,
                                   'A',
                                   'Concur Accrual',
                                   'Concur',
                                   v_me_code,
                                   v_le_code,
                                   v_book_type,
                                   DECODE(j,1,v_accr_offset_account,v_sae_offset_account),
                                   DECODE(j,1,v_oracle_cc,v_default_cc),
                                   DECODE(j,1,decode(p_flag, -1,v_project,0,v_project_1),'0000000000'),
                                   '000000',
                                   '000000',
                                   DECODE(j,1,v_reference,'000000'),
                                   '0',
                                   '0',
                                   DECODE(j,1,v_home_amount,NULL), /*entered dr */
                                   DECODE(j,1,NULL,v_home_amount),  /*entered cr */
                                   NULL, /*accounted dr */
                                   NULL, /*accounted_cr*/
        --                         'CONC2GL ACCR Batch Number '||'"'||v_batch_id||'"',
                                   '"'||v_batch_id||'"',
                                   v_reference10,
                                   v_attribute10,
                                   v_concur_export_date,
                                   'MOR',
                                   NULL,
                                   fnd_global.user_id,
                                   SYSDATE,
                                   g_group_id,
                                   v_sob_id
                                  );
                        END LOOP;
    
                          /* CREATING FOR REVERSAL JOURNAL IN NEXT PERIOD*/
                        /*DR : If Net Amt Exists*/
    
                        FOR k IN 1..2
                        LOOP
                        INSERT INTO GL_INTERFACE (status,
                                accounting_date,
                                currency_code,
                                actual_flag,
                                user_je_category_name,
                                user_je_source_name,
                                segment1,
                                segment2,
                                segment3,
                                segment4,
                                segment5,
                                segment6,
                                segment7,
                                segment8,
                                segment9,
                                segment10,
                                segment11,
                                entered_dr,
                                entered_cr,
                                accounted_dr,
                                accounted_cr,
                                reference4,
                                reference6,
                                reference10,
                                attribute10,
                                currency_conversion_date ,
                                user_currency_conversion_type,
                                currency_conversion_rate,
                                created_by,
                                date_created,
                                group_id,
                                set_of_books_id
                                )
                            VALUES('NEW',
                                   v_start_date,
                                   v_entity_iso_curr_code,
                                   'A',
                                   'Concur Accrual Reversal',
                                   'Concur',
                                   v_me_code,
                                   v_le_code,
                                   v_book_type,
                                   DECODE(k,1,v_sae_offset_account,v_accr_offset_account),
                                   DECODE(k,1,v_default_cc,v_oracle_cc),
                                   DECODE(k,1,'0000000000',decode(p_flag, -1,v_project,0,v_project_1)),
                                   '000000',
                                   '000000',
                                   DECODE(k,1,'000000',v_reference),
                                   '0',
                                   '0',
                                   DECODE(k,1,v_home_amount,NULL), /*entered dr */
                                   DECODE(k,1,NULL,v_home_amount),  /*entered cr */
                                   NULL, /*accounted dr */
                                   NULL,  /*accounted_cr*/
                                   'Reversal',
                        --                         'CONC2GL ACCR Batch Number '||'"'||v_batch_id||'_REVERSAL"',
                                   '"'||v_batch_id||'_REVERSAL"',
                                   v_reference10,
                                   v_attribute10,
                                   v_start_date,
                                   'MOR',
                                   NULL,
                                   fnd_global.user_id,
                                   SYSDATE,
                                   --test by george
                                   g_group_id,
                                   --g_group_id||'9',
                                   v_sob_id
                                  );
                        END loop;
    
                    ELSIF (v_debit_credit_indicator = 'CR') then
                        /* CREATING FOR ORIGINAL JOURNAL IN CURRRENT PERIOD*/
                        /*CR : If Net Amt Exists*/
    
                        FOR j IN 1..2
                        LOOP
                            INSERT INTO GL_INTERFACE (status,
                                accounting_date,
                                currency_code,
                                actual_flag,
                                user_je_category_name,
                                user_je_source_name,
                                segment1,
                                segment2,
                                segment3,
                                segment4,
                                segment5,
                                segment6,
                                segment7,
                                segment8,
                                segment9,
                                segment10,
                                segment11,
                                entered_dr,
                                entered_cr,
                                accounted_dr,
                                accounted_cr,
                                reference6,
                                reference10,
                                attribute10,
                                currency_conversion_date ,
                                user_currency_conversion_type,
                                currency_conversion_rate,
                                created_by,
                                date_created,
                                group_id,
                                set_of_books_id
                                )
                            VALUES('NEW',
                                   v_concur_export_date,
                                   v_entity_iso_curr_code,
                                   'A',
                                   'Concur Accrual',
                                   'Concur',
                                   v_me_code,
                                   v_le_code,
                                   v_book_type,
                                   DECODE(j,1,v_accr_offset_account,v_sae_offset_account),
                                   DECODE(j,1,v_oracle_cc,v_default_cc),
                                   DECODE(j,1,decode(p_flag, -1,v_project,0,v_project_1),'0000000000'),
                                   '000000',
                                   '000000',
                                   DECODE(j,1,v_reference,'000000'),
                                   '0',
                                   '0',
                                   DECODE(j,1,NULL,v_home_amount),/*entered dr */
                                   DECODE(j,1,v_home_amount,NULL),  /*entered cr */
                                   NULL, /*accounted dr */
                                   NULL, /*accounted_cr*/
                        --                         'CONC2GL ACCR Batch Number '||'"'||v_batch_id||'"',
                                   '"'||v_batch_id||'"',
                                   v_reference10,
                                   v_attribute10,
                                   v_concur_export_date,
                                   'MOR',
                                   NULL,
                                   fnd_global.user_id,
                                   SYSDATE,
                                   g_group_id,
                                   v_sob_id
                                  );
                        
                        END LOOP;
                        
                        
                              /* CREATING FOR REVERSAL JOURNAL IN NEXT PERIOD*/
                        /*CR : If Net Amt Exists*/
                        
                        FOR k IN 1..2
                        LOOP
                            INSERT INTO GL_INTERFACE (status,
                                accounting_date,
                                currency_code,
                                actual_flag,
                                user_je_category_name,
                                user_je_source_name,
                                segment1,
                                segment2,
                                segment3,
                                segment4,
                                segment5,
                                segment6,
                                segment7,
                                segment8,
                                segment9,
                                segment10,
                                segment11,
                                entered_dr,
                                entered_cr,
                                accounted_dr,
                                accounted_cr,
                                reference4,
                                reference6,
                                reference10,
                                attribute10,
                                currency_conversion_date ,
                                user_currency_conversion_type,
                                currency_conversion_rate,
                                created_by,
                                date_created,
                                group_id,
                                set_of_books_id
                                )
                            VALUES('NEW',
                                   v_start_date,
                                   v_entity_iso_curr_code,
                                   'A',
                                   'Concur Accrual Reversal',
                                   'Concur',
                                   v_me_code,
                                   v_le_code,
                                   v_book_type,
                                   DECODE(k,1,v_sae_offset_account,v_accr_offset_account),
                                   DECODE(k,1,v_default_cc,v_oracle_cc),
                                   DECODE(k,1,'0000000000',decode(p_flag, -1,v_project,0,v_project_1)),
                                   '000000',
                                   '000000',
                                   DECODE(k,1,'000000',v_reference),
                                   '0',
                                   '0',
                                   DECODE(k,1,NULL,v_home_amount), /*entered dr */
                                   DECODE(k,1,v_home_amount,NULL),  /*entered cr */
                                   NULL, /*accounted dr */
                                   NULL,  /*accounted_cr*/
                                   'Reversal',
                        --                         'CONC2GL ACCR Batch Number '||'"'||v_batch_id||'_REVERSAL"',
                                   '"'||v_batch_id||'_REVERSAL"',
                                   v_reference10,
                                   v_attribute10,
                                   v_start_date,
                                   'MOR',
                                   NULL,
                                   fnd_global.user_id,
                                   SYSDATE,
                                   --test by george
                                   g_group_id,
                                   --g_group_id||'9',
                                   v_sob_id
                                  );
                        END loop;
    
                    END IF;
                    /*End if for CR-DR Indicator*/
                EXCEPTION
                    WHEN OTHERS THEN
                    debug_message('-> Exception in Inserting data in GL Interface : -> '||SQLERRM);
                    v_err_msg := v_err_msg||' /'||'Exception in Inserting data in GL Interface : -> '||SQLERRM;
                    RAISE e_skip_to_next_rec;
                END;

            END IF; --HH/AD control


            UPDATE gerfp_congl_accr_stg
            SET process_flag = DECODE(v_no_cc_flag,'Y','CR','P')
            , err_msg = DECODE(v_no_cc_flag,'Y',v_cc_err_msg,NULL)
            WHERE rowid=rec_concur_accr_data.rowid;

        EXCEPTION
            /*LOOP EXCEPTION*/
            WHEN e_skip_to_next_rec THEN
                debug_message('--> Updating staging table with error message..');
                
                UPDATE gerfp_congl_accr_stg
                SET process_flag = 'R'
                , err_msg = v_err_msg
                WHERE rowid=rec_concur_accr_data.rowid;
                
                retcode := '1';
                
                COMMIT;

           WHEN OTHERS THEN
                debug_message('--> Updating staging table with OTHER exception message..');
                
                v_err_msg := v_err_msg||'Exception in Processing Information - '||SQLERRM;
                
                UPDATE gerfp_congl_accr_stg
                SET process_flag = 'R'
                , err_msg = v_err_msg
                WHERE rowid=rec_concur_accr_data.rowid;
                
                retcode := '2';
            
                COMMIT;

        END;
            
            /*INSIDE FOR-LOOP BEGIN..END*/
            v_err_msg                :=  NULL;
            v_no_cc_flag             :=  NULL;
            v_cc_err_msg             :=  NULL;
            
            v_last_name              :=  NULL;
            v_first_name             :=  NULL;
            v_glid           :=  NULL;
            v_department             :=  NULL;
            v_submission_name        :=  NULL;
            v_transaction_date       :=  NULL;
            v_entity_iso_curr_code   :=  NULL;
            v_home_amount        :=  NULL;
            v_debit_credit_indicator :=  NULL;
            v_hh_description         :=  NULL;
            v_concur_export_date     :=  NULL;

        END LOOP;
        /*Main Loop End*/
        
        --check stage table
        --EXIT;
/*Loop for file added by george on 15-JUL-2010 for comment  */
    END LOOP; -- For Each File
    debug_message('Processed staging table.');

/*
1, Get the notifier list
2, Check file list of the notifier
    2.1, Process gl_interface
    2.2, Process stage error
*/  

--1, Get the notifier list
    FOR NOTIFIER in NOTIFIER_LIST
    LOOP
        g_recipients := NOTIFIER.future2 || g_Mail_Domain; 
        debug_message('Send mail to:' || g_recipients);
        
        V_HTML :='Concur Accrual inbound notification';
        SEND_Mail('O',V_HTML);        
        
        V_HTML :='<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">' 
                    || '<html xmlns="http://www.w3.org/1999/xhtml" lang="en" xml:lang="en">' 
                    || '<head>'
                    || '<meta http-equiv="Content-Type" content="text/html; charset=utf-8"></meta>' 
                    || '<title>Concur Accrual inbound notification</title>'
                    || '<style type="text/css"> '
                    || '  table {border:1; cellspacing:0;bordercolor:black;frame:box;}'
                    || '  td {white-space: nowrap;}'
                    || '</style>'
                    || '</head>'
                    || '<body>'
                    || '<h1 align="left">Concur inbound notification</h1>';
        SEND_Mail('S',V_HTML); 
        
        BEGIN 
            select count(1) into v_file_count
            FROM 
            gerfp_congl_accr_stg stg,apps.xxrfp_concur_bus_map glid
            where glid.CONCUR_LEDGER_CODE = stg.GLID
            and CONCUR_REQ_ID=V_CONC_REQUEST
            and glid.future2=NOTIFIER.future2;

            IF V_FILE_COUNT>0 THEN 
                V_HTML :=  '<table border="1" cellspacing="0" frame="box">'
                        || '<tr><td>File name</td>'
                        || '<td colspan="4">Batch id</td>'
                        || '<td colspan="2">Request id</td>'
                        || '<td colspan="7">Result</td></TR>';    
            ELSE
                V_HTML :='No data for your GLID.';
            END IF; 
            SEND_Mail('S',V_HTML);
        END;   

--2, Check file list of the notifier                    
        FOR file_status in CUR_FILE_STATUS(V_CONC_REQUEST,NOTIFIER.future2)
        LOOP      
-- DISTINCT FILE_SEQ,FILE_NAME,CONCUR_BATCH_ID,CONCUR_REQ_ID,SOB_ID,GLID,FUTURE2      
--2.1, Process gl_interface      

            FOR rec_iface_data IN cur_iface_data(p_source   => 'Concur'
                                  , p_group_id => file_status.FILE_SEQ
                            )
            LOOP
                --gi.set_of_books_id sob_id, sob.NAME sob_name, gi.reference6 Batch_name,     
                v_chk_status := NULL;
                
                debug_message('Checking Duplicate File Process');
                debug_message(rec_iface_data.batch_name || rec_iface_data.group_id);
                check_dup_file_process( p_sob_id         => rec_iface_data.sob_id
                       ,p_batch_number   => rec_iface_data.batch_name
                       ,p_group_id       => rec_iface_data.group_id
                       ,x_status         => v_chk_status
                       );
    
  
                IF (v_chk_status = 'Y') THEN

                    debug_message(' Already processed and Journal exist for this batch for '||g_entries||': '||rec_iface_data.batch_name||' under SOB Name : '||rec_iface_data.sob_name);
                    debug_message('*** Purging records from Interface table for this batch ..');

                    FND_FILE.PUT_LINE( FND_FILE.OUTPUT, ' Already processed and Journal exist for this batch : '||rec_iface_data.batch_name||' under SOB Name : '||rec_iface_data.sob_name);
                    FND_FILE.PUT_LINE( FND_FILE.OUTPUT, '*** Purging records from Interface table for this batch ..');

                    DELETE
                       FROM gl_interface
                    WHERE group_id=file_status.FILE_SEQ
                        AND set_of_books_id = rec_iface_data.sob_id;
                        --AND reference6 like rec_iface_data.batch_name;
                    
                    DELETE
                    FROM gerfp_congl_accr_stg
                    WHERE CONCUR_BATCH_ID= file_status.CONCUR_BATCH_ID
                    and FILE_SEQ=file_status.FILE_SEQ
                    AND CONCUR_REQ_ID = file_status.CONCUR_REQ_ID;    

                    COMMIT;
                    debug_message('test end: '||rec_iface_data.batch_name||' under SOB Name : '||rec_iface_data.sob_name);
                    COMMIT;
                    
                    V_HTML := '<TR><TD>' || file_status.FILE_NAME || '</TD>'
                        || '<TD colspan="4">' || file_status.CONCUR_BATCH_ID || '</TD>'
                        || '<TD colspan="2">' || V_CONC_REQUEST || '</TD>'                        
                        || '<TD colspan="7">Duplicate file has been cleaned.</TD></TR>';
                    APPS.FND_FILE.PUT_LINE (APPS.FND_FILE.OUTPUT, V_HTML);
            
                    SEND_Mail('S',V_HTML);  
                ELSE
                    debug_message(' Journal Import Program Submission Process');
                    debug_message(' -------------------------------------------------------- ');
                    BEGIN
                        debug_message(' Number of Records for SOB# '||rec_iface_data.sob_name||' , Batch # '||rec_iface_data.batch_name||' is :'||rec_iface_data.rec_cnt);
        
                        submit_journal_import(p_user_id => v_userid
                                         ,p_resp_id => v_resp_id
                                         ,p_sob_id  => rec_iface_data.sob_id
                                         -- ,p_group_id=> g_group_id            /*Commented by Soori on 13-FEB-2010 for Automation*/
                                         ,p_group_id=> rec_iface_data.group_id  /*Added by Soori on 13-FEB-2010 for Automation*/
                                         ,p_source  => 'Concur'
                                         ,x_status  => v_import_status
                                         ,x_req_id => v_req_id);
            
                        debug_message('--> Journal Import Program Submitted ..');
                        debug_message(' JOURNAL IMPORT Program Status for SOB# '||rec_iface_data.sob_name||' is '||v_import_status); 
                        
                        COMMIT; 
                       
                        IF V_REQ_ID=0 THEN
                            V_HTML := '<TR><TD>' || file_status.FILE_NAME || '</TD>'
                                || '<TD colspan="4">' || file_status.CONCUR_BATCH_ID || '</TD>'
                                || '<TD colspan="2">' || V_REQ_ID || '</TD>'
                                || '<TD colspan="7">Import journal error.</TD></TR>';
                            APPS.FND_FILE.PUT_LINE (APPS.FND_FILE.OUTPUT, V_HTML);
                                                
                            SEND_Mail('S',V_HTML);  
                            
                            RAISE_APPLICATION_ERROR(-20160, FND_MESSAGE.GET);
                            X_STATUS := 'FAILED';
                        ELSE
                            X_STATUS := 'DONE';
                            LOOP
                              V_PHASE                   := NULL;
                              V_STATUS                  := NULL;
                              V_DEV_PHASE               := NULL;
                              V_DEV_STATUS              := NULL;
                              V_MESSAGE                 := NULL;
                 
                              
                              V_REQUEST_COMPLETE := APPS.FND_CONCURRENT.WAIT_FOR_REQUEST(V_REQ_ID,
                                                                                    10,
                                                                                    9999,
                                                                                    V_PHASE,
                                                                                    V_STATUS,
                                                                                    V_DEV_PHASE,
                                                                                    V_DEV_STATUS,
                                                                                    V_MESSAGE);
                
                                IF UPPER(V_PHASE) = 'COMPLETED' THEN
                                    FND_FILE.PUT_LINE(FND_FILE.LOG,'Import journal completed.');
                                    EXIT;
                                END IF;
                            END LOOP;
                            
                            BEGIN
                                SELECT COUNT(gjh.je_header_id) into 
                                 v_rc
                                 FROM gl_je_headers gjh
                                     ,gl_je_sources gjs
                                     ,gl_je_categories gjc
                                WHERE gjh.external_reference=rec_iface_data.batch_name
                                  AND gjh.set_of_books_id = rec_iface_data.sob_id
                                  AND gjc.je_category_name = gjh.je_category
                                  AND gjs.je_source_name = gjh.je_source
                                  AND UPPER(gjc.user_je_category_name) = 'CONCUR ACCRUAL'
                                  AND UPPER(gjs.user_je_source_name) = 'CONCUR'; 
                                
                                If nvl(v_rc,0)>0 then
                                    V_HTML := '<TR><TD>' || file_status.FILE_NAME || '</TD>'
                                    || '<TD colspan="4">' || file_status.CONCUR_BATCH_ID || '</TD>'
                                    || '<TD colspan="2">' || V_REQ_ID || '</TD>'
                                    || '<TD colspan="7">Import journal succeeded.</TD></TR>';        
                                else
                                    V_HTML := '<TR><TD>' || file_status.FILE_NAME || '</TD>'
                                    || '<TD colspan="4">' || file_status.CONCUR_BATCH_ID || '</TD>'
                                    || '<TD colspan="2">' || V_REQ_ID || '</TD>'
                                    || '<TD colspan="7">Import journal failed with group_id:' ||  rec_iface_data.group_id || '</TD></TR>';
                                end if;
                            
                                APPS.FND_FILE.PUT_LINE (APPS.FND_FILE.OUTPUT, V_HTML);
                    
                                SEND_Mail('S',V_HTML);                    
                            END;
                        end if;
                    END;
                    
                    /*1, Stage process */   
                    BEGIN
                    SELECT COUNT(1)
                           INTO v_err_cnt
                        FROM gerfp_congl_accr_stg
                         WHERE process_flag IN ('R','CR')                         
                         AND err_msg IS NOT NULL
                         And file_name=file_status.file_name
                         and CONCUR_BATCH_ID=file_status.CONCUR_BATCH_ID
                        AND detail_format_ind = 'AD'  /*Added by Soori on 13-FEB-2010 for Automation*/
                        AND concur_req_id = V_CONC_REQUEST;
        
                    EXCEPTION
                    WHEN NO_DATA_FOUND THEN
                        V_ERR_CNT := 0;
                    END;
                    
                    IF V_ERR_CNT=0 THEN
                         V_HTML := '<TR><TD>' || file_status.FILE_NAME || '</TD>'
                                    || '<TD colspan="4">' || file_status.CONCUR_BATCH_ID || '</TD>'
                                    || '<TD colspan="2">' || V_CONC_REQUEST || '</TD>'
                                    || '<TD colspan="7">Inbound succeeded.</TD></TR>';
                                APPS.FND_FILE.PUT_LINE (APPS.FND_FILE.OUTPUT, V_HTML);
                                SEND_Mail('S',V_HTML);       
                    ELSE
                        V_HTML := '<TR><TD>' || file_status.FILE_NAME || '</TD>'
                        || '<TD colspan="4">' || file_status.CONCUR_BATCH_ID || '</TD>'
                        || '<TD colspan="2">' || V_CONC_REQUEST || '</TD>'
                        || '<TD colspan="7">Inbound failed with exceptions as below.</TD></TR>';
                        APPS.FND_FILE.PUT_LINE (APPS.FND_FILE.OUTPUT, V_HTML);
                        SEND_Mail('S',V_HTML);

                        SELECT 
                            RPAD('Detail Format Ind',20) ||'</TD><TD>' ||
                            RPAD('CC Trans Key',20)||'</TD><TD>' ||
                            RPAD('Last Name',15)||'</TD><TD>'||
                            RPAD('First Name',15)||'</TD><TD>'||
                            RPAD('GLID',10)||'</TD><TD>'||
                            RPAD('Department',15)||'</TD><TD>'||
                            RPAD('Transaction#',20) ||'</TD><TD>'||
                            RPAD('Transaction Date',20)||'</TD><TD>'||
                            RPAD('Entity ISO Currency Code',25)||'</TD><TD>'||
                            RPAD('CR/DR Indicator',18)||'</TD><TD>'||
                            RPAD('Home Amount',15) ||'</TD><TD>'||
                            RPAD('Process Flag',20) ||'</TD><TD>'||
                            RPAD('Error Message',150)
                            into v_err_buffer
                        FROM DUAL;
                        
                        V_HTML := '<TR><TD></TD>'
                                    || '<TD>' || v_err_buffer || '</TD></TR>';
                        SEND_Mail('S',V_HTML); 
                                        
                        For rec_err_cgl in CUR_ERR_CGL(V_CONC_REQUEST,file_status.file_name, file_status.CONCUR_BATCH_ID)
                        loop
               
                        
                            SELECT   RPAD(rec_err_cgl.DETAIL_FORMAT_IND,20)||
                             '</TD><TD>'||
                            RPAD(rec_err_cgl.CC_TRANS_KEY,20)||
                             '</TD><TD>'||
                            RPAD(rec_err_cgl.LAST_NAME,15)||
                             '</TD><TD>'||
                            RPAD(rec_err_cgl.FIRST_NAME,15)||
                             '</TD><TD>'||
                            RPAD(rec_err_cgl.GLID,10)||
                             '</TD><TD>'||
                            RPAD(rec_err_cgl.DEPARTMENT,15)||
                             '</TD><TD>'||
                            RPAD(rec_err_cgl.TRANSACTION_NUMBER,20)||
                             '</TD><TD>'||
                            RPAD(rec_err_cgl.TRANSACTION_DATE,20)||
                             '</TD><TD>'||
                            RPAD(rec_err_cgl.ENTITY_ISO_CURR_CODE,25)||
                             '</TD><TD>'||
                            RPAD(rec_err_cgl.DEBIT_CREDIT_INDICATOR,18)||
                             '</TD><TD>'||
                            RPAD(NVL(rec_err_cgl.HOME_AMOUNT,0),15)||
                             '</TD><TD>'||
                            RPAD(rec_err_cgl.process_flag,15)||
                             '</TD><TD>'||
                            RPAD(rec_err_cgl.err_msg,150)
                            INTO v_err_buffer
                            FROM DUAL;
                            
                            V_HTML := '<TR><TD></TD>'
                                    || '<TD>' || v_err_buffer || '</TD></TR>';
                            APPS.FND_FILE.PUT_LINE (APPS.FND_FILE.OUTPUT, V_HTML);
                            SEND_Mail('S',V_HTML);       
                        END LOOP;
                    End if;                    
                END IF;
            END LOOP;
            --End 2.1, Process gl_interface
        END LOOP;
        --2, Check file list of the notifier
        
        If v_file_count>0 then 
            V_HTML:='</table></html>';
            SEND_Mail('S',V_HTML); 
        End if;
                 
        SEND_Mail('C',V_HTML); 
    END LOOP;

    EXCEPTION
    /*Procedure EXCEPTION*/

      WHEN end_of_program THEN
        debug_message('ERROR in Processing : '||v_err_msg);
    retcode := '1';

      WHEN e_end_program THEN
    debug_message(' No Records to Process ..');
    retcode := '1';

      WHEN OTHERS THEN
        debug_message('Exception in processing the program :'||v_err_msg||' :'||SQLERRM);
    retcode := '2';

    END process_gl_accr_data;

  /***************************************************/
  /*               PROCEDURE FOR ERROR REPORT        */
  /***************************************************/

PROCEDURE display_err_congl( errbuff       OUT  VARCHAR2
                           , retcode       OUT  VARCHAR2
                           )
IS

 CURSOR cur_err_cgl
 IS
 SELECT *
   FROM gerfp_congl_accr_stg
  WHERE process_flag IN ('R','CR')
    AND err_msg IS NOT NULL
    AND concur_req_id = (SELECT MAX(fcq.request_id)
                           FROM fnd_concurrent_requests fcq,
                    fnd_concurrent_programs fcp
                          WHERE fcq.concurrent_program_id = fcp.concurrent_program_id
                AND UPPER(concurrent_program_name) = 'GERFP_CONCUR_GL_ACCR_INBOUND'
             );


v_err_buffer     VARCHAR2(4000);
v_err_cnt        NUMBER;

BEGIN

        FND_FILE.PUT_LINE(FND_FILE.OUTPUT,'************************************  Concur TO GL ACCURAL Error Record Details  *******************************************');
    FND_FILE.PUT_LINE(FND_FILE.OUTPUT,'  ');
    FND_FILE.PUT_LINE(FND_FILE.OUTPUT,'********************************************************************************************************************');

    FND_FILE.PUT_LINE(FND_FILE.OUTPUT,'  ');
    FND_FILE.PUT_LINE(FND_FILE.OUTPUT,RPAD('-',350,'-'));
    FND_FILE.PUT_LINE(FND_FILE.OUTPUT,RPAD('Detail Format Ind',20)||CHR(9)||RPAD('CC Trans Key',20)||CHR(9)||
                      RPAD('Last Name',15)||CHR(9)||RPAD('First Name',15)||CHR(9)||
                          RPAD('GLID',10)||CHR(9)||RPAD('Department',15)||CHR(9)||
                          RPAD('Transaction#',20)||CHR(9)||RPAD('Transaction Date',20)||CHR(9)||
                      RPAD('Entity ISO Currency Code',25)||CHR(9)||RPAD('CR/DR Indicator',18)||CHR(9)||
                      RPAD('Home Amount',15)||CHR(9)||RPAD('Process Flag',20)||CHR(9)||
                      RPAD('Error Message',150)
             );
    FND_FILE.PUT_LINE(FND_FILE.OUTPUT,RPAD('-',350,'-'));

   /*Fetching the count of error records*/
      BEGIN

      SELECT COUNT(1)
        INTO v_err_cnt
            FROM gerfp_congl_accr_stg
           WHERE process_flag IN ('R','CR')
             AND err_msg IS NOT NULL
             AND concur_req_id = (SELECT MAX(fcq.request_id)
                                    FROM fnd_concurrent_requests fcq,
                             fnd_concurrent_programs fcp
                                   WHERE fcq.concurrent_program_id = fcp.concurrent_program_id
                         AND UPPER(concurrent_program_name) = 'GERFP_CONCUR_GL_ACCR_INBOUND'
                      );
      EXCEPTION
         WHEN NO_DATA_FOUND THEN
            v_err_cnt := 0;
         WHEN OTHERS THEN
           FND_FILE.PUT_LINE(FND_FILE.OUTPUT,'EXCEPTION IN FETCHING COUNT  '||SQLERRM);
      END;

  IF (v_err_cnt > 0) THEN
   retcode := '1';

   FOR rec_err_cgl IN cur_err_cgl
   LOOP

   SELECT   RPAD(rec_err_cgl.DETAIL_FORMAT_IND,20)||
            CHR(9)||
        RPAD(rec_err_cgl.CC_TRANS_KEY,20)||
        CHR(9)||
        RPAD(rec_err_cgl.LAST_NAME,15)||
        CHR(9)||
        RPAD(rec_err_cgl.FIRST_NAME,15)||
        CHR(9)||
        RPAD(rec_err_cgl.GLID,10)||
        CHR(9)||
        RPAD(rec_err_cgl.DEPARTMENT,15)||
        CHR(9)||
        RPAD(rec_err_cgl.TRANSACTION_NUMBER,20)||
        CHR(9)||
        RPAD(rec_err_cgl.TRANSACTION_DATE,20)||
        CHR(9)||
        RPAD(rec_err_cgl.ENTITY_ISO_CURR_CODE,25)||
        CHR(9)||
        RPAD(rec_err_cgl.DEBIT_CREDIT_INDICATOR,18)||
        CHR(9)||
        RPAD(NVL(rec_err_cgl.HOME_AMOUNT,0),15)||
        CHR(9)||
        RPAD(rec_err_cgl.process_flag,15)||
        CHR(9)||
        RPAD(rec_err_cgl.err_msg,150)
        INTO v_err_buffer
        FROM DUAL;

       FND_FILE.PUT_LINE(FND_FILE.OUTPUT,v_err_buffer);
   END LOOP;
  ELSE
    FND_FILE.PUT_LINE(FND_FILE.OUTPUT,' ');
    FND_FILE.PUT_LINE(FND_FILE.OUTPUT,'                           *** No Errored Accural Concur Entries ***');
  END IF;

   FND_FILE.PUT_LINE(FND_FILE.OUTPUT,'      ');
   FND_FILE.PUT_LINE(FND_FILE.OUTPUT,RPAD('-',350,'-'));


EXCEPTION
 WHEN NO_DATA_FOUND THEN
  FND_FILE.PUT_LINE(FND_FILE.OUTPUT,'NO DATA FOUND '||SQLERRM);
  retcode := 1;
 WHEN OTHERS THEN
  FND_FILE.PUT_LINE(FND_FILE.OUTPUT,'EXCEPTION :  '||SQLERRM);
  retcode := 1;

END display_err_congl;


/*PROCEDURE SEND_Mail
      (
        p_action in varchar2,
        p_content in varchar2
        )
    IS
    Begin
           Case p_action
        When 'O' then
            g_conn := GERFP_CCL_MAIL.begin_mail(sender     => g_sender,
                     recipients => g_recipients,
                     subject    => p_content,
                     mime_type  => 'text/html');
        When 'S' then
            GERFP_CCL_MAIL.write_text(conn    => g_conn,
                 message => p_content || utl_tcp.CRLF);
        When 'C' then   
            GERFP_CCL_MAIL.end_mail( conn => g_conn );
        End case;
    
End SEND_Mail; 
*/

  PROCEDURE send_mail(p_action  IN VARCHAR2,
                      p_content IN VARCHAR2) IS
  BEGIN
  
    NULL;
  
  END send_mail;

END GERFP_CONC_GL_ACCR_AUTO_PKG; 
/
