## Console Output to UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

## Global Variables
# $file_name =    "APACTechSupRealTimeDashboard.xlsx"
#$sp_link =  "https://tableau.sharepoint.com/sites/APACTechSupport/Shared%20Documents/"+$file_name+"?web=1"
# $sp_link =  "http://angel:1004/cases/""+?web=1"
# $uri =  "https://hooks.slack.com/services/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" # sandbox-kpop-stars
$uri2 = "https://hooks.slack.com/services/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" # Direct sandbox


$sp_link =  "http://EC2AMAZ-8DLJNCT.TSI.LAN:1004/newcases"
$uri = "https://hooks.slack.com/services/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"
$uri2="https://hooks.slack.com/services/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"
$SFCred = "DparkOrg"


### SalesForce Query ###
$query = "SELECT 
    Id, casenumber, Priority, Case_Age__c, Status, Preferred_Case_Language__c, 
    Tier__c, Category__c, Product__c, subject, CreatedDate, Account.Name, Case_Owner_Name__c,Entitlement_Type__c,
    (SELECT CreatedById, body FROM Feeds), Case_Preferred_Timezone__c
FROM case 
WHERE 
    Id IN (SELECT ParentId FROM CaseFeed) AND
    RecordTypeId='012600000000nrwAAA' AND 
    (Status='New' or Status='Active' or Status='Re-opened') AND 
    Preferred_Support_Region__c ='APAC' AND 
    OwnedbyQueue__c=True AND 
    Preferred_Case_Language__c != 'Japanese' AND 
    Tier__c != 'Admin'
ORDER BY Priority,Case_Age__c desc" -replace "`n", " "

$query2 = "SELECT 
	Id, CaseNumber, Priority, Case_Age__c, Status, Preferred_Case_Language__c, Tier__c, 
	Category__c, Product__c, subject, First_Response_Complete__c, CreatedDate, 
	Entitlement_Type__c, Plan_of_Action_Status__c, Case_Owner_Name__c,
    AccountId, Account.Name,
    (SELECT CreatedDate, field, OldValue, NewValue, CreatedById FROM Histories WHERE CreatedDate < TODAY and field='Owner'),
    IsEscalated, Escalated_Case__c, 
    (SELECT CreatedById, body FROM Feeds)
FROM case 
WHERE 
    Id IN (SELECT CaseID FROM CaseHistory ) AND Id IN (SELECT ParentId FROM CaseFeed) AND
	RecordTypeId='012600000000nrwAAA' AND 
	(Status='New' or Status='Active' or Status='Re-opened') AND 
	Preferred_Support_Region__c ='APAC' AND 
	Preferred_Case_Language__c != 'Japanese' AND 
	Tier__c != 'Admin'
ORDER BY Case_Owner_Name__c, Priority,Case_Age__c DESC" -replace "`n", " "

<# Functions #>
function Get-QueryResult {
    [CmdletBinding()]
    param($Query)
    do {
        $ts = (Get-Date).ToString("yyyy-MM-dd-HH:mm:ss")
        Write-Host "Query starts at $ts ==" -ForegroundColor Yellow
        $json_result = (sfdx force:data:soql:query -q $Query -u $SFCred --json)
    } While (($json_result -eq $null) -or ($json_result -eq $false))

    # return ($json_result | ConvertFrom-Json).result.records
    $raw_obj = ($json_result | ConvertFrom-Json).result.records
    $new_obj = @()

    $raw_obj | % {
        # Protips
        if ($_.feeds.records.body -like "*protip*") {
            $_.feeds.records = "YES"
        } else {
            $_.feeds.records = "" #$null
        }
        $new_obj += $_
    }
    return $new_obj
}


function Convert-LabelArray {
    param ($LabelArray)
    $r = $null
    foreach ($a in $LabelArray) {
        $r += "'"+"$($a)" + "'" + ","
    }
    $r = $r -replace ".$"
    $c_label = "[" + $r + "]"
    return $c_label
}

function Convert-DataArray {
    param ($DataArray)
    $r = $null
    foreach ($a in $DataArray) {
        $r += "$($a)" + ","
    }
    $r = $r -replace ".$"
    $c_data = "[" + $r + "]"
    return $c_data
}

function Convert-ImageUrl {
    param ($ImageUrl)
    return $ImageUrl.Replace("'","%27").Replace(" ","%20")
}

function MessageTo-Slack {
    [CmdletBinding()]
    param($Channel, $Message)
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-RestMethod -Method POST -ContentType "application/json" -uri $Channel -Body $Message | Out-Null
}

function mrkdwn {
    [CmdletBinding()]
    param ($Text)
    return (ConvertTo-Json -Depth 10 @{blocks=@(@{type="section";text=@{type="mrkdwn";text="$Text"}})})
} 



