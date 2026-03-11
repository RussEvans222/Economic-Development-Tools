public with sharing class EconDevHomeHeaderController {
    // Developer note:
    // Simple chart datapoint model consumed by multiple LWC chart sections.
    public class MetricPoint {
        @AuraEnabled public String label;
        @AuraEnabled public Integer countValue;
        @AuraEnabled public Decimal amountValue;
    }

    public class HomeSnapshot {
        @AuraEnabled public Integer openOpportunityCount;
        @AuraEnabled public Decimal openPipelineAmount;
        @AuraEnabled public String topOpenStage;

        @AuraEnabled public Integer mansfieldSiteCount;
        @AuraEnabled public Integer mansfieldMappedSiteCount;

        @AuraEnabled public Integer inFlightFundingRequestCount;
        @AuraEnabled public Decimal inFlightFundingRequestedAmount;
        @AuraEnabled public Decimal totalAvailableFundsAmount;
        @AuraEnabled public Decimal totalAwardedFundsAmount;

        @AuraEnabled public Integer acceptedBackgroundCheckCount;
        @AuraEnabled public Integer meetingsNext7Days;
        @AuraEnabled public List<MetricPoint> openStageMetrics;
        @AuraEnabled public List<MetricPoint> fundingStatusMetrics;

        @AuraEnabled public Datetime generatedAt;
    }

    @AuraEnabled(cacheable=true)
    public static HomeSnapshot getHomeSnapshot() {
        HomeSnapshot snap = new HomeSnapshot();

        // Developer note:
        // Opportunity KPIs emphasize open economic development pipeline velocity.
        snap.openOpportunityCount = [SELECT COUNT() FROM Opportunity WHERE IsClosed = false];

        AggregateResult oppAgg = [
            SELECT SUM(Amount) amountTotal
            FROM Opportunity
            WHERE IsClosed = false
        ];
        snap.openPipelineAmount = (Decimal) oppAgg.get('amountTotal');
        if (snap.openPipelineAmount == null) {
            snap.openPipelineAmount = 0;
        }

        List<AggregateResult> topStage = [
            SELECT StageName stage, COUNT(Id) stageCount
            FROM Opportunity
            WHERE IsClosed = false
            GROUP BY StageName
            ORDER BY COUNT(Id) DESC
            LIMIT 1
        ];
        snap.topOpenStage = topStage.isEmpty() ? 'N/A' : (String) topStage[0].get('stage');

        snap.openStageMetrics = new List<MetricPoint>();
        for (AggregateResult row : [
            SELECT StageName stage, COUNT(Id) stageCount, SUM(Amount) stageAmount
            FROM Opportunity
            WHERE IsClosed = false
            GROUP BY StageName
            ORDER BY COUNT(Id) DESC
            LIMIT 6
        ]) {
            MetricPoint p = new MetricPoint();
            p.label = (String) row.get('stage');
            p.countValue = Integer.valueOf((Long) row.get('stageCount'));
            p.amountValue = (Decimal) row.get('stageAmount');
            if (p.amountValue == null) p.amountValue = 0;
            snap.openStageMetrics.add(p);
        }

        // Developer note:
        // Site KPIs focus on map-ready Mansfield inventory.
        snap.mansfieldSiteCount = [
            SELECT COUNT()
            FROM Site__c
            WHERE City__c = 'Mansfield' AND State__c = 'Texas'
        ];

        snap.mansfieldMappedSiteCount = [
            SELECT COUNT()
            FROM Site__c
            WHERE City__c = 'Mansfield'
              AND State__c = 'Texas'
              AND Latitude__c != null
              AND Longitude__c != null
        ];

        // Developer note:
        // Funding KPIs align with in-flight request workload.
        snap.inFlightFundingRequestCount = [
            SELECT COUNT()
            FROM outfunds__Funding_Request__c
            WHERE outfunds__Status__c IN ('Submitted', 'In Progress', 'In Review')
        ];

        AggregateResult frAgg = [
            SELECT SUM(outfunds__Requested_Amount__c) requestedTotal
            FROM outfunds__Funding_Request__c
            WHERE outfunds__Status__c IN ('Submitted', 'In Progress', 'In Review')
        ];
        snap.inFlightFundingRequestedAmount = (Decimal) frAgg.get('requestedTotal');
        if (snap.inFlightFundingRequestedAmount == null) {
            snap.inFlightFundingRequestedAmount = 0;
        }

        AggregateResult fundingProgramAgg = [
            SELECT SUM(Available_Funds__c) availableTotal, SUM(Total_Awarded_Funds__c) awardedTotal
            FROM outfunds__Funding_Program__c
        ];
        // Developer note:
        // This powers the "Available vs Awarded" chart on the command center.
        snap.totalAvailableFundsAmount = (Decimal) fundingProgramAgg.get('availableTotal');
        if (snap.totalAvailableFundsAmount == null) {
            snap.totalAvailableFundsAmount = 0;
        }

        snap.totalAwardedFundsAmount = (Decimal) fundingProgramAgg.get('awardedTotal');
        if (snap.totalAwardedFundsAmount == null) {
            snap.totalAwardedFundsAmount = 0;
        }

        snap.fundingStatusMetrics = new List<MetricPoint>();
        // Developer note:
        // Keep this grouped summary lightweight for fast Home page rendering.
        for (AggregateResult row : [
            SELECT outfunds__Status__c status, COUNT(Id) statusCount, SUM(outfunds__Requested_Amount__c) statusAmount
            FROM outfunds__Funding_Request__c
            GROUP BY outfunds__Status__c
            ORDER BY COUNT(Id) DESC
            LIMIT 6
        ]) {
            MetricPoint p = new MetricPoint();
            p.label = (String) row.get('status');
            p.countValue = Integer.valueOf((Long) row.get('statusCount'));
            p.amountValue = (Decimal) row.get('statusAmount');
            if (p.amountValue == null) p.amountValue = 0;
            snap.fundingStatusMetrics.add(p);
        }

        // Developer note:
        // Lightweight operational indicators for underwriting/readiness monitoring.
        snap.acceptedBackgroundCheckCount = [
            SELECT COUNT()
            FROM Background_Check__c
            WHERE Accepted__c = true
        ];

        Datetime nowValue = System.now();
        snap.meetingsNext7Days = [
            SELECT COUNT()
            FROM Event
            WHERE StartDateTime >= :nowValue
              AND StartDateTime <= :nowValue.addDays(7)
        ];

        snap.generatedAt = System.now();
        return snap;
    }
}
