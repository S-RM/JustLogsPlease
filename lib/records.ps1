function Get-UALRecordTypes {

    $RecordTypes = @(
        # Critical
        "AzureActiveDirectory",
        "AzureActiveDirectoryAccountLogon",
        "AzureActiveDirectoryStsLogon",

        # Important
        "ExchangeAdmin",
        "ExchangeItem",
        "ExchangeItemGroup",
        "SharePoint",
        "MicrosoftTeams",
        "MicrosoftTeamsAdmin",
        "OneDrive",
        "DataInsightsRestApiAudit",

        # Security alerts
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

        # Misc
        "MailSubmission",
        "ComplianceDLPSharePointClassification",
        "SharePointCommentOperation",
        "DataGovernance",
        "PowerBIAudit",

        # Remainder office
        "SharePointSharingOperation",
        "SharePointListOperation",
        "ExchangeItemAggregated",
        "MicrosoftTeamsDevice",
        "MicrosoftTeamsAnalytics",
        "ExchangeAggregatedOperation",
        "SharePointListItemOperation",
        "SharePointContentTypeOperation",
        "SharePointFieldOperation",
        "SharePointFileOperation" # High volume
    )

    return $RecordTypes

}