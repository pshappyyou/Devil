## Console Output to UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Slack Channel
# $uri = "https://hooks.slack.com/services/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" # sandbox-kpop-stars
# $uri2 =  "https://hooks.slack.com/services/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" # Direct sandbox

$uri = "https://hooks.slack.com/services/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"
$SFCred = "DparkOrg"


### SalesForce Query ###
$query = "SELECT 
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
Tier__c != 'Admin' AND
Status = 'New'
ORDER BY Priority,Case_Age__c desc" -replace "`n", " "

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
    return ($json_result | ConvertFrom-Json).result.records
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
#$all = $all | ?{ (([datetime]$_.CreatedDate).ToUniversalTime() -gt [datetime]"14/02/2022 23:59") -or (($_.Entitlement_Type__c -match "Premium") -or ($_.Entitlement_Type__c -match "Extended") -or ($_.Entitlement_Type__c -match "Elite")) }
$core =    $all | ?{ !( ($_.Tier__c -eq "Premium") -or ($_.Entitlement_Type__c -match "Extended") -or ($_.Entitlement_Type__c -match "Elite") )}

# Creating Priority Doughnut Chart
$p_total = $core.Count
$p_arr = $core | Group-Object Priority | Select-Object Name, Count | Sort-Object Name
$p1_cnt = $p_arr.Count
$p2_cnt = $p_arr.Count
$p3_cnt = $p_arr
$p4_cnt = $p_arr
$p_label = $p_arr | Select-Object -ExpandProperty Name
$p_data = $p_arr | Select-Object -ExpandProperty Count
$pc_label = Convert-LabelArray -LabelArray $p_label
$pc_data = Convert-DataArray -DataArray $p_data

<# Chart 3 : Priority Chart #>
# original
$priority_chart = "https://quickchart.io/chart?width=500&height=120&c={type:'horizontalBar',data:{labels:$pc_label,datasets:[{label:'Priority',data:$pc_data,order:1,backgroundColor:['rgba(255,99,132,0.5)','rgba(255,159,64,0.5)','rgba(54,162,235,0.5)','rgba(75,192,192,0.5)'],borderColor:['rgb(255,99,132)','rgb(255,159,64)','rgb(54,162,235)','rgb(75,192,192)'],borderWidth:1}]},options:{scales:{xAxes:[{ticks:{min:0}}]},legend:false,plugins:{datalabels:{font:{weight:'bold',size:15},anchor:'end',align:'left',color:'rgb(0,0,0)'}}}}"

# $priority_chart = "https://quickchart.io/chart?width=500&height=200&c={type:'horizontalBar',data:{labels:$pc_label,datasets:[{label:'Total',data:$pc_data,order:1,backgroundColor:['rgba(255,99,132,0.5)','rgba(255,159,64,0.5)','rgba(54,162,235,0.5)','rgba(75,192,192,0.5)'],borderColor:['rgb(255,99,132)','rgb(255,159,64)','rgb(54,162,235)','rgb(75,192,192)'],borderWidth:1},{label:'First Responded',data:[1,2,3,4]}]},options:{scales:{yAxes:[{stacked:true}],xAxes:[{stacked:true,ticks:{min:0}}]},plugins:{datalabels:{font:{weight:'bold',size:11},anchor:'end',align:'center',color:'rgb(0,0,0)'}}}}"

$ImageUrl3 = Convert-ImageUrl -ImageUrl $priority_chart

$body = '{
    "blocks": [
        {   "type": "divider"   },
        {
            "type": "image",
            "block_id": "image1",
            "title": {
                "type": "plain_text",
                "text": "APAC Support (Standard) Case Priority Status"
            },
            "image_url": "' + $ImageUrl3 + '",
            "alt_text": "Queue Total: '+ $p_total +'"
        },
        {
            "type": "section",
            "text": {
                "type": "mrkdwn",
                "text": "*Total (Standard Cases): '+ $p_total +'*"
            }
        },
        {   "type": "divider"   }
    ]
}'

MessageTo-Slack -Channel $uri -Message $body