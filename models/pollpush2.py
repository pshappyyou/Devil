# -*- coding: utf-8 -*-

import subprocess
import json
import re
import time
import pprint
import datacompy
import logging
import pandas as pd
#from rethinkdb import RethinkDB
import rethinkdb as rdb

logging.basicConfig(filename='catchpy.log', level=logging.DEBUG)

r = rdb.RethinkDB()
conn = r.connect(host='10.108.8.108', db='DevilCASE')
#r.connect(host='3ef0c5d6ba19477.tsi.lan', db='DevilCASE')

query = '''
SELECT 
	Id, CaseNumber, Priority, Case_Age__c, Status, Description, Preferred_Case_Language__c, 
	Case_Preferred_Timezone__c, Tier__c, Category__c, Product__c, Subject, First_Response_Complete__c, 
	CreatedDate, Entitlement_Type__c, Plan_of_Action_Status__c, Case_Owner_Name__c,
    IsEscalated, Escalated_Case__c,
    ClosedDate, IsClosed, isClosedText__c, 
    AccountId, Account.Name, Account.CSM_Name__c, Account.CSM_Email__c,
    (SELECT CreatedDate, field, OldValue, NewValue, CreatedById FROM Histories WHERE CreatedDate=TODAY and field='Owner')
FROM Case 
WHERE
	RecordTypeId='012600000000nrwAAA' AND
	( (IsClosed=False) OR (IsClosed=True AND ClosedDate=TODAY) ) AND
	Preferred_Support_Region__c ='APAC' AND 
	Preferred_Case_Language__c != 'Japanese' AND 
	Tier__c != 'Admin'
'''


soql = re.sub("\n", " ", query)
old_dict = []
old_df = pd.DataFrame()
initial_loading = True

if old_df.empty:
    print('OLD DataFrame is empty!')

while True:
    result_is_empty = True
    while result_is_empty:
        print('Query starts...')
        start_time = time.time()
        try:
            result = subprocess.run(
                ['sfdx', 'force:data:soql:query', '-q', soql, '-u', 'DparkOrg', '--json'],
                shell=True,
                capture_output=True
            )
            print('Query ended...')
            end_time = time.time()
            print('Elapsed... ' + str(round(end_time - start_time)) + " sec")
            result_dict = json.loads(result.stdout)
            result_is_empty = False
        except:
            print("Query got error")

    # Error handling - https://developer.salesforce.com/docs/atlas.en-us.sfdx_cli_plugins.meta/sfdx_cli_plugins/cli_plugins_customize_errors.htm
    # if (new_dict == None or len(new_dict) <= 0):
    if (result_dict['status'] == 1): # status == 1 means Error
        print('There is an error while querying')
        # print(item_dict['name'] + ": " + item_dict['message'])
        print(result_dict['stack'])
    else: # assume status == 0
        new_dict = sorted(result_dict['result']['records'], key = lambda x: x['CaseNumber'])
        print('Total Size: ' + str(result_dict['result']['totalSize']))
        print('Records Size: ' + str(len(new_dict)))

        new_df = pd.DataFrame(new_dict)
        exploded = new_df.Account.apply(json.dumps).apply(json.loads).apply(pd.Series).drop(columns='attributes')

        df_filtered = new_df[[
                                "CaseNumber",
                                "Case_Age__c", 
                                "Status", 
                                "Priority", 
                                "Entitlement_Type__c",
                                "First_Response_Complete__c", 
                                "Product__c", 
                                "Category__c",
                                "Case_Owner_Name__c", 
                                "IsEscalated",
                                "Preferred_Case_Language__c",
                                "Case_Preferred_Timezone__c",
                                "Subject"
                            ]]
        # sorting can be done in the code above using "by"
        
        new_df_filtered = pd.concat([df_filtered, exploded], axis=1)
        new_df_filtered.columns = new_df_filtered.columns.str.lower()
        new_df_filtered["id"] = new_df_filtered['casenumber']
        # print(new_df_filtered.columns)

        if old_df.empty:
            print('OLD DataFrame is empty!')
        else:
            df1 = new_df_filtered
            df2 = old_df

            compare = datacompy.Compare(
            df1,
            df2,
            join_columns='CaseNumber', #You can also specify a list of columns
            abs_tol=0.0001,
            rel_tol=0,
            df1_name='new',
            df2_name='old',
            ignore_case=True,
            cast_column_names_lower=True
            )

            # print(compare.report())
            # print(compare.intersect_rows)
            
            # print(compare.sample_mismatch('case_age__c'))
            # print(compare.sample_mismatch('status').empty)
            # print(compare.sample_mismatch('priority'))
            # print(compare.sample_mismatch('first_response_complete__c'))
            # print(compare.sample_mismatch('product__c'))
            # print(compare.sample_mismatch('case_owner_name__c'))

            print("==========================================================================================")
            print("New Case Only - To add in the table")
            if compare.df1_unq_rows.empty:
                print("-- No new case!!")
                logging.warning("no new case")
            else:
                logging.error('Yes! We got a new CASE!')
                print("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!ADD ROWS!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!")
                print(compare.df1_unq_rows)
                print("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!ADD ROWS!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!")
            
            print("Closed Yesterday - To remove from the table")
            if compare.df2_unq_rows.empty:
                print("-- Nothing to remove from the queue")
            else:
                print("@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@REMOVE ROWS@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@")
                print(compare.df2_unq_rows)
                print("@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@REMOVE ROWS@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@")
            # print("Changed values")
            # print(compare.intersect_rows)
            print("==========================================================================================")
            print("Mismatched All")
            # print(compare.all_mismatch())
            changed_rows = compare.all_mismatch()
            clean_new_data = changed_rows.drop(list(changed_rows.filter(regex='df2')), axis='columns')
            clean_new_data.columns = clean_new_data.columns.str.replace('_df1','')
            # print(clean_new_data.columns)
            changed_data = changed_rows.filter(regex='df1')
            # original_data = changed_rows.filter(regex='df2')
            changed_data.columns = changed_data.columns.str.replace('_df1','')
            # print(changed_data.columns.str.replace('_df1',''))
            # print(changed_data.columns)
            print("Changed Data")
            print(changed_data)
            # print("Original Data")
            # print(original_data)
            # print(changed_data.columns)
            # print(changed_rows.columns)
            changed_data = changed_data.fillna('')

            for namedTuple in changed_data.itertuples(index=False):
                #print(namedTuple)
                dictRow = namedTuple._asdict()
                #print(dictRow)
                print("Result from DB")
                print(r.table('table1').get(dictRow['id']).run(conn))
                #r.table('table1').get(dictRow['id']).run(conn)
                print("DB updated")

                print(r.table('table1').get(dictRow['id']).update(dictRow).run(conn))

        old_df = new_df_filtered
        old_dict = new_dict

        # new_df_filtered["id"] = new_df_filtered['casenumber']
        new_df_filtered = new_df_filtered.fillna('')
        conversion = new_df_filtered.to_dict(orient='records')
        # print(conversion)

        ## RethinkDB
        # When the program is firstly loaded
        if initial_loading:
            r.table('table1').delete().run(conn)
            r.table('table1').insert(conversion).run(conn)

        # conn.close()
    initial_loading = False
    print('----------------------------------------------------------------------')
