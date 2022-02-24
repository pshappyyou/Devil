# -*- coding: utf-8 -*-

from cmath import exp
import subprocess
import json
import re
import time
import pprint
import datacompy
import logging
import pandas as pd
#from rethinkdb import RethinkDB
# import rethinkdb as rdb
import threading
import numpy as np
import psycopg2
import os
# from io import StringIO
import sys
from simple_salesforce import Salesforce
import requests

logging.basicConfig(filename='catchpy.log', level=logging.DEBUG)

# r = rdb.RethinkDB()
# def redbcon():   
#     return r.connect(host='10.108.8.108', db='DevilCASE')

# conn_string = 'postgres://test:Password@123@10.108.15.110'

# sf = Salesforce(username='dpark@tableau.com', password='DaisyQkrgkfka012!', security_token='2SvsCA3F4QxixUd7z5qfcw4a')

param_dic = {
    "host"  : "EC2AMAZ-HT8RV9C",
    "database" : "APACsupport",
    "user"  : "test",
    "password"  : "Pass1234",
    "sslmode" : "disable"
}


def queryPrep():
    query = '''
    SELECT 
        Id, CaseNumber, Priority, Case_Age__c, Status, Description, Preferred_Case_Language__c, 
        Case_Preferred_Timezone__c, Tier__c, Category__c, Product__c, Subject, First_Response_Complete__c, 
        CreatedDate, Entitlement_Type__c, Plan_of_Action_Status__c, Case_Owner_Name__c,
        IsEscalated, Escalated_Case__c,
        ClosedDate, IsClosed, isClosedText__c
    FROM Case 
    WHERE
        RecordTypeId='012600000000nrwAAA' AND
        IsClosed=False AND
        Preferred_Support_Region__c ='APAC' AND 
        Preferred_Case_Language__c != 'Japanese' AND 
        Tier__c != 'Admin'
    '''
    return query

# pick up today 
soql = re.sub("\n", " ", queryPrep())

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
        # sf_data = sf.query_all(soql)
        # sf_df=pd.DataFrame(sf_data['records'].drop(columns='attributes'))
        # return(sf_df)
    except:
        print("Query got error")




# stop the while loop with any key input
i=threading.Thread(target=get_input)
i.start()
flag = 1

# if old_df.empty:
#     print('OLD DataFrame is empty!')

def connect(params_dic) :
    conn = None
    try:
        print('Connecting to the PostgreSQL database...')
        conn = psycopg2.connect(**params_dic)
    except (Exception, psycopg2.DatabaseError) as error:
        print(error)
        sys.exit(1)
    print("Connection Successful")
    return conn

conn = connect(param_dic)


def prepDataframe(result_dict):
    new_dict = sorted(result_dict['result']['records'], key = lambda x: x['CaseNumber'])
    print('Total Size: ' + str(result_dict['result']['totalSize']))
    print('Records Size: ' + str(len(new_dict)))

    new_df = pd.DataFrame(new_dict)
    # print("new_df")
    # print(new_df)
    # exploded = new_df.Account.apply(json.dumps).apply(json.loads).apply(pd.Series, dtype='object').drop(columns='attributes')
    
    
    # df_filtered = new_df.loc[new_df["Case_Owner_Name__c"].isnull() | (new_df["Case_Owner_Name__c"].notnull() & new_df["Histories"].notnull()), [
    df_filtered = new_df.loc[new_df["Case_Owner_Name__c"].isnull() , [
                            "Id",
                            "CaseNumber",
                            # "Case_Age__c", 
                            # "Status", 
                            # "Priority", 
                            # "Entitlement_Type__c",
                            # "First_Response_Complete__c", 
                            # "Product__c", 
                            # "Category__c",
                            # "Case_Owner_Name__c", 
                            # "IsEscalated",
                            # "Preferred_Case_Language__c",
                            # "Case_Preferred_Timezone__c",
                            "Subject"
    ]]

    # exploded = df_filtered.Account.apply(json.dumps).apply(json.loads).apply(pd.Series, dtype='object').drop(columns='attributes')
    # print("exploded :"+ str(len(exploded)) + " " + str(exploded.size))
    # # print(exploded)

    # new_df_filtered = pd.concat([df_filtered, exploded], axis=1)
    # new_df_filtered.columns = new_df_filtered.columns.str.lower()
    # new_df_filtered.loc[new_df_filtered['csm_name__c'].notnull(), 'csm'] = 'VIP'
    # # print(new_df_filtered)


    # # new_df_filtered["id"] = new_df_filtered['casenumber']
    # new_df_filtered = new_df_filtered.fillna('')
    # print(new_df_filtered)
    # return new_df_filtered
    df_filtered.columns = df_filtered.columns.str.lower()
    df_filtered = df_filtered.fillna('')
    print("df_filtered") 
    print(df_filtered)
    print(df_filtered.dtypes)
    # print(df_filtered)
    return df_filtered
    
def push2Postgre(conn, df, table) :
    tuples = [tuple(x) for x in df.to_numpy()]
    cols = ','.join(list(df.columns))
    print(cols)
    query = "INSERT INTO %s(%s) VALUES(%%s, %%s, %%s)" % (table, cols)
    print(query)
    cursor = conn.cursor()
    try:
        cursor.executemany(query, tuples)
        conn.commit()
    except (Exception, psycopg2.DatabaseError) as error:
        print("Error: %s" % error)
        conn.rollback()
        cursor.close()
        return 1
    print("execute_many() done")
    cursor.close()


while flag==1:

    result_dict = sfCasedata()

    if (result_dict['status'] == 1): # status == 1 means Error
        print('There is an error while querying')
        # print(item_dict['name'] + ": " + item_dict['message'])
        print(result_dict['stack'])
    else: # assume status == 0
        push2Postgre(conn, prepDataframe(result_dict), "cases")
        
        # prepedDF = prepDataframe(result_dict)
        # print("predata--")
        # print(prepedDF)
        flag=0
    time.sleep(20)

    print('----------------------------------------------------------------------')

#conn.close()