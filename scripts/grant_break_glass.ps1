param(
    [Parameter(Mandatory = $true)]
    [string]$Reason,

    [int]$TtlMinutes = 30,

    [string]$RequestId = "",

    [string]$Region = "ap-northeast-2",

    [string]$ClusterName = "eks-secure-infra-dev",

    [string]$TerraformDirectory = "",

    [string]$RequestedBy = $env:USERNAME,

    [string]$ApprovedBy = "local-terminal",

    [string]$TerraformStateBucket = $env:TERRAFORM_STATE_BUCKET,

    [string]$TerraformStateKey = $env:INFRA_TERRAFORM_STATE_KEY,

    [string]$TerraformStateRegion = $env:TERRAFORM_STATE_REGION
)

$ErrorActionPreference = "Stop"

if ($TtlMinutes -le 0) {
    throw "TtlMinutes must be greater than 0."
}

$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($TerraformDirectory)) {
    $TerraformDirectory = Join-Path $repoRoot "environments\infra"
}

if ([string]::IsNullOrWhiteSpace($TerraformStateKey)) {
    $TerraformStateKey = "infra/terraform.tfstate"
}

if ([string]::IsNullOrWhiteSpace($TerraformStateRegion)) {
    $TerraformStateRegion = $Region
}

Push-Location $TerraformDirectory
try {
    if (-not [string]::IsNullOrWhiteSpace($TerraformStateBucket)) {
        terraform init `
            -input=false `
            "-backend-config=bucket=$TerraformStateBucket" `
            "-backend-config=key=$TerraformStateKey" `
            "-backend-config=region=$TerraformStateRegion"
    }

    $outputs = @{
        BreakGlassRoleArn      = terraform output -raw break_glass_role_arn
        AlertTopicArn          = terraform output -raw break_glass_alert_topic_arn
        TableName              = terraform output -raw break_glass_jit_state_table_name
        SchedulerGroup         = terraform output -raw break_glass_scheduler_group_name
        SchedulerRoleArn       = terraform output -raw break_glass_scheduler_role_arn
        RevokerLambdaArn       = terraform output -raw break_glass_revoker_lambda_arn
    }
}
finally {
    Pop-Location
}

foreach ($key in $outputs.Keys) {
    if ([string]::IsNullOrWhiteSpace($outputs[$key])) {
        throw "Terraform output $key is empty. Apply break-glass resources first."
    }
}

$manageScript = Join-Path $repoRoot "scripts\manage_break_glass.py"

python $manageScript grant `
    --region $Region `
    --cluster-name $ClusterName `
    --principal-arn $outputs.BreakGlassRoleArn `
    --table-name $outputs.TableName `
    --scheduler-group $outputs.SchedulerGroup `
    --scheduler-role-arn $outputs.SchedulerRoleArn `
    --revoker-lambda-arn $outputs.RevokerLambdaArn `
    --ttl-minutes $TtlMinutes `
    --requested-by $RequestedBy `
    --approved-by $ApprovedBy `
    --reason $Reason `
    --request-id $RequestId `
    --sns-topic-arn $outputs.AlertTopicArn