$all = Get-QueryResult -Query $query
$all = $all | ?{ (([datetime]$_.CreatedDate).ToUniversalTime() -gt [datetime]"8/7/2021 23:59") -or (($_.Entitlement_Type__c -match "Premium") -or ($_.Entitlement_Type__c -match "Extended") -or ($_.Entitlement_Type__c -match "Elite")) }
$desktop = $all | ?{ ($_.Product__c -eq "Tableau Desktop") -or ($_.Product__c -eq "Tableau Public Desktop") -or ($_.Product__c -eq "Tableau Reader") -or ($_.Product__c -eq "Tableau Prep") -or ($_.Product__c -eq "Tableau Public Desktop")}
$server =  $all | ?{ (($_.Product__c -eq "Tableau Server") -or ($_.Product__c -eq "Tableau Public Server") -or ($_.Product__c -eq "Tableau Online") -or ($_.Product__c -eq "Tableau Mobile") -or ($_.Product__c -eq "Tableau Resource Monitoring Tool") -or ($_.Product__c -eq "Tableau Content Migration Tool") ) }
$premium = $all | ?{ ($_.Tier__c -eq "Premium") -or $_.Entitlement_Type__c -match "Extended"}
$p1p2 =    $all | ?{ ( ($_.Priority -eq "P1") -or ($_.Priority -eq "P2") ) -and !( ($_.Tier__c -eq "Premium") -or ($_.Entitlement_Type__c -match "Extended") )}


<# Creating a Case Dashboard Chart - Doughnut#>
$q_total = $all.Count
$chart_arr = $all | Group-Object Product__c | Select-Object Name, Count
$chart_label = $chart_arr | Select-Object -ExpandProperty Name
$chart_data = $chart_arr | Select-Object -ExpandProperty Count
$c_label = Convert-LabelArray -LabelArray $chart_label
$c_data = Convert-DataArray -DataArray $chart_data

<# Creating assigned Charts - Barchart #>
$result = Get-QueryResult -Query $query2
$assigned = $result | ?{$_.Case_Owner_Name__c -ne $null}
$a_total = $assigned.Count
$assgn_arr = $assigned | Group-Object Case_Owner_Name__c | Select-Object Name, Count | Sort-Object Count
$assgn_label = $assgn_arr | Select-Object -ExpandProperty Name
$assgn_data = $assgn_arr | Select-Object -ExpandProperty Count
$a_label = Convert-LabelArray -LabelArray $assgn_label
$a_data = Convert-DataArray -DataArray $assgn_data

$chart1 =  "https://quickchart.io/chart?c={type:'doughnut',data:{labels:$c_label,datasets:[{data:$c_data}]},options:{plugins:{doughnutlabel:{labels:[{text:'$q_total',font:{size:20}},{text:'Total'}]}}}}"

$ImageUrl =  Convert-ImageUrl -ImageUrl $chart1

$number = [math]::Round($q_total/10)
$dog = ":tableau:"
$dogs = 1..$number | %{"$dog "}
$dogs = -join $dogs

$body = '{
    "blocks": [
        {   "type": "divider"   },
        {
            "type": "section",
            "text": { "type": "mrkdwn", "text": "Hello team!  '+ $dogs +':thumbsup_all:" },
            "accessory": {
                "action_id": "text1234",
                "type": "button",
                "text": {
                    "type": "plain_text",
                    "text": "Click me for the case list"
                },
                "value": "old_case_link",
                "style": "primary",
                "url": "'+ $sp_link +'"
            }
        },
        {
            "type": "image",
            "block_id": "image1",
            "title": {
                "type": "plain_text",
                "text": "APAC Support Queue Status"
            },
            "image_url": "' + $ImageUrl + '",
            "alt_text": "Queue Total: '+ $q_total +'"
        },
        {
            "type": "section",
            "text": {
                "type": "mrkdwn",
                "text": "Unassigned: '+ $q_total +'\n Assigned: '+ $a_total +'\n *Case Total: '+ ($q_total+$a_total) +'*"
            }
        },
        {   "type": "divider"   }
    ]
}'
MessageTo-Slack -Channel $uri -Message $body


$chart2 = "https://quickchart.io/chart?c={type:'horizontalBar',data:{labels:$a_label,datasets:[{label:'Owner',data:$a_data,order:1}]}}"

$ImageUrl2 = Convert-ImageUrl -ImageUrl $chart2

$body = '{
    "blocks": [
        {   "type": "divider"   },
        {
            "type": "section",
            "text": { "type": "mrkdwn", "text": "Assigned Status" }
        },
        {
            "type": "image",
            "block_id": "image2",
            "title": {
                "type": "plain_text",
                "text": "Queue Assigned Status"
            },
            "image_url": "' + $ImageUrl2 + '",
            "alt_text": "Queue Total: '+ $a_total +'"
        },
        {
            "type": "section",
            "text": {
                "type": "mrkdwn",
                "text": "Unassigned: '+ $q_total +'\n Assigned: '+ $a_total +'\n *Case Total: '+ ($q_total+$a_total) +'*"
            }
        },
        {   "type": "divider"   }
    ]
}'
MessageTo-Slack -Channel $uri2 -Message $body


<#  Posting Premium Cases #>
$p_cnt = $premium.Count
$msg_title = ConvertTo-Json -Depth 10 @{blocks=@(@{type="section";text=@{type="mrkdwn";text="*Premium Case List* ($p_cnt)"}},@{type="divider"})}
MessageTo-Slack -Channel $uri2 -Message $msg_title
$premium | Select-Object CaseNumber, @{n="Account";e={$_.Account.Name}}, Id, Product__c, Priority, Preferred_Case_Language__c, Case_Age__c, Status | % {
    $id = $_.Id
    $case_url = "https://tableau.my.salesforce.com/$id"
    $case_number = $_.CaseNumber
    $priority = $_.Priority
    $product = ($_.Product__c).split(" ")[1]
    $lang = ($_.Preferred_Case_Language__c).split(" ")[0]
    $age = $_.Case_Age__c
    $status = $_.Status
    $acc = ($_.Account).split(" ")[0]
    $style = "danger"

    $message = '{
        "blocks": [
            {
                "type": "section",
                "block_id": "section1",
                "text": {
                    "type": "mrkdwn",
                    "text": "<'+$case_url+'|'+$case_number+'> \t '+$priority+' \t '+$product+' \t '+$lang+' \t '+$age+'hrs \t '+$status+' \t '+$acc+'"
                },
                "accessory": {
                    "type": "button",
                    "text": {
                        "type": "plain_text",
                        "text": "Premium"
                    },
                    "value": "'+$case_number+'",
                    "style": "'+$style+'",
                    "url": "'+$case_url+'"
                }
            }
        ]
    }'
    MessageTo-Slack -Channel $uri2 -Message $message
}
MessageTo-Slack -Channel $uri2 -Message $divider



## Posting P1 & P2 Cases ##
$p1p2_cnt = $p1p2.Count
$msg_title = ConvertTo-Json -Depth 10 @{blocks=@(@{type="section";text=@{type="mrkdwn";text="*P1 & P2 Case List* ("+$p1p2.Count+")"}},@{type="divider"})}
MessageTo-Slack -Channel $uri2 -Message $msg_title
$p1p2 | Select-Object CaseNumber, @{n="Account";e={$_.Account.Name}}, Id, Product__c, Priority, Preferred_Case_Language__c, Case_Age__c, Status | % {
    $id = $_.Id
    $case_url = "https://tableau.my.salesforce.com/$id"
    $case_number = $_.CaseNumber
    $priority = $_.Priority
    $product = ($_.Product__c).split(" ")[1].PadRight(10, ' ')
    $lang = ($_.Preferred_Case_Language__c).split(" ")[0]
    $age = $_.Case_Age__c
    $status = $_.Status
    $acc = ($_.Account).split(" ")[0]
    $style = "primary"

    $message = '{
        "blocks": [
            {
                "type": "section",
                "block_id": "section1",
                "text": {
                    "type": "mrkdwn",
                    "text": "<'+$case_url+'|'+$case_number+'> \t '+$priority+' \t '+$product+' \t '+$lang+' \t '+$age+'hrs \t '+$status+' \t '+$acc+'"
                },
                "accessory": {
                    "type": "button",
                    "text": {
                        "type": "plain_text",
                        "text": "View Case"
                    },
                    "value": "'+$case_number+'",
                    "style": "'+$style+'",
                    "url": "'+$case_url+'"
                }
            }
        ]
    }'
    MessageTo-Slack -Channel $uri2 -Message $message
}
MessageTo-Slack -Channel $uri2 -Message $divider

# https://mcpmag.com/articles/2018/04/06/find-excel-data-with-powershell.aspx

<# Slack #>
$divider = ConvertTo-Json -Depth 10 @{blocks=@(@{type="divider"})}
$slack_divider = '{"blocks":[{"type":"divider"}]}'







$body = '{
	"type": "modal",
	"title": {
		"type": "plain_text",
		"text": "My App",
		"emoji": true
	},
	"submit": {
		"type": "plain_text",
		"text": "Submit",
		"emoji": true
	},
	"close": {
		"type": "plain_text",
		"text": "Cancel",
		"emoji": true
	},
	"blocks": [
		{
			"type": "section",
			"text": {
				"type": "plain_text",
				"text": "Check out these charming checkboxes"
			},
			"accessory": {
				"type": "checkboxes",
				"action_id": "this_is_an_action_id",
				"initial_options": [{
					"value": "A1",
					"text": {
						"type": "plain_text",
						"text": "Checkbox 1"
					}
				}],
				"options": [
					{
						"value": "A1",
						"text": {
							"type": "plain_text",
							"text": "Checkbox 1"
						}
					},
					{
						"value": "A2",
						"text": {
							"type": "plain_text",
							"text": "Checkbox 2"
						}
					}
				]
			}
		}
	]
}'

MessageTo-Slack -Channel $uri2 -Message $body