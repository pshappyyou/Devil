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
import threading
import numpy as np

logging.basicConfig(filename='catchpy.log', level=logging.DEBUG)

r = rdb.RethinkDB()

def redbcon():   
    return r.connect(host='10.108.8.108', db='DevilCASE')

def queryPrep():
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
    return query

def get_input():
    global flag
    keystrk=input('') 
    flag = False

def sfCasedata():
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
        result_dictjson = json.loads(result.stdout)
        return result_dictjson
    except:
        print("Query got error")


def push2Rethink(result_dict):
    #connect to RethinkDB    
    conn = redbcon()
    new_dict = sorted(result_dict['result']['records'], key = lambda x: x['CaseNumber'])
    print('Total Size: ' + str(result_dict['result']['totalSize']))
    print('Records Size: ' + str(len(new_dict)))

    new_df = pd.DataFrame(new_dict)
    #print(new_df)
    exploded = new_df.Account.apply(json.dumps).apply(json.loads).apply(pd.Series, dtype='object').drop(columns='attributes')

    df_filtered = new_df.loc[new_df["Case_Owner_Name__c"].isnull() | (new_df["Case_Owner_Name__c"].notnull() & new_df["Histories"].notnull()), [
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

    # df_filtered = new_df.loc[new_df["Case_Owner_Name__c"].isnull() | (new_df["Case_Owner_Name__c"].notnull() & new_df["Histories"].notnull()),[
    #                         "CaseNumber",
    #                         "Case_Age__c", 
    #                         "Status", 
    #                         "Priority", 
    #                         "Entitlement_Type__c",
    #                         "First_Response_Complete__c", 
    #                         "Product__c", 
    #                         "Category__c",
    #                         "Case_Owner_Name__c", 
    #                         "IsEscalated",
    #                         "Preferred_Case_Language__c",
    #                         "Case_Preferred_Timezone__c",
    #                         "Subject"
    #                     ]]
    # sorting can be done in the code above using "by"
    
    new_df_filtered = pd.concat([df_filtered, exploded], axis=1)
    new_df_filtered.columns = new_df_filtered.columns.str.lower()
    new_df_filtered["id"] = new_df_filtered['casenumber']

    # new_df_filtered["CSM"] =""
    # print(new_df_filtered)
    # new_df_filtered["CSM"]=np.where(new_df_filtered["CSM_Name__c"] is, "", "VIP")
    new_df_filtered.loc[new_df_filtered['csm_name__c'].notnull(), 'csm'] = 'VIP'
    # print(new_df_filtered)
    # old_df = new_df_filtered
    # old_dict = new_dict

    # new_df_filtered["id"] = new_df_filtered['casenumber']
    new_df_filtered = new_df_filtered.fillna('')
    conversion = new_df_filtered.to_dict(orient='records')
    # print(conversion)

    #print(new_df_filtered)
    premium_df = new_df_filtered.loc[new_df_filtered['entitlement_type__c'] =='Premium']
    #print(premium_df)
    dic_premiumcase = premium_df.to_dict(orient='records')

    print(r.table('TBLAllCase').delete().run(conn))
    print(r.table('TBLAllCase').insert(conversion).run(conn))  

    r.table('TBLPremiumCase').delete().run(conn)
    print(r.table('TBLPremiumCase').insert(dic_premiumcase).run(conn))

    #conn.close()

# pick up today 
soql = re.sub("\n", " ", queryPrep())
# old_dict = []
# old_df = pd.DataFrame()
#initial_loading = True

# stop the while loop with any key input
i=threading.Thread(target=get_input)
i.start()
flag = 1

# if old_df.empty:
#     print('OLD DataFrame is empty!')

while flag==1:

    result_dict = sfCasedata()

    if (result_dict['status'] == 1): # status == 1 means Error
        print('There is an error while querying')
        # print(item_dict['name'] + ": " + item_dict['message'])
        print(result_dict['stack'])
    else: # assume status == 0
        push2Rethink(result_dict)

    time.sleep(20)
    print('----------------------------------------------------------------------')

#conn.close()