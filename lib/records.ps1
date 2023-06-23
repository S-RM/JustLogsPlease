function Get-UALRecordTypes {

    $RecordTypes = @(
        "AzureActiveDirectory",
        "AzureActiveDirectoryAccountLogon",
        "AzureActiveDirectoryStsLogon",
        "ExchangeAdmin",
        "ExchangeItem",
        "ExchangeItemGroup",
        "SharePoint",
        "MicrosoftTeams",
        "MicrosoftTeamsAdmin",
        "OneDrive",
        "DataInsightsRestApiAudit",
        "ThreatIntelligence",
        "ThreatFinder",
        "SecurityComplianceAlerts",
        "ThreatIntelligenceUrl",
        "SecurityComplianceInsights",
        "ThreatIntelligenceAtpContent",
        "DataCenterSecurityCmdlet",
        "ComplianceDLPSharePoint",
        "ComplianceDLPExchange",
        "Quarantine",
        "MailSubmission",
        "ComplianceDLPSharePointClassification",
        "SharePointCommentOperation",
        "DataGovernance",
        "PowerBIAudit",
        "SharePointSharingOperation",
        "SharePointListOperation",
        "ExchangeItemAggregated",
        "MicrosoftTeamsDevice",
        "MicrosoftTeamsAnalytics",
        "ExchangeAggregatedOperation",
        "SharePointListItemOperation",
        "SharePointContentTypeOperation",
        "SharePointFieldOperation",
        "SharePointFileOperation"
    )

    return $RecordTypes

}